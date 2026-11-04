# Mx: <title> (manual VM test)

Copy this file to `docs/testing/Mx-<short-name>.md` and fill it in. One file per milestone. Lab setup: vault page *VM Lab VMware Workstation*.

| | |
|---|---|
| Milestone | Mx |
| Test doc version | YYYY-MM-DD |
| Time estimate | ~NN min (setup NN, run NN, collecting results NN) |
| Destructive? | yes/no (e.g. "wipes the disk of `mtx-pxe`") |

## Goal
One or two sentences: what this test proves. Example: "The inventory script lists all installed apps of a Windows 11 PC in a CSV that matches the contract."

## VMs needed
Tick what this test uses. You never need all three.

| VM | Needed | Snapshot to restore first | Notes |
|---|---|---|---|
| `mtx-server` (Ubuntu Server 24.04, Docker) | ☐ | `server-clean` | IP: write it down with `ip -4 addr` |
| `mtx-win` (Windows 10/11 client) | ☐ | `win-clean` | `Set-ExecutionPolicy -Scope Process Bypass` before running scripts |
| `mtx-pxe` (empty VM, network boot first) | ☐ | `pxe-empty` | |

All VMs on VMware NAT (VMnet8).

## Before you start
- Repo version to use: branch/commit `<...>` (`git log -1 --oneline` on the VM or the copy you used).
- Files to copy onto the VM, and where to.

## Steps
1. Restore the snapshots listed above.
2. …
3. …

Write the exact command for each step, e.g.

```powershell
cd C:\migratux
.\collect\Get-Inventory.ps1 -OutDir C:\migratux\out
```

## Expected result
Concrete and checkable, e.g.:
- [ ] Command ends with exit code 0 and no red error text.
- [ ] `C:\migratux\out\inventory-<HOSTNAME>.csv` exists.
- [ ] `.\collect\Test-InventoryCsv.ps1 -Path <file>` shows `Valid : True`.
- [ ] These apps appear: …

## If it fails
Typical causes and what to check first.

## What to send back
Send this to the vault (management) Claude, or paste it into the repo session:

```
Mx test: OK | FAILED
Date / tester:
Repo commit:
VMs + OS build (winver / lsb_release -a):
Time taken:
Result per expected-result box: …
Problem (if any): what you saw, at which step
```

Attach:
- the log file(s): `<path>`
- a screenshot of: `<what>`
- the output file(s): `<path>`
