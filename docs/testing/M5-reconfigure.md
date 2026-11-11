# M5: Full chain, apps and data arrive on Linux (manual VM test)

| | |
|---|---|
| Milestone | M5 (chain M1 → M2 → M4 → M5) |
| Test doc version | 2026-11-11 |
| Time estimate | ~90 min (Windows part 15, install 35, first boot 15–30, checks 10) |
| Destructive? | yes: wipes the disk of `mtx-pxe`. `mtx-win` is **not** touched. |

## Goal
After inventory and backup on Windows, a PC that installs over the network becomes that user's Linux PC: the Linux alternatives of the Windows apps are installed, the user's files are back and verified, and a report says what is missing. Includes the pitch scenario **many user files**.

To keep the Windows VM, the Linux install goes to `mtx-pxe`, which the server is told to treat as the Windows PC (`migratux assign`). The real "same PC" path is tested in M6.

## VMs needed

| VM | Needed | Snapshot to restore first | Notes |
|---|---|---|---|
| `mtx-server` | ☑ | `server-clean` | needs internet |
| `mtx-win` | ☑ | `win-clean` | for inventory + backup only |
| `mtx-pxe` | ☑ | `pxe-empty` | UEFI, 8 GB RAM, needs internet |

## Before you start
- Lab set up as in [lab-setup.md](../lab-setup.md). Go back to the snapshots in the table above (**VM → Snapshot → Revert**).
- Start `mtx-server` and get the newest code (nothing is downloaded again):
  ```bash
  cd ~/MigraTux/server && git pull && ./setup.sh && docker compose up -d
  docker compose ps          # samba, pxe, http: all "running"
  ```
- On `mtx-win`: get the newest code into `C:\migratux` (the PowerShell block in [lab-setup.md](../lab-setup.md), part 3). Use **Windows PowerShell** (blue icon), not `pwsh`.
- In the commands below replace `192.168.80.130` with your server IP (`ip -4 -br addr` on the server).
- MAC address of `mtx-pxe` (VM > Settings > Network Adapter > Advanced).
- Good moment for the **test recording** of the timelapse (VM Lab page §5).

## Steps
1. On `mtx-win`, Windows PowerShell as a normal user: create 2000 files with umlauts, then inventory and backup. Note the Windows user name and the computer name `<HOST>` (`hostname`).
   ```powershell
   Set-ExecutionPolicy -Scope Process Bypass
   cd C:\migratux
   $dir = "$env:USERPROFILE\Documents\Aufträge Müller"
   New-Item -ItemType Directory -Path $dir -Force | Out-Null
   1..2000 | ForEach-Object { "Auftrag $_" | Set-Content "$dir\Auftrag_${_}_Zürich_Größe.txt" }
   .\collect\Get-Inventory.ps1 -OutDir C:\migratux\out
   .\collect\Backup-ToServer.ps1 -InventoryPath C:\migratux\out\inventory-$env:COMPUTERNAME.csv `
       -Destination \\192.168.80.130\migratux -User migratux -Password ChangeMe-Lab1
   echo "exit code: $LASTEXITCODE"
   ```
   The last line must be `exit code: 0`. Windows can stay on or be shut down; it is not touched again.
2. On `mtx-server`:
   ```bash
   cd ~/MigraTux/server
   ./migratux status                                  # <HOST>: Backup ja
   wc -l data/share/<HOST>/manifest.sha256            # number of files, needed for the check later
   ./migratux assign <HOST> 00:0C:29:12:34:56         # MAC of mtx-pxe
   ./migratux start <HOST> --no-image
   watch -n 10 ./migratux status
   ```
3. Start a stopwatch and power on `mtx-pxe`. Do not touch it.
4. After the install and the reboot, a text screen "MigraTux - dieser PC wird auf Linux umgestellt" appears with the steps, the remaining time and the next steps. Take a photo/screenshot while "Programme installieren" is running. Note the time when the login screen appears.
5. Log in with the **Windows user name in lower case** and the password `USER_PASSWORD` from `server/.env` (default `Willkommen1`). Ubuntu asks for a new password.
6. Check on the desktop:
   - open "MigraTux-Bericht.txt" on the Desktop
   - open Files: Documents, Desktop, Pictures hold the Windows files; open one document with an umlaut in its name
   - open the app menu: LibreOffice, VLC, … are there (as listed under "installiert" in the report)
7. In a terminal (as `mtxadmin` via `su - mtxadmin`, or over SSH from the server):
   ```bash
   hostname
   sudo cat /var/log/migratux/report.txt
   sudo wc -l /var/log/migratux/verify.list; sudo cat /var/log/migratux/verify.failed
   find /home/*/Documents -name 'Auftrag_*' | wc -l
   sudo cp /var/log/migratux/*.log /var/log/migratux/report.txt /tmp/ && ls /tmp
   ```
8. On `mtx-server`: `./migratux status <HOST> > ~/m5-status.txt; cp data/share/<HOST>/report.txt data/share/<HOST>/reconfigure.log ~/`

## Expected result
- [ ] No input between power-on and the login screen.
- [ ] `migratux status` walked through `install`, `installed`, `firstboot`, `connect`, `apps`, `data`, `verify`, `report`, `finished`; "PXE-Job: keiner" at the end.
- [ ] The info screen showed the current step and a remaining time that went down.
- [ ] Login with the Windows user name works and forces a password change.
- [ ] The report lists every Windows app in exactly one section; "Installation FEHLGESCHLAGEN (0)".
- [ ] The apps under "installiert" start.
- [ ] The report says `Prüfung: OK, N von N Dateien`; `N` equals the manifest line count from step 2; `verify.failed` is empty.
- [ ] `find` counts 2000; file names with `ä ö ü ß` are correct.
- [ ] `hostname` is the Windows computer name in lower case.
- [ ] Times: power-on → login screen ____ min; of that first boot (info screen) ____ min.

## If it fails
- Info screen: "Kein Inventar für diesen PC": the `assign` step was skipped or the MAC is wrong. Fix it on the server, then on the client: `sudo migratux-firstboot --force`.
- Info screen: "Server-Freigabe … nicht erreichbar": Samba is down or the password in `server/.env` changed after `setup.sh`. Run `./setup.sh` again and reinstall, or check `docker compose ps`.
- No info screen, only the Ubuntu boot logo for a long time: the work still runs; follow it with `./migratux status`. Note it: the screen is the part that is hardest to predict without a VM.
- Apps under "FEHLGESCHLAGEN": send `reconfigure.log`. Flatpak downloads are large; no internet = all flatpaks fail.
- `Prüfung: FEHLER`: send `verify.failed`. Run again: `sudo migratux-firstboot --force`.
- Any step can be repeated without reinstalling: `sudo migratux-firstboot --force`.

## What to send back
```
M5 test: OK | FAILED
Date / tester:
Repo commit:
VMs + OS builds:
Times: power-on -> login / info screen duration:
Apps: installed / failed / winboat / unknown (numbers from the report)
Files: N of N verified
Result per expected-result box: …
Problem (if any): what you saw, at which step
```

Attach:
- the log files: `report.txt`, `reconfigure.log`, `firstboot.log`, `install.log`, `~/m5-status.txt`
- a screenshot of: the info screen, the desktop with the files, the report
