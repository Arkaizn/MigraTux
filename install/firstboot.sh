#!/usr/bin/env bash
# First boot of a migrated PC (installed as /usr/local/sbin/migratux-firstboot,
# started by migratux-firstboot.service). Fetches the newest MigraTux scripts
# from the server and starts reconfigure/reconfigure.sh.
#
# Needs root. Run it again by hand with:  sudo migratux-firstboot --force
# Log: /var/log/migratux/firstboot.log (+ reconfigure.log, report.txt).
# Exit: 0 ok, 1 fatal (will run again at the next boot), 2 done but data check failed.
set -uo pipefail

root="${MTX_ROOT:-}"
state="$root/var/lib/migratux"
current="$root/opt/migratux/current"
mkdir -p "$state" "$root/var/log/migratux"
export MTX_CLIENT_LOG="$root/var/log/migratux/firstboot.log"

if [[ "${1:-}" == "--force" ]]; then
    rm -f "$state/done"
fi
if [[ -e "$state/done" ]]; then
    echo "MigraTux first boot already ran. Use --force to run it again."
    exit 0
fi
if [[ ! -r "$current/lib/client.sh" ]]; then
    echo "ERROR: $current/lib/client.sh is missing" >&2
    exit 1
fi

# shellcheck source=lib/client.sh
source "$current/lib/client.sh"
mtx_client_load_env "$root/etc/migratux/client.env" || exit 1
mtx_event firstboot "Erster Start: MigraTux richtet den PC ein"

# Newest scripts from the server; keep the installed ones if that fails.
tmp="$(mktemp -d)"
if curl -fsS -m 60 --retry 5 --retry-delay 3 -o "$tmp/bundle.tar.gz" "$MTX_URL/files/migratux-client.tar.gz" \
    && mkdir "$tmp/new" && tar -xzf "$tmp/bundle.tar.gz" -C "$tmp/new" \
    && [[ -r "$tmp/new/reconfigure/reconfigure.sh" ]]; then
    rm -rf "$current.old"
    mv "$current" "$current.old"
    mv "$tmp/new" "$current"
    mtx_clog "firstboot: scripts updated from the server"
else
    mtx_clog "firstboot: could not fetch new scripts, using the installed ones"
fi
rm -rf "$tmp"

bash "$current/reconfigure/reconfigure.sh"
rc=$?
case "$rc" in
    0|2) touch "$state/done" ;;
esac
mtx_clog "firstboot: reconfigure ended with exit code $rc"
exit "$rc"
