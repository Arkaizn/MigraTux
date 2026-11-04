# reconfigure/ (Linux post-install)

Milestone M5. Planned, not built yet. Runs once on the freshly installed Linux PC.

Planned steps:
1. Fetch `inventory-<HOSTNAME>.csv` from the server share.
2. Map apps with `mapping/map-apps.sh` and install the `apt` and `flatpak` packages.
3. Restore user folders (Documents, Desktop, …) from the server backup.
4. Set up printers and network drives from the CSV.
5. Write a report: installed, not needed (`none`), needs WinBoat (`winboat`), unknown.
