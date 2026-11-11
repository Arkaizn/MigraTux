# M6: Rollback, Windows comes back after a failed migration (manual VM test)

| | |
|---|---|
| Milestone | M6 |
| Test doc version | 2026-11-11 |
| Time estimate | ~2 h, mostly waiting (image 20–40 min, broken install 10, restore 20–40, checks 10) |
| Destructive? | **yes: wipes the disk of `mtx-win`** and writes it back. Take a snapshot first. |

## Goal
Pitch scenario **failure → rollback**: before the disk is wiped, a full copy of it goes to the server. The install is then broken on purpose. One command on the server and one network boot bring Windows back, with all data.

This test uses the Windows VM itself as the PC that is migrated (the real path, same MAC address).

## VMs needed

| VM | Needed | Snapshot to restore first | Notes |
|---|---|---|---|
| `mtx-server` | ☑ | the state after M3 (stack running) | free disk space: at least the **used** size of the Windows disk (check with `df -h ~/MigraTux/server/data`) |
| `mtx-win` | ☑ | `win-clean`, then see below | UEFI, set RAM to **8 GB** for this test |
| `mtx-pxe` | ☐ | – | |

## Before you start
- M2 and M4 passed. On `mtx-server`: `cd ~/MigraTux/server && git pull && ./setup.sh && docker compose up -d`.
- On `mtx-win`: put a file `ROLLBACK-TEST.txt` with today's date on the Desktop. Run inventory + backup (run A of `M2-backup.md`). Shut Windows down **completely**: `shutdown /s /t 0` in PowerShell.
- VM settings of `mtx-win`: 8 GB RAM. Take a VMware snapshot `win-before-m6` (safety net if the rollback itself fails).
- If you used `migratux assign` in M5: `./migratux unassign <HOST>`.

## Steps
1. On `mtx-server`:
   ```bash
   cd ~/MigraTux/server
   ./migratux start <HOST>          # disk image + install
   ./migratux status <HOST>         # PXE-Job: migrate
   watch -n 10 ./migratux status <HOST>
   ```
2. Start `mtx-win` **from the network**: VM > Power > Power On to Firmware > "EFI Network" (or put network boot first in the boot order).
3. Wait while the status shows `image: Disk-Abbild von … wird gesichert`. Note how long it takes. Then the status changes to `image-done` and `install`.
4. **Break it on purpose:** about 3 minutes after `install` appeared (the installer is now writing to the disk), power the VM off hard: VM > Power > Power Off.
5. Prove that it is broken: power the VM on normally (from disk). Windows does not start. Take a screenshot. Power off.
6. On `mtx-server`:
   ```bash
   ./migratux status <HOST>         # Disk-Abbild: ja (… GB, date)
   ls -lh data/images/<HOST>/
   ./migratux rollback <HOST>       # checks the image, then: PXE-Job restore
   ```
7. Start `mtx-win` from the network again (as in step 2). Do not touch it. The status shows `restore`, later `restored`. The VM reboots by itself.
8. Windows starts. Log in. Check that `ROLLBACK-TEST.txt` is on the Desktop, open a few documents, start one app.
9. On `mtx-server`: `./migratux status <HOST> > ~/m6-status.txt; docker compose logs http > ~/m6-http.log; cp data/log/migratux.log ~/m6-migratux.log`

### Extra check: a second try keeps the good image
10. Optional, 5 minutes: after step 5 (broken disk), instead of the rollback run `./migratux start <HOST>` and network-boot once more. The status must show `image-kept: Vorhandenes Disk-Abbild … bleibt erhalten`, **not** a new `image`. Power off, then continue with step 6.

## Expected result
- [ ] Step 3: the image is uploaded before anything is installed. Duration ____ min, size on the server ____ GB (`ls -lh`).
- [ ] Step 5: Windows no longer boots (the failure is real).
- [ ] Step 6: `rollback` prints no `ERROR` and sets the job `restore`.
- [ ] Step 7: restore runs with no input and the VM reboots by itself. Duration ____ min.
- [ ] Step 8: Windows boots, login works, `ROLLBACK-TEST.txt` and the documents are there, apps start.
- [ ] After the rollback `migratux status` shows `PXE-Job: keiner` and `restored: Rollback fertig …`; a normal reboot of the VM starts Windows, not the installer.
- [ ] Step 10 (if done): `image-kept` appeared and `data/images/<HOST>/disk.info` kept its old date.

## If it fails
- Step 3 fails with "disk image upload failed … Nothing was wiped": the server disk is full (`df -h data`). Windows is untouched: boot it from disk, free space, `./migratux start <HOST> --new-image`.
- Windows does not boot after the restore, firmware says no boot device or starts "ubuntu": open the firmware boot menu (Power On to Firmware) and choose "Windows Boot Manager". Note that this was needed.
- Windows asks for a **BitLocker recovery key**: note it. Device encryption reacts to the changed boot path. Lab VMs normally have BitLocker off.
- `rollback` says the image is damaged: do not continue; send `m6-http.log`. Go back to the snapshot `win-before-m6`.
- Restore stops with "disk … is smaller than the image": the VM disk was changed between image and restore.
- Windows starts a disk check after the restore: the VM was not shut down cleanly before the image (fast startup). Let it finish and note it.
- Anything else: go back to `win-before-m6`, nothing is lost.

## What to send back
```
M6 test: OK | FAILED
Date / tester:
Repo commit:
VMs + OS builds, size of the Windows disk (total / used):
Image: minutes, size on the server
Restore: minutes
Result per expected-result box: …
Problem (if any): what you saw, at which step
```

Attach:
- the log files: `~/m6-status.txt`, `~/m6-http.log`, `~/m6-migratux.log`
- a screenshot of: the broken boot (step 5), the restore running, Windows with `ROLLBACK-TEST.txt` (step 8)
