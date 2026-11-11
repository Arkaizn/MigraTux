<#
.SYNOPSIS
    MigraTux inventory (M1): reads this Windows PC into inventory-<HOSTNAME>.csv.
.DESCRIPTION
    BASELINE written by the repo tooling so the rest of the chain can be tested.
    The teammate's inventory script may replace it or be merged into it, as
    long as the output matches docs/contracts/inventory-csv.md.

    Collects: installed apps (HKLM + HKCU uninstall keys, 32- and 64-bit),
    user folders with size, printers, network drives and adapters (with MAC
    address), hardware (OS, model, CPU, RAM, system disk with free space).

    Admin rights: NOT required. Without admin only the folders of the user who
    runs the script are measured; other profiles are skipped and logged. Run
    it in an elevated PowerShell to cover all users of the PC.

    Runs on Windows PowerShell 5.1 and PowerShell 7. Changes nothing on the PC.
    Keep this file ASCII-only: PowerShell 5.1 reads BOM-less scripts as ANSI.
.PARAMETER OutDir
    Folder for the CSV and the log. Default: .\out
.PARAMETER ComputerName
    Name written into the CSV. Default: the name of this PC.
.OUTPUTS
    Exit code 0 = CSV written and valid, 1 = failed (see the log).
.EXAMPLE
    .\collect\Get-Inventory.ps1 -OutDir C:\migratux\out
#>
[CmdletBinding()]
param(
    [string]$OutDir,
    [string]$ComputerName
)

$script:MtxLogFile = $null
$script:MtxFolderNames = @('Desktop', 'Documents', 'Pictures', 'Downloads', 'Music', 'Videos')

function Write-MtxLog {
    param([string]$Message, [string]$Level = 'INFO')
    $line = '{0} {1} {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    if ($script:MtxLogFile) { Add-Content -LiteralPath $script:MtxLogFile -Value $line -Encoding UTF8 }
    if ($Level -eq 'ERROR') { Write-Host $line -ForegroundColor Red }
    elseif ($Level -eq 'WARN') { Write-Host $line -ForegroundColor Yellow }
    else { Write-Host $line }
}

# One line of text for a CSV field: no line breaks, trimmed.
function ConvertTo-MtxText {
    param($Value)
    if ($null -eq $Value) { return '' }
    return (([string]$Value) -replace '[\r\n]+', ' ').Trim()
}

# A value inside the Extra column: no ';' and no '='.
function ConvertTo-MtxExtraValue {
    param($Value)
    return ((ConvertTo-MtxText $Value) -replace '[;=]', ' ').Trim()
}

function New-MtxRow {
    param(
        [string]$Hostname, [string]$Category, [string]$Name, $Version, $Publisher, $Path, $SizeMB,
        [System.Collections.IDictionary]$Extra
    )
    $pairs = @()
    if ($Extra) {
        foreach ($key in $Extra.Keys) {
            $value = ConvertTo-MtxExtraValue $Extra[$key]
            if ($value -ne '') { $pairs += ('{0}={1}' -f $key, $value) }
        }
    }
    $size = ''
    if ($null -ne $SizeMB -and "$SizeMB" -ne '') { $size = [string][long][math]::Round([double]$SizeMB) }
    [pscustomobject]@{
        Hostname  = $Hostname
        Category  = $Category
        Name      = ConvertTo-MtxText $Name
        Version   = ConvertTo-MtxText $Version
        Publisher = ConvertTo-MtxText $Publisher
        Path      = ConvertTo-MtxText $Path
        SizeMB    = $size
        Extra     = ($pairs -join ';')
    }
}

# ---- Thin wrappers around Windows. The Pester tests replace them with mocks. ----

function Get-MtxIsAdmin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-MtxIs64Bit {
    return [Environment]::Is64BitOperatingSystem
}

# Raw entries of the four uninstall keys, tagged with Scope and Arch.
function Get-MtxUninstallEntry {
    $os64 = Get-MtxIs64Bit
    $native = 'x86'
    if ($os64) { $native = 'x64' }
    $keys = @(
        @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*';             Scope = 'machine'; Arch = $native },
        @{ Path = 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'; Scope = 'machine'; Arch = 'x86' },
        @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*';             Scope = 'user';    Arch = $native },
        @{ Path = 'HKCU:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'; Scope = 'user';    Arch = 'x86' }
    )
    foreach ($key in $keys) {
        $items = @(Get-ItemProperty -Path $key.Path -ErrorAction SilentlyContinue)
        foreach ($item in $items) {
            [pscustomobject]@{
                DisplayName     = $item.DisplayName
                DisplayVersion  = $item.DisplayVersion
                Publisher       = $item.Publisher
                InstallLocation = $item.InstallLocation
                EstimatedSize   = $item.EstimatedSize
                SystemComponent = $item.SystemComponent
                ParentKeyName   = $item.ParentKeyName
                Scope           = $key.Scope
                Arch            = $key.Arch
            }
        }
    }
}

function Get-MtxCim {
    param([string]$ClassName, [string]$Filter)
    if ($Filter) { return @(Get-CimInstance -ClassName $ClassName -Filter $Filter -ErrorAction Stop) }
    return @(Get-CimInstance -ClassName $ClassName -ErrorAction Stop)
}

# User profiles: User, Path, IsCurrent.
function Get-MtxProfile {
    $skip = @('Public', 'Default', 'Default User', 'All Users', 'defaultuser0', 'WDAGUtilityAccount')
    $usersRoot = Split-Path -Parent $env:USERPROFILE
    foreach ($dir in @(Get-ChildItem -LiteralPath $usersRoot -Directory -ErrorAction SilentlyContinue)) {
        if ($skip -contains $dir.Name) { continue }
        [pscustomobject]@{
            User      = $dir.Name
            Path      = $dir.FullName
            IsCurrent = ($dir.FullName -eq $env:USERPROFILE)
        }
    }
}

# Where a known folder of a profile is. For the current user this follows
# redirections (e.g. Documents moved to OneDrive).
function Get-MtxFolderPath {
    param($UserProfile, [string]$Name)
    if ($UserProfile.IsCurrent) {
        $special = @{ Desktop = 'DesktopDirectory'; Documents = 'MyDocuments'; Pictures = 'MyPictures'; Music = 'MyMusic'; Videos = 'MyVideos' }
        if ($special.ContainsKey($Name)) {
            $path = [Environment]::GetFolderPath($special[$Name])
            if ($path) { return $path }
        }
    }
    return (Join-Path $UserProfile.Path $Name)
}

function Get-MtxFirmware {
    if ($env:firmware_type) { return $env:firmware_type.ToLower() }
    return ''
}

# ---- Collectors: each returns rows for one category. ----

function Get-MtxAppRows {
    param([string]$Hostname)
    $seen = @{}
    foreach ($entry in @(Get-MtxUninstallEntry)) {
        $name = ConvertTo-MtxText $entry.DisplayName
        if ($name -eq '') { continue }
        if ($entry.SystemComponent -eq 1) { continue }
        if ($entry.ParentKeyName) { continue }
        if ($name -match '^(Security Update|Update|Hotfix) for ' -or $name -match '\(KB\d{6,}\)') { continue }
        $id = ('{0}|{1}' -f $name, (ConvertTo-MtxText $entry.DisplayVersion)).ToLower()
        if ($seen.ContainsKey($id)) { continue }
        $seen[$id] = $true
        $size = ''
        if ($entry.EstimatedSize) { $size = [double]$entry.EstimatedSize / 1024 }
        New-MtxRow -Hostname $Hostname -Category 'app' -Name $name -Version $entry.DisplayVersion `
            -Publisher $entry.Publisher -Path $entry.InstallLocation -SizeMB $size `
            -Extra ([ordered]@{ scope = $entry.Scope; arch = $entry.Arch })
    }
}

function Get-MtxUserFolderRows {
    param([string]$Hostname)
    $admin = Get-MtxIsAdmin
    foreach ($userProfile in @(Get-MtxProfile)) {
        if (-not $userProfile.IsCurrent -and -not $admin) {
            Write-MtxLog "Profile '$($userProfile.User)' skipped: no admin rights. Run elevated to include all users." 'WARN'
            continue
        }
        foreach ($name in $script:MtxFolderNames) {
            $path = Get-MtxFolderPath -UserProfile $userProfile -Name $name
            if (-not (Test-Path -LiteralPath $path -PathType Container)) { continue }
            $files = @(Get-ChildItem -LiteralPath $path -Recurse -File -Force -ErrorAction SilentlyContinue)
            $bytes = 0
            foreach ($file in $files) { $bytes += $file.Length }
            New-MtxRow -Hostname $Hostname -Category 'userfolder' -Name $name -Path $path -SizeMB ($bytes / 1MB) `
                -Extra ([ordered]@{ user = $userProfile.User; files = $files.Count })
        }
    }
}

function Get-MtxPrinterRows {
    param([string]$Hostname)
    foreach ($printer in @(Get-MtxCim -ClassName 'Win32_Printer')) {
        $default = 'false'
        if ($printer.Default) { $default = 'true' }
        New-MtxRow -Hostname $Hostname -Category 'printer' -Name $printer.Name `
            -Extra ([ordered]@{ driver = $printer.DriverName; port = $printer.PortName; default = $default })
    }
}

function Get-MtxNetworkRows {
    param([string]$Hostname)
    # Mapped network drives (DriveType 4).
    foreach ($drive in @(Get-MtxCim -ClassName 'Win32_LogicalDisk' -Filter 'DriveType=4')) {
        New-MtxRow -Hostname $Hostname -Category 'network' -Name $drive.DeviceID -Path $drive.ProviderName `
            -Extra ([ordered]@{ type = 'drive' })
    }
    # Physical adapters, also the ones without a cable: the MAC address is how
    # the server finds this PC again after the Linux install.
    $configs = @{}
    foreach ($config in @(Get-MtxCim -ClassName 'Win32_NetworkAdapterConfiguration')) {
        $configs[[string]$config.Index] = $config
    }
    foreach ($adapter in @(Get-MtxCim -ClassName 'Win32_NetworkAdapter' -Filter 'PhysicalAdapter=True')) {
        if (-not $adapter.MACAddress) { continue }
        $extra = [ordered]@{ type = 'adapter'; mac = ([string]$adapter.MACAddress).ToUpper() -replace ':', '-' }
        $config = $configs[[string]$adapter.DeviceID]
        if ($config) {
            if ($config.IPAddress) { $extra['ip'] = @($config.IPAddress)[0] }
            if ($null -ne $config.DHCPEnabled) { $extra['dhcp'] = ([string][bool]$config.DHCPEnabled).ToLower() }
        }
        $name = $adapter.NetConnectionID
        if (-not $name) { $name = $adapter.Name }
        New-MtxRow -Hostname $Hostname -Category 'network' -Name $name -Publisher $adapter.Manufacturer -Extra $extra
    }
}

function Get-MtxHardwareRows {
    param([string]$Hostname)
    $os = @(Get-MtxCim -ClassName 'Win32_OperatingSystem')[0]
    if ($os) {
        New-MtxRow -Hostname $Hostname -Category 'hardware' -Name 'OS' -Version $os.Version -Publisher $os.Manufacturer `
            -Extra ([ordered]@{ caption = $os.Caption; arch = $os.OSArchitecture; firmware = (Get-MtxFirmware) })
    }
    $cs = @(Get-MtxCim -ClassName 'Win32_ComputerSystem')[0]
    if ($cs) {
        $bios = @(Get-MtxCim -ClassName 'Win32_BIOS')[0]
        $serial = ''
        if ($bios) { $serial = $bios.SerialNumber }
        New-MtxRow -Hostname $Hostname -Category 'hardware' -Name 'Model' -Publisher $cs.Manufacturer `
            -Extra ([ordered]@{ model = $cs.Model; serial = $serial })
        New-MtxRow -Hostname $Hostname -Category 'hardware' -Name 'RAM' -SizeMB ([double]$cs.TotalPhysicalMemory / 1MB)
    }
    $cpu = @(Get-MtxCim -ClassName 'Win32_Processor')[0]
    if ($cpu) {
        New-MtxRow -Hostname $Hostname -Category 'hardware' -Name 'CPU' -Publisher $cpu.Manufacturer `
            -Extra ([ordered]@{ model = $cpu.Name; cores = $cpu.NumberOfCores })
    }
    foreach ($disk in @(Get-MtxCim -ClassName 'Win32_LogicalDisk' -Filter 'DriveType=3')) {
        New-MtxRow -Hostname $Hostname -Category 'hardware' -Name 'Disk' -Path $disk.DeviceID `
            -SizeMB ([double]$disk.Size / 1MB) `
            -Extra ([ordered]@{ free_mb = [long][math]::Floor([double]$disk.FreeSpace / 1MB); fs = $disk.FileSystem })
    }
}

# Run all collectors. One failing collector is logged and does not stop the others.
function Invoke-MtxInventory {
    param([string]$Hostname)
    $rows = New-Object System.Collections.Generic.List[object]
    $collectors = [ordered]@{
        app        = { param($h) Get-MtxAppRows -Hostname $h }
        userfolder = { param($h) Get-MtxUserFolderRows -Hostname $h }
        printer    = { param($h) Get-MtxPrinterRows -Hostname $h }
        network    = { param($h) Get-MtxNetworkRows -Hostname $h }
        hardware   = { param($h) Get-MtxHardwareRows -Hostname $h }
    }
    foreach ($category in $collectors.Keys) {
        try {
            $found = @(& $collectors[$category] $Hostname)
            foreach ($row in $found) { $rows.Add($row) }
            Write-MtxLog ('{0,-10} {1} rows' -f $category, $found.Count)
        } catch {
            Write-MtxLog "Collector '$category' failed: $($_.Exception.Message)" 'ERROR'
            $script:MtxCollectorErrors++
        }
    }
    return $rows.ToArray()
}

function Export-MtxInventory {
    param([object[]]$Rows, [string]$Path)
    # UTF-8 with BOM in both PowerShell editions (see the contract).
    $encoding = 'UTF8'
    if ($PSVersionTable.PSEdition -eq 'Core') { $encoding = 'utf8BOM' }
    $Rows | Select-Object Hostname, Category, Name, Version, Publisher, Path, SizeMB, Extra |
        Export-Csv -LiteralPath $Path -NoTypeInformation -Encoding $encoding
}

function Invoke-MtxMain {
    param([string]$OutDir, [string]$ComputerName)
    $script:MtxCollectorErrors = 0
    if (-not $OutDir) { $OutDir = Join-Path (Get-Location).Path 'out' }
    if (-not $ComputerName) { $ComputerName = [Environment]::MachineName }
    if (-not (Test-Path -LiteralPath $OutDir)) { New-Item -ItemType Directory -Path $OutDir -Force | Out-Null }
    $script:MtxLogFile = Join-Path $OutDir 'inventory.log'
    $csv = Join-Path $OutDir "inventory-$ComputerName.csv"

    Write-MtxLog "MigraTux inventory of $ComputerName (PowerShell $($PSVersionTable.PSVersion), admin: $(Get-MtxIsAdmin))"
    $rows = @(Invoke-MtxInventory -Hostname $ComputerName)
    if ($rows.Count -eq 0) {
        Write-MtxLog 'Nothing collected. No CSV written.' 'ERROR'
        return 1
    }
    Export-MtxInventory -Rows $rows -Path $csv

    $checker = Join-Path $PSScriptRoot 'Test-InventoryCsv.ps1'
    if (Test-Path -LiteralPath $checker) {
        $result = & $checker -Path $csv
        if (-not $result.Valid) {
            foreach ($problem in $result.Errors) { Write-MtxLog "Contract: $problem" 'ERROR' }
            Write-MtxLog "The CSV does not match the contract: $csv" 'ERROR'
            return 1
        }
    }
    if ($script:MtxCollectorErrors -gt 0) {
        Write-MtxLog "$($script:MtxCollectorErrors) collector(s) failed. The CSV is incomplete: $csv" 'ERROR'
        return 1
    }
    Write-MtxLog "OK: $($rows.Count) rows written to $csv"
    return 0
}

# Dot-sourced (tests): only define the functions.
if ($MyInvocation.InvocationName -ne '.') {
    exit (Invoke-MtxMain -OutDir $OutDir -ComputerName $ComputerName)
}
