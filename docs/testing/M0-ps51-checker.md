# M0: Contract checker on Windows PowerShell 5.1 (manual VM test)

| | |
|---|---|
| Milestone | M0 (follow-up), repeat for every new `.ps1` in `collect/` |
| Test doc version | 2026-11-11 |
| Time estimate | ~15 min (setup 5, run 5, collecting results 5) |
| Destructive? | no |

## Goal
Prove that `collect/Test-InventoryCsv.ps1` and its Pester tests also work on **Windows PowerShell 5.1**, the version built into Windows 10/11. The automatic tests only run PowerShell 7 on Linux. Older versions (PowerShell 2–4, Windows 7/8) are out of scope.

## VMs needed

| VM | Needed | Snapshot to restore first | Notes |
|---|---|---|---|
| `mtx-server` | ☐ | – | |
| `mtx-win` (Windows 10/11 client) | ☑ | `win-clean` | needs internet once to install Pester 5 |
| `mtx-pxe` | ☐ | – | |

## Before you start
- Lab set up as in [lab-setup.md](../lab-setup.md). Go back to the snapshot `win-clean`.
- On `mtx-win`: get the newest code into `C:\migratux` (the PowerShell block in [lab-setup.md](../lab-setup.md), part 3). Use **Windows PowerShell** (blue icon), not `pwsh`.

## Steps
1. Open Windows PowerShell.
2. Check the version (must show `5.1.x` and `Desktop`):
   ```powershell
   $PSVersionTable.PSVersion; $PSVersionTable.PSEdition
   ```
3. Allow scripts for this window only:
   ```powershell
   Set-ExecutionPolicy -Scope Process Bypass
   cd C:\migratux
   ```
4. Check the sample file:
   ```powershell
   .\collect\Test-InventoryCsv.ps1 -Path .\tests\fixtures\inventory-sample.csv | Format-List
   ```
5. Round trip: write a CSV the way the contract says and check it:
   ```powershell
   [pscustomobject]@{ Hostname=$env:COMPUTERNAME; Category='app'; Name='Offerte Müller'; Version='1'; Publisher='Test, AG'; Path='C:\Temp'; SizeMB=5; Extra='scope=machine' } |
       Export-Csv -Path $env:TEMP\inv.csv -NoTypeInformation -Encoding UTF8
   .\collect\Test-InventoryCsv.ps1 -Path $env:TEMP\inv.csv | Format-List
   ```
6. Install Pester 5 (Windows ships the old Pester 3.4) and run the test suite:
   ```powershell
   Install-Module Pester -RequiredVersion 5.7.1 -Scope CurrentUser -Force -SkipPublisherCheck
   Import-Module Pester -RequiredVersion 5.7.1
   Invoke-Pester .\tests\pester -Output Detailed *> $env:TEMP\pester-ps51.txt
   Get-Content $env:TEMP\pester-ps51.txt -Tail 5
   ```

## Expected result
- [ ] Step 2 shows `5.1.x` and `Desktop`.
- [ ] Step 4: `Valid : True`, `RowCount : 26`, `Errors : {}`.
- [ ] Step 5: `Valid : True`, `RowCount : 1`.
- [ ] Step 6: `Failed: 0` (since M1/M2 the suite also tests `Get-Inventory.ps1` and `Backup-ToServer.ps1`: about 53 passed, 3 skipped, because three tests need Linux or PowerShell 7).
- [ ] No red error text in any step.

## If it fails
- Red text about the script not being signed or blocked: step 3 was skipped, or run `Unblock-File` on the copied files.
- `Install-Module` asks for NuGet: answer `Y`.
- An error about `::new` or `-cnotmatch`: that is a real PowerShell 5.1 incompatibility. Send the exact message.

## What to send back
```
M0 PS 5.1 test: OK | FAILED
Date / tester:
Repo commit:
Windows build (winver) + PSVersion:
Time taken:
Step 4 / 5 / 6 result:
Problem (if any): step, exact error text
```

Attach:
- the log file: `%TEMP%\pester-ps51.txt`
- a screenshot of steps 4 and 5
