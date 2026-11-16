#!/usr/bin/env bash
# Runs inside the setup image (server/setup/Dockerfile), started by server/setup.sh.
# Fills /data/tftp (boot loader, kernel, initrd), /data/http (ISO) and
# /data/nfsroot (the unpacked ISO, exported over NFS to the installer).
#
# Usage: fetch.sh [--skip-iso]
# Env:   ISO_URL (optional). Empty = newest 24.04 live-server ISO.
set -euo pipefail

releases="https://releases.ubuntu.com/24.04"
skip_iso=0
[[ "${1:-}" == "--skip-iso" ]] && skip_iso=1

mkdir -p /data/tftp/grub/hosts /data/http
cp /boot-files/bootx64.efi /boot-files/grubx64.efi /data/tftp/
echo "boot loader: bootx64.efi (shim) and grubx64.efi copied"

if [[ $skip_iso -eq 1 ]]; then
    echo "ISO: skipped (--skip-iso). PXE boot will not work without it."
    exit 0
fi

iso=/data/http/ubuntu.iso
url="${ISO_URL:-}"
sum=""
if [[ -z "$url" ]]; then
    # Line format: "<sha256> *ubuntu-24.04.N-live-server-amd64.iso"
    line="$(curl -fsSL "$releases/SHA256SUMS" | grep 'live-server-amd64\.iso$' | sort -k2 -V | tail -n 1)"
    [[ -n "$line" ]] || { echo "ERROR: no live-server ISO found in $releases/SHA256SUMS" >&2; exit 1; }
    sum="${line%% *}"
    name="${line##*[ *]}"
    url="$releases/$name"
fi

if [[ -f "$iso" && -f "$iso.url" && "$(cat "$iso.url")" == "$url" ]]; then
    echo "ISO: already downloaded ($url)"
else
    echo "ISO: downloading $url (about 4 GB)"
    curl -fL --retry 5 -C - -o "$iso.part" "$url"
    if [[ -n "$sum" ]]; then
        echo "ISO: checking SHA-256"
        echo "$sum  $iso.part" | sha256sum -c - >/dev/null \
            || { echo "ERROR: ISO checksum is wrong. Delete $iso.part and run setup again." >&2; exit 1; }
    fi
    mv "$iso.part" "$iso"
    echo "$url" > "$iso.url"
fi

echo "ISO: extracting kernel and initrd"
tmp="$(mktemp -d)"
bsdtar -xf "$iso" -C "$tmp" casper/vmlinuz casper/initrd
cp "$tmp/casper/vmlinuz" "$tmp/casper/initrd" /data/tftp/
rm -rf "$tmp"
chmod 644 /data/tftp/vmlinuz /data/tftp/initrd /data/tftp/*.efi "$iso"

# The installer mounts the unpacked ISO over NFS (netboot=nfs). Kernel, initrd
# and this folder must come from the same ISO: the initrd checks the ID in
# .disk/casper-uuid-*. The marker is written last, so a broken run is redone.
nfsroot=/data/nfsroot
marker=/data/nfsroot.url
if [[ -f "$marker" && "$(cat "$marker")" == "$url" ]] && compgen -G "$nfsroot/casper/*.squashfs" >/dev/null; then
    echo "NFS root: already unpacked"
else
    echo "NFS root: unpacking the ISO into $nfsroot (needs as much space as the ISO)"
    rm -f "$marker"
    mkdir -p "$nfsroot"
    # The folder itself stays (a running nfs container has it mounted). The
    # ISO has read-only folders: make them writable before deleting.
    chmod -R u+w "$nfsroot"
    find "$nfsroot" -mindepth 1 -delete
    bsdtar -xf "$iso" -C "$nfsroot"
    chmod -R u+w,a+rX "$nfsroot"
    compgen -G "$nfsroot/casper/*.squashfs" >/dev/null \
        || { echo "ERROR: $iso has no casper/*.squashfs. Is it an Ubuntu live-server ISO?" >&2; exit 1; }
    echo "$url" > "$marker"
fi
echo "done: $(du -h "$iso" | cut -f1) ISO, kernel and initrd in /data/tftp, unpacked ISO in $nfsroot"
