# collect/ (Windows, PowerShell)

Runs on the Windows PC before the migration. Milestones M1 (inventory) and M2 (backup to the server).

| Script | What | Admin? |
|---|---|---|
| `Get-Inventory.ps1` | writes `inventory-<HOSTNAME>.csv` in the format of [`docs/contracts/inventory-csv.md`](../docs/contracts/inventory-csv.md): apps, user folders, printers, network, hardware. **Baseline**: the teammate's script may replace it or be merged into it, as long as the CSV matches the contract. | no; without admin only the current user's folders |
| `Backup-ToServer.ps1` | copies the user folders from the CSV and the CSV to `\\server\migratux\<HOSTNAME>\`, checks free space first, verifies every file, writes `manifest.sha256` last | no |
| `Test-InventoryCsv.ps1` | checks a CSV against the contract | no |

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\collect\Get-Inventory.ps1 -OutDir C:\migratux\out
.\collect\Backup-ToServer.ps1 -InventoryPath C:\migratux\out\inventory-$env:COMPUTERNAME.csv `
    -Destination \\<server-ip>\migratux -User migratux -Password <SMB_PASSWORD>
```

Logs: `inventory.log` and `backup.log` in the output folder. Exit code 0 = ok; the backup uses 3 for "not enough space on the server" and 4 for "some files failed".

Rules for scripts here:
- Must run on Windows PowerShell 5.1 (Windows 10/11 default). Test under pwsh 7 with Pester as well (`tests/run.sh pester`).
- Keep `.ps1` files ASCII-only, or save them as UTF-8 **with BOM**. PowerShell 5.1 reads BOM-less files as ANSI and breaks umlauts.
- Say at the top whether the script needs admin rights.
- Calls to Windows (registry, WMI, `net use`) go through small wrapper functions, so Pester can mock them on Linux.

Manual tests: [M1](../docs/testing/M1-inventory.md), [M2](../docs/testing/M2-backup.md), [PowerShell 5.1](../docs/testing/M0-ps51-checker.md).
