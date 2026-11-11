# Shared helpers for the bats tests. Load with: load helpers/common

ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
FIXTURE="$ROOT/tests/fixtures/inventory-sample.csv"
# MAC of the "Ethernet" adapter in the fixture.
export FIXTURE_MAC="00:0c:29:ab:cd:ef"

# Write a server .env into the test temp dir and point the scripts at it.
make_server_env() {
    export MTX_ENV_FILE="$BATS_TEST_TMPDIR/server.env"
    DATA="$BATS_TEST_TMPDIR/data"
    cat > "$MTX_ENV_FILE" <<ENV
SERVER_IP=192.168.80.10
PXE_INTERFACE=ens33
HTTP_PORT=8080
SHARE_NAME=migratux
SMB_USER=migratux
SMB_PASSWORD=Lab-Pass1
ADMIN_USER=mtxadmin
ADMIN_PASSWORD=Lab-Pass1
USER_PASSWORD=Willkommen1
DATA_DIR=$DATA
ISO_URL=
ENV
    mkdir -p "$DATA/share/_assign" "$DATA/tftp/grub/hosts" "$DATA/images" "$DATA/events"
}

# make_client_folder SHARE: a client folder like the Windows backup leaves it:
# inventory (fixture, host KMU-PC01, user mmueller), data, manifest.
make_client_folder() {
    local dir="$1/KMU-PC01"
    mkdir -p "$dir/data/mmueller/Documents/Unter ordner" "$dir/data/mmueller/Desktop" "$dir/data/mmueller/Pictures"
    cp "$FIXTURE" "$dir/inventory-KMU-PC01.csv"
    echo "Offerte für Herrn Müller" > "$dir/data/mmueller/Documents/Offerte_Müller.docx"
    echo "Bericht" > "$dir/data/mmueller/Documents/Unter ordner/Bericht 2025.txt"
    echo "Notiz" > "$dir/data/mmueller/Desktop/Notiz.txt"
    head -c 4096 /dev/urandom > "$dir/data/mmueller/Pictures/Foto #1.jpg"
    (cd "$dir" && find data -type f | LC_ALL=C sort | while IFS= read -r f; do sha256sum "$f"; done > manifest.sha256)
}

# make_stub NAME BODY...: put an executable NAME first in PATH. The body runs
# in bash; every call is logged to $STUB_LOG as "NAME args".
make_stub() {
    local name="$1"; shift
    STUB_DIR="$BATS_TEST_TMPDIR/stubs"
    export STUB_LOG="$BATS_TEST_TMPDIR/stubs.log"
    mkdir -p "$STUB_DIR"
    {
        echo '#!/usr/bin/env bash'
        echo "echo \"$name \$*\" >> \"\$STUB_LOG\""
        printf '%s\n' "$@"
    } > "$STUB_DIR/$name"
    chmod +x "$STUB_DIR/$name"
    case ":$PATH:" in
        *":$STUB_DIR:"*) ;;
        *) PATH="$STUB_DIR:$PATH" ;;
    esac
}

# Use the fake curl (helpers/bin/curl) with a "server" folder.
use_fake_curl() {
    export FAKE_SERVER="$BATS_TEST_TMPDIR/fakeserver"
    mkdir -p "$FAKE_SERVER"
    : > "$FAKE_SERVER/.log"
    PATH="$BATS_TEST_DIRNAME/helpers/bin:$PATH"
}

# make_fake_sys MAC: a /sys tree with one physical NIC, loopback and a bridge.
make_fake_sys() {
    export MTX_SYS="$BATS_TEST_TMPDIR/sys"
    mkdir -p "$MTX_SYS/class/net/lo" "$MTX_SYS/class/net/ens33/device" "$MTX_SYS/class/net/docker0"
    echo "00:00:00:00:00:00" > "$MTX_SYS/class/net/lo/address"
    echo "$1" > "$MTX_SYS/class/net/ens33/address"
    echo "02:42:aa:bb:cc:dd" > "$MTX_SYS/class/net/docker0/address"
}

# make_client_env FILE: what the server serves as /files/client.env.
make_client_env() {
    mkdir -p "$(dirname "$1")"
    cat > "$1" <<ENV
SERVER_IP=192.168.80.10
HTTP_PORT=8080
SHARE_NAME=migratux
SMB_USER=migratux
SMB_PASSWORD=Lab-Pass1
ADMIN_USER=mtxadmin
USER_PASSWORD=Willkommen1
ENV
}

# stub_calls REGEX: how many logged stub calls match (0 if no stub ran at all).
stub_calls() {
    if [[ -f "$STUB_LOG" ]]; then
        grep -c "$1" "$STUB_LOG" || true
    else
        echo 0
    fi
}
