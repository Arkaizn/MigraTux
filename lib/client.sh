#!/usr/bin/env bash
# Shared functions for the scripts that run on the client PC: in the installer
# (install/mtx-early.sh, install/mtx-late.sh) and on the installed Linux
# (install/firstboot.sh, reconfigure/reconfigure.sh). Sourced.
#
# Test hooks: MTX_SYS (default /sys), MTX_CMDLINE_FILE (default /proc/cmdline),
# MTX_DISK (use this disk instead of the largest one).

MTX_CLIENT_LOG="${MTX_CLIENT_LOG:-}"

mtx_clog() {
    local line
    line="$(date '+%Y-%m-%d %H:%M:%S') $*"
    echo "$line"
    if [[ -n "$MTX_CLIENT_LOG" ]]; then
        echo "$line" >> "$MTX_CLIENT_LOG"
    fi
}

mtx_cdie() {
    mtx_clog "ERROR: $*" >&2
    mtx_event failed "$*" || true
    exit 1
}

# mtx_client_load_env FILE: read SERVER_IP, HTTP_PORT, SHARE_NAME, SMB_USER,
# SMB_PASSWORD, ADMIN_USER, USER_PASSWORD (written by server/setup.sh).
mtx_client_load_env() {
    local key
    [[ -r "$1" ]] || { echo "ERROR: $1 not found" >&2; return 1; }
    # shellcheck disable=SC1090
    source "$1"
    for key in SERVER_IP HTTP_PORT SHARE_NAME SMB_USER SMB_PASSWORD ADMIN_USER USER_PASSWORD; do
        [[ -n "${!key:-}" ]] || { echo "ERROR: $key is missing in $1" >&2; return 1; }
    done
    MTX_URL="http://$SERVER_IP:$HTTP_PORT"
    export MTX_URL
}

# mtx_macs: MAC addresses of this PC (no loopback, no virtual interfaces), one per line.
mtx_macs() {
    local sys="${MTX_SYS:-/sys}" dev mac
    for dev in "$sys"/class/net/*; do
        [[ -r "$dev/address" ]] || continue
        [[ "$(basename "$dev")" == lo ]] && continue
        # Physical interfaces have a "device" link; bridges, veth etc. do not.
        [[ -e "$dev/device" ]] || continue
        mac="$(tr 'A-F' 'a-f' < "$dev/address")"
        [[ "$mac" =~ ^([0-9a-f]{2}:){5}[0-9a-f]{2}$ && "$mac" != 00:00:00:00:00:00 ]] || continue
        echo "$mac"
    done | sort -u
}

# mtx_primary_mac: the MAC used for status events. MTX_MAC wins if set.
mtx_primary_mac() {
    if [[ -n "${MTX_MAC:-}" ]]; then
        echo "$MTX_MAC"
        return 0
    fi
    mtx_macs | head -n 1
}

# mtx_cmdline_arg KEY: value of KEY=value on the kernel command line, or nothing.
mtx_cmdline_arg() {
    local word
    # shellcheck disable=SC2013
    for word in $(cat "${MTX_CMDLINE_FILE:-/proc/cmdline}"); do
        if [[ "$word" == "$1="* ]]; then
            echo "${word#*=}"
            return 0
        fi
    done
    return 0
}

# mtx_event STEP TEXT: tell the server what this PC is doing (shown by
# `migratux status`). Never fatal: a lost event must not stop a migration.
mtx_event() {
    local step="$1" text="$2" mac
    [[ -n "${MTX_URL:-}" ]] || return 0
    mac="$(mtx_primary_mac)"
    [[ -n "$mac" ]] || return 0
    printf '%s\n' "$text" | curl -fsS -m 10 -o /dev/null -T - "$MTX_URL/events/${mac//:/-}/$step" 2>/dev/null || return 0
}

# mtx_disarm: delete the PXE job of this PC on the server, so the next network
# boot starts from the disk. Fails if the server does not answer.
mtx_disarm() {
    local mac code ok=0 any=0
    while read -r mac; do
        [[ -n "$mac" ]] || continue
        any=1
        code="$(curl -sS -m 15 -o /dev/null -w '%{http_code}' -X DELETE "$MTX_URL/pxe/hosts/$mac.cfg" 2>/dev/null || true)"
        case "$code" in
            204|404) ok=1 ;;
            *) mtx_clog "disarm: server answered '$code' for $mac" ;;
        esac
    done < <(mtx_macs)
    [[ $any -eq 1 && $ok -eq 1 ]]
}

# mtx_pick_disk: the largest fixed disk, e.g. /dev/sda. The Ubuntu installer
# picks the same one for its "direct" layout.
mtx_pick_disk() {
    local name size type rm best="" best_size=0
    if [[ -n "${MTX_DISK:-}" ]]; then
        echo "$MTX_DISK"
        return 0
    fi
    while read -r name size type rm; do
        [[ "$type" == disk && "$rm" == 0 ]] || continue
        if (( size > best_size )); then
            best="$name"; best_size="$size"
        fi
    done < <(lsblk -dnb -o NAME,SIZE,TYPE,RM)
    [[ -n "$best" ]] || return 1
    echo "/dev/$best"
}
