# collect/ (Windows, PowerShell)

Runs on the Windows PC before the migration. Milestones M1 (inventory) and M2 (backup to the server).

- Inventory script (M1): written by a teammate. It writes `inventory-<HOSTNAME>.csv` in the format of [`docs/contracts/inventory-csv.md`](../docs/contracts/inventory-csv.md).
- `Test-InventoryCsv.ps1`: checks a CSV against that contract. Works on Windows PowerShell 5.1 and PowerShell 7.

Rules for scripts here:
- Must run on Windows PowerShell 5.1 (Windows 10/11 default). Test under pwsh 7 with Pester as well (`tests/run.sh pester`).
- Keep `.ps1` files ASCII-only, or save them as UTF-8 **with BOM**. PowerShell 5.1 reads BOM-less files as ANSI and breaks umlauts.
- Say at the top whether the script needs admin rights.
