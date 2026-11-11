#!/usr/bin/env bats
# Single quotes are meant literally in this file (GRUB/shell text, stub bodies),
# and variables set inside a test are only needed in that test.
# shellcheck disable=SC2016,SC2030,SC2031
# Tests for server/setup.sh (config rendering) and server/migratux (CLI).
# Run: tests/run.sh bats

load helpers/common

setup() {
    make_server_env
    CLI="$ROOT/server/migratux"
    SETUP="$ROOT/server/setup.sh"
    HOSTS="$DATA/tftp/grub/hosts"
}

# ---- setup.sh: rendering ----

@test "setup --no-build renders every config file without leftover placeholders" {
    run "$SETUP" --no-build
    [ "$status" -eq 0 ]
    for f in conf/dnsmasq.conf conf/smb.conf tftp/grub/grub.cfg http/files/client.env http/autoinstall/user-data http/autoinstall/meta-data; do
        [ -f "$DATA/$f" ]
        run grep -c '@[A-Z_]*@' "$DATA/$f"
        [ "$output" = "0" ]
    done
    [ -s "$DATA/log/setup.log" ]
}

@test "dnsmasq accepts the rendered config and it is proxy-DHCP only" {
    "$SETUP" --no-build
    run dnsmasq --test --conf-file="$DATA/conf/dnsmasq.conf"
    [ "$status" -eq 0 ]
    grep -qx 'dhcp-range=192.168.80.10,proxy' "$DATA/conf/dnsmasq.conf"
    grep -qx 'port=0' "$DATA/conf/dnsmasq.conf"
    grep -qx 'interface=ens33' "$DATA/conf/dnsmasq.conf"
    grep -q 'bootx64.efi' "$DATA/conf/dnsmasq.conf"
}

@test "grub.cfg boots from disk by default and only installs with a job" {
    "$SETUP" --no-build
    local cfg="$DATA/tftp/grub/grub.cfg"
    grep -qx 'set default=local' "$cfg"
    grep -q 'hosts/\$net_default_mac.cfg' "$cfg"
    grep -q 'url=http://192.168.80.10:8080/ubuntu.iso' "$cfg"
    grep -q 'ds=nocloud-net;s=http://192.168.80.10:8080/autoinstall/' "$cfg"
    grep -q 'migratux.mode=\$mtx_mode migratux.host=\$mtx_host' "$cfg"
}

@test "grub.cfg and a job file are valid GRUB script" {
    "$SETUP" --no-build
    "$CLI" start 00:50:56:aa:bb:cc
    run grub-script-check "$DATA/tftp/grub/grub.cfg"
    [ "$status" -eq 0 ]
    run grub-script-check "$HOSTS/00:50:56:aa:bb:cc.cfg"
    [ "$status" -eq 0 ]
}

@test "smb.conf has the share and allows only the share user" {
    "$SETUP" --no-build
    grep -qx '\[migratux\]' "$DATA/conf/smb.conf"
    grep -q 'valid users = migratux' "$DATA/conf/smb.conf"
    grep -q 'map to guest = never' "$DATA/conf/smb.conf"
}

@test "client bundle holds the scripts the client needs" {
    "$SETUP" --no-build
    run tar -tzf "$DATA/http/files/migratux-client.tar.gz"
    [ "$status" -eq 0 ]
    for f in install/mtx-early.sh install/mtx-late.sh install/firstboot.sh install/migratux-firstboot.service \
             reconfigure/reconfigure.sh reconfigure/screen.sh mapping/map-apps.sh mapping/apps.csv \
             lib/client.sh lib/inventory.sh; do
        [[ "$output" == *"$f"* ]]
    done
}

@test "setup fails clearly when .env is missing or a value is empty or has a space" {
    MTX_ENV_FILE="$BATS_TEST_TMPDIR/nope.env" run "$SETUP" --no-build
    [ "$status" -eq 1 ]
    [[ "$output" == *".env.example"* ]]

    sed -i 's/^SMB_PASSWORD=.*/SMB_PASSWORD=/' "$MTX_ENV_FILE"
    run "$SETUP" --no-build
    [ "$status" -eq 1 ]
    [[ "$output" == *"SMB_PASSWORD is empty"* ]]

    sed -i 's/^SMB_PASSWORD=.*/SMB_PASSWORD="two words"/' "$MTX_ENV_FILE"
    run "$SETUP" --no-build
    [ "$status" -eq 1 ]
    [[ "$output" == *"SMB_PASSWORD"*"contains"* ]]
}

@test "mtx_render fails when a placeholder has no value" {
    source "$ROOT/server/lib.sh"
    echo 'ip=@SERVER_IP@ x=@NOT_SET_ANYWHERE@' > "$BATS_TEST_TMPDIR/t.tmpl"
    SERVER_IP=1.2.3.4
    run mtx_render "$BATS_TEST_TMPDIR/t.tmpl"
    [ "$status" -eq 1 ]
    [[ "$output" == *"NOT_SET_ANYWHERE"* ]]
}

@test "mtx_render keeps special characters of a value (password hash)" {
    source "$ROOT/server/lib.sh"
    echo 'password: "@ADMIN_PASSWORD_HASH@"' > "$BATS_TEST_TMPDIR/t.tmpl"
    export ADMIN_PASSWORD_HASH='$6$ab/cd$x&y|z\w.'
    [ "$(mtx_render "$BATS_TEST_TMPDIR/t.tmpl")" = 'password: "$6$ab/cd$x&y|z\w."' ]
}

# ---- migratux CLI ----

@test "status without clients says what to do first" {
    run "$CLI" status
    [ "$status" -eq 0 ]
    [[ "$output" == *"Noch keine Clients"* ]]
}

@test "start refuses an unknown host" {
    run "$CLI" start NOPE
    [ "$status" -eq 1 ]
    [[ "$output" == *"no client folder 'NOPE'"* ]]
}

@test "start refuses a host without a finished backup, unless --force" {
    make_client_folder "$DATA/share"
    rm "$DATA/share/KMU-PC01/manifest.sha256"
    run "$CLI" start KMU-PC01
    [ "$status" -eq 1 ]
    [[ "$output" == *"no finished backup"* ]]
    [ ! -e "$HOSTS/$FIXTURE_MAC.cfg" ]

    run "$CLI" start KMU-PC01 --force
    [ "$status" -eq 0 ]
    [ -e "$HOSTS/$FIXTURE_MAC.cfg" ]
}

@test "start writes a migrate job for the MAC of the inventory (host name case-insensitive)" {
    make_client_folder "$DATA/share"
    run "$CLI" start kmu-pc01
    [ "$status" -eq 0 ]
    [ "$(cat "$HOSTS/$FIXTURE_MAC.cfg")" = "$(printf 'set mtx_mode=migrate\nset mtx_host=KMU-PC01')" ]
    grep -q "start: KMU-PC01" "$DATA/log/migratux.log"
}

@test "start --no-image writes an install job" {
    make_client_folder "$DATA/share"
    "$CLI" start KMU-PC01 --no-image
    grep -qx 'set mtx_mode=install' "$HOSTS/$FIXTURE_MAC.cfg"
    grep -qx 'set mtx_host=KMU-PC01' "$HOSTS/$FIXTURE_MAC.cfg"
}

@test "start says that an existing disk image is kept; --new-image replaces it" {
    make_client_folder "$DATA/share"
    make_image
    run "$CLI" start KMU-PC01
    [ "$status" -eq 0 ]
    [[ "$output" == *"disk image from 2026-11-11 10:00:00 is KEPT"* ]]
    grep -qx 'set mtx_mode=migrate' "$HOSTS/$FIXTURE_MAC.cfg"

    "$CLI" start KMU-PC01 --new-image
    grep -qx 'set mtx_mode=migrate-new' "$HOSTS/$FIXTURE_MAC.cfg"
}

@test "start MAC writes an install job without host" {
    run "$CLI" start 00-50-56-AA-BB-CC
    [ "$status" -eq 0 ]
    grep -qx 'set mtx_mode=install' "$HOSTS/00:50:56:aa:bb:cc.cfg"
    grep -qx 'set mtx_host=' "$HOSTS/00:50:56:aa:bb:cc.cfg"
}

@test "config check: start warns about little RAM (fixture has 4 GB)" {
    make_client_folder "$DATA/share"
    run "$CLI" start KMU-PC01
    [ "$status" -eq 0 ]
    [[ "$output" == *"WARNING: PC has 4096 MB RAM"* ]]
}

@test "config check: start stops cleanly when the disk is too small" {
    make_client_folder "$DATA/share"
    sed -i 's/"C:","61440"/"C:","20000"/' "$DATA/share/KMU-PC01/inventory-KMU-PC01.csv"
    run "$CLI" start KMU-PC01
    [ "$status" -eq 1 ]
    [[ "$output" == *"config check: disk has only 20000 MB"* ]]
    [ ! -e "$HOSTS/$FIXTURE_MAC.cfg" ]

    run "$CLI" start KMU-PC01 --force
    [ "$status" -eq 0 ]
}

@test "rollback refuses a host without disk image" {
    make_client_folder "$DATA/share"
    run "$CLI" rollback KMU-PC01
    [ "$status" -eq 1 ]
    [[ "$output" == *"no finished disk image"* ]]
    [ ! -e "$HOSTS/$FIXTURE_MAC.cfg" ]
}

# A finished image as install/mtx-early.sh uploads it.
make_image() {
    mkdir -p "$DATA/images/KMU-PC01"
    echo "pretend this is a disk" > "$DATA/images/KMU-PC01/disk.img.zst"
    {
        echo "host=KMU-PC01"
        echo "ext=zst"
        echo "size_bytes=1000"
        echo "sha256=$(sha256sum "$DATA/images/KMU-PC01/disk.img.zst" | cut -d' ' -f1)"
        echo "date=2026-11-11 10:00:00"
    } > "$DATA/images/KMU-PC01/disk.info"
}

@test "rollback checks the image and writes a restore job" {
    make_client_folder "$DATA/share"
    make_image
    run "$CLI" rollback KMU-PC01
    [ "$status" -eq 0 ]
    [ "$(cat "$HOSTS/$FIXTURE_MAC.cfg")" = "$(printf 'set mtx_mode=restore\nset mtx_host=KMU-PC01')" ]
}

@test "rollback refuses a damaged image" {
    make_client_folder "$DATA/share"
    make_image
    echo "bit rot" >> "$DATA/images/KMU-PC01/disk.img.zst"
    run "$CLI" rollback KMU-PC01
    [ "$status" -eq 1 ]
    [[ "$output" == *"damaged"* ]]
    [ ! -e "$HOSTS/$FIXTURE_MAC.cfg" ]
}

@test "stop removes the job" {
    make_client_folder "$DATA/share"
    "$CLI" start KMU-PC01
    run "$CLI" stop KMU-PC01
    [ "$status" -eq 0 ]
    [ ! -e "$HOSTS/$FIXTURE_MAC.cfg" ]
    [[ "$output" == *"1 PXE job(s) removed"* ]]
}

@test "assign replaces the inventory MAC: the job goes only to the assigned MAC" {
    make_client_folder "$DATA/share"
    run "$CLI" assign KMU-PC01 00:50:56:11:22:33
    [ "$status" -eq 0 ]
    "$CLI" start KMU-PC01
    grep -qx 'set mtx_host=KMU-PC01' "$HOSTS/00:50:56:11:22:33.cfg"
    # The original Windows PC gets no job.
    [ ! -e "$HOSTS/$FIXTURE_MAC.cfg" ]

    run "$CLI" assign KMU-PC01 not-a-mac
    [ "$status" -eq 1 ]
}

@test "unassign goes back to the inventory MAC and removes the job of the assigned one" {
    make_client_folder "$DATA/share"
    "$CLI" assign KMU-PC01 00:50:56:11:22:33
    "$CLI" start KMU-PC01
    run "$CLI" unassign KMU-PC01
    [ "$status" -eq 0 ]
    [ ! -e "$HOSTS/00:50:56:11:22:33.cfg" ]
    [ ! -e "$DATA/share/_assign/00-50-56-11-22-33" ]
    "$CLI" start KMU-PC01
    [ -e "$HOSTS/$FIXTURE_MAC.cfg" ]
}

@test "status shows backup, image, job and the newest event" {
    make_client_folder "$DATA/share"
    make_image
    "$CLI" start KMU-PC01
    mkdir -p "$DATA/events/00-0c-29-ab-cd-ef"
    echo "Ubuntu wird installiert" > "$DATA/events/00-0c-29-ab-cd-ef/install"
    touch -d '10 minutes ago' "$DATA/events/00-0c-29-ab-cd-ef/install"
    echo "Programm 3 von 12: vlc" > "$DATA/events/00-0c-29-ab-cd-ef/apps"
    run "$CLI" status
    [ "$status" -eq 0 ]
    [[ "$output" == *"KMU-PC01"* ]]
    [[ "$output" == *"MAC:          $FIXTURE_MAC"* ]]
    [[ "$output" == *"Backup:       ja (4 Dateien)"* ]]
    [[ "$output" == *"Disk-Abbild:  ja"* ]]
    [[ "$output" == *"PXE-Job:      migrate"* ]]
    [[ "$output" == *"apps: Programm 3 von 12: vlc"* ]]
}

@test "status lists jobs of MACs without inventory" {
    "$CLI" start 00:50:56:aa:bb:cc
    run "$CLI" status
    [[ "$output" == *"00:50:56:aa:bb:cc (ohne Inventar)"* ]]
    [[ "$output" == *"PXE-Job:      install"* ]]
}

@test "status still lists a MAC without inventory after its job is done" {
    mkdir -p "$DATA/events/00-50-56-aa-bb-cc"
    echo "Ubuntu ist installiert, Neustart" > "$DATA/events/00-50-56-aa-bb-cc/installed"
    run "$CLI" status
    [ "$status" -eq 0 ]
    [[ "$output" == *"00:50:56:aa:bb:cc (ohne Inventar)"* ]]
    [[ "$output" == *"PXE-Job:      keiner"* ]]
    [[ "$output" == *"installed: Ubuntu ist installiert, Neustart"* ]]
}

@test "unknown command prints the usage and exits 2" {
    run "$CLI" frobnicate
    [ "$status" -eq 2 ]
    [[ "$output" == *"migratux status"* ]]
}
