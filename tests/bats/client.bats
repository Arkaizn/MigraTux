#!/usr/bin/env bats
# Single quotes are meant literally in this file (GRUB/shell text, stub bodies),
# and variables set inside a test are only needed in that test.
# shellcheck disable=SC2016,SC2030,SC2031
# Tests for the scripts that run on the client around the install:
# lib/client.sh, install/mtx-early.sh (disk image, rollback), install/mtx-late.sh,
# install/firstboot.sh. Disks are plain files, the server is a fake curl.
# Run: tests/run.sh bats

load helpers/common

setup() {
    use_fake_curl
    make_fake_sys "$FIXTURE_MAC"
    make_client_env "$BATS_TEST_TMPDIR/client.env"
    export MTX_CLIENT_ENV="$BATS_TEST_TMPDIR/client.env"
    export MTX_CLIENT_LOG="$BATS_TEST_TMPDIR/early.log"
    export MTX_RUN_DIR="$BATS_TEST_TMPDIR/run"
    export MTX_CMDLINE_FILE="$BATS_TEST_TMPDIR/cmdline"
    mkdir -p "$MTX_RUN_DIR"
    EARLY="$ROOT/install/mtx-early.sh"
    # A 3 MB "Windows disk" with random content.
    DISK="$BATS_TEST_TMPDIR/disk.bin"
    head -c 3145728 /dev/urandom > "$DISK"
    export MTX_DISK="$DISK"
    # blockdev cannot size a plain file.
    make_stub blockdev 'stat -c %s "$2"'
    make_stub sfdisk 'echo "label: gpt"'
    export MTX_REBOOT_DELAY=0 MTX_REBOOT_WAIT=0 MTX_REBOOT_CMD="touch $BATS_TEST_TMPDIR/rebooted"
}

cmdline() {
    echo "BOOT_IMAGE=/vmlinuz ip=dhcp url=http://192.168.80.10:8080/ubuntu.iso autoinstall $* ---" > "$MTX_CMDLINE_FILE"
}

# ---- lib/client.sh ----

@test "mtx_macs lists only physical network cards" {
    source "$ROOT/lib/client.sh"
    [ "$(mtx_macs)" = "$FIXTURE_MAC" ]
}

@test "mtx_cmdline_arg reads a value and gives nothing for a missing key" {
    source "$ROOT/lib/client.sh"
    cmdline migratux.mode=migrate migratux.host=KMU-PC01
    [ "$(mtx_cmdline_arg migratux.mode)" = "migrate" ]
    [ "$(mtx_cmdline_arg migratux.host)" = "KMU-PC01" ]
    [ -z "$(mtx_cmdline_arg migratux.other)" ]
}

@test "mtx_pick_disk takes the largest fixed disk" {
    source "$ROOT/lib/client.sh"
    unset MTX_DISK
    make_stub lsblk 'printf "sda 64424509440 disk 0\nsdb 128849018880 disk 1\nnvme0n1 256060514304 disk 0\nloop0 1000 loop 0\n"'
    [ "$(mtx_pick_disk)" = "/dev/nvme0n1" ]
}

@test "mtx_event sends the text to /events/<mac>/<step>" {
    source "$ROOT/lib/client.sh"
    mtx_client_load_env "$MTX_CLIENT_ENV"
    mtx_event apps "Programm 1 von 3"
    [ "$(cat "$FAKE_SERVER/events/00-0c-29-ab-cd-ef/apps")" = "Programm 1 von 3" ]
}

@test "mtx_event never fails, even when the server is down" {
    source "$ROOT/lib/client.sh"
    mtx_client_load_env "$MTX_CLIENT_ENV"
    FAKE_CURL_FAIL=. run mtx_event apps "x"
    [ "$status" -eq 0 ]
}

@test "mtx_disarm deletes the job and fails when the server is down" {
    source "$ROOT/lib/client.sh"
    mtx_client_load_env "$MTX_CLIENT_ENV"
    mkdir -p "$FAKE_SERVER/pxe/hosts"
    echo job > "$FAKE_SERVER/pxe/hosts/$FIXTURE_MAC.cfg"
    run mtx_disarm
    [ "$status" -eq 0 ]
    [ ! -e "$FAKE_SERVER/pxe/hosts/$FIXTURE_MAC.cfg" ]
    # No job any more (404) still counts: the server answered.
    run mtx_disarm
    [ "$status" -eq 0 ]
    FAKE_CURL_FAIL=. run mtx_disarm
    [ "$status" -eq 1 ]
}

# ---- install/mtx-early.sh ----

@test "early: without migratux.mode it refuses to touch the PC" {
    cmdline
    run bash "$EARLY"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Refusing to touch this PC"* ]]
    run grep -c 'PUT /images' "$FAKE_SERVER/.log"
    [ "$output" = "0" ]
}

@test "early: mode install reports the start and uploads no image" {
    cmdline migratux.mode=install
    run bash "$EARLY"
    [ "$status" -eq 0 ]
    grep -q 'PUT /events/00-0c-29-ab-cd-ef/install' "$FAKE_SERVER/.log"
    run grep -c 'PUT /images' "$FAKE_SERVER/.log"
    [ "$output" = "0" ]
}

@test "early: mode migrate without host fails" {
    cmdline migratux.mode=migrate
    run bash "$EARLY"
    [ "$status" -eq 1 ]
    [[ "$output" == *"needs migratux.host"* ]]
}

@test "early: mode migrate uploads a compressed image with a matching checksum" {
    cmdline migratux.mode=migrate migratux.host=KMU-PC01
    run bash "$EARLY"
    [ "$status" -eq 0 ]
    local dir="$FAKE_SERVER/images/KMU-PC01"
    [ -s "$dir/disk.img.zst" ]
    grep -qx 'ext=zst' "$dir/disk.info"
    grep -qx 'size_bytes=3145728' "$dir/disk.info"
    grep -qx "sha256=$(sha256sum "$dir/disk.img.zst" | cut -d' ' -f1)" "$dir/disk.info"
    # The image really is the disk.
    [ "$(zstd -d -c "$dir/disk.img.zst" | sha256sum)" = "$(sha256sum < "$DISK")" ]
    # The disk itself was only read.
    [ "$(stat -c %s "$DISK")" -eq 3145728 ]
}

@test "early: migrate keeps an image that is already on the server (failed install, second try)" {
    cmdline migratux.mode=migrate migratux.host=KMU-PC01
    bash "$EARLY"
    local first
    first="$(sha256sum < "$FAKE_SERVER/images/KMU-PC01/disk.img.zst")"
    # The half-installed disk must not replace the Windows image.
    head -c 3145728 /dev/zero > "$DISK"
    run bash "$EARLY"
    [ "$status" -eq 0 ]
    [[ "$output" == *"bleibt erhalten"* ]]
    [ "$(sha256sum < "$FAKE_SERVER/images/KMU-PC01/disk.img.zst")" = "$first" ]
}

@test "early: migrate-new replaces the image on the server" {
    cmdline migratux.mode=migrate migratux.host=KMU-PC01
    bash "$EARLY"
    local first
    first="$(sha256sum < "$FAKE_SERVER/images/KMU-PC01/disk.img.zst")"
    head -c 3145728 /dev/urandom > "$DISK"
    cmdline migratux.mode=migrate-new migratux.host=KMU-PC01
    run bash "$EARLY"
    [ "$status" -eq 0 ]
    [ "$(sha256sum < "$FAKE_SERVER/images/KMU-PC01/disk.img.zst")" != "$first" ]
    [ "$(zstd -d -c "$FAKE_SERVER/images/KMU-PC01/disk.img.zst" | sha256sum)" = "$(sha256sum < "$DISK")" ]
}

@test "early: a failed image upload stops before the install (exit 1)" {
    cmdline migratux.mode=migrate migratux.host=KMU-PC01
    FAKE_CURL_FAIL='/images/' run bash "$EARLY"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Nothing was wiped"* ]]
    [ ! -e "$FAKE_SERVER/images/KMU-PC01/disk.info" ]
}

@test "early: migrate then restore brings back the identical disk, removes the job, reboots" {
    cmdline migratux.mode=migrate migratux.host=KMU-PC01
    bash "$EARLY"
    local before
    before="$(sha256sum < "$DISK")"

    # The "failed install" overwrites the disk.
    head -c 3145728 /dev/zero > "$DISK"
    mkdir -p "$FAKE_SERVER/pxe/hosts"
    echo job > "$FAKE_SERVER/pxe/hosts/$FIXTURE_MAC.cfg"

    cmdline migratux.mode=restore migratux.host=KMU-PC01
    run bash "$EARLY"
    # Exit 1 on purpose: after the reboot command the script must never
    # return 0, or the installer would go on and wipe the restored disk.
    [ "$status" -eq 1 ]
    [ "$(sha256sum < "$DISK")" = "$before" ]
    [ ! -e "$FAKE_SERVER/pxe/hosts/$FIXTURE_MAC.cfg" ]
    [ -e "$BATS_TEST_TMPDIR/rebooted" ]
    [ -e "$FAKE_SERVER/events/00-0c-29-ab-cd-ef/restored" ]
}

@test "early: restore detects a damaged image and does not reboot" {
    cmdline migratux.mode=migrate migratux.host=KMU-PC01
    bash "$EARLY"
    sed -i 's/^sha256=.*/sha256=0000/' "$FAKE_SERVER/images/KMU-PC01/disk.info"
    cmdline migratux.mode=restore migratux.host=KMU-PC01
    run bash "$EARLY"
    [ "$status" -eq 1 ]
    [[ "$output" == *"checksum is wrong"* ]]
    [ ! -e "$BATS_TEST_TMPDIR/rebooted" ]
}

@test "early: restore refuses a disk that is smaller than the image" {
    cmdline migratux.mode=migrate migratux.host=KMU-PC01
    bash "$EARLY"
    head -c 1048576 /dev/zero > "$DISK"
    cmdline migratux.mode=restore migratux.host=KMU-PC01
    run bash "$EARLY"
    [ "$status" -eq 1 ]
    [[ "$output" == *"smaller than the image"* ]]
    # Nothing was written.
    [ "$(stat -c %s "$DISK")" -eq 1048576 ]
}

@test "early: restore without an image on the server fails" {
    cmdline migratux.mode=restore migratux.host=KMU-PC01
    run bash "$EARLY"
    [ "$status" -eq 1 ]
    [[ "$output" == *"no disk image for KMU-PC01"* ]]
}

# ---- install/mtx-late.sh ----

# A bundle as the early-commands unpack it to /run/migratux.
make_bundle() {
    BUNDLE="$BATS_TEST_TMPDIR/bundle"
    mkdir -p "$BUNDLE"
    cp -r "$ROOT/install" "$ROOT/reconfigure" "$ROOT/mapping" "$ROOT/lib" "$BUNDLE/"
    make_client_env "$BUNDLE/client.env"
    unset MTX_CLIENT_ENV
}

@test "late: installs scripts, first-boot unit and NetworkManager config into the target" {
    make_bundle
    local target="$BATS_TEST_TMPDIR/target"
    mkdir -p "$target/etc/netplan"
    echo "network: {version: 2}" > "$target/etc/netplan/50-cloud-init.yaml"
    mkdir -p "$FAKE_SERVER/pxe/hosts"
    echo job > "$FAKE_SERVER/pxe/hosts/$FIXTURE_MAC.cfg"

    run bash "$BUNDLE/install/mtx-late.sh" "$target"
    [ "$status" -eq 0 ]
    [ -x "$target/usr/local/sbin/migratux-firstboot" ]
    [ -f "$target/opt/migratux/current/reconfigure/reconfigure.sh" ]
    [ -f "$target/opt/migratux/current/mapping/apps.csv" ]
    [ "$(stat -c %a "$target/etc/migratux/client.env")" = "600" ]
    [ -L "$target/etc/systemd/system/multi-user.target.wants/migratux-firstboot.service" ]
    [ ! -e "$target/etc/netplan/50-cloud-init.yaml" ]
    grep -q 'renderer: NetworkManager' "$target/etc/netplan/01-network-manager-all.yaml"
    # The PXE job is gone, so the PC does not install again.
    [ ! -e "$FAKE_SERVER/pxe/hosts/$FIXTURE_MAC.cfg" ]
    [ -s "$target/var/log/migratux/install.log" ]
}

@test "late: fails when the PXE job cannot be removed (would install again)" {
    make_bundle
    mkdir -p "$BATS_TEST_TMPDIR/target"
    FAKE_CURL_FAIL='/pxe/hosts/' run bash "$BUNDLE/install/mtx-late.sh" "$BATS_TEST_TMPDIR/target"
    [ "$status" -eq 1 ]
    [[ "$output" == *"could not be removed"* ]]
}

# ---- install/firstboot.sh ----

# An installed client under MTX_ROOT whose reconfigure.sh exits with $1.
make_installed() {
    export MTX_ROOT="$BATS_TEST_TMPDIR/root"
    mkdir -p "$MTX_ROOT/opt/migratux/current/lib" "$MTX_ROOT/opt/migratux/current/reconfigure" "$MTX_ROOT/etc/migratux"
    cp "$ROOT/lib/client.sh" "$MTX_ROOT/opt/migratux/current/lib/"
    printf '#!/usr/bin/env bash\necho reconfigure-ran\nexit %s\n' "$1" > "$MTX_ROOT/opt/migratux/current/reconfigure/reconfigure.sh"
    make_client_env "$MTX_ROOT/etc/migratux/client.env"
    unset MTX_CLIENT_LOG
}

@test "firstboot: runs reconfigure and marks itself done" {
    make_installed 0
    run bash "$ROOT/install/firstboot.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"reconfigure-ran"* ]]
    [ -e "$MTX_ROOT/var/lib/migratux/done" ]

    run bash "$ROOT/install/firstboot.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"already ran"* ]]
    [[ "$output" != *"reconfigure-ran"* ]]

    run bash "$ROOT/install/firstboot.sh" --force
    [[ "$output" == *"reconfigure-ran"* ]]
}

@test "firstboot: a fatal reconfigure error is not marked done (runs again next boot)" {
    make_installed 1
    run bash "$ROOT/install/firstboot.sh"
    [ "$status" -eq 1 ]
    [ ! -e "$MTX_ROOT/var/lib/migratux/done" ]
}

@test "firstboot: exit 2 (data check failed) is passed on but marked done" {
    make_installed 2
    run bash "$ROOT/install/firstboot.sh"
    [ "$status" -eq 2 ]
    [ -e "$MTX_ROOT/var/lib/migratux/done" ]
}

@test "firstboot: takes newer scripts from the server" {
    make_installed 1
    local new="$BATS_TEST_TMPDIR/new"
    mkdir -p "$new/reconfigure" "$new/lib" "$FAKE_SERVER/files"
    cp "$ROOT/lib/client.sh" "$new/lib/"
    printf '#!/usr/bin/env bash\necho new-version\nexit 0\n' > "$new/reconfigure/reconfigure.sh"
    tar -czf "$FAKE_SERVER/files/migratux-client.tar.gz" -C "$new" reconfigure lib
    run bash "$ROOT/install/firstboot.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"new-version"* ]]
}
