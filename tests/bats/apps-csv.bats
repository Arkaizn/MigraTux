#!/usr/bin/env bats
# Format checks for mapping/apps.csv (see mapping/README.md). Run: tests/run.sh bats

setup() {
    APPS="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)/mapping/apps.csv"
}

@test "header is exact" {
    [ "$(head -n1 "$APPS")" = "Match,WindowsApp,LinuxApp,Package,Source,Note" ]
}

@test "no quotes, no CR, no BOM" {
    run grep -c '"' "$APPS"
    [ "$output" = "0" ]
    run grep -c $'\r' "$APPS"
    [ "$output" = "0" ]
    [ "$(head -c3 "$APPS" | od -An -tx1 | tr -d ' ')" != "efbbbf" ]
}

@test "every row has 6 fields" {
    run awk -F, 'NF != 6 { print NR": "$0 }' "$APPS"
    [ -z "$output" ]
}

@test "Source is apt, flatpak, none or winboat" {
    run awk -F, 'NR > 1 && $5 !~ /^(apt|flatpak|none|winboat)$/ { print NR": "$5 }' "$APPS"
    [ -z "$output" ]
}

@test "apt and flatpak rows have a package, none and winboat rows have none" {
    run awk -F, 'NR > 1 && (($5 ~ /^(apt|flatpak)$/) != ($4 != "")) { print NR": "$0 }' "$APPS"
    [ -z "$output" ]
}

@test "flatpak packages look like app IDs" {
    run awk -F, 'NR > 1 && $5 == "flatpak" && $4 !~ /^[A-Za-z0-9_-]+(\.[A-Za-z0-9_-]+)+$/ { print NR": "$4 }' "$APPS"
    [ -z "$output" ]
}

@test "Match patterns are unique" {
    run sh -c "tail -n +2 '$APPS' | cut -d, -f1 | sort | uniq -d"
    [ -z "$output" ]
}

@test "at least 25 Windows apps are mapped" {
    [ "$(tail -n +2 "$APPS" | wc -l)" -ge 25 ]
}
