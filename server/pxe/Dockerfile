# dnsmasq as proxy-DHCP + TFTP server for PXE boot.
FROM alpine:3.20
RUN apk add --no-cache dnsmasq
EXPOSE 67/udp 69/udp 4011/udp
ENTRYPOINT ["dnsmasq", "--keep-in-foreground", "--conf-file=/etc/dnsmasq.conf"]
