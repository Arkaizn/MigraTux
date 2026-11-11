#!/usr/bin/env bash
# Run the automatic tests. No VM needed.
#
# Usage: tests/run.sh [all|pester|lint|bats|server] [--local]
#   pester:     Pester 5 via local pwsh
#   lint:       shellcheck on all shell scripts and *.bats (Docker, Ubuntu 24.04)
#   bats:       shell unit tests in tests/bats (Docker, Ubuntu 24.04)
#   server:     builds the server images and checks them with the rendered
#               config: compose file, dnsmasq, Samba, HTTP (always Docker)
#   --local:    use local shellcheck/bats instead of Docker
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
image="migratux-shelltest:24.04"
what="all"
local_tools=0
for arg in "$@"; do
    case "$arg" in
        --local) local_tools=1 ;;
        all|pester|lint|shellcheck|bats|server) what="$arg" ;;
        *) echo "usage: tests/run.sh [all|pester|lint|bats|server] [--local]" >&2; exit 2 ;;
    esac
done

# Run a command in the shell test image, or locally with --local.
in_image() {
    if [[ $local_tools -eq 1 ]]; then
        (cd "$root" && "$@")
    else
        # Host network for the build (apt), no network for the tests.
        docker build -q --network host -t "$image" "$root/tests/docker" >/dev/null
        docker run --rm --network none -v "$root:/repo:ro" "$image" "$@"
    fi
}

shell_files() {
    # Also the shell scripts without .sh: the CLI and the test helpers.
    (cd "$root" && git ls-files --cached --others --exclude-standard -- '*.sh' '*.bats' '*.bash' \
        server/migratux tests/bats/helpers/bin)
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

# Check one HTTP request inside the test web server: http_expect CODE curl-args...
http_expect() {
    local want="$1" got
    shift
    got="$(docker exec "$http_name" curl -s -o /dev/null -w '%{http_code}' "$@")"
    if [[ "$got" != "$want" ]]; then
        echo "FAILED: curl $* gave HTTP $got, expected $want" >&2
        return 1
    fi
    echo "ok   HTTP $got  curl $*"
}

run_server() {
    echo "== server"
    local tmp http_name="migratux-test-http-$$" rc=0
    tmp="$(mktemp -d)"
    (cd "$root/server" && docker compose --env-file .env.example config -q)
    echo "ok   docker compose config"
    (cd "$root/server" && docker compose --env-file .env.example build -q >/dev/null 2>&1)
    echo "ok   images built"

    # Render the config like setup.sh does on the server, into a temp folder.
    sed "s|^DATA_DIR=.*|DATA_DIR=$tmp/data|" "$root/server/.env.example" > "$tmp/env"
    MTX_ENV_FILE="$tmp/env" "$root/server/setup.sh" --no-build >/dev/null

    docker run --rm --network none -v "$tmp/data/conf/dnsmasq.conf:/etc/dnsmasq.conf:ro" \
        --entrypoint dnsmasq migratux-pxe --test --conf-file=/etc/dnsmasq.conf 2>&1 | sed 's/^/ok   /'
    docker run --rm --network none -v "$tmp/data/conf/smb.conf:/etc/samba/smb.conf:ro" \
        --entrypoint testparm migratux-samba -s /etc/samba/smb.conf >/dev/null 2>&1
    echo "ok   Samba accepts smb.conf"

    # HTTP server without network: requests are made inside the container.
    echo job > "$tmp/data/tftp/grub/hosts/00:0c:29:ab:cd:ef.cfg"
    docker run -d --rm --name "$http_name" --network none \
        -v "$root/server/http/nginx.conf:/etc/nginx/nginx.conf:ro" \
        -v "$tmp/data/http:/srv/http:ro" -v "$tmp/data/tftp/grub/hosts:/srv/pxe-hosts" \
        -v "$tmp/data/events:/srv/events" -v "$tmp/data/images:/srv/images" nginx:1.27-alpine >/dev/null
    sleep 1
    local u="http://127.0.0.1"
    {
        http_expect 200 "$u/autoinstall/user-data" &&
        http_expect 200 "$u/autoinstall/meta-data" &&
        http_expect 200 "$u/files/migratux-client.tar.gz" &&
        http_expect 201 -T /etc/hostname "$u/events/00-0c-29-ab-cd-ef/install" &&
        http_expect 405 -X DELETE "$u/events/00-0c-29-ab-cd-ef/install" &&
        http_expect 201 -T /etc/hostname "$u/images/KMU-PC01/disk.info" &&
        http_expect 200 "$u/images/KMU-PC01/disk.info" &&
        http_expect 403 -T /etc/hostname "$u/pxe/hosts/aa:bb:cc:dd:ee:ff.cfg" &&
        http_expect 204 -X DELETE "$u/pxe/hosts/00:0c:29:ab:cd:ef.cfg" &&
        http_expect 404 -X DELETE "$u/pxe/hosts/00:0c:29:ab:cd:ef.cfg"
    } || rc=1
    # Files written by the container belong to root: remove them from inside.
    docker exec "$http_name" sh -c 'rm -rf /srv/events/* /srv/images/* /srv/images/.upload' || true
    docker stop "$http_name" >/dev/null || true
    rm -rf "$tmp"
    return "$rc"
}

case "$what" in
    server)     run_server ;;
    pester)     run_pester ;;
    lint|shellcheck) run_shellcheck ;;
    bats)       run_bats ;;
    all)        run_pester; run_shellcheck; run_bats; run_server ;;
esac
