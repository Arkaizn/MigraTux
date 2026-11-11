<#
.SYNOPSIS
    MigraTux backup (M2): copies the user folders listed in the inventory CSV
    and the CSV itself to the MigraTux server, with a checksum manifest.
.DESCRIPTION
    Target layout (docs/contracts/backup-layout.md):
        <Destination>\<HOSTNAME>\inventory-<HOSTNAME>.csv
        <Destination>\<HOSTNAME>\data\<user>\<Folder>\...
        <Destination>\<HOSTNAME>\manifest.sha256      (written last = backup complete)
        <Destination>\<HOSTNAME>\backup.log

    Before copying, the script compares the size of the data with the free
    space on the server and stops without copying anything if it does not fit.
    Every file is hashed (SHA-256) at the source and again on the server.

    Admin rights: NOT required for the folders of the current user. To back up
    all profiles, run Get-Inventory.ps1 and this script elevated.

    Runs on Windows PowerShell 5.1 and PowerShell 7. Source files are only read.
    Keep this file ASCII-only: PowerShell 5.1 reads BOM-less scripts as ANSI.
.PARAMETER InventoryPath
    The CSV written by Get-Inventory.ps1.
.PARAMETER Destination
    The share, e.g. \\192.168.80.10\migratux (or a local folder for tests).
.PARAMETER User
    Share user. With -Password the share is connected with "net use" first.
.PARAMETER MarginPercent
    Free space that must remain on top of the data size. Default 10 (+100 MB).
.OUTPUTS
    Exit code 0 = all files copied and verified
              1 = bad arguments, inventory invalid or share not reachable
              3 = not enough free space on the server (nothing copied)
              4 = some files failed to copy or verify (no manifest written)
.EXAMPLE
    .\collect\Backup-ToServer.ps1 -InventoryPath C:\migratux\out\inventory-KMU-PC01.csv `
        -Destination \\192.168.80.10\migratux -User migratux -Password ChangeMe-Lab1
#>
[CmdletBinding()]
param(
    [string]$InventoryPath,
    [string]$Destination,
    [string]$User,
    [string]$Password,
    [int]$MarginPercent = 10,
    [string]$LogPath
)

$script:MtxLogFile = $null
$script:MtxFixedMarginBytes = 100MB

function Write-MtxLog {
    param([string]$Message, [string]$Level = 'INFO')
    $line = '{0} {1} {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    if ($script:MtxLogFile) { Add-Content -LiteralPath $script:MtxLogFile -Value $line -Encoding UTF8 }
    if ($Level -eq 'ERROR') { Write-Host $line -ForegroundColor Red }
    elseif ($Level -eq 'WARN') { Write-Host $line -ForegroundColor Yellow }
    else { Write-Host $line }
}

# ---- Thin wrappers. The Pester tests replace them with mocks. ----

# Log in to the share. Returns $true when it worked.
function Connect-MtxShare {
    param([string]$Share, [string]$User, [string]$Password)
    $output = & net.exe use $Share $Password "/user:$User" 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-MtxLog "net use failed: $($output -join ' ')" 'ERROR'
        return $false
    }
    return $true
}

# Free bytes at a path. Works for UNC paths (GetDiskFreeSpaceEx) and local folders.
function Get-MtxFreeBytes {
    param([string]$Path)
    if ($Path.StartsWith('\\')) {
        if (-not ('MigraTux.Native' -as [type])) {
            Add-Type -Namespace MigraTux -Name Native -MemberDefinition @'
[DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
public static extern bool GetDiskFreeSpaceEx(string lpDirectoryName, out ulong lpFreeBytesAvailable, out ulong lpTotalNumberOfBytes, out ulong lpTotalNumberOfFreeBytes);
'@
        }
        [uint64]$free = 0; [uint64]$total = 0; [uint64]$totalFree = 0
        if (-not [MigraTux.Native]::GetDiskFreeSpaceEx($Path, [ref]$free, [ref]$total, [ref]$totalFree)) {
            throw "Cannot read the free space of $Path"
        }
        return [long]$free
    }
    $full = (Resolve-Path -LiteralPath $Path).ProviderPath
    $drive = New-Object System.IO.DriveInfo ([System.IO.Path]::GetPathRoot($full))
    return [long]$drive.AvailableFreeSpace
}

function Get-MtxFileHash {
    param([string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLower()
}

# ---- Steps ----

# The files to copy: one object per file with Source, Relative (forward
# slashes, below the host folder) and Bytes.
function Get-MtxBackupPlan {
    param([object[]]$Rows)
    $plan = New-Object System.Collections.Generic.List[object]
    $seen = @{}
    foreach ($row in $Rows) {
        if ($row.Category -ne 'userfolder') { continue }
        $user = ''
        foreach ($pair in ($row.Extra -split ';')) {
            if ($pair -like 'user=*') { $user = $pair.Substring(5) }
        }
        if ($user -eq '' -or $row.Path -eq '') {
            Write-MtxLog "Folder row '$($row.Name)' has no user or path, skipped." 'WARN'
            continue
        }
        if (-not (Test-Path -LiteralPath $row.Path -PathType Container)) {
            Write-MtxLog "Folder not found, skipped: $($row.Path)" 'WARN'
            continue
        }
        $root = (Resolve-Path -LiteralPath $row.Path).ProviderPath.TrimEnd('\', '/')
        $files = @(Get-ChildItem -LiteralPath $root -Recurse -File -Force -ErrorAction SilentlyContinue)
        foreach ($file in $files) {
            $inside = $file.FullName.Substring($root.Length).TrimStart('\', '/') -replace '\\', '/'
            $relative = 'data/{0}/{1}/{2}' -f $user, $row.Name, $inside
            if ($seen.ContainsKey($relative)) { continue }
            $seen[$relative] = $true
            $plan.Add([pscustomobject]@{ Source = $file.FullName; Relative = $relative; Bytes = [long]$file.Length })
        }
    }
    return $plan.ToArray()
}

# $true if the data plus the margin fits into the free space.
function Test-MtxSpace {
    param([long]$NeededBytes, [long]$FreeBytes, [int]$MarginPercent)
    $required = [long]($NeededBytes * (1 + $MarginPercent / 100.0)) + $script:MtxFixedMarginBytes
    return ($required -le $FreeBytes)
}

# Copy and verify every file. Returns the manifest lines and the failures.
function Copy-MtxPlan {
    param([object[]]$Plan, [string]$HostDir)
    $lines = New-Object System.Collections.Generic.List[string]
    $failed = New-Object System.Collections.Generic.List[string]
    $done = 0
    foreach ($item in $Plan) {
        $target = Join-Path $HostDir ($item.Relative -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        try {
            $dir = Split-Path -Parent $target
            if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
            $sourceHash = Get-MtxFileHash -Path $item.Source
            Copy-Item -LiteralPath $item.Source -Destination $target -Force -ErrorAction Stop
            $targetHash = Get-MtxFileHash -Path $target
            if ($sourceHash -ne $targetHash) { throw 'checksum on the server differs from the source' }
            $lines.Add(('{0}  {1}' -f $sourceHash, $item.Relative))
        } catch {
            $failed.Add($item.Relative)
            Write-MtxLog "FAILED $($item.Source): $($_.Exception.Message)" 'ERROR'
        }
        $done++
        if ($done % 200 -eq 0) { Write-MtxLog "$done of $($Plan.Count) files" }
    }
    [pscustomobject]@{ Lines = $lines.ToArray(); Failed = $failed.ToArray() }
}

# sha256sum format, UTF-8 without BOM, LF: Linux checks it with `sha256sum -c`.
function Write-MtxManifest {
    param([string[]]$Lines, [string]$Path)
    $text = ''
    if ($Lines.Count -gt 0) { $text = ($Lines -join "`n") + "`n" }
    [System.IO.File]::WriteAllText($Path, $text, (New-Object System.Text.UTF8Encoding $false))
}

function Invoke-MtxBackup {
    param([string]$InventoryPath, [string]$Destination, [string]$User, [string]$Password, [int]$MarginPercent, [string]$LogPath)

    if (-not $InventoryPath -or -not $Destination) {
        Write-MtxLog 'Usage: Backup-ToServer.ps1 -InventoryPath <csv> -Destination <\\server\share> [-User u -Password p]' 'ERROR'
        return 1
    }
    if (-not $LogPath) { $LogPath = Join-Path (Split-Path -Parent $InventoryPath) 'backup.log' }
    $script:MtxLogFile = $LogPath
    $started = Get-Date
    Write-MtxLog "MigraTux backup: $InventoryPath -> $Destination"

    $checker = Join-Path $PSScriptRoot 'Test-InventoryCsv.ps1'
    $check = & $checker -Path $InventoryPath
    if (-not $check.Valid) {
        foreach ($problem in $check.Errors) { Write-MtxLog "Inventory: $problem" 'ERROR'}
        Write-MtxLog 'The inventory CSV is not valid. Nothing copied.' 'ERROR'
        return 1
    }
    $rows = @(Import-Csv -LiteralPath $InventoryPath -Encoding UTF8)
    $hostname = $rows[0].Hostname

    if ($User -and $Password) {
        if (-not (Connect-MtxShare -Share $Destination -User $User -Password $Password)) {
            Write-MtxLog "Cannot log in to $Destination. Nothing copied." 'ERROR'
            return 1
        }
    }
    if (-not (Test-Path -LiteralPath $Destination -PathType Container)) {
        Write-MtxLog "Destination not reachable: $Destination. Nothing copied." 'ERROR'
        return 1
    }

    $plan = @(Get-MtxBackupPlan -Rows $rows)
    [long]$needed = 0
    foreach ($item in $plan) { $needed += $item.Bytes }
    $free = Get-MtxFreeBytes -Path $Destination
    Write-MtxLog ('{0} files, {1:N0} MB to copy. Free on the server: {2:N0} MB.' -f $plan.Count, ($needed / 1MB), ($free / 1MB))
    if (-not (Test-MtxSpace -NeededBytes $needed -FreeBytes $free -MarginPercent $MarginPercent)) {
        Write-MtxLog ('NOT ENOUGH SPACE on the server: {0:N0} MB needed (+{1}% and 100 MB reserve), {2:N0} MB free. Nothing was copied. Free up space on the server and start again.' -f ($needed / 1MB), $MarginPercent, ($free / 1MB)) 'ERROR'
        return 3
    }

    $hostDir = Join-Path $Destination $hostname
    if (-not (Test-Path -LiteralPath $hostDir)) { New-Item -ItemType Directory -Path $hostDir -Force | Out-Null }
    # A manifest from an older run would mark this run as complete too early.
    $manifest = Join-Path $hostDir 'manifest.sha256'
    if (Test-Path -LiteralPath $manifest) { Remove-Item -LiteralPath $manifest -Force }
    Copy-Item -LiteralPath $InventoryPath -Destination (Join-Path $hostDir "inventory-$hostname.csv") -Force

    $result = Copy-MtxPlan -Plan $plan -HostDir $hostDir
    $seconds = [int]((Get-Date) - $started).TotalSeconds
    $code = 0
    if ($result.Failed.Count -gt 0) {
        Write-MtxLog "$($result.Failed.Count) of $($plan.Count) files FAILED. No manifest written, the backup is NOT complete." 'ERROR'
        $code = 4
    } else {
        Write-MtxManifest -Lines $result.Lines -Path $manifest
        Write-MtxLog ('OK: {0} files ({1:N0} MB) copied and verified in {2} s. Manifest: {3}' -f $plan.Count, ($needed / 1MB), $seconds, $manifest)
    }
    try { Copy-Item -LiteralPath $LogPath -Destination (Join-Path $hostDir 'backup.log') -Force } catch { }
    return $code
}

# Dot-sourced (tests): only define the functions.
if ($MyInvocation.InvocationName -ne '.') {
    exit (Invoke-MtxBackup -InventoryPath $InventoryPath -Destination $Destination -User $User `
            -Password $Password -MarginPercent $MarginPercent -LogPath $LogPath)
}
