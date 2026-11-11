# M7: Control command and info screen (manual VM test)

| | |
|---|---|
| Milestone | M7 |
| Test doc version | 2026-11-11 |
| Time estimate | ~15 min on its own; the screen checks are done **during M5 and M6** |
| Destructive? | no (steps 1–6). The screen checks belong to the M5/M6 runs. |

## Goal
A technician controls a migration with one command on the server (`migratux status|start|rollback|stop`) and always sees where each PC is. The user at the PC sees a simple screen with the current step, the remaining time and what to do next (e.g. turn network boot off).

## VMs needed

| VM | Needed | Snapshot to restore first | Notes |
|---|---|---|---|
| `mtx-server` | ☑ | `server-clean` | |
| `mtx-win` | ☑ | `win-clean` | for one inventory + backup |
| `mtx-pxe` | ☐ | – | only if you combine it with M5 |

## Before you start
- Lab set up as in [lab-setup.md](../lab-setup.md). Go back to the snapshots in the table above (**VM → Snapshot → Revert**).
- Start `mtx-server` and get the newest code (nothing is downloaded again):
  ```bash
  cd ~/MigraTux/server && git pull && ./setup.sh && docker compose up -d
  docker compose ps          # samba, pxe, http: all "running"
  ```
- On `mtx-win`: get the newest code into `C:\migratux` (the PowerShell block in [lab-setup.md](../lab-setup.md), part 3). Use **Windows PowerShell** (blue icon), not `pwsh`.
- On `mtx-win`, Windows PowerShell: one inventory + backup, so the server knows one PC (replace `192.168.80.130` with your server IP):
  ```powershell
  Set-ExecutionPolicy -Scope Process Bypass
  cd C:\migratux
  .\collect\Get-Inventory.ps1 -OutDir C:\migratux\out
  .\collect\Backup-ToServer.ps1 -InventoryPath C:\migratux\out\inventory-$env:COMPUTERNAME.csv `
      -Destination \\192.168.80.130\migratux -User migratux -Password ChangeMe-Lab1
  echo "exit code: $LASTEXITCODE"
  ```
- On `mtx-server`: `./migratux status` now lists your Windows PC `<HOST>` with a backup.

## Steps
Part 1, on `mtx-server` in `~/MigraTux/server`. No PC is booted in this part.
1. Help and status:
   ```bash
   ./migratux help
   ./migratux status
   ./migratux status <HOST>
   ```
2. Safety checks, each must refuse:
   ```bash
   ./migratux start NOSUCHPC;        echo "exit: $?"
   ./migratux rollback <HOST>;       echo "exit: $?"      # only if <HOST> has no disk image yet
   mv data/share/<HOST>/manifest.sha256 /tmp/ 2>/dev/null || sudo mv data/share/<HOST>/manifest.sha256 /tmp/
   ./migratux start <HOST>;          echo "exit: $?"      # no finished backup
   sudo mv /tmp/manifest.sha256 data/share/<HOST>/
   ```
3. Set and remove a job:
   ```bash
   ./migratux start <HOST>;          echo "exit: $?"
   ./migratux status <HOST>          # PXE-Job: migrate
   ls data/tftp/grub/hosts/
   ./migratux stop <HOST>
   ./migratux status <HOST>          # PXE-Job: keiner
   ```
4. Log: `tail -n 20 data/log/migratux.log`

Part 2, during the M5 run (client `mtx-pxe`):
5. Keep `watch -n 10 ./migratux status` open on the server and note each step text with the time.
6. On the client, photograph the info screen three times: at the start, during "Programme installieren", and the final screen. Compare the remaining time on the first photo with the real duration.
7. After the login, reboot the PC: it starts from the disk into Ubuntu, and nothing is installed again.

Part 3, during the M6 run: note the status texts for `image`, `install`, `restore`, `restored`.

## Expected result
- [ ] Step 1: `help` lists `status`, `start`, `rollback`, `stop`, `assign`, `unassign`. `status` shows per PC: inventory, MAC, backup, disk image, PXE job, last step.
- [ ] Step 2: all three refuse with a clear `ERROR:` line and `exit: 1`. No file appears in `data/tftp/grub/hosts/`.
- [ ] Step 3: `start` sets the job, `stop` removes it; if the PC has under 6 GB RAM, `start` prints a warning.
- [ ] Step 4: every command is in the log with date and time.
- [ ] Step 5: the status followed the client step by step, with a remaining time during the first boot.
- [ ] Step 6: the screen is readable (umlauts correct), shows `[x]` for done steps and `[>]` for the current one, and the remaining time goes down. First estimate ____ min, real ____ min.
- [ ] Step 6: the final screen names the next steps (network boot off, login name, start password, report).
- [ ] Step 7: the PC boots straight into Ubuntu.

## If it fails
- `./migratux`: "server/.env not found": run it from `~/MigraTux/server` after `cp .env.example .env`.
- Status never changes during an install: the client cannot reach `http://SERVER_IP:8080/events/`. Check `docker compose logs http | grep events`.
- The info screen does not appear (boot logo or black screen instead) but the status on the server moves: note it and send a photo. The work is done anyway; only the display is missing.
- Umlauts on the info screen are broken (`Ã¼` or boxes): send a photo.
- The remaining time is far off (more than double): send both numbers; the estimates are rough constants.

## What to send back
```
M7 test: OK | FAILED
Date / tester:
Repo commit:
Part 1: result per box
Part 2: status texts with times; ETA first estimate vs real
Result per expected-result box: …
Problem (if any): what you saw, at which step
```

Attach:
- the log file: `server/data/log/migratux.log`
- the output of steps 1–3
- photos of: the info screen (start, middle, end)
