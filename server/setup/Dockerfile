# One-shot helper image for server/setup.sh: holds Ubuntu's signed UEFI network
# boot loader (shim + GRUB) and the tools to fetch and unpack the ISO.
FROM ubuntu:24.04
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl libarchive-tools openssl \
 && mkdir -p /tmp/debs /boot-files \
 && cd /tmp/debs \
 && apt-get download shim-signed grub-efi-amd64-signed \
 && for deb in *.deb; do dpkg-deb -x "$deb" /tmp/debs/root; done \
 && cp "$(ls /tmp/debs/root/usr/lib/shim/shimx64.efi.signed.latest /tmp/debs/root/usr/lib/shim/shimx64.efi.signed 2>/dev/null | head -n 1)" /boot-files/bootx64.efi \
 && cp /tmp/debs/root/usr/lib/grub/x86_64-efi-signed/grubnetx64.efi.signed /boot-files/grubx64.efi \
 && rm -rf /tmp/debs /var/lib/apt/lists/*
COPY fetch.sh /fetch.sh
RUN chmod +x /fetch.sh
ENTRYPOINT ["/fetch.sh"]
