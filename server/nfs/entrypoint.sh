#!/bin/sh
# Export /srv/nfsroot (the unpacked Ubuntu ISO) read-only over NFSv3 and stay
# in the foreground. The NFS server itself is part of the host kernel, so the
# container runs privileged on the host network and only steers it.
#
# Env: SERVER_IP, PXE_INTERFACE (to find the client subnet)
#      NFS_CLIENTS (optional): who may mount, e.g. 192.168.0.0/24. Empty = the
#      subnet of SERVER_IP on PXE_INTERFACE.
# Ports: 111 (rpcbind), 2049 (nfs), 20048 (mountd).
set -eu

export_dir=/srv/nfsroot
mountd_port=20048
threads=8

: "${SERVER_IP:?SERVER_IP is not set}"
: "${PXE_INTERFACE:?PXE_INTERFACE is not set}"

die() {
    echo "ERROR: $*" >&2
    exit 1
}

if ! ls "$export_dir"/casper/*.squashfs >/dev/null 2>&1; then
    die "$export_dir holds no unpacked Ubuntu ISO (casper/*.squashfs). Run server/setup.sh, then 'docker compose up -d' again."
fi

clients="${NFS_CLIENTS:-}"
if [ -z "$clients" ]; then
    # Line format: "192.168.0.0/24 proto kernel scope link src 192.168.0.10 ..."
    clients="$(ip -4 route show dev "$PXE_INTERFACE" scope link 2>/dev/null \
        | awk -v ip="$SERVER_IP" '{ for (i = 1; i < NF; i++) if ($i == "src" && $(i + 1) == ip) { print $1; exit } }')"
fi
[ -n "$clients" ] || die "no subnet found for SERVER_IP $SERVER_IP on $PXE_INTERFACE. Check both in server/.env (ip -4 -br addr), or set NFS_CLIENTS."

# fsid: a fixed number, so the export does not depend on a disk UUID that the
# container cannot look up. all_squash + ro: every client reads as "nobody".
# insecure: also accept clients that use a source port above 1023.
echo "$export_dir $clients(ro,all_squash,no_subtree_check,insecure,fsid=17)" > /etc/exports

# /proc/fs/nfsd only exists once the module is loaded.
modprobe nfsd 2>/dev/null || true
if [ ! -d /proc/fs/nfsd ]; then
    die "the host kernel has no NFS server (module nfsd). Check on the server: sudo modprobe nfsd"
fi
if ! grep -q ' /proc/fs/nfsd nfsd ' /proc/mounts; then
    mount -t nfsd nfsd /proc/fs/nfsd || die "cannot mount /proc/fs/nfsd (the container must run privileged)"
fi

mkdir -p /run/rpcbind /var/lib/nfs/rpc_pipefs /var/lib/nfs/v4recovery
# With the host network, a rpcbind of the host itself may already hold port 111.
rpcbind -w 2>/dev/null || rpcbind 2>/dev/null || echo "WARNING: rpcbind did not start here (port 111 in use?). Using the one that is running."

# Called by the trap below.
# shellcheck disable=SC2317
stop() {
    echo "stopping the NFS server"
    exportfs -ua 2>/dev/null || true
    rpc.nfsd 0 2>/dev/null || true
    kill "$mountd_pid" 2>/dev/null || true
    exit 0
}
trap stop TERM INT

rpc.mountd --foreground --port "$mountd_port" --no-nfs-version 4 &
mountd_pid=$!
exportfs -ra || die "exportfs refused /etc/exports: $(cat /etc/exports)"
rpc.nfsd --no-nfs-version 4 "$threads" || die "the NFS server did not start (rpc.nfsd)"

echo "NFS: exporting $(cat /etc/exports)"
echo "NFS: ready, clients mount $SERVER_IP:$export_dir"
wait "$mountd_pid"
die "rpc.mountd stopped"
