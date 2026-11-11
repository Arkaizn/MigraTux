# Shell test image: same base as the target system (Ubuntu 24.04, mawk as awk).
# Built and used by tests/run.sh. dnsmasq, grub-common (grub-script-check), openssl,
# python3-yaml and zstd are
# for the server config, autoinstall and disk image tests.
FROM ubuntu:24.04
RUN apt-get update \
 && apt-get install -y --no-install-recommends bats shellcheck dnsmasq-base grub-common openssl python3-yaml zstd \
 && rm -rf /var/lib/apt/lists/*
WORKDIR /repo
