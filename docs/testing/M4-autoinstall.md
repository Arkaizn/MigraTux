# M4: Unattended Ubuntu install over the network (manual VM test)

| | |
|---|---|
| Milestone | M4 |
| Test doc version | 2026-11-16 (NFS netboot) |
| Time estimate | ~50 min (setup 5, run 30–40 mostly waiting, collecting results 5) |
| Destructive? | yes: wipes the disk of `mtx-pxe` |

## Goal
An empty PC becomes an Ubuntu 24.04 desktop with no input: network boot, install, reboot, login screen. Measure how long it takes.

## VMs needed

| VM | Needed | Snapshot to restore first | Notes |
|---|---|---|---|
| `mtx-server` | ☑ | `server-clean` | needs internet |
| `mtx-win` | ☐ | – | |
| `mtx-pxe` (empty VM) | ☑ | `pxe-empty` | UEFI, 8 GB RAM (4 GB also works but is slower, see step 9 and the 2026-11-17 result), 40 GB disk, needs internet |

## Before you start
- Lab set up as in [lab-setup.md](../lab-setup.md). Go back to the snapshots in the table above (**VM → Snapshot → Revert**).
- Start `mtx-server` and get the newest code (nothing is downloaded again):
  ```bash
  cd ~/MigraTux/server && git pull && ./setup.sh && docker compose up -d
  docker compose ps          # samba, pxe, nfs, http: all "running"
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
   - "lade Installer": kernel and installer start files are loaded (under a minute). Then boot messages; the installer reads its files from the server over NFS.
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
9. Optional, only when everything above was OK: measure the RAM. Revert `mtx-pxe` to `pxe-empty`, set its memory to **4 GB**, run steps 1-5 again. Note if it works. (A snapshot revert also sets the memory back to the value of the snapshot. Check the setting after every revert.)

## Expected result
- [ ] No key was pressed between power-on and the login screen.
- [ ] `migratux status` showed `install`, later `installed`, later `failed: Kein Inventar …`; "PXE-Job" is gone after the install.
- [ ] After the reboot the PC does **not** install a second time.
- [ ] Login as `mtxadmin` works; the desktop is German; the keyboard layout is Swiss (`z`/`y`, `ä ö ü`).
- [ ] Step 6: `LANG=de_CH.UTF-8`, layout `ch`, `ssh` and `NetworkManager` are `active`.
- [ ] Step 7: SSH login works.
- [ ] Time from power-on to login screen: ____ min.
- [ ] Step 9 (optional): the install works with 4 GB RAM: yes / no / not tried.

## If it fails
- After "lade Installer" the screen shows "Unable to find a live file system on the network" and an `(initramfs)` prompt: the installer could not mount `SERVER_IP:/srv/nfsroot`. On the server: `docker compose ps` (is `nfs` running?) and `docker compose logs nfs` (is there a line "authenticated mount request from" the client?). No such line: the client does not reach the ports 111, 2049, 20048 (firewall on the server: `sudo ufw status`), or its IP is not in the subnet named in the line "NFS: exporting …". Take a screenshot of the lines above the prompt.
- The same message right after `setup.sh` downloaded a newer ISO: kernel, initrd and the unpacked ISO must be from the same ISO. Run `./setup.sh` again and check that it ends with `setup: done` without a "Missing:" warning.
- The install hangs for minutes with "nfs: server … not responding": the network to the server was cut, or the `nfs` container was restarted. Send `m4-compose.log`.
- Kernel panic or "out of memory" during the install: too little RAM. Set the VM to 8 GB and note it in the result.
- Old problem, solved on 2026-11-16 by the switch to NFS: `wget: short write: No space left on device` at "lade Installer". If you still see it, the server runs old code: sync the code, run `./setup.sh` and `docker compose up -d`. History: [results/M4-2026-11-16.md](results/M4-2026-11-16.md).
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
VMs + RAM of mtx-pxe (check with the VM settings after the snapshot revert), VMware version:
Time power-on -> login screen:
Result per expected-result box: …
Problem (if any): what you saw, at which step
```

Attach:
- the log files: `~/m4-status.txt`, `~/m4-compose.log`, from the client `install.log` and `firstboot.log`
- a screenshot of: the boot menu with the job entry, the login screen, the output of step 6

## Results
Logs and screenshots are in [results/m4/](results/m4/).

| Date | Result | File |
|---|---|---|
| 2026-11-16 | FAILED (the ISO did not fit into RAM; led to the switch to NFS) | [results/M4-2026-11-16.md](results/M4-2026-11-16.md) |
| 2026-11-17 | OK in runs 3 and 4 (NFS netboot; needs internet; e1000 hang fixed with vmxnet3; works with 4 GB RAM) | [results/M4-2026-11-17.md](results/M4-2026-11-17.md) |
