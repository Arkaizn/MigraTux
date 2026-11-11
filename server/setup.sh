#!/usr/bin/env bash
# Prepare the MigraTux server (M3/M4). Safe to run again: downloads are kept,
# the config files and the client bundle are always rebuilt.
#
#   1. builds the Docker images
#   2. downloads the UEFI boot loader and the Ubuntu 24.04 ISO, extracts kernel + initrd
#   3. renders dnsmasq, Samba, GRUB and autoinstall config from server/.env
#   4. packs the client scripts (install/, reconfigure/, mapping/, lib/)
#
# Usage: server/setup.sh [--skip-iso] [--no-build]
#   --skip-iso   no ISO download (only for trying out the config)
#   --no-build   do not build Docker images or fetch anything; render only
# Needs: docker with compose, a user in the docker group. No root.
# Log: <DATA_DIR>/log/setup.log. Exit code not 0 = failed, see the last line.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=server/lib.sh
source "$here/lib.sh"

skip_iso=0
build=1
for arg in "$@"; do
    case "$arg" in
        --skip-iso) skip_iso=1 ;;
        --no-build) build=0 ;;
        *) echo "usage: server/setup.sh [--skip-iso] [--no-build]" >&2; exit 2 ;;
    esac
done

mtx_load_env
mkdir -p "$MTX_DATA/log" "$MTX_SHARE" "$MTX_ASSIGN" "$MTX_TFTP/grub" "$MTX_HOSTS" "$MTX_HTTP/autoinstall" \
         "$MTX_HTTP/files" "$MTX_CONF" "$MTX_IMAGES" "$MTX_EVENTS"
MTX_LOG_FILE="$MTX_DATA/log/setup.log"
mtx_log "setup: start (data in $MTX_DATA)"

if [[ $build -eq 1 ]]; then
    command -v docker >/dev/null || mtx_die "docker is not installed"
    mtx_log "setup: building Docker images"
    docker build -q --network host -t migratux-setup "$here/setup" >/dev/null || mtx_die "building the setup image failed"
    (cd "$here" && docker compose build -q) || mtx_die "docker compose build failed"

    fetch_args=()
    [[ $skip_iso -eq 1 ]] && fetch_args+=(--skip-iso)
    mtx_log "setup: fetching boot files"
    docker run --rm --network host --user "$(id -u):$(id -g)" -e ISO_URL="$ISO_URL" -v "$MTX_DATA:/data" \
        migratux-setup "${fetch_args[@]}" || mtx_die "fetching the boot files failed"
fi

# Password hash for the autoinstall identity (SHA-512 crypt).
if command -v openssl >/dev/null; then
    ADMIN_PASSWORD_HASH="$(openssl passwd -6 "$ADMIN_PASSWORD")"
else
    ADMIN_PASSWORD_HASH="$(docker run --rm --network none --entrypoint openssl migratux-setup passwd -6 "$ADMIN_PASSWORD")"
fi
[[ "$ADMIN_PASSWORD_HASH" == \$6\$* ]] || mtx_die "could not hash ADMIN_PASSWORD"
export ADMIN_PASSWORD_HASH

# "docker compose up" before a finished setup creates the missing config
# files as empty folders. Remove them, or the files cannot be written.
for f in "$MTX_CONF/dnsmasq.conf" "$MTX_CONF/smb.conf"; do
    if [[ -d "$f" ]]; then
        rmdir "$f" 2>/dev/null || mtx_die "$f is a folder, not a file. Run 'docker compose down', delete this folder and run setup.sh again."
        mtx_log "setup: removed the empty folder $f (docker compose was started before setup was done)"
    fi
done

mtx_log "setup: rendering config"
mtx_render "$here/templates/dnsmasq.conf.tmpl" > "$MTX_CONF/dnsmasq.conf"
mtx_render "$here/templates/smb.conf.tmpl" > "$MTX_CONF/smb.conf"
mtx_render "$here/templates/grub.cfg.tmpl" > "$MTX_TFTP/grub/grub.cfg"
mtx_render "$here/templates/client.env.tmpl" > "$MTX_HTTP/files/client.env"
mtx_render "$MTX_REPO_DIR/install/user-data.tmpl" > "$MTX_HTTP/autoinstall/user-data"
: > "$MTX_HTTP/autoinstall/meta-data"
: > "$MTX_HTTP/autoinstall/vendor-data"

mtx_log "setup: packing the client bundle"
tar -czf "$MTX_HTTP/files/migratux-client.tar.gz" -C "$MTX_REPO_DIR" \
    --exclude='README.md' install reconfigure mapping lib

missing=()
for f in "$MTX_TFTP/bootx64.efi" "$MTX_TFTP/grubx64.efi" "$MTX_TFTP/vmlinuz" "$MTX_TFTP/initrd" "$MTX_HTTP/ubuntu.iso"; do
    [[ -s "$f" ]] || missing+=("${f#"$MTX_DATA"/}")
done
if [[ ${#missing[@]} -gt 0 ]]; then
    mtx_log "setup: WARNING, PXE boot will not work yet. Missing: ${missing[*]}"
fi

mtx_log "setup: done"
cat <<EOF

Next:
  cd $here && docker compose up -d      # start Samba, PXE and HTTP
  docker compose ps                     # all three must be "running"
  ./migratux status                     # list clients and jobs
Windows share: \\\\$SERVER_IP\\$SHARE_NAME   (user $SMB_USER)
EOF
