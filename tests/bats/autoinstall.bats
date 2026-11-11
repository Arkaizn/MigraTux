#!/usr/bin/env bats
# Single quotes are meant literally in this file (GRUB/shell text, stub bodies),
# and variables set inside a test are only needed in that test.
# shellcheck disable=SC2016,SC2030,SC2031
# Tests for the rendered Ubuntu autoinstall file (install/user-data.tmpl) and
# the first-boot unit. The real install can only be tested on a VM
# (docs/testing/M4-autoinstall.md). Run: tests/run.sh bats

load helpers/common

setup() {
    make_server_env
    "$ROOT/server/setup.sh" --no-build >/dev/null
    USERDATA="$DATA/http/autoinstall/user-data"
}

# Evaluate a Python expression on the parsed autoinstall section (variable a).
ai() {
    python3 -c '
import sys, yaml
a = yaml.safe_load(open(sys.argv[1]))["autoinstall"]
print(eval(sys.argv[2]))' "$USERDATA" "$1"
}

@test "user-data starts with #cloud-config and is valid YAML" {
    [ "$(head -n 1 "$USERDATA")" = "#cloud-config" ]
    [ "$(ai 'a["version"]')" = "1" ]
}

@test "locale, keyboard and time zone are Swiss German" {
    [ "$(ai 'a["locale"]')" = "de_CH.UTF-8" ]
    [ "$(ai 'a["keyboard"]["layout"]')" = "ch" ]
    [ "$(ai 'a["timezone"]')" = "Europe/Zurich" ]
}

@test "identity has the admin user with a SHA-512 password hash, not the clear password" {
    [ "$(ai 'a["identity"]["username"]')" = "mtxadmin" ]
    [[ "$(ai 'a["identity"]["password"]')" == '$6$'* ]]
    run grep -c 'Lab-Pass1' "$USERDATA"
    [ "$output" = "0" ]
}

@test "the hash matches ADMIN_PASSWORD" {
    local hash salt
    hash="$(ai 'a["identity"]["password"]')"
    salt="$(echo "$hash" | cut -d'$' -f3)"
    [ "$(openssl passwd -6 -salt "$salt" Lab-Pass1)" = "$hash" ]
}

@test "SSH server, whole-disk layout, desktop packages, reboot at the end" {
    [ "$(ai 'a["ssh"]["install-server"]')" = "True" ]
    [ "$(ai 'a["storage"]["layout"]["name"]')" = "direct" ]
    [ "$(ai '"ubuntu-desktop-minimal" in a["packages"]')" = "True" ]
    [ "$(ai '"cifs-utils" in a["packages"] and "flatpak" in a["packages"]')" = "True" ]
    [ "$(ai 'a["shutdown"]')" = "reboot" ]
}

@test "no interactive sections: the install asks nothing" {
    [ "$(ai '"interactive-sections" in a')" = "False" ]
}

@test "early-commands fetch the bundle from the server and run mtx-early.sh last" {
    [ "$(ai 'all(isinstance(c, str) for c in a["early-commands"])')" = "True" ]
    [ "$(ai 'any("http://192.168.80.10:8080/files/migratux-client.tar.gz" in c for c in a["early-commands"])')" = "True" ]
    [ "$(ai 'a["early-commands"][-1]')" = "bash /run/migratux/install/mtx-early.sh" ]
}

@test "late-commands run mtx-late.sh on /target" {
    [ "$(ai 'a["late-commands"]')" = "['bash /run/migratux/install/mtx-late.sh /target']" ]
}

@test "first-boot unit runs once, before the login screen, after the network" {
    local unit="$ROOT/install/migratux-firstboot.service"
    grep -qx 'ConditionPathExists=!/var/lib/migratux/done' "$unit"
    grep -qx 'Before=display-manager.service getty@tty1.service' "$unit"
    grep -qx 'After=network-online.target' "$unit"
    grep -qx 'ExecStart=/usr/local/sbin/migratux-firstboot' "$unit"
    grep -qx 'Type=oneshot' "$unit"
}
