# M2: Backup of the user data to the server (manual VM test)

| | |
|---|---|
| Milestone | M2 |
| Test doc version | 2026-11-11 |
| Time estimate | ~45 min (setup 10, three runs 25, collecting results 10) |
| Destructive? | no (source files are only read) |

## Goal
`collect/Backup-ToServer.ps1` copies the user folders and the inventory to `\\server\migratux\<HOSTNAME>\`, and every file arrives unchanged. It covers two pitch scenarios: **many user files** and **low disk space** (the script must stop cleanly before copying).

## VMs needed

| VM | Needed | Snapshot to restore first | Notes |
|---|---|---|---|
| `mtx-server` | ☑ | `server-clean` | |
| `mtx-win` (Windows 10/11 client) | ☑ | `win-clean` | |
| `mtx-pxe` | ☐ | – | |

## Before you start
- Lab set up as in [lab-setup.md](../lab-setup.md). Go back to the snapshots in the table above (**VM → Snapshot → Revert**).
- Start `mtx-server` and get the newest code (nothing is downloaded again):
  ```bash
  cd ~/MigraTux/server && git pull && ./setup.sh && docker compose up -d
  docker compose ps          # samba, pxe, http: all "running"
  ```
- On `mtx-win`: get the newest code into `C:\migratux` (the PowerShell block in [lab-setup.md](../lab-setup.md), part 3). Use **Windows PowerShell** (blue icon), not `pwsh`.
- In the commands below replace `192.168.80.130` with your server IP and the password with `SMB_PASSWORD` from `server/.env`.

## Steps

### Run A: normal backup
1. On `mtx-win`, Windows PowerShell as a normal user:
   ```powershell
   Set-ExecutionPolicy -Scope Process Bypass
   cd C:\migratux
   .\collect\Get-Inventory.ps1 -OutDir C:\migratux\out
   .\collect\Backup-ToServer.ps1 -InventoryPath C:\migratux\out\inventory-$env:COMPUTERNAME.csv `
       -Destination \\192.168.80.130\migratux -User migratux -Password ChangeMe-Lab1
   echo "exit code: $LASTEXITCODE"
   ```
2. On `mtx-server` (replace `<HOST>` with the Windows computer name):
   ```bash
   cd ~/MigraTux/server
   ./migratux status
   cd data/share/<HOST>
   wc -l manifest.sha256
   sha256sum -c --quiet manifest.sha256 && echo ALL-FILES-OK
   ```

### Run B: many files with umlauts (pitch scenario)
3. On `mtx-win`, create 2000 small files and one large one, then inventory and backup again:
   ```powershell
   $dir = "$env:USERPROFILE\Documents\Aufträge Müller"
   New-Item -ItemType Directory -Path $dir -Force | Out-Null
   1..2000 | ForEach-Object { "Auftrag $_" | Set-Content "$dir\Auftrag_${_}_Zürich_Größe.txt" }
   fsutil file createnew "$env:USERPROFILE\Documents\gross.bin" 314572800
   Measure-Command {
       .\collect\Get-Inventory.ps1 -OutDir C:\migratux\out
       .\collect\Backup-ToServer.ps1 -InventoryPath C:\migratux\out\inventory-$env:COMPUTERNAME.csv `
           -Destination \\192.168.80.130\migratux -User migratux -Password ChangeMe-Lab1
   } | Select-Object TotalSeconds
   echo "exit code: $LASTEXITCODE"
   ```
4. On `mtx-server`, repeat step 2. Also: `ls "data/mmueller" 2>/dev/null; find data -name 'Auftrag_*' | wc -l` (inside `data/share/<HOST>`).

### Run C: low disk space on the server (pitch scenario)
5. On `mtx-server`, fill the disk until about 200 MB are free:
   ```bash
   cd ~/MigraTux/server
   free_mb=$(df --output=avail -BM data | tail -n 1 | tr -dc 0-9)
   fallocate -l $((free_mb - 200))M data/fill.bin
   df -h data
   ```
6. On `mtx-win`, run the backup command from step 1 again (data is now over 300 MB).
7. On `mtx-server`: `ls data/share/<HOST>/` and then **free the space again**:
   ```bash
   rm data/fill.bin; df -h data
   ```
8. On `mtx-win`, run the backup once more (must work again).

## Expected result
- [ ] Run A: last line starts with `OK:` and names the number of files; `exit code: 0`.
- [ ] Run A: `migratux status` shows the host with `Backup: ja (N Dateien)`; `ALL-FILES-OK` appears; `N` equals the number of files in the Windows folders.
- [ ] Run B: `exit code: 0`, the manifest has at least 2001 more lines, `find` counts 2000, `ALL-FILES-OK` again. Time: ____ s.
- [ ] Run B: file names on the server show `ä ö ü ß` correctly (`ls`).
- [ ] Run C: red line `NOT ENOUGH SPACE on the server … Nothing was copied.`; `exit code: 3`.
- [ ] Run C: `manifest.sha256` on the server is the old one from run B, untouched; no half-copied new data.
- [ ] Step 8: `exit code: 0` again.

## If it fails
- `net use failed` / "Cannot log in": wrong password, or Windows still has an old connection: `net use * /delete` and try again.
- `FAILED <file>: … being used by another process`: a program has the file open (e.g. Outlook). Close it. The backup then ends with exit code 4 and writes no manifest: that is intended.
- `FAILED` for paths longer than 260 characters: known limit of Windows PowerShell 5.1. Note the path.
- Very slow in run B: note the time; each file is read twice for the checksum.
- Run C copies anyway: check `df -h data` (less than 300 MB free?) and send `backup.log`.

## What to send back
```
M2 test: OK | FAILED
Date / tester:
Repo commit:
VMs + OS build:
Run A: files, MB, seconds, exit code
Run B: files, seconds, exit code
Run C: exit code, the red message
Result per expected-result box: …
Problem (if any): what you saw, at which step
```

Attach:
- the log file: `C:\migratux\out\backup.log`
- the output of steps 2, 4 and 7
- a screenshot of: the red message in run C
