# M1: Windows inventory to CSV (manual VM test)

| | |
|---|---|
| Milestone | M1 |
| Test doc version | 2026-11-11 |
| Time estimate | ~20 min (setup 5, run 10, collecting results 5) |
| Destructive? | no (the script only reads) |

## Goal
`collect/Get-Inventory.ps1` lists the installed apps, user folders, printers, network adapters and hardware of a real Windows PC in a CSV that matches the contract, on **Windows PowerShell 5.1**. This script is a baseline; the teammate's script may replace it and must pass the same test.

## VMs needed

| VM | Needed | Snapshot to restore first | Notes |
|---|---|---|---|
| `mtx-server` | ☐ | – | |
| `mtx-win` (Windows 10/11 client) | ☑ | `win-clean` | with a few apps and test files, as the VM Lab page says |
| `mtx-pxe` | ☐ | – | |

## Before you start
- Copy the repo to `C:\migratux` on `mtx-win`. Write down `git log -1 --oneline`.
- Write down which apps you installed on the VM (for the check in step 5) and which files are in Documents and on the Desktop.
- Use **Windows PowerShell** (blue icon), not `pwsh`.

## Steps
1. Open Windows PowerShell **as a normal user** (not as administrator):
   ```powershell
   Set-ExecutionPolicy -Scope Process Bypass
   cd C:\migratux
   .\collect\Get-Inventory.ps1 -OutDir C:\migratux\out
   echo "exit code: $LASTEXITCODE"
   ```
2. Check the file against the contract:
   ```powershell
   .\collect\Test-InventoryCsv.ps1 -Path C:\migratux\out\inventory-$env:COMPUTERNAME.csv | Format-List
   ```
3. Count the rows per category:
   ```powershell
   $rows = Import-Csv C:\migratux\out\inventory-$env:COMPUTERNAME.csv
   $rows | Group-Object Category | Format-Table Name, Count
   $rows | Where-Object Category -eq app | Sort-Object Name | Format-Table Name, Version, Extra
   $rows | Where-Object Category -ne app | Format-Table Category, Name, Path, SizeMB, Extra
   ```
4. Compare with Windows: Settings > Apps > Installed apps.
5. Repeat step 1 in a PowerShell **as administrator** with `-OutDir C:\migratux\out-admin`, and compare the `userfolder` rows.
6. Optional, together with `docs/testing/M0-ps51-checker.md`: the Pester suite on PowerShell 5.1 (expect `Failed: 0`).

## Expected result
- [ ] Step 1: last line starts with `OK:` and `exit code: 0`. No red text.
- [ ] Step 2: `Valid : True`, `Errors : {}`.
- [ ] Step 3: all five categories appear: `app`, `userfolder`, `printer`, `network`, `hardware`.
- [ ] Every app you installed on the VM appears (e.g. Chrome, Firefox, 7-Zip, VLC). No Windows updates (KB…) in the list.
- [ ] `userfolder`: Desktop, Documents, Pictures … of your user, with a plausible size and file count.
- [ ] `network`: one `type=adapter` row with the MAC address of the VM (compare with `getmac`).
- [ ] `hardware`: `OS`, `Model`, `RAM`, `CPU`, `Disk` with `free_mb=`. `OS` has `firmware=uefi`.
- [ ] Umlauts in names (e.g. a printer or folder with `ü`) are correct when you open the CSV in Notepad.
- [ ] Step 5: as administrator the CSV also has the folders of the other users; as a normal user the log says they were skipped.

## If it fails
- "running scripts is disabled": the `Set-ExecutionPolicy` line was skipped.
- A red parser error mentioning a character or `::new`: a real PowerShell 5.1 problem. Send the exact text.
- An app is missing: look it up in the registry (`HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall`, the `WOW6432Node` twin, and `HKCU`). Store apps (e.g. the new Outlook, WhatsApp) are **not** in these keys and are not listed: known limit.
- `Collector 'xyz' failed`: send `inventory.log`.

## What to send back
```
M1 test: OK | FAILED
Date / tester:
Repo commit:
Windows build (winver) + $PSVersionTable.PSVersion:
Time taken:
Rows per category: app / userfolder / printer / network / hardware
Apps installed on the VM but missing in the CSV:
Result per expected-result box: …
Problem (if any): what you saw, at which step
```

Attach:
- the log file: `C:\migratux\out\inventory.log`
- the output files: `C:\migratux\out\inventory-<HOSTNAME>.csv` (and the one from `out-admin`)
- a screenshot of: step 3
