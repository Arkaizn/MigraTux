#!/usr/bin/env bash
# MigraTux reconfigure (M5): runs once on the freshly installed Linux PC,
# started by install/firstboot.sh.
#
#   1. mount the server share and find this PC's folder (by MAC address)
#   2. install the Linux alternatives for the Windows apps (apt, flatpak)
#   3. create the Windows users and restore their folders
#   4. check every restored file against the backup manifest (SHA-256)
#   5. write a report: installed, no alternative (WinBoat), failed, to do by hand
#
# Needs root. Config: /etc/migratux/client.env.
# Log:    /var/log/migratux/reconfigure.log   (copy on the server: <HOST>/reconfigure.log)
# Report: /var/log/migratux/report.txt        (copy on the server: <HOST>/report.txt)
# Exit: 0 ok (single apps may have failed, see the report)
#       1 fatal: server not reachable, PC not found, no backup
#       2 finished, but restored files do not match the manifest
#
# Test hooks: MTX_ROOT (prefix for all local paths), MTX_SKIP_MOUNT=1,
# MTX_SYS, MTX_MAC, MTX_TTY, MTX_HOLD_SECONDS.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/inventory.sh
source "$here/../lib/inventory.sh"
# shellcheck source=lib/client.sh
source "$here/../lib/client.sh"
# shellcheck source=reconfigure/screen.sh
source "$here/screen.sh"

RC_ROOT="${MTX_ROOT:-}"
RC_LOG_DIR="$RC_ROOT/var/log/migratux"
RC_MNT="$RC_ROOT/mnt/migratux"
RC_HOME="$RC_ROOT/home"
RC_REPORT="$RC_LOG_DIR/report.txt"
RC_MAP="$here/../mapping/map-apps.sh"

RC_HOSTDIR=""
RC_HOST=""
RC_INV=""
declare -A RC_USERMAP=()        # windows user -> linux user
declare -A RC_PKG_STATE=()      # "apt:vlc" -> ok | failed
RC_APT=()
RC_FLATPAK=()
RC_RESTORED=()                  # "user/Folder" lines for the report
RC_VERIFY_TOTAL=0
RC_VERIFY_BAD=0
RC_FAILED_STEP=""

# ---- small helpers ----

rc_step() {
    # rc_step ID NOTE: mark a step as running and tell screen + server.
    RC_FAILED_STEP="$1"
    SCREEN_NOTE="$2"
    screen_set "$1" run
    screen_show
    mtx_clog "step $1: $2"
    mtx_event "$1" "$2 (Restzeit $(screen_eta_text))"
}

rc_done() {
    screen_set "$1" ok
    screen_show
}

rc_fatal() {
    if [[ -n "$RC_FAILED_STEP" ]]; then
        screen_set "$RC_FAILED_STEP" fail
    fi
    SCREEN_NOTE="FEHLER: $*"
    screen_show
    mtx_cdie "$*"
}

# Linux login name for a Windows user name: lowercase, a-z 0-9 _ - only.
rc_linux_user() {
    local name
    name="$(printf '%s' "$1" | LC_ALL=C tr '[:upper:]' '[:lower:]' | LC_ALL=C sed 's/[^a-z0-9_-]\{1,\}/_/g; s/^[^a-z]*//; s/_*$//')"
    name="${name:0:31}"
    [[ -n "$name" ]] || name="benutzer"
    echo "$name"
}

# ---- step 1: server share and client folder ----

rc_mount_share() {
    mkdir -p "$RC_MNT"
    if [[ "${MTX_SKIP_MOUNT:-0}" == 1 ]] || mountpoint -q "$RC_MNT"; then
        return 0
    fi
    local cred="$RC_ROOT/etc/migratux/smb.cred" try
    (umask 077; printf 'username=%s\npassword=%s\n' "$SMB_USER" "$SMB_PASSWORD" > "$cred")
    for try in 1 2 3 4 5 6; do
        if mount -t cifs "//$SERVER_IP/$SHARE_NAME" "$RC_MNT" \
            -o "credentials=$cred,vers=3.0,iocharset=utf8,file_mode=0644,dir_mode=0755" 2>>"$MTX_CLIENT_LOG"; then
            return 0
        fi
        mtx_clog "share //$SERVER_IP/$SHARE_NAME not reachable yet (try $try of 6)"
        sleep "${MTX_RETRY_SECONDS:-10}"
    done
    return 1
}

# Find the client folder whose inventory (or manual assignment) has one of our MACs.
rc_find_host() {
    local mac f dir host
    local -a macs
    mapfile -t macs < <(mtx_macs)
    [[ ${#macs[@]} -gt 0 ]] || return 1
    for mac in "${macs[@]}"; do
        f="$RC_MNT/_assign/${mac//:/-}"
        if [[ -r "$f" ]]; then
            host="$(tr -d '\r\n' < "$f")"
            if [[ -d "$RC_MNT/$host" ]]; then
                RC_HOSTDIR="$RC_MNT/$host"
                MTX_MAC="$mac"
                return 0
            fi
        fi
    done
    for dir in "$RC_MNT"/*/; do
        dir="${dir%/}"
        [[ "$(basename "$dir")" == _* ]] && continue
        for f in "$dir"/inventory-*.csv; do
            [[ -r "$f" ]] || continue
            for mac in "${macs[@]}"; do
                if inv_macs "$f" | grep -qx "$mac"; then
                    RC_HOSTDIR="$dir"
                    MTX_MAC="$mac"
                    return 0
                fi
            done
        done
    done
    return 1
}

rc_set_hostname() {
    local name
    name="$(printf '%s' "$RC_HOST" | LC_ALL=C tr '[:upper:]' '[:lower:]' | LC_ALL=C sed 's/[^a-z0-9-]/-/g')"
    hostnamectl set-hostname "$name" 2>>"$MTX_CLIENT_LOG" || mtx_clog "WARNING: could not set the hostname to $name"
    if [[ -w "$RC_ROOT/etc/hosts" ]] && ! grep -q "[[:space:]]$name\$" "$RC_ROOT/etc/hosts"; then
        echo "127.0.1.1 $name" >> "$RC_ROOT/etc/hosts"
    fi
}

# ---- step 2: apps ----

# The mapped apps (apps.tsv without header), empty fields written as "-",
# because `read` merges empty tab-separated fields.
rc_app_lines() {
    tail -n +2 "$RC_LOG_DIR/apps.tsv" | awk -F'\t' -v OFS='\t' '{ for (i = 2; i <= 5; i++) if ($i == "") $i = "-"; print }'
}

# Fill RC_APT / RC_FLATPAK (unique packages) from the mapping.
rc_plan_apps() {
    local source package
    RC_APT=(); RC_FLATPAK=()
    "$RC_MAP" "$RC_INV" > "$RC_LOG_DIR/apps.tsv"
    while IFS=$'\t' read -r _ _ source package _; do
        [[ "$package" != "-" ]] || continue
        case "$source" in
            apt)     [[ " ${RC_APT[*]} " == *" $package "* ]] || RC_APT+=("$package") ;;
            flatpak) [[ " ${RC_FLATPAK[*]} " == *" $package "* ]] || RC_FLATPAK+=("$package") ;;
        esac
    done < <(rc_app_lines)
}

rc_install_apps() {
    local pkg n=0 total=$(( ${#RC_APT[@]} + ${#RC_FLATPAK[@]} ))
    export DEBIAN_FRONTEND=noninteractive
    if [[ ${#RC_APT[@]} -gt 0 ]]; then
        apt-get -o DPkg::Lock::Timeout=900 update >>"$MTX_CLIENT_LOG" 2>&1 || mtx_clog "WARNING: apt-get update failed"
    fi
    for pkg in "${RC_APT[@]}"; do
        n=$((n + 1))
        rc_step apps "Programm $n von $total: $pkg"
        if apt-get -o DPkg::Lock::Timeout=900 install -y "$pkg" >>"$MTX_CLIENT_LOG" 2>&1; then
            RC_PKG_STATE["apt:$pkg"]=ok
        else
            RC_PKG_STATE["apt:$pkg"]=failed
            mtx_clog "FAILED apt package $pkg"
        fi
        screen_set apps run $(( (total - n) * 90 ))
    done
    if [[ ${#RC_FLATPAK[@]} -gt 0 ]]; then
        flatpak remote-add --system --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo \
            >>"$MTX_CLIENT_LOG" 2>&1 || mtx_clog "WARNING: could not add the Flathub remote"
    fi
    for pkg in "${RC_FLATPAK[@]}"; do
        n=$((n + 1))
        rc_step apps "Programm $n von $total: $pkg"
        if flatpak install --system --noninteractive -y flathub "$pkg" >>"$MTX_CLIENT_LOG" 2>&1; then
            RC_PKG_STATE["flatpak:$pkg"]=ok
        else
            RC_PKG_STATE["flatpak:$pkg"]=failed
            mtx_clog "FAILED flatpak app $pkg"
        fi
        screen_set apps run $(( (total - n) * 90 ))
    done
}

# ---- step 3: users and data ----

rc_ensure_user() {
    local win="$1" user="$2"
    if id -u "$user" >/dev/null 2>&1; then
        return 0
    fi
    useradd -m -s /bin/bash -c "$win" "$user" >>"$MTX_CLIENT_LOG" 2>&1 || return 1
    echo "$user:$USER_PASSWORD" | chpasswd >>"$MTX_CLIENT_LOG" 2>&1 || return 1
    # The start password must be changed at the first login.
    chage -d 0 "$user" >>"$MTX_CLIENT_LOG" 2>&1 || true
}

# Use the English folder names (Documents, Pictures, ...) for the restored
# data, also on a German desktop, so paths match the Windows ones.
rc_write_user_dirs() {
    local home="$1" user="$2"
    mkdir -p "$home/.config"
    cat > "$home/.config/user-dirs.dirs" <<'EOF'
XDG_DESKTOP_DIR="$HOME/Desktop"
XDG_DOCUMENTS_DIR="$HOME/Documents"
XDG_PICTURES_DIR="$HOME/Pictures"
XDG_DOWNLOAD_DIR="$HOME/Downloads"
XDG_MUSIC_DIR="$HOME/Music"
XDG_VIDEOS_DIR="$HOME/Videos"
EOF
    chown -R "$user:" "$home/.config" 2>>"$MTX_CLIENT_LOG" || true
}

rc_restore_data() {
    local name extra win user src dest count
    while IFS="$INV_SEP" read -r name _ _ _ _ extra; do
        win="$(inv_extra user "$extra")" || continue
        [[ "$name" != */* && "$name" != .* && "$win" != */* && "$win" != .* ]] || continue
        user="${RC_USERMAP[$win]:-}"
        if [[ -z "$user" ]]; then
            user="$(rc_linux_user "$win")"
            if ! rc_ensure_user "$win" "$user"; then
                mtx_clog "FAILED to create user $user (Windows: $win)"
                RC_RESTORED+=("FEHLER: Benutzer $user ($win) konnte nicht angelegt werden")
                continue
            fi
            RC_USERMAP[$win]="$user"
            mkdir -p "$RC_HOME/$user"
            rc_write_user_dirs "$RC_HOME/$user" "$user"
        fi
        src="$RC_HOSTDIR/data/$win/$name"
        dest="$RC_HOME/$user/$name"
        mkdir -p "$dest"
        if [[ -d "$src" ]]; then
            rc_step data "Daten von $win: $name"
            if cp -a --no-preserve=ownership "$src/." "$dest/" 2>>"$MTX_CLIENT_LOG"; then
                count="$(find "$dest" -type f | wc -l)"
                RC_RESTORED+=("$user/$name: $count Dateien")
            else
                RC_RESTORED+=("FEHLER: $user/$name konnte nicht vollständig kopiert werden")
                mtx_clog "FAILED to copy $src"
            fi
        else
            RC_RESTORED+=("$user/$name: nichts im Backup")
        fi
        chown -R "$user:" "$dest" 2>>"$MTX_CLIENT_LOG" || true
    done < <(inv_rows "$RC_INV" userfolder)
}

# ---- step 4: verify against the manifest ----

# Build a sha256sum list with local paths and check it.
rc_verify() {
    local manifest="$RC_HOSTDIR/manifest.sha256" list="$RC_LOG_DIR/verify.list" out="$RC_LOG_DIR/verify.failed"
    local line hash path rest win user
    : > "$list"; : > "$out"
    RC_VERIFY_TOTAL=0; RC_VERIFY_BAD=0
    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line%$'\r'}"
        [[ -n "$line" ]] || continue
        hash="${line%%  *}"
        path="${line#*  }"
        RC_VERIFY_TOTAL=$((RC_VERIFY_TOTAL + 1))
        rest="${path#data/}"
        win="${rest%%/*}"
        user="${RC_USERMAP[$win]:-}"
        if [[ "$path" != data/* || -z "$user" || "$path" == *"/../"* ]]; then
            echo "$path: no restored user for this file" >> "$out"
            RC_VERIFY_BAD=$((RC_VERIFY_BAD + 1))
            continue
        fi
        printf '%s  %s\n' "$hash" "$RC_HOME/$user/${rest#*/}" >> "$list"
    done < "$manifest"
    if [[ -s "$list" ]]; then
        # --quiet prints only the files that fail.
        if ! sha256sum -c --quiet "$list" >> "$out" 2>/dev/null; then
            RC_VERIFY_BAD=$((RC_VERIFY_BAD + $(grep -c ': FAILED' "$out" || true)))
        fi
    fi
    [[ "$RC_VERIFY_BAD" -eq 0 ]]
}

# ---- step 5: report ----

rc_report() {
    local name source package linux state line path extra
    local -a s_ok=() s_failed=() s_winboat=() s_none=() s_unknown=()
    while IFS=$'\t' read -r name _ source package linux; do
        case "$source" in
            apt|flatpak)
                state="${RC_PKG_STATE["$source:$package"]:-failed}"
                if [[ "$state" == ok ]]; then
                    s_ok+=("$name  ->  $linux ($source: $package)")
                else
                    s_failed+=("$name  ->  $linux ($source: $package)")
                fi ;;
            winboat) s_winboat+=("$name") ;;
            none)    s_none+=("$name  ->  $linux") ;;
            *)       s_unknown+=("$name") ;;
        esac
    done < <(rc_app_lines)

    {
        echo "MigraTux-Bericht für $RC_HOST"
        echo "Erstellt: $(date '+%Y-%m-%d %H:%M')"
        echo
        echo "== Programme: installiert (${#s_ok[@]}) =="
        for line in "${s_ok[@]}"; do echo "  $line"; done
        echo
        echo "== Programme: Installation FEHLGESCHLAGEN (${#s_failed[@]}) =="
        for line in "${s_failed[@]}"; do echo "  $line"; done
        echo
        echo "== Programme: keine Linux-Alternative, WinBoat nötig (${#s_winboat[@]}) =="
        for line in "${s_winboat[@]}"; do echo "  $line"; done
        echo
        echo "== Programme: unbekannt, bitte prüfen (${#s_unknown[@]}) =="
        for line in "${s_unknown[@]}"; do echo "  $line"; done
        echo
        echo "== Programme: nichts zu installieren (${#s_none[@]}) =="
        for line in "${s_none[@]}"; do echo "  $line"; done
        echo
        echo "== Daten =="
        for line in "${RC_RESTORED[@]}"; do echo "  $line"; done
        if [[ "$RC_VERIFY_BAD" -eq 0 ]]; then
            echo "  Prüfung: OK, $RC_VERIFY_TOTAL von $RC_VERIFY_TOTAL Dateien stimmen mit dem Backup überein (SHA-256)."
        else
            echo "  Prüfung: FEHLER, $RC_VERIFY_BAD von $RC_VERIFY_TOTAL Dateien fehlen oder sind verändert."
            echo "  Liste: $RC_LOG_DIR/verify.failed. Erneut versuchen: sudo migratux-firstboot --force"
        fi
        echo
        echo "== Von Hand einzurichten (nicht automatisch) =="
        while IFS="$INV_SEP" read -r name _ _ _ _ extra; do
            echo "  Drucker: $name ($(inv_extra port "$extra" || echo '?'))"
        done < <(inv_rows "$RC_INV" printer)
        while IFS="$INV_SEP" read -r name _ _ path _ extra; do
            if [[ "$(inv_extra type "$extra" || true)" == drive ]]; then
                echo "  Netzlaufwerk: $name $path"
            fi
        done < <(inv_rows "$RC_INV" network)
        echo
        echo "== Nächste Schritte =="
        screen_next_steps
    } > "$RC_REPORT"

    cp "$RC_REPORT" "$RC_HOSTDIR/report.txt" 2>>"$MTX_CLIENT_LOG" || mtx_clog "WARNING: could not copy the report to the server"
    for name in "${RC_USERMAP[@]}"; do
        mkdir -p "$RC_HOME/$name/Desktop"
        cp "$RC_REPORT" "$RC_HOME/$name/Desktop/MigraTux-Bericht.txt"
        chown "$name:" "$RC_HOME/$name/Desktop" "$RC_HOME/$name/Desktop/MigraTux-Bericht.txt" 2>>"$MTX_CLIENT_LOG" || true
    done
}

# ---- main ----

main() {
    local total_mb=0 path size failed_apps=0 key
    mkdir -p "$RC_LOG_DIR"
    MTX_CLIENT_LOG="$RC_LOG_DIR/reconfigure.log"
    mtx_client_load_env "$RC_ROOT/etc/migratux/client.env"

    screen_add connect "Verbindung zum MigraTux-Server" 15
    screen_add apps    "Programme installieren" 600
    screen_add data    "Daten zurückspielen" 300
    screen_add verify  "Daten prüfen" 60
    screen_add report  "Bericht schreiben" 5
    screen_grab
    mtx_clog "reconfigure: start, macs=$(mtx_macs | tr '\n' ' ')"

    rc_step connect "Verbindung zum Server $SERVER_IP"
    rc_mount_share || rc_fatal "Server-Freigabe //$SERVER_IP/$SHARE_NAME nicht erreichbar"
    rc_find_host || rc_fatal "Kein Inventar für diesen PC auf dem Server (MAC $(mtx_macs | tr '\n' ' ')). Auf dem Server: migratux assign HOST MAC"
    RC_HOST="$(basename "$RC_HOSTDIR")"
    for path in "$RC_HOSTDIR"/inventory-*.csv; do
        if [[ -r "$path" ]]; then
            RC_INV="$path"
            break
        fi
    done
    [[ -n "$RC_INV" ]] || rc_fatal "Kein Inventar in $RC_HOSTDIR"
    [[ -r "$RC_HOSTDIR/manifest.sha256" ]] || rc_fatal "Kein fertiges Backup für $RC_HOST (manifest.sha256 fehlt)"
    SCREEN_HOST="$RC_HOST"
    mtx_clog "reconfigure: this PC is $RC_HOST"
    rc_set_hostname
    rc_done connect

    # Better estimates now that we know the apps and the amount of data.
    rc_plan_apps
    while IFS="$INV_SEP" read -r _ _ _ _ size _; do
        if [[ "$size" =~ ^[0-9]+$ ]]; then
            total_mb=$((total_mb + size))
        fi
    done < <(inv_rows "$RC_INV" userfolder)
    screen_set apps todo $(( (${#RC_APT[@]} + ${#RC_FLATPAK[@]}) * 90 + 30 ))
    screen_set data todo $(( total_mb / 20 + 10 ))
    screen_set verify todo $(( total_mb / 100 + 5 ))

    rc_step apps "${#RC_APT[@]} apt-Pakete, ${#RC_FLATPAK[@]} Flatpak-Programme"
    rc_install_apps
    rc_done apps

    rc_step data "Benutzer anlegen und Daten kopieren ($total_mb MB)"
    rc_restore_data
    rc_done data

    rc_step verify "Prüfsummen vergleichen"
    if rc_verify; then
        rc_done verify
    else
        screen_set verify fail
        mtx_clog "VERIFY FAILED: $RC_VERIFY_BAD of $RC_VERIFY_TOTAL files, see $RC_LOG_DIR/verify.failed"
    fi

    rc_step report "Bericht schreiben"
    rc_report
    rc_done report
    cp "$MTX_CLIENT_LOG" "$RC_HOSTDIR/reconfigure.log" 2>/dev/null || true

    for key in "${!RC_PKG_STATE[@]}"; do
        if [[ "${RC_PKG_STATE[$key]}" == failed ]]; then
            failed_apps=$((failed_apps + 1))
        fi
    done
    if [[ "$RC_VERIFY_BAD" -gt 0 ]]; then
        SCREEN_NOTE="FERTIG MIT FEHLERN: $RC_VERIFY_BAD Dateien stimmen nicht. Siehe Bericht."
        mtx_event finished-with-errors "Fertig, aber $RC_VERIFY_BAD von $RC_VERIFY_TOTAL Dateien stimmen nicht mit dem Backup überein"
    else
        SCREEN_NOTE="FERTIG. $RC_VERIFY_TOTAL Dateien geprüft, $failed_apps Programme fehlgeschlagen."
        mtx_event finished "Fertig: $RC_VERIFY_TOTAL Dateien geprüft, $failed_apps Programme fehlgeschlagen. Netzwerk-Boot ausschalten."
    fi
    screen_show
    mtx_clog "reconfigure: $SCREEN_NOTE"
    # Leave the result on the screen for a moment before the login screen comes.
    sleep "${MTX_HOLD_SECONDS:-20}"
    if [[ "$RC_VERIFY_BAD" -gt 0 ]]; then
        exit 2
    fi
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
