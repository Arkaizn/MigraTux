# Contract: Inventory CSV

The Windows inventory script (`collect/`) writes one CSV per PC. Everything later in the chain reads it: the backup (M2), the app mapping (`mapping/map-apps.sh`) and the Linux post-install (M5). This page is the only definition of the format. Version 1, 2026-11-04.

Example: [`tests/fixtures/inventory-sample.csv`](../../tests/fixtures/inventory-sample.csv). Checker: `collect/Test-InventoryCsv.ps1`.

## File

| Rule | Value |
|---|---|
| File name | `inventory-<HOSTNAME>.csv`, e.g. `inventory-KMU-PC01.csv` |
| Encoding | **UTF-8 with BOM**. This is what `Export-Csv -Encoding UTF8` writes on Windows PowerShell 5.1. On PowerShell 7 use `-Encoding utf8BOM`. Umlauts (`Müller`, `Büro`) must survive. |
| Delimiter | **Comma** `,`. Do not use `-UseCulture` or `-Delimiter ';'` (Swiss/German Windows would give `;`). |
| Header | First line, exactly these 8 columns in this order. No `#TYPE` line, so always pass `-NoTypeInformation`. |
| Quoting | Fields may be in double quotes (PowerShell quotes all of them, that's fine). A `"` inside a field is written as `""`. |
| Line breaks | CRLF or LF. **No line breaks inside a field**: replace them with a space. |
| One host | Every row has the same `Hostname`. |

## Columns

| Column | Required | Content |
|---|---|---|
| `Hostname` | yes | `$env:COMPUTERNAME` |
| `Category` | yes | exactly one of `app`, `userfolder`, `printer`, `network`, `hardware` (lowercase) |
| `Name` | yes | what the row is about (see table below) |
| `Version` | no | version string as Windows reports it |
| `Publisher` | no | vendor / manufacturer |
| `Path` | no | file system path or UNC path |
| `SizeMB` | no | **whole number** of megabytes, empty if unknown. No decimals (avoids `12,5` vs `12.5`). |
| `Extra` | no | more facts as `key=value` pairs, separated by `;`. Keys lowercase `a-z 0-9 _`. Values contain no `;` and no `=`. Unknown keys are allowed. |

## What goes where, per category

| Category | Name | Version | Publisher | Path | SizeMB | Extra keys |
|---|---|---|---|---|---|---|
| `app` | `DisplayName` from the Uninstall key | `DisplayVersion` | `Publisher` | `InstallLocation` | `EstimatedSize` / 1024, rounded | `scope=machine\|user`, `arch=x64\|x86` |
| `userfolder` | `Documents`, `Desktop`, `Pictures`, `Downloads`, `Music`, `Videos`, … | – | – | full path | total size | `user=<login>`, `files=<count>` |
| `printer` | printer name | – | driver vendor if known | – | – | `driver=`, `port=`, `default=true\|false` |
| `network` | drive letter `Z:` or adapter name | – | adapter vendor | UNC path for drives | – | `type=drive\|adapter`, adapters: `mac=`, `ip=`, `dhcp=true\|false` |
| `hardware` | `OS`, `Model`, `CPU`, `RAM`, `Disk` | OS build for `OS` | manufacturer | `C:` for `Disk` | RAM / disk size | `caption=`, `model=`, `cores=`, `free_mb=`, `type=SSD\|HDD` |

Rows that do not fit any category are left out. Add new facts as `Extra` keys first; a new column means a new contract version.

## Writing it from PowerShell

The script only has to build objects with these 8 properties and export them:

```powershell
$rows = [System.Collections.Generic.List[object]]::new()
$rows.Add([pscustomobject]@{
    Hostname  = $env:COMPUTERNAME
    Category  = 'app'
    Name      = $app.DisplayName
    Version   = $app.DisplayVersion
    Publisher = $app.Publisher
    Path      = $app.InstallLocation
    SizeMB    = if ($app.EstimatedSize) { [int][math]::Round($app.EstimatedSize / 1024) } else { '' }
    Extra     = 'scope=machine;arch=x64'
})
# ... more rows ...
$out = Join-Path $PWD "inventory-$env:COMPUTERNAME.csv"
$rows | Select-Object Hostname, Category, Name, Version, Publisher, Path, SizeMB, Extra |
    Export-Csv -Path $out -NoTypeInformation -Encoding UTF8      # PowerShell 7: -Encoding utf8BOM
```

`Select-Object` fixes the column order. Check the result:

```powershell
$r = .\collect\Test-InventoryCsv.ps1 -Path $out
$r.Valid; $r.Errors
```

## Reading it

- PowerShell: `Import-Csv -Path $f -Encoding UTF8`.
- Shell: strip the BOM and `\r`, then parse quoted fields (see `mapping/map-apps.sh`). Readers also accept files without BOM.
