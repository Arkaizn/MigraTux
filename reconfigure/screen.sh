#!/usr/bin/env bash
# MigraTux info screen (M7): shows the user what the PC is doing, how long it
# will take and what to do afterwards. Text only, on the first console.
# Sourced by reconfigure.sh.
#
# Steps are registered once with screen_add; screen_show redraws the screen.
# MTX_TTY: where to draw (default /dev/tty1). Empty = do not draw.

SCREEN_IDS=()
SCREEN_LABELS=()
SCREEN_SECONDS=()     # estimated seconds left per step
SCREEN_STATE=()       # todo | run | ok | fail
SCREEN_HOST=""
SCREEN_NOTE=""

# screen_add ID LABEL SECONDS
screen_add() {
    SCREEN_IDS+=("$1")
    SCREEN_LABELS+=("$2")
    SCREEN_SECONDS+=("$3")
    SCREEN_STATE+=(todo)
}

screen_index() {
    local i
    for i in "${!SCREEN_IDS[@]}"; do
        if [[ "${SCREEN_IDS[$i]}" == "$1" ]]; then
            echo "$i"
            return 0
        fi
    done
    return 1
}

# screen_set ID STATE [SECONDS]
screen_set() {
    local i
    i="$(screen_index "$1")" || return 0
    SCREEN_STATE[i]="$2"
    if [[ -n "${3:-}" ]]; then
        SCREEN_SECONDS[i]="$3"
    fi
    if [[ "$2" == ok || "$2" == fail ]]; then
        SCREEN_SECONDS[i]=0
    fi
}

# Seconds left over all steps that are not finished.
screen_eta_seconds() {
    local i total=0
    for i in "${!SCREEN_IDS[@]}"; do
        case "${SCREEN_STATE[$i]}" in
            todo|run) total=$((total + SCREEN_SECONDS[i])) ;;
        esac
    done
    echo "$total"
}

# "ca. 12 Minuten" / "weniger als 1 Minute"
screen_eta_text() {
    local s
    s="$(screen_eta_seconds)"
    if (( s < 60 )); then
        echo "weniger als 1 Minute"
    else
        echo "ca. $(( (s + 59) / 60 )) Minuten"
    fi
}

# The next steps for the user. Also used in the report.
screen_next_steps() {
    cat <<EOF
  1. Netzwerk-Boot (PXE) im BIOS/UEFI wieder ausschalten oder die
     Festplatte an die erste Stelle der Boot-Reihenfolge setzen.
  2. Mit dem bisherigen Windows-Benutzernamen anmelden (klein geschrieben).
     Startpasswort: ${USER_PASSWORD:-siehe Techniker}  (muss sofort geändert werden)
  3. Den Bericht "MigraTux-Bericht.txt" auf dem Desktop lesen:
     dort steht, welche Programme ersetzt wurden und was noch fehlt.
EOF
}

# Print the whole screen to stdout.
screen_render() {
    local i mark
    echo "=================================================================="
    echo "   MigraTux  -  dieser PC wird auf Linux umgestellt"
    echo "=================================================================="
    echo
    echo "   PC: ${SCREEN_HOST:-wird ermittelt}"
    echo
    for i in "${!SCREEN_IDS[@]}"; do
        case "${SCREEN_STATE[$i]}" in
            ok)   mark="[x]" ;;
            run)  mark="[>]" ;;
            fail) mark="[!]" ;;
            *)    mark="[ ]" ;;
        esac
        echo "   $mark ${SCREEN_LABELS[$i]}"
    done
    echo
    if [[ -n "$SCREEN_NOTE" ]]; then
        echo "   Aktuell:  $SCREEN_NOTE"
    fi
    echo "   Restzeit: $(screen_eta_text)"
    echo
    echo "   Bitte den PC nicht ausschalten. Der Anmeldebildschirm"
    echo "   erscheint automatisch, wenn alles fertig ist."
    echo
    echo "   Danach:"
    screen_next_steps
    echo
}

# Draw the screen on the console (if there is one).
screen_show() {
    local tty="${MTX_TTY-/dev/tty1}"
    [[ -n "$tty" && -w "$tty" ]] || return 0
    {
        printf '\033[2J\033[H'
        screen_render
    } > "$tty" 2>/dev/null || true
}

# Take the console away from the boot splash so the screen is visible.
screen_grab() {
    local tty="${MTX_TTY-/dev/tty1}"
    [[ -n "$tty" && -w "$tty" ]] || return 0
    plymouth quit 2>/dev/null || true
    chvt 1 2>/dev/null || true
}
