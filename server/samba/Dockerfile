# Samba file server for the MigraTux share.
# Ubuntu base like the setup image: the server then needs only one package
# mirror (the one the host already uses), not a second one for Alpine.
FROM ubuntu:24.04
RUN apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends samba \
 && rm -rf /var/lib/apt/lists/*
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
EXPOSE 445
ENTRYPOINT ["/entrypoint.sh"]
