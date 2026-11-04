#!/usr/bin/env bats
# Tests for mapping/map-apps.sh. Run: tests/run.sh bats

setup() {
    ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    MAP="$ROOT/mapping/map-apps.sh"
    FIXTURE="$ROOT/tests/fixtures/inventory-sample.csv"
}

# Print the mapped line for one app name from the fixture.
line_for() {
    "$MAP" "$FIXTURE" | awk -F'\t' -v n="$1" '$1 == n'
}

@test "prints the header first" {
    run "$MAP" "$FIXTURE"
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "$(printf 'Name\tVersion\tSource\tPackage\tLinuxApp')" ]
}

@test "lists only app rows (13 apps in the fixture)" {
    run "$MAP" "$FIXTURE"
    [ "${#lines[@]}" -eq 14 ]
}

@test "maps Office to LibreOffice via apt" {
    [ "$(line_for 'Microsoft 365 Apps for business - de-ch')" = "$(printf 'Microsoft 365 Apps for business - de-ch\t16.0.17928.20156\tapt\tlibreoffice\tLibreOffice')" ]
}

@test "maps Chrome to a flatpak" {
    [ "$(line_for 'Google Chrome' | cut -f3,4)" = "$(printf 'flatpak\tcom.google.Chrome')" ]
}

@test "first match wins: WebView2 runtime is ignored, not mapped to Edge" {
    [ "$(line_for 'Microsoft Edge WebView2 Runtime' | cut -f3)" = "none" ]
}

@test "marks apps without alternative as winboat" {
    [ "$(line_for 'Abacus ERP Client' | cut -f3)" = "winboat" ]
}

@test "marks unmatched apps as unknown and keeps umlauts" {
    [ "$(line_for 'Kassenbuch Müller Spezial' | cut -f3)" = "unknown" ]
}

@test "publisher with a comma does not shift columns" {
    [ "$(line_for 'Zoom Workplace' | cut -f2,3)" = "$(printf '6.2.5\tflatpak')" ]
}

@test "matching is case-insensitive" {
    tmp="$BATS_TEST_TMPDIR/inv.csv"
    printf 'Hostname,Category,Name,Version,Publisher,Path,SizeMB,Extra\nPC1,app,GOOGLE CHROME,1,,,,\n' > "$tmp"
    run "$MAP" "$tmp"
    [ "$(echo "${lines[1]}" | cut -f3)" = "flatpak" ]
}

@test "works without BOM and with LF line endings" {
    tmp="$BATS_TEST_TMPDIR/inv.csv"
    printf 'Hostname,Category,Name,Version,Publisher,Path,SizeMB,Extra\nPC1,app,VLC media player,3,,,,\n' > "$tmp"
    run "$MAP" "$tmp"
    [ "$status" -eq 0 ]
    [ "$(echo "${lines[1]}" | cut -f4)" = "vlc" ]
}

@test "exits 2 without arguments" {
    run "$MAP"
    [ "$status" -eq 2 ]
}

@test "exits 2 when the inventory is missing" {
    run "$MAP" /nonexistent.csv
    [ "$status" -eq 2 ]
}

@test "exits 3 when the inventory has no Category column" {
    tmp="$BATS_TEST_TMPDIR/inv.csv"
    printf 'Hostname;Category;Name\nPC1;app;X\n' > "$tmp"
    run "$MAP" "$tmp"
    [ "$status" -eq 3 ]
}
