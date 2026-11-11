# M3: Server stack and network boot (manual VM test)

| | |
|---|---|
| Milestone | M3 |
| Test doc version | 2026-11-11 |
| Time estimate | ~20 min (run 15, collecting results 5) |
| Destructive? | no |

## Goal
The server stack starts. An empty PC that boots from the network reaches the MigraTux boot menu, and Windows can open the share `\\server\migratux`.

## VMs needed

| VM | Needed | Snapshot to restore first | Notes |
|---|---|---|---|
| `mtx-server` (Ubuntu Server 24.04, Docker) | ☑ | `server-clean` | |
| `mtx-win` (Windows 10/11 client) | ☑ | `win-clean` | only for step 6 |
| `mtx-pxe` (empty VM) | ☑ | `pxe-empty` | UEFI, **8 GB RAM** |

All VMs on VMware NAT (VMnet8).

## Before you start
- Lab set up as in [lab-setup.md](../lab-setup.md). Go back to the snapshots in the table above (**VM → Snapshot → Revert**).
- Start `mtx-server` and get the newest code (nothing is downloaded again):
  ```bash
  cd ~/MigraTux/server && git pull && ./setup.sh && docker compose up -d
  docker compose ps          # samba, pxe, http: all "running"
  ```

## Steps
1. On `mtx-server`, look up the IP (you need it in step 6) and check the stack:
   ```bash
   ip -4 -br addr             # e.g.  ens33  UP  192.168.80.130/24
   ./migratux status          # "Noch keine Clients ..."
   curl -sI http://localhost:8080/ubuntu.iso | head -n 1      # HTTP/1.1 200 OK
   ```
2. Watch the PXE log in a second terminal: `docker compose logs -f pxe`
3. Power on `mtx-pxe`. Do **not** press anything. Its disk is empty, so VMware boots from the network by itself.
4. Watch the screen of `mtx-pxe`: after the network boot messages a menu appears with "Von der Festplatte starten" and "Manuell: Ubuntu installieren …". After 8 seconds it takes the first entry; the disk is empty, so the VM then reports that there is nothing to boot. That is correct. Take a screenshot of the menu. Power the VM off.
5. Start `mtx-win`.
6. On `mtx-win`, in PowerShell (replace the IP):
   ```powershell
   net use \\192.168.80.130\migratux ChangeMe-Lab1 /user:migratux
   "hello" | Set-Content \\192.168.80.130\migratux\test.txt
   dir \\192.168.80.130\migratux
   ```
7. Back on `mtx-server`: `cat data/share/test.txt` shows `hello`. Then `rm data/share/test.txt` (if "permission denied": `sudo rm`).
8. Save the logs: `docker compose logs > ~/m3-compose.log`

## Expected result
- [ ] Before you start: `setup.sh` ends with `setup: done`, three services are running.
- [ ] Step 1: the ISO answers with `200`.
- [ ] Step 3: the PXE log shows lines with `PXE` and `bootx64.efi`, then `sent /srv/tftp/bootx64.efi`, `grubx64.efi` and `grub/grub.cfg`.
- [ ] Step 4: the MigraTux menu is visible. **No install starts by itself** (there is no job for this PC).
- [ ] Step 6: `net use` says the command completed successfully; `dir` lists `test.txt`.
- [ ] Step 7: the file is on the server.

## If it fails
- `setup.sh`: "SERVER_IP … is not an IPv4 address" or "is empty": fix `server/.env`.
- `setup.sh`: "dnsmasq.conf: Is a directory", or `docker compose up` says "Are you trying to mount a directory onto a file": `docker compose up` was started before `setup.sh` had finished. Fix: `docker compose down`, `git pull`, `./setup.sh`, `docker compose up -d`.
- The IP in step 1 is not the `SERVER_IP` in `server/.env`: put the new IP in `.env`, run `./setup.sh` and `docker compose up -d` again, and take the snapshot `server-clean` again.
- `mtx-pxe` shows "No DHCP offers" or goes straight to "no boot device": is `PXE_INTERFACE` right? Are both VMs on NAT? Does `docker compose logs pxe` show anything when the VM starts? If the log stays empty, the server does not see the client.
- The PXE log shows the request, but the VM does not load `bootx64.efi`: send the log. This is the part that could not be tested without VMs (proxy-DHCP with VMware's own DHCP server).
- The VM firmware must be **UEFI**. BIOS/legacy network boot is not supported.
- Secure Boot error: send a screenshot. The boot loader is Ubuntu's signed shim.
- `net use` error 53 / 67: Windows cannot reach port 445. Check `docker compose ps` and `sudo ss -ltnp | grep 445`.
- `docker compose up` says port 445 or 8080 is in use: another service on the server uses it.

## What to send back
```
M3 test: OK | FAILED
Date / tester:
Repo commit:
VMs + OS build (winver / lsb_release -a), VMware version:
Time taken:
Result per expected-result box: …
Problem (if any): what you saw, at which step
```

Attach:
- the log files: `~/m3-compose.log`, `server/data/log/setup.log`
- a screenshot of: the boot menu on `mtx-pxe`; the `dir` output on `mtx-win`
