# reconfigure/ (Linux post-install)

Milestones M5 (apps and data) and M7 (info screen). Runs once on the freshly installed Linux PC, started by `install/firstboot.sh`, before the login screen.

`reconfigure.sh`:
1. Mounts the server share and finds the folder of this PC by its MAC address.
2. Maps the Windows apps with `mapping/map-apps.sh` and installs the `apt` and `flatpak` packages. A failing package is reported and does not stop the run.
3. Creates a Linux user for each Windows user (name in lower case, start password from the server settings, must be changed at the first login) and copies the folders back (`Documents`, `Desktop`, `Pictures`, …).
4. Checks every restored file against `manifest.sha256` from the backup.
5. Writes the report: installed, failed, needs WinBoat, unknown, nothing to install, plus printers and network drives to set up by hand. The report goes to `/var/log/migratux/report.txt`, to the server (`<HOST>/report.txt`) and to each user's Desktop (`MigraTux-Bericht.txt`).

`screen.sh` draws the info screen on the first console: steps, current action, remaining time, next steps (turn network boot off, how to log in). Every step is also reported to the server (`migratux status`).

Exit codes: 0 ok, 1 fatal (server or inventory not found; runs again at the next boot), 2 finished but files differ from the backup.

Not done automatically: printers, network drives, app settings, WinBoat itself.

Tests: `tests/run.sh bats` (whole runs with stubs for apt, flatpak, useradd). Manual: [M5](../docs/testing/M5-reconfigure.md).
