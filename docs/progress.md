# MigraTux: where are we? (simple version)

Last update: 2026-11-11

## In one sentence

All parts are **written** and pass the automatic tests. **None is tested on a real VM yet.** That is the next job.

## What MigraTux does, in 5 steps

1. **Collect**: a script looks at the Windows PC and writes a list (CSV): apps, folders, printers, hardware.
2. **Back up**: the user's files are copied to the server and checked.
3. **Install**: the PC starts from the network and installs Ubuntu by itself.
4. **Reconfigure**: Linux installs replacement apps and copies the files back.
5. **Rollback**: if something goes wrong, a saved copy of the whole disk brings Windows back.

## What is written

| Part | Where | Written | Automatic tests | Tested on a VM |
|---|---|---|---|---|
| Server (file share, network boot, web server) | `server/` | yes | yes | **no** |
| Unattended Ubuntu install | `install/` | yes | yes | **no** |
| Windows list script (baseline) | `collect/Get-Inventory.ps1` | yes | yes | **no** |
| Windows backup script | `collect/Backup-ToServer.ps1` | yes | yes | **no** |
| Apps + files on Linux | `reconfigure/` | yes | yes | **no** |
| Rollback (disk copy and restore) | `install/mtx-early.sh` | yes | yes | **no** |
| Control command `migratux` | `server/migratux` | yes | yes | **no** |
| Info screen on the PC | `reconfigure/screen.sh` | yes | yes | **no** |

"Automatic tests" run on the dev machine with fake Windows, fake disks and a fake server
(`tests/run.sh`). They catch logic mistakes. They **cannot** prove that network boot,
the install or Windows really work. Only the VM tests can.

## What you can test now

Every part has a step-by-step guide in `docs/testing/`. Do them in this order,
because each one needs the one before:

| # | Guide | What you check | VMs | Time |
|---|---|---|---|---|
| 1 | `M3-server-pxe.md` | server starts, empty VM shows the boot menu, Windows opens the share | server, pxe, win | 45 min |
| 2 | `M4-autoinstall.md` | empty VM installs Ubuntu with no input | server, pxe | 50 min |
| 3 | `M1-inventory.md` | Windows list script | win | 20 min |
| 4 | `M2-backup.md` | backup; also many files; also server disk full | server, win | 45 min |
| 5 | `M5-reconfigure.md` | full chain: apps and files arrive on Linux | all three | 90 min |
| 6 | `M6-rollback.md` | break it on purpose, roll back to Windows | server, win | 2 h |
| 7 | `M7-cli.md` | `migratux` command and the info screen | server | 15 min |

Each guide ends with "What to send back". Paste that to Claude; failures become fix tasks.

**Start with number 1.** It is the riskiest part (network boot) and everything else depends on it.

## The three pitch scenarios

| Scenario | Where it is tested |
|---|---|
| Low disk space: stops cleanly | `M2-backup.md`, run C |
| Many user files: all arrive | `M2-backup.md` run B, `M5-reconfigure.md` |
| Failure, then rollback | `M6-rollback.md` |

## Good to know

- The empty test VM `mtx-pxe` needs **8 GB RAM** (the installer is 3.9 GB and loads into RAM).
- Network boot works with **UEFI** only, not old BIOS mode.
- A PC is only installed after `./migratux start <PC-NAME>` on the server. It never installs by itself.
- Passwords in `server/.env` are for the lab only (no encryption yet).
- Not moved over automatically: printers, network drives, app settings. The report lists them as "to do by hand".
- The Windows list script is a **baseline**. The teammate's script can replace it if its CSV has the same format (`docs/contracts/inventory-csv.md`).

## Not started

- M8: WinBoat for apps without a Linux alternative, web UI (only if time is left).
- M9: the demo on the two real laptops and the timelapse video.
