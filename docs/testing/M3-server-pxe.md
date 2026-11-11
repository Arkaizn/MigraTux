# M3: Server stack and network boot (manual VM test)

| | |
|---|---|
| Milestone | M3 |
| Test doc version | 2026-11-11 |
| Time estimate | ~45 min (setup 30 incl. 3.9 GB download, run 10, collecting results 5) |
| Destructive? | no |

## Goal
The server stack starts with one setup command. An empty PC that boots from the network reaches the MigraTux boot menu, and Windows can open the share `\\server\migratux`.

## VMs needed

| VM | Needed | Snapshot to restore first | Notes |
|---|---|---|---|
| `mtx-server` (Ubuntu Server 24.04, Docker) | ☑ | `server-clean` | needs ~10 GB free for this test, much more for M6 |
| `mtx-win` (Windows 10/11 client) | ☑ | `win-clean` | only for step 8 |
| `mtx-pxe` (empty VM, network boot first) | ☑ | `pxe-empty` | UEFI, **8 GB RAM** (from M4 on) |

All VMs on VMware NAT (VMnet8).

## Before you start
- The repo on `mtx-server`, e.g. `git clone https://github.com/Arkaizn/MigraTux.git ~/MigraTux`. Write down `git log -1 --oneline`.
- Your user on `mtx-server` is in the `docker` group (`docker ps` works without sudo).

## Steps
1. On `mtx-server`, find the IP and the network interface:
   ```bash
   ip -4 -br addr        # e.g.  ens33  UP  192.168.80.130/24
   ```
2. Create the settings file and enter both values (`SERVER_IP`, `PXE_INTERFACE`). Leave the rest:
   ```bash
   cd ~/MigraTux/server
   cp .env.example .env
   nano .env
   ```
3. Run the setup. It builds the images and downloads the Ubuntu ISO (3.9 GB):
   ```bash
   ./setup.sh
   ```
4. Start the stack and check it:
   ```bash
   docker compose up -d
   docker compose ps          # samba, pxe, http: all "running"
   ./migratux status          # "Noch keine Clients ..."
   curl -sI http://localhost:8080/ubuntu.iso | head -n 1      # HTTP/1.1 200 OK
   ```
5. Watch the PXE log in a second terminal: `docker compose logs -f pxe`
6. Power on `mtx-pxe` (network boot first). Do **not** press anything.
7. Watch the screen of `mtx-pxe`: after the network boot messages a menu appears with "Von der Festplatte starten" and "Manuell: Ubuntu installieren …". After 8 seconds it takes the first entry; the disk is empty, so the VM then reports that there is nothing to boot. That is correct. Take a screenshot of the menu. Power the VM off.
8. On `mtx-win`, in PowerShell (replace the IP):
   ```powershell
   net use \\192.168.80.130\migratux ChangeMe-Lab1 /user:migratux
   "hello" | Set-Content \\192.168.80.130\migratux\test.txt
   dir \\192.168.80.130\migratux
   ```
9. Back on `mtx-server`: `cat data/share/test.txt` shows `hello`. Then `rm data/share/test.txt` (if "permission denied": `sudo rm`).
10. Save the logs: `docker compose logs > ~/m3-compose.log`

## Expected result
- [ ] Step 3 ends with `setup: done` and no line starting with `ERROR`.
- [ ] Step 4: three services running, the ISO answers with `200`.
- [ ] Step 6: the PXE log shows lines with `PXE` and `bootx64.efi`, then `sent /srv/tftp/bootx64.efi`, `grubx64.efi` and `grub/grub.cfg`.
- [ ] Step 7: the MigraTux menu is visible. **No install starts by itself** (there is no job for this PC).
- [ ] Step 8: `net use` says the command completed successfully; `dir` lists `test.txt`.
- [ ] Step 9: the file is on the server.

## If it fails
- `setup.sh`: "SERVER_IP … is not an IPv4 address" or "is empty": fix `server/.env`.
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
Time taken (setup.sh / rest):
Result per expected-result box: …
Problem (if any): what you saw, at which step
```

Attach:
- the log files: `~/m3-compose.log`, `server/data/log/setup.log`
- a screenshot of: the boot menu on `mtx-pxe`; the `dir` output on `mtx-win`
