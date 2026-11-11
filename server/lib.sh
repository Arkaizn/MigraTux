#!/usr/bin/env bash
# Shared functions for server/setup.sh and server/migratux. Sourced.

MTX_SERVER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MTX_REPO_DIR="$(cd "$MTX_SERVER_DIR/.." && pwd)"
MTX_ENV_KEYS="SERVER_IP PXE_INTERFACE HTTP_PORT SHARE_NAME SMB_USER SMB_PASSWORD ADMIN_USER ADMIN_PASSWORD USER_PASSWORD DATA_DIR"
MTX_LOG_FILE="${MTX_LOG_FILE:-}"

# shellcheck source=lib/inventory.sh
source "$MTX_REPO_DIR/lib/inventory.sh"

mtx_log() {
    local line
    line="$(date '+%Y-%m-%d %H:%M:%S') $*"
    echo "$line"
    if [[ -n "$MTX_LOG_FILE" ]]; then
        echo "$line" >> "$MTX_LOG_FILE"
    fi
}

mtx_die() {
    local line
    line="$(date '+%Y-%m-%d %H:%M:%S') ERROR: $*"
    echo "$line" >&2
    if [[ -n "$MTX_LOG_FILE" ]]; then
        echo "$line" >> "$MTX_LOG_FILE"
    fi
    exit 1
}

# Load server/.env (or $MTX_ENV_FILE), check it, and set the MTX_* data paths.
mtx_load_env() {
    local env_file="${MTX_ENV_FILE:-$MTX_SERVER_DIR/.env}" key
    [[ -r "$env_file" ]] || mtx_die "$env_file not found. Copy server/.env.example to server/.env and edit it."
    set -a
    # shellcheck disable=SC1090
    source "$env_file"
    set +a
    for key in $MTX_ENV_KEYS; do
        [[ -n "${!key:-}" ]] || mtx_die "$key is empty in $env_file"
        [[ "${!key}" =~ [[:space:]\'\"\$\\#] ]] && mtx_die "$key in $env_file contains a space or one of ' \" \$ \\ #"
    done
    [[ "$SERVER_IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || mtx_die "SERVER_IP '$SERVER_IP' is not an IPv4 address"
    [[ "$HTTP_PORT" =~ ^[0-9]+$ ]] || mtx_die "HTTP_PORT '$HTTP_PORT' is not a number"
    ISO_URL="${ISO_URL:-}"

    case "$DATA_DIR" in
        /*) MTX_DATA="$DATA_DIR" ;;
        *)  MTX_DATA="$MTX_SERVER_DIR/${DATA_DIR#./}" ;;
    esac
    MTX_SHARE="$MTX_DATA/share"
    MTX_TFTP="$MTX_DATA/tftp"
    MTX_HTTP="$MTX_DATA/http"
    MTX_CONF="$MTX_DATA/conf"
    MTX_IMAGES="$MTX_DATA/images"
    MTX_EVENTS="$MTX_DATA/events"
    MTX_HOSTS="$MTX_TFTP/grub/hosts"
    MTX_ASSIGN="$MTX_SHARE/_assign"
    export MTX_DATA MTX_SHARE MTX_TFTP MTX_HTTP MTX_CONF MTX_IMAGES MTX_EVENTS MTX_HOSTS MTX_ASSIGN
}

# mtx_render TEMPLATE: print the template with every @KEY@ replaced by the
# value of the shell variable KEY. Fails if a placeholder has no value.
mtx_render() {
    local template="$1" key value script="" left
    [[ -r "$template" ]] || mtx_die "template $template not found"
    while read -r key; do
        [[ -n "${!key+x}" ]] || mtx_die "$template uses @$key@ but $key is not set"
        value="${!key}"
        value="${value//\\/\\\\}"
        value="${value//&/\\&}"
        value="${value//|/\\|}"
        script+="s|@${key}@|${value}|g;"
    done < <(grep -o '@[A-Z_][A-Z0-9_]*@' "$template" | tr -d '@' | sort -u)
    sed "$script" "$template"
    left="$(sed "$script" "$template" | grep -c '@[A-Z_][A-Z0-9_]*@' || true)"
    [[ "$left" == "0" ]] || mtx_die "$template still has placeholders after rendering"
}

# mtx_host_dir NAME: print the client folder in the share (case-insensitive match).
mtx_host_dir() {
    local want="${1,,}" d
    for d in "$MTX_SHARE"/*/; do
        [[ -d "$d" ]] || continue
        d="${d%/}"
        if [[ "$(basename "${d,,}")" == "$want" && "$(basename "$d")" != _* ]]; then
            echo "$d"
            return 0
        fi
    done
    return 1
}

# mtx_host_inventory HOSTDIR: path of the inventory CSV in a client folder.
mtx_host_inventory() {
    local f
    for f in "$1"/inventory-*.csv; do
        if [[ -r "$f" ]]; then
            echo "$f"
            return 0
        fi
    done
    return 1
}

# mtx_host_macs HOSTDIR: the MACs that count as this host. Manual assignments
# (migratux assign) replace the MACs of the inventory, so a lab install on
# another VM never puts a job on the original Windows PC.
mtx_host_macs() {
    local host inv f assigned=""
    host="$(basename "$1")"
    for f in "$MTX_ASSIGN"/*; do
        [[ -f "$f" ]] || continue
        if [[ "$(tr -d '\r\n' < "$f")" == "$host" ]]; then
            assigned+="$(basename "$f" | tr '-' ':')"$'\n'
        fi
    done
    if [[ -n "$assigned" ]]; then
        printf '%s' "$assigned" | sort -u
    elif inv="$(mtx_host_inventory "$1")"; then
        inv_macs "$inv"
    fi
}
