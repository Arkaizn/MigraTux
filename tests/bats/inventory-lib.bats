#!/usr/bin/env bats
# Tests for lib/inventory.sh. Run: tests/run.sh bats

load helpers/common

setup() {
    source "$ROOT/lib/inventory.sh"
}

@test "inv_hostname reads the host of the fixture" {
    [ "$(inv_hostname "$FIXTURE")" = "KMU-PC01" ]
}

@test "inv_rows lists the rows of one category" {
    [ "$(inv_rows "$FIXTURE" app | wc -l)" -eq 13 ]
    [ "$(inv_rows "$FIXTURE" userfolder | wc -l)" -eq 4 ]
    [ "$(inv_rows "$FIXTURE" nothing | wc -l)" -eq 0 ]
}

@test "inv_rows keeps empty fields, commas in quotes and umlauts" {
    local name version publisher path size extra found=0
    while IFS="$INV_SEP" read -r name version publisher path size extra; do
        if [ "$name" = "HP LaserJet, Büro 1" ]; then
            found=1
            [ -z "$version" ]
            [ "$publisher" = "HP" ]
            [ -z "$path" ]
            [ -z "$size" ]
            [ "$extra" = "driver=HP Universal Printing PCL 6;port=IP_192.168.1.50;default=true" ]
        fi
    done < <(inv_rows "$FIXTURE" printer)
    [ "$found" -eq 1 ]
}

@test "inv_rows fails on a file with the wrong header" {
    printf 'A,B\n1,2\n' > "$BATS_TEST_TMPDIR/bad.csv"
    run inv_rows "$BATS_TEST_TMPDIR/bad.csv" app
    [ "$status" -eq 3 ]
    [[ "$output" == *"no column"* ]]
}

@test "inv_extra returns one value and fails for a missing key" {
    [ "$(inv_extra user 'user=mmueller;files=12')" = "mmueller" ]
    [ "$(inv_extra files 'user=mmueller;files=12')" = "12" ]
    run inv_extra mac 'user=mmueller;files=12'
    [ "$status" -eq 1 ]
}

@test "mac_normalize accepts Windows and Linux spelling" {
    [ "$(mac_normalize 00-0C-29-AB-CD-EF)" = "00:0c:29:ab:cd:ef" ]
    [ "$(mac_normalize 00:0c:29:ab:cd:ef)" = "00:0c:29:ab:cd:ef" ]
    run mac_normalize KMU-PC01
    [ "$status" -eq 1 ]
}

@test "inv_macs finds the adapter MAC of the fixture" {
    [ "$(inv_macs "$FIXTURE")" = "$FIXTURE_MAC" ]
}
