#!/usr/bin/env bats
# Single quotes are meant literally in this file (GRUB/shell text, stub bodies),
# and variables set inside a test are only needed in that test.
# shellcheck disable=SC2016,SC2030,SC2031
# Tests for reconfigure/reconfigure.sh and reconfigure/screen.sh: a whole run
# against a prepared "server share" in a temp folder. apt, flatpak, useradd
# etc. are stubs, so nothing is installed. Run: tests/run.sh bats

load helpers/common

setup() {
    use_fake_curl
    make_fake_sys "$FIXTURE_MAC"
    export MTX_ROOT="$BATS_TEST_TMPDIR/root"
    export MTX_SKIP_MOUNT=1 MTX_HOLD_SECONDS=0 MTX_TTY=""
    SHARE="$MTX_ROOT/mnt/migratux"
    mkdir -p "$SHARE/_assign" "$MTX_ROOT/home" "$MTX_ROOT/etc"
    make_client_env "$MTX_ROOT/etc/migratux/client.env"
    make_client_folder "$SHARE"
    echo "127.0.0.1 localhost" > "$MTX_ROOT/etc/hosts"
    RC="$ROOT/reconfigure/reconfigure.sh"
    REPORT="$MTX_ROOT/var/log/migratux/report.txt"
    HOME_MM="$MTX_ROOT/home/mmueller"

    make_stub apt-get 'if [[ -n "${STUB_APT_FAIL:-}" && " $* " == *" $STUB_APT_FAIL "* ]]; then exit 100; fi'
    make_stub flatpak ''
    make_stub useradd 'for last; do :; done; mkdir -p "$MTX_ROOT/home/$last"'
    make_stub id '[[ -d "$MTX_ROOT/home/$2" ]]'
    make_stub chpasswd 'cat >> "$STUB_LOG"'
    make_stub chage ''
    make_stub chown ''
    make_stub hostnamectl ''
    make_stub plymouth ''
    make_stub chvt ''
}

@test "full run: exit 0, apps installed, data restored and verified, report written" {
    run bash "$RC"
    [ "$status" -eq 0 ]

    # Apps from the fixture, mapped by mapping/apps.csv.
    grep -q '^apt-get .*install -y libreoffice$' "$STUB_LOG"
    grep -q '^flatpak install .*com.google.Chrome$' "$STUB_LOG"
    grep -q '^flatpak remote-add .*flathub' "$STUB_LOG"

    # User and data, umlauts and spaces in names intact.
    grep -q '^useradd .* mmueller$' "$STUB_LOG"
    grep -qx 'mmueller:Willkommen1' "$STUB_LOG"
    grep -q '^chage -d 0 mmueller$' "$STUB_LOG"
    [ "$(cat "$HOME_MM/Documents/Offerte_Müller.docx")" = "Offerte für Herrn Müller" ]
    [ -f "$HOME_MM/Documents/Unter ordner/Bericht 2025.txt" ]
    [ -f "$HOME_MM/Pictures/Foto #1.jpg" ]
    [ -d "$HOME_MM/Downloads" ]
    grep -q 'XDG_DOCUMENTS_DIR="$HOME/Documents"' "$HOME_MM/.config/user-dirs.dirs"

    # Report: locally, on the server and on the user's desktop.
    grep -q 'Prüfung: OK, 4 von 4 Dateien' "$REPORT"
    cmp "$REPORT" "$SHARE/KMU-PC01/report.txt"
    cmp "$REPORT" "$HOME_MM/Desktop/MigraTux-Bericht.txt"
    [ -s "$SHARE/KMU-PC01/reconfigure.log" ]
}

@test "the report sorts the apps: installed, WinBoat, unknown, nothing to install" {
    bash "$RC"
    # Print the lines of one report section.
    section() { awk -v s="$1" '/^== / { on = index($0, s) > 0 } on' "$REPORT"; }
    section "installiert" | grep -q 'Microsoft 365 Apps for business - de-ch  ->  LibreOffice (apt: libreoffice)'
    section "WinBoat" | grep -q 'Abacus ERP Client'
    section "unbekannt" | grep -q 'Kassenbuch Müller Spezial'
    section "nichts zu installieren" | grep -q 'Microsoft Edge WebView2 Runtime'
    section "Von Hand" | grep -q 'Drucker: HP LaserJet, Büro 1 (IP_192.168.1.50)'
    section "Von Hand" | grep -q 'Netzlaufwerk: Z: \\\\nas01\\Buchhaltung'
    section "Nächste Schritte" | grep -q 'Netzwerk-Boot (PXE)'
    section "FEHLGESCHLAGEN (0)" | grep -q 'FEHLGESCHLAGEN (0)'
}

@test "each package is installed once, even when several apps map to it" {
    # Add a second Office product: both map to libreoffice.
    sed -i '2a "KMU-PC01","app","Microsoft Office Professional Plus 2019","16.0","Microsoft Corporation","","","scope=machine;arch=x64"' \
        "$SHARE/KMU-PC01/inventory-KMU-PC01.csv"
    bash "$RC"
    [ "$(grep -c '^apt-get .*install -y libreoffice$' "$STUB_LOG")" -eq 1 ]
}

@test "a failing package is reported, the rest goes on (exit 0)" {
    STUB_APT_FAIL=libreoffice run bash "$RC"
    [ "$status" -eq 0 ]
    grep -q 'FEHLGESCHLAGEN (1)' "$REPORT"
    awk '/FEHLGESCHLAGEN/ { on = 1; next } /^== / { on = 0 } on' "$REPORT" | grep -q 'libreoffice'
    grep -q 'Prüfung: OK' "$REPORT"
}

@test "a file that differs from the manifest gives exit 2 and a clear report" {
    echo "kaputt" > "$SHARE/KMU-PC01/data/mmueller/Desktop/Notiz.txt"
    run bash "$RC"
    [ "$status" -eq 2 ]
    grep -q 'Prüfung: FEHLER, 1 von 4 Dateien' "$REPORT"
    grep -q 'Desktop/Notiz.txt: FAILED' "$MTX_ROOT/var/log/migratux/verify.failed"
    grep -q 'PUT /events/00-0c-29-ab-cd-ef/finished-with-errors' "$FAKE_SERVER/.log"
}

@test "a file missing in the backup gives exit 2" {
    rm "$SHARE/KMU-PC01/data/mmueller/Pictures/Foto #1.jpg"
    run bash "$RC"
    [ "$status" -eq 2 ]
    grep -q 'Prüfung: FEHLER, 1 von 4 Dateien' "$REPORT"
}

@test "unknown PC (no inventory with this MAC): exit 1, nothing installed" {
    make_fake_sys "00:50:56:99:99:99"
    run bash "$RC"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Kein Inventar für diesen PC"* ]]
    [[ "$output" == *"migratux assign"* ]]
    [ "$(stub_calls '^apt-get')" -eq 0 ]
    [ "$(stub_calls '^useradd')" -eq 0 ]
    grep -q 'PUT /events/00-50-56-99-99-99/failed' "$FAKE_SERVER/.log"
}

@test "a manual assignment on the server maps another MAC to the host" {
    make_fake_sys "00:50:56:99:99:99"
    echo "KMU-PC01" > "$SHARE/_assign/00-50-56-99-99-99"
    run bash "$RC"
    [ "$status" -eq 0 ]
    [ -f "$HOME_MM/Desktop/Notiz.txt" ]
}

@test "no finished backup (manifest missing): exit 1 before anything is installed" {
    rm "$SHARE/KMU-PC01/manifest.sha256"
    run bash "$RC"
    [ "$status" -eq 1 ]
    [[ "$output" == *"manifest.sha256 fehlt"* ]]
    [ "$(stub_calls '^apt-get')" -eq 0 ]
    [ "$(stub_calls '^useradd')" -eq 0 ]
}

@test "progress is reported to the server step by step" {
    bash "$RC"
    for step in connect apps data verify report finished; do
        grep -q "PUT /events/00-0c-29-ab-cd-ef/$step" "$FAKE_SERVER/.log"
    done
    grep -q 'Fertig: 4 Dateien geprüft, 0 Programme fehlgeschlagen' "$FAKE_SERVER/events/00-0c-29-ab-cd-ef/finished"
}

@test "the hostname becomes the Windows name in lower case" {
    bash "$RC"
    grep -q '^hostnamectl set-hostname kmu-pc01$' "$STUB_LOG"
    grep -q '127.0.1.1 kmu-pc01' "$MTX_ROOT/etc/hosts"
}

@test "rc_linux_user makes valid login names" {
    # shellcheck source=reconfigure/reconfigure.sh
    source "$RC"
    [ "$(rc_linux_user 'MMueller')" = "mmueller" ]
    [ "$(rc_linux_user 'Max Muster')" = "max_muster" ]
    [ "$(rc_linux_user '1user')" = "user" ]
    [ "$(rc_linux_user '###')" = "benutzer" ]
}

# ---- screen.sh ----

@test "screen shows steps, state marks, ETA and the next steps" {
    source "$ROOT/reconfigure/screen.sh"
    USER_PASSWORD=Willkommen1
    screen_add connect "Verbindung zum MigraTux-Server" 15
    screen_add apps "Programme installieren" 600
    screen_add data "Daten zurückspielen" 120
    SCREEN_HOST="KMU-PC01"
    screen_set connect ok
    screen_set apps run
    SCREEN_NOTE="Programm 3 von 12: vlc"
    run screen_render
    [[ "$output" == *"PC: KMU-PC01"* ]]
    [[ "$output" == *"[x] Verbindung zum MigraTux-Server"* ]]
    [[ "$output" == *"[>] Programme installieren"* ]]
    [[ "$output" == *"[ ] Daten zurückspielen"* ]]
    [[ "$output" == *"Aktuell:  Programm 3 von 12: vlc"* ]]
    [[ "$output" == *"Restzeit: ca. 12 Minuten"* ]]
    [[ "$output" == *"Netzwerk-Boot (PXE) im BIOS/UEFI wieder ausschalten"* ]]
    [[ "$output" == *"Startpasswort: Willkommen1"* ]]
}

@test "screen ETA counts only unfinished steps and ends below one minute" {
    source "$ROOT/reconfigure/screen.sh"
    screen_add a "A" 100
    screen_add b "B" 50
    [ "$(screen_eta_seconds)" -eq 150 ]
    screen_set a ok
    [ "$(screen_eta_seconds)" -eq 50 ]
    [ "$(screen_eta_text)" = "weniger als 1 Minute" ]
    screen_set b fail
    [ "$(screen_eta_seconds)" -eq 0 ]
}
