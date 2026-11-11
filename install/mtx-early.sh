#!/usr/bin/env bash
# Runs in the Ubuntu installer (live system, RAM) as an autoinstall
# early-command, BEFORE the disk is touched. Does what the PXE job says
# (kernel command line, set by `migratux start|rollback` on the server):
#
#   migratux.mode=install             just install
#   migratux.mode=migrate  + host     upload a full disk image first (rollback), then install.
#                                     An image that is already on the server is KEPT: after a
#                                     failed install the disk no longer holds Windows.
#   migratux.mode=migrate-new + host  like migrate, but replace an existing image
#   migratux.mode=restore  + host     write the disk image back, reboot, do NOT install
#
# Needs root. Log: /var/log/migratux-early.log (copied into the installed
# system by mtx-late.sh). Exit code not 0 stops the install.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/client.sh
source "$here/../lib/client.sh"

MTX_CLIENT_LOG="${MTX_CLIENT_LOG:-/var/log/migratux-early.log}"
run_dir="${MTX_RUN_DIR:-/run}"

# Print to the log and, if there is one, to the screen of the PC.
say() {
    mtx_clog "$*"
    if [[ -w /dev/tty1 ]]; then
        echo "MigraTux: $*" > /dev/tty1 2>/dev/null || true
    fi
}

pick_compressor() {
    if command -v zstd >/dev/null 2>&1; then
        echo zst
    else
        echo gz
    fi
}

compress() {
    case "$1" in
        zst) zstd -T0 -3 -q -c ;;
        gz)  gzip -1 -c ;;
    esac
}

decompress() {
    case "$1" in
        zst) zstd -d -q -c ;;
        gz)  gzip -d -c ;;
        *)   return 1 ;;
    esac
}

# Wait until a background `sha256sum > file` has written its result.
wait_for_sum() {
    for _ in $(seq 1 60); do
        [[ -s "$1" ]] && return 0
        sleep 0.5
    done
    return 1
}

put() {
    curl -fsS --retry 3 -o /dev/null -T "$1" "$2"
}

# image_disk HOST: upload the whole disk to the server, compressed.
# The info file goes last: it marks the image as complete.
image_disk() {
    local host="$1" disk size ext url sum start
    disk="$(mtx_pick_disk)" || mtx_cdie "no disk found to image"
    size="$(blockdev --getsize64 "$disk")"
    ext="$(pick_compressor)"
    url="$MTX_URL/images/$host"
    start="$(date +%s)"

    say "Sicherung: Abbild von $disk ($((size / 1024 / 1024 / 1024)) GB) wird auf den Server kopiert. Das dauert."
    mtx_event image "Disk-Abbild von $disk wird gesichert ($((size / 1024 / 1024 / 1024)) GB)"

    sfdisk -d "$disk" > "$run_dir/mtx-disk.sfdisk" 2>/dev/null || true
    rm -f "$run_dir/mtx-image.sha256"
    dd if="$disk" bs=4M status=none \
        | compress "$ext" \
        | tee >(sha256sum | cut -d' ' -f1 > "$run_dir/mtx-image.sha256") \
        | curl -fsS -o /dev/null -H 'Expect:' -T - "$url/disk.img.$ext" \
        || mtx_cdie "disk image upload failed. Nothing was wiped. Check free space on the server."
    wait_for_sum "$run_dir/mtx-image.sha256" || mtx_cdie "no checksum for the disk image"
    sum="$(cat "$run_dir/mtx-image.sha256")"

    {
        echo "host=$host"
        echo "disk=$disk"
        echo "size_bytes=$size"
        echo "ext=$ext"
        echo "sha256=$sum"
        echo "mac=$(mtx_primary_mac)"
        echo "date=$(date '+%Y-%m-%d %H:%M:%S')"
    } > "$run_dir/mtx-disk.info"
    if [[ -s "$run_dir/mtx-disk.sfdisk" ]]; then
        put "$run_dir/mtx-disk.sfdisk" "$url/disk.sfdisk" || true
    fi
    put "$run_dir/mtx-disk.info" "$url/disk.info" || mtx_cdie "could not upload disk.info. Nothing was wiped."

    say "Sicherung fertig nach $(( ($(date +%s) - start) / 60 )) Minuten."
    mtx_event image-done "Disk-Abbild gesichert (sha256 ${sum:0:12}...)"
}

# info_value KEY FILE
info_value() {
    sed -n "s/^$1=//p" "$2" | head -n 1
}

# restore_disk HOST: write the saved image back to the disk and check it.
restore_disk() {
    local host="$1" disk size want_size ext want_sum sum url
    url="$MTX_URL/images/$host"
    curl -fsS --retry 3 -o "$run_dir/mtx-disk.info" "$url/disk.info" \
        || mtx_cdie "no disk image for $host on the server (disk.info missing)"
    ext="$(info_value ext "$run_dir/mtx-disk.info")"
    want_size="$(info_value size_bytes "$run_dir/mtx-disk.info")"
    want_sum="$(info_value sha256 "$run_dir/mtx-disk.info")"
    [[ "$ext" == zst || "$ext" == gz ]] || mtx_cdie "disk.info has no valid ext"
    [[ "$want_size" =~ ^[0-9]+$ && -n "$want_sum" ]] || mtx_cdie "disk.info is incomplete"

    disk="$(mtx_pick_disk)" || mtx_cdie "no disk found to restore to"
    size="$(blockdev --getsize64 "$disk")"
    (( size >= want_size )) || mtx_cdie "disk $disk ($size bytes) is smaller than the image ($want_size bytes)"

    say "Rollback: Abbild wird auf $disk zurueckgeschrieben. Das dauert."
    mtx_event restore "Rollback: Abbild wird zurueckgeschrieben"
    rm -f "$run_dir/mtx-image.sha256"
    curl -fsS "$url/disk.img.$ext" \
        | tee >(sha256sum | cut -d' ' -f1 > "$run_dir/mtx-image.sha256") \
        | decompress "$ext" \
        | dd of="$disk" bs=4M conv=fsync status=none \
        || mtx_cdie "writing the image to $disk failed. Start the rollback again."
    sync
    wait_for_sum "$run_dir/mtx-image.sha256" || mtx_cdie "no checksum for the downloaded image"
    sum="$(cat "$run_dir/mtx-image.sha256")"
    [[ "$sum" == "$want_sum" ]] || mtx_cdie "image checksum is wrong (got ${sum:0:12}, expected ${want_sum:0:12}). Start the rollback again."
    say "Rollback fertig, Pruefsumme stimmt."
}

main() {
    local mode host
    mtx_client_load_env "${MTX_CLIENT_ENV:-$here/../client.env}"
    mode="$(mtx_cmdline_arg migratux.mode)"
    host="$(mtx_cmdline_arg migratux.host)"
    mtx_clog "mtx-early: mode='$mode' host='$host' macs=$(mtx_macs | tr '\n' ' ')"

    case "$mode" in
        install)
            mtx_event install "Ubuntu wird installiert (ca. 20-30 Minuten)"
            ;;
        migrate|migrate-new)
            [[ -n "$host" ]] || mtx_cdie "mode $mode needs migratux.host"
            if [[ "$mode" == migrate ]] && curl -fsS -o "$run_dir/mtx-old.info" "$MTX_URL/images/$host/disk.info" 2>/dev/null; then
                say "Sicherung: Abbild vom $(info_value date "$run_dir/mtx-old.info") ist schon auf dem Server und bleibt erhalten."
                mtx_event image-kept "Vorhandenes Disk-Abbild vom $(info_value date "$run_dir/mtx-old.info") bleibt erhalten"
            else
                image_disk "$host"
            fi
            mtx_event install "Ubuntu wird installiert (ca. 20-30 Minuten)"
            ;;
        restore)
            [[ -n "$host" ]] || mtx_cdie "mode restore needs migratux.host"
            restore_disk "$host"
            mtx_disarm || mtx_cdie "restore is done, but the PXE job could not be removed. Run 'migratux stop $host' on the server, then reboot."
            mtx_event restored "Rollback fertig: Windows ist zurueck. Netzwerk-Boot ausschalten."
            say "Neustart in 10 Sekunden. Danach startet wieder Windows."
            sleep "${MTX_REBOOT_DELAY:-10}"
            # shellcheck disable=SC2086
            ${MTX_REBOOT_CMD:-reboot -f}
            # Never fall through into the installer.
            sleep "${MTX_REBOOT_WAIT:-600}"
            exit 1
            ;;
        *)
            mtx_cdie "no valid migratux.mode on the kernel command line ('$mode'). Refusing to touch this PC."
            ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
