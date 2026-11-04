#!/usr/bin/env bash
# Map the apps in an inventory CSV (docs/contracts/inventory-csv.md) to Linux
# alternatives from mapping/apps.csv. First matching pattern wins.
#
# Usage: map-apps.sh INVENTORY.csv [APPS.csv]
# Output (stdout, tab-separated, with header): Name Version Source Package LinuxApp
# Source is apt|flatpak|none|winboat, or "unknown" when no pattern matches.
# Exit codes: 0 ok, 2 usage or missing file, 3 bad header.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
inventory="${1:-}"
apps="${2:-$here/apps.csv}"

if [[ -z "$inventory" ]]; then
    echo "usage: $(basename "$0") INVENTORY.csv [APPS.csv]" >&2
    exit 2
fi
for f in "$inventory" "$apps"; do
    if [[ ! -r "$f" ]]; then
        echo "error: cannot read $f" >&2
        exit 2
    fi
done

# LC_ALL=C: compare bytes, so umlauts pass through unchanged.
LC_ALL=C awk '
# Split one CSV line into fld[1..n]. Handles "quoted, fields" and "" escapes.
function parse(line,    n, i, c, f, inq) {
    split("", fld); n = 0; f = ""; inq = 0
    for (i = 1; i <= length(line); i++) {
        c = substr(line, i, 1)
        if (inq) {
            if (c == "\"") {
                if (substr(line, i + 1, 1) == "\"") { f = f "\""; i++ } else inq = 0
            } else f = f c
        } else if (c == "\"") inq = 1
        else if (c == ",") { fld[++n] = f; f = "" }
        else f = f c
    }
    fld[++n] = f
    return n
}
# Turn a glob (* and ?) into an anchored regex.
function glob2re(g,    i, c, r) {
    r = "^"
    for (i = 1; i <= length(g); i++) {
        c = substr(g, i, 1)
        if (c == "*") r = r ".*"
        else if (c == "?") r = r "."
        else if (index("\\^$.[]|()+{}", c)) r = r "\\" c
        else r = r c
    }
    return r "$"
}
# Map header names to column numbers; fail if one is missing.
function columns(n, need, file,    i, k, want) {
    split("", col)
    for (i = 1; i <= n; i++) col[fld[i]] = i
    k = split(need, want, " ")
    for (i = 1; i <= k; i++) if (!(want[i] in col)) {
        printf "error: %s has no column %s\n", file, want[i] > "/dev/stderr"
        bad = 1; exit 3
    }
}
FNR == 1 { file++; sub(/^\357\273\277/, "") }
{ sub(/\r$/, "") }
$0 == "" { next }
file == 1 && FNR == 1 {
    columns(parse($0), "Match LinuxApp Package Source", "apps.csv")
    am = col["Match"]; al = col["LinuxApp"]; ap = col["Package"]; as = col["Source"]
    next
}
file == 1 {
    parse($0)
    rules++
    re[rules] = glob2re(tolower(fld[am])); lin[rules] = fld[al]
    pkg[rules] = fld[ap]; src[rules] = fld[as]
    next
}
file == 2 && FNR == 1 {
    columns(parse($0), "Category Name Version", "inventory")
    ic = col["Category"]; iname = col["Name"]; iv = col["Version"]
    print "Name\tVersion\tSource\tPackage\tLinuxApp"
    next
}
file == 2 {
    parse($0)
    if (fld[ic] != "app") next
    out = "unknown\t\t"
    for (r = 1; r <= rules; r++) if (tolower(fld[iname]) ~ re[r]) {
        out = src[r] "\t" pkg[r] "\t" lin[r]; break
    }
    print fld[iname] "\t" fld[iv] "\t" out
}
END { if (bad) exit 3 }
' "$apps" "$inventory"
