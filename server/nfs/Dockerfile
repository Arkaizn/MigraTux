# NFS server for the network installer: exports the unpacked Ubuntu ISO
# read-only, so a client mounts it instead of loading the whole ISO into RAM.
# Ubuntu base like the other server images. kmod and iproute2 are for the
# entrypoint (load the nfsd module, find the client subnet).
FROM ubuntu:24.04
RUN apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends nfs-kernel-server iproute2 kmod \
 && rm -rf /var/lib/apt/lists/*
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
EXPOSE 111 2049 20048
ENTRYPOINT ["/entrypoint.sh"]
