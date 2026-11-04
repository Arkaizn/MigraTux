# mapping/

Which Linux program replaces which Windows program.

## apps.csv

UTF-8 without BOM, comma-separated, LF. **No commas and no quotes inside fields** (use `;` or `-` in notes).

| Column | Meaning |
|---|---|
| `Match` | Pattern for the `Name` of an `app` row in the inventory CSV. `*` = any text, `?` = one character, case-insensitive, whole name. |
| `WindowsApp` | Readable Windows name |
| `LinuxApp` | Readable Linux name (`-` if there is none) |
| `Package` | apt package or Flathub app ID; empty for `none` and `winboat` |
| `Source` | `apt` (Ubuntu 24.04 archive), `flatpak` (Flathub), `none` (nothing to install: web app, built in, or a Windows runtime), `winboat` (no alternative: run the Windows app with WinBoat) |
| `Note` | What the user should know |

**First match wins.** Put specific patterns above general ones (e.g. `Microsoft Edge WebView2*` before `Microsoft Edge*`).

Package names checked on 2026-11-04 against packages.ubuntu.com (noble) and the Flathub API.

WinBoat is a third-party open-source project; MigraTux integrates it, it does not own it.

## map-apps.sh

```bash
mapping/map-apps.sh tests/fixtures/inventory-sample.csv
```

Prints one tab-separated line per app: `Name Version Source Package LinuxApp`. Source `unknown` means no pattern matched; add a row to `apps.csv`.
