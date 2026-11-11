# Samba file server for the MigraTux share.
FROM alpine:3.20
RUN apk add --no-cache samba samba-common-tools
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
EXPOSE 445
ENTRYPOINT ["/entrypoint.sh"]
