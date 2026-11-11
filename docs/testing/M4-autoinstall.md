# M4: Unattended Ubuntu install over the network (manual VM test)

| | |
|---|---|
| Milestone | M4 |
| Test doc version | 2026-11-11 |
| Time estimate | ~50 min (setup 5, run 30–40 mostly waiting, collecting results 5) |
| Destructive? | yes: wipes the disk of `mtx-pxe` |

## Goal
An empty PC becomes an Ubuntu 24.04 desktop with no input: network boot, install, reboot, login screen. Measure how long it takes.

## VMs needed

| VM | Needed | Snapshot to restore first | Notes |
|---|---|---|---|
| `mtx-server` | ☑ | `server-clean` | needs internet |
| `mtx-win` | ☐ | – | |
| `mtx-pxe` (empty VM) | ☑ | `pxe-empty` | UEFI, **8 GB RAM**, 40 GB disk, needs internet |

## Before you start
- Lab set up as in [lab-setup.md](../lab-setup.md). Go back to the snapshots in the table above (**VM → Snapshot → Revert**).
- Start `mtx-server` and get the newest code (nothing is downloaded again):
  ```bash
  cd ~/MigraTux/server && git pull && ./setup.sh && docker compose up -d
  docker compose ps          # samba, pxe, http: all "running"
  ```
- The MAC address of `mtx-pxe`: VM > Settings > Network Adapter > Advanced > MAC Address.

## Steps
1. On `mtx-server`, give this MAC an install job (replace the MAC):
   ```bash
   cd ~/MigraTux/server
   ./migratux start 00:0C:29:12:34:56
   ./migratux status
   ```
2. Start a stopwatch. Power on `mtx-pxe`. Do **not** touch keyboard or mouse.
3. Watch from the server (new line every few minutes):
   ```bash
   watch -n 10 ./migratux status
   ```
4. What you see on `mtx-pxe`, in this order:
   - boot menu, entry "MigraTux: install (startet automatisch)" is chosen after 5 s
   - "lade Installer": the 3.9 GB ISO is loaded into RAM (a few minutes, little output)
   - the Ubuntu installer runs by itself (text screen)
   - the VM reboots and starts from the disk (if the MigraTux boot menu appears again, it chooses "Von der Festplatte starten")
   - a MigraTux text screen appears for a moment and reports "Kein Inventar für diesen PC". **That is expected in this test**: the PC has no Windows inventory.
   - the graphical login screen
5. Stop the stopwatch at the login screen. Log in as `mtxadmin` with `ADMIN_PASSWORD` from `server/.env`.
6. In a terminal on `mtx-pxe`:
   ```bash
   locale | head -n 1; localectl status | grep -i layout
   systemctl is-active ssh NetworkManager
   systemctl status migratux-firstboot --no-pager | head -n 5
   sudo cp /var/log/migratux/install.log /var/log/migratux/firstboot.log ~/ 2>/dev/null; ls ~
   ```
7. From `mtx-server`: `ssh mtxadmin@<IP of mtx-pxe> hostname`
8. Save: `./migratux status > ~/m4-status.txt; docker compose logs > ~/m4-compose.log`

## Expected result
- [ ] No key was pressed between power-on and the login screen.
- [ ] `migratux status` showed `install`, later `installed`, later `failed: Kein Inventar …`; "PXE-Job" is gone after the install.
- [ ] After the reboot the PC does **not** install a second time.
- [ ] Login as `mtxadmin` works; the desktop is German; the keyboard layout is Swiss (`z`/`y`, `ä ö ü`).
- [ ] Step 6: `LANG=de_CH.UTF-8`, layout `ch`, `ssh` and `NetworkManager` are `active`.
- [ ] Step 7: SSH login works.
- [ ] Time from power-on to login screen: ____ min.

## If it fails
- Stuck at "lade Installer" or kernel panic / "out of memory" / "no space left": the VM has too little RAM. It needs 8 GB.
- The installer stops and asks a question, or shows an error in red: screenshot. Then press Alt+F2 (or choose "Help > Enter shell") and run `cat /var/log/migratux-early.log; tail -n 50 /var/log/installer/subiquity-server-debug.log`. Photograph it.
- "no valid migratux.mode … Refusing to touch this PC": the boot menu entry had no job. Check `./migratux status`.
- The install ends with "the PXE job on the server could not be removed": the client could not reach `http://SERVER_IP:8080`. Check `docker compose ps`.
- The PC installs again after the reboot: the job was not removed. Run `./migratux stop <MAC>` and send `m4-compose.log`.
- Black screen instead of the login screen after the first boot: wait 2 minutes (the first-boot step retries the server), then send a screenshot.
- No internet in the VM: the desktop packages cannot be downloaded and the install fails.

## What to send back
```
M4 test: OK | FAILED
Date / tester:
Repo commit:
VMs + RAM of mtx-pxe, VMware version:
Time power-on -> login screen:
Result per expected-result box: …
Problem (if any): what you saw, at which step
```

Attach:
- the log files: `~/m4-status.txt`, `~/m4-compose.log`, from the client `install.log` and `firstboot.log`
- a screenshot of: the boot menu with the job entry, the login screen, the output of step 6
