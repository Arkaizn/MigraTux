#!/bin/sh
# Create the Samba user from the environment and start smbd in the foreground.
set -eu

: "${SMB_USER:?SMB_USER is not set}"
: "${SMB_PASSWORD:?SMB_PASSWORD is not set}"

if ! id "$SMB_USER" >/dev/null 2>&1; then
    useradd -M -s /usr/sbin/nologin "$SMB_USER"
fi
printf '%s\n%s\n' "$SMB_PASSWORD" "$SMB_PASSWORD" | smbpasswd -a -s "$SMB_USER" >/dev/null

testparm -s /etc/samba/smb.conf >/dev/null
exec smbd --foreground --no-process-group --debug-stdout
