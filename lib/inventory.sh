#!/usr/bin/env bash
# Read an inventory CSV (docs/contracts/inventory-csv.md) from shell.
# Sourced by server/migratux and reconfigure/reconfigure.sh.
#
# Fields are printed with the ASCII unit separator (0x1f) between them, because
# `read` merges empty fields when the separator is a tab. Read them like this:
#   while IFS=$'\x1f' read -r name version publisher path size extra; do ...
#   done < <(inv_rows "$csv" app)

INV_SEP=$'\x1f'
export INV_SEP

# inv_rows FILE CATEGORY: Name Version Publisher Path SizeMB Extra of each row.
inv_rows() {
    LC_ALL=C awk -v want="$2" -v sep="$INV_SEP" '
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
    FNR == 1 { sub(/^\357\273\277/, "") }
    { sub(/\r$/, "") }
    $0 == "" { next }
    FNR == 1 {
        n = parse($0)
        for (i = 1; i <= n; i++) col[fld[i]] = i
        k = split("Hostname Category Name Version Publisher Path SizeMB Extra", need, " ")
        for (i = 1; i <= k; i++) if (!(need[i] in col)) {
            printf "error: inventory has no column %s\n", need[i] > "/dev/stderr"
            bad = 1; exit 3
        }
        next
    }
    {
        parse($0)
        if (want == "hostname") { print fld[col["Hostname"]]; exit }
        if (fld[col["Category"]] != want) next
        print fld[col["Name"]] sep fld[col["Version"]] sep fld[col["Publisher"]] sep \
              fld[col["Path"]] sep fld[col["SizeMB"]] sep fld[col["Extra"]]
    }
    END { if (bad) exit 3 }
    ' "$1"
}

# inv_hostname FILE: the Hostname of the first data row.
inv_hostname() {
    inv_rows "$1" hostname
}

# inv_extra KEY EXTRA: value of one key in a "k=v;k=v" string. Returns 1 if absent.
inv_extra() {
    local pair
    local IFS=';'
    for pair in $2; do
        if [[ "${pair%%=*}" == "$1" ]]; then
            printf '%s\n' "${pair#*=}"
            return 0
        fi
    done
    return 1
}

# mac_normalize MAC: 00-0C-29-AB-CD-EF or 000C29ABCDEF -> 00:0c:29:ab:cd:ef.
# Returns 1 if it is not a MAC address.
mac_normalize() {
    local m
    m="$(printf '%s' "$1" | tr 'A-F' 'a-f' | tr -d ':.-')"
    [[ "$m" =~ ^[0-9a-f]{12}$ ]] || return 1
    printf '%s:%s:%s:%s:%s:%s\n' "${m:0:2}" "${m:2:2}" "${m:4:2}" "${m:6:2}" "${m:8:2}" "${m:10:2}"
}

# inv_macs FILE: MAC addresses of all network adapters, one per line, normalized.
inv_macs() {
    local extra mac
    while IFS="$INV_SEP" read -r _ _ _ _ _ extra; do
        mac="$(inv_extra mac "$extra")" || continue
        mac_normalize "$mac" || true
    done < <(inv_rows "$1" network) | sort -u
}
