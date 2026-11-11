#!/usr/bin/env bash
# Runs in the Ubuntu installer as an autoinstall late-command, after the
# system is installed to TARGET (normally /target) and before the reboot.
#
# - installs the MigraTux scripts and the first-boot hook into the new system
# - hands the network to NetworkManager (desktop)
# - removes the PXE job on the server, so the PC does not install again
#
# Usage: mtx-late.sh TARGET. Needs root. Log: /var/log/migratux-early.log,
# copied to TARGET/var/log/migratux/install.log.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/client.sh
source "$here/../lib/client.sh"

MTX_CLIENT_LOG="${MTX_CLIENT_LOG:-/var/log/migratux-early.log}"
target="${1:-}"
[[ -n "$target" && -d "$target" ]] || { echo "usage: mtx-late.sh TARGET" >&2; exit 2; }
bundle="$(cd "$here/.." && pwd)"

mtx_client_load_env "${MTX_CLIENT_ENV:-$bundle/client.env}"
mtx_clog "mtx-late: target=$target"

# Scripts: /opt/migratux/current (replaced by the newest bundle at first boot).
mkdir -p "$target/opt/migratux/current" "$target/etc/migratux" "$target/var/lib/migratux" \
         "$target/var/log/migratux" "$target/usr/local/sbin" "$target/etc/systemd/system/multi-user.target.wants"
for part in install reconfigure mapping lib; do
    rm -rf "$target/opt/migratux/current/$part"
    cp -a "$bundle/$part" "$target/opt/migratux/current/$part"
done
install -m 600 "$bundle/client.env" "$target/etc/migratux/client.env"
install -m 755 "$bundle/install/firstboot.sh" "$target/usr/local/sbin/migratux-firstboot"
install -m 644 "$bundle/install/migratux-firstboot.service" "$target/etc/systemd/system/migratux-firstboot.service"
ln -sf /etc/systemd/system/migratux-firstboot.service \
    "$target/etc/systemd/system/multi-user.target.wants/migratux-firstboot.service"

# The server installer configures systemd-networkd. A desktop needs NetworkManager.
mkdir -p "$target/etc/netplan" "$target/etc/cloud/cloud.cfg.d"
rm -f "$target"/etc/netplan/*.yaml
cat > "$target/etc/netplan/01-network-manager-all.yaml" <<'YAML'
# Written by MigraTux (install/mtx-late.sh).
network:
  version: 2
  renderer: NetworkManager
YAML
chmod 600 "$target/etc/netplan/01-network-manager-all.yaml"
echo 'network: {config: disabled}' > "$target/etc/cloud/cloud.cfg.d/99-migratux-no-network.cfg"

mtx_event installed "Ubuntu ist installiert, Neustart"
mtx_disarm || mtx_cdie "the PXE job on the server could not be removed. The PC would install again after the reboot. Run 'migratux stop <host>' on the server."

mtx_clog "mtx-late: done"
cp "$MTX_CLIENT_LOG" "$target/var/log/migratux/install.log" 2>/dev/null || true
