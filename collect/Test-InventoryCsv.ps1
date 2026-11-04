<#
.SYNOPSIS
    Checks an inventory CSV against docs/contracts/inventory-csv.md.
.DESCRIPTION
    Runs on Windows PowerShell 5.1 and PowerShell 7 (also on Linux).
    Returns an object with Valid, RowCount and Errors. Prints nothing else,
    so it can be used in scripts and in Pester tests.
    Keep this file ASCII-only: PowerShell 5.1 reads BOM-less scripts as ANSI.
.EXAMPLE
    $r = .\Test-InventoryCsv.ps1 -Path .\inventory-KMU-PC01.csv
    if (-not $r.Valid) { $r.Errors }
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$Path
)

$Columns    = @('Hostname', 'Category', 'Name', 'Version', 'Publisher', 'Path', 'SizeMB', 'Extra')
$Categories = @('app', 'userfolder', 'printer', 'network', 'hardware')
$errors     = [System.Collections.Generic.List[string]]::new()

function New-Result([int]$RowCount) {
    [pscustomobject]@{
        Valid    = ($errors.Count -eq 0)
        RowCount = $RowCount
        Errors   = $errors.ToArray()
    }
}

if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    $errors.Add("File not found: $Path")
    return New-Result 0
}
$full  = (Resolve-Path -LiteralPath $Path).ProviderPath
$bytes = [System.IO.File]::ReadAllBytes($full)

if ($bytes.Length -lt 3 -or $bytes[0] -ne 0xEF -or $bytes[1] -ne 0xBB -or $bytes[2] -ne 0xBF) {
    $errors.Add('Encoding: file must be UTF-8 with BOM (Export-Csv -Encoding UTF8 on PowerShell 5.1, utf8BOM on 7).')
}

# Header: exact column names and order, comma delimiter, no #TYPE line.
$lines = [System.IO.File]::ReadAllLines($full, [System.Text.Encoding]::UTF8)
if ($lines.Count -eq 0) {
    $errors.Add('File is empty.')
    return New-Result 0
}
if ($lines[0].StartsWith('#TYPE')) {
    $errors.Add('Line 1: #TYPE line found. Use Export-Csv -NoTypeInformation.')
    return New-Result 0
}
$header = ($lines[0] -split ',') | ForEach-Object { $_.Trim('"') }
if (($header -join ',') -cne ($Columns -join ',')) {
    $errors.Add("Line 1: header must be exactly $($Columns -join ',') (comma-separated). Found: $($lines[0])")
    return New-Result 0
}

$rows = @(Import-Csv -LiteralPath $full -Encoding UTF8)
if ($rows.Count -eq 0) {
    $errors.Add('No data rows.')
}

$hostname = if ($rows.Count -gt 0) { $rows[0].Hostname } else { '' }
for ($i = 0; $i -lt $rows.Count; $i++) {
    $row  = $rows[$i]
    $line = $i + 2

    foreach ($col in $Columns) {
        if ($row.$col -match "[`r`n]") { $errors.Add("Line ${line}: $col contains a line break.") }
    }
    if ([string]::IsNullOrWhiteSpace($row.Hostname)) {
        $errors.Add("Line ${line}: Hostname is empty.")
    } elseif ($row.Hostname -cne $hostname) {
        $errors.Add("Line ${line}: Hostname '$($row.Hostname)' differs from '$hostname' (one host per file).")
    }
    if ($Categories -cnotcontains $row.Category) {
        $errors.Add("Line ${line}: Category '$($row.Category)' is not one of $($Categories -join '|').")
    }
    if ([string]::IsNullOrWhiteSpace($row.Name)) {
        $errors.Add("Line ${line}: Name is empty.")
    }
    if ($row.SizeMB -ne '' -and $row.SizeMB -notmatch '^\d+$') {
        $errors.Add("Line ${line}: SizeMB '$($row.SizeMB)' must be empty or a whole number.")
    }
    if ($row.Extra -ne '') {
        foreach ($pair in $row.Extra -split ';') {
            if ($pair -cnotmatch '^[a-z0-9_]+=[^=]*$') {
                $errors.Add("Line ${line}: Extra part '$pair' must look like key=value (lowercase key, ';' between pairs).")
            }
        }
    }
}

New-Result $rows.Count
