# Shell test image: same base as the target system (Ubuntu 24.04, mawk as awk).
# Built and used by tests/run.sh.
FROM ubuntu:24.04
RUN apt-get update \
 && apt-get install -y --no-install-recommends bats shellcheck \
 && rm -rf /var/lib/apt/lists/*
WORKDIR /repo
