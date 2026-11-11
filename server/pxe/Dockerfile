# dnsmasq as proxy-DHCP + TFTP server for PXE boot.
# Ubuntu base like the setup image (one package mirror for the whole server).
FROM ubuntu:24.04
RUN apt-get update \
 && apt-get install -y --no-install-recommends dnsmasq-base \
 && rm -rf /var/lib/apt/lists/*
EXPOSE 67/udp 69/udp 4011/udp
ENTRYPOINT ["dnsmasq", "--keep-in-foreground", "--conf-file=/etc/dnsmasq.conf"]
