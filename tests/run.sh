#!/usr/bin/env bash
# Run the automatic tests. No VM needed.
#
# Usage: tests/run.sh [all|pester|lint|bats] [--local]
#   pester:     Pester 5 via local pwsh
#   lint:       shellcheck on all *.sh and *.bats       (Docker, Ubuntu 24.04)
#   bats:       shell unit tests in tests/bats (Docker, Ubuntu 24.04)
#   --local:    use local shellcheck/bats instead of Docker
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
image="migratux-shelltest:24.04"
what="all"
local_tools=0
for arg in "$@"; do
    case "$arg" in
        --local) local_tools=1 ;;
        all|pester|lint|shellcheck|bats) what="$arg" ;;
        *) echo "usage: tests/run.sh [all|pester|lint|bats] [--local]" >&2; exit 2 ;;
    esac
done

# Run a command in the shell test image, or locally with --local.
in_image() {
    if [[ $local_tools -eq 1 ]]; then
        (cd "$root" && "$@")
    else
        docker build -q -t "$image" "$root/tests/docker" >/dev/null
        docker run --rm -v "$root:/repo:ro" "$image" "$@"
    fi
}

shell_files() {
    (cd "$root" && git ls-files --cached --others --exclude-standard -- '*.sh' '*.bats')
}

run_pester() {
    echo "== pester"
    pwsh -NoProfile -Command "
        Import-Module Pester -MinimumVersion 5.5
        \$c = New-PesterConfiguration
        \$c.Run.Path = '$root/tests/pester'
        \$c.Run.Exit = \$true
        \$c.Output.Verbosity = 'Detailed'
        Invoke-Pester -Configuration \$c"
}

run_shellcheck() {
    echo "== shellcheck"
    mapfile -t files < <(shell_files)
    in_image shellcheck -x "${files[@]}"
    echo "shellcheck: ${#files[@]} files clean"
}

run_bats() {
    echo "== bats"
    in_image bats tests/bats
}

case "$what" in
    pester)     run_pester ;;
    lint|shellcheck) run_shellcheck ;;
    bats)       run_bats ;;
    all)        run_pester; run_shellcheck; run_bats ;;
esac
