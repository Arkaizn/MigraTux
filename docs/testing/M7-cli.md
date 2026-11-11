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
| `mtx-server` | ☑ | the state after M2 (one client folder with backup) | |
| `mtx-win` | ☐ | – | only if you combine it with M6 |
| `mtx-pxe` | ☐ | – | only if you combine it with M5 |

## Before you start
- M2 passed: `./migratux status` lists your Windows PC `<HOST>` with a backup.

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
7. After the login, follow the "next steps" from the screen: turn network boot off in the VM firmware, reboot, the PC starts from disk without the boot menu.

Part 3, during the M6 run: note the status texts for `image`, `install`, `restore`, `restored`.

## Expected result
- [ ] Step 1: `help` lists `status`, `start`, `rollback`, `stop`, `assign`, `unassign`. `status` shows per PC: inventory, MAC, backup, disk image, PXE job, last step.
- [ ] Step 2: all three refuse with a clear `ERROR:` line and `exit: 1`. No file appears in `data/tftp/grub/hosts/`.
- [ ] Step 3: `start` sets the job, `stop` removes it; if the PC has under 6 GB RAM, `start` prints a warning.
- [ ] Step 4: every command is in the log with date and time.
- [ ] Step 5: the status followed the client step by step, with a remaining time during the first boot.
- [ ] Step 6: the screen is readable (umlauts correct), shows `[x]` for done steps and `[>]` for the current one, and the remaining time goes down. First estimate ____ min, real ____ min.
- [ ] Step 6: the final screen names the next steps (network boot off, login name, start password, report).
- [ ] Step 7: with network boot off the PC boots straight into Ubuntu.

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
