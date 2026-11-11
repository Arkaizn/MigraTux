# Pester 5 tests for collect/Get-Inventory.ps1. Run: tests/run.sh pester
# Windows (registry, WMI) is replaced by mocks, so the tests also run under
# pwsh on Linux. The real thing is tested by hand: docs/testing/M1-inventory.md.
# Keep this file ASCII-only (umlauts are built with [char]).
BeforeAll {
    $script:Script    = Join-Path $PSScriptRoot '../../collect/Get-Inventory.ps1'
    $script:Validator = Join-Path $PSScriptRoot '../../collect/Test-InventoryCsv.ps1'
    $script:ue        = [string][char]0xFC
    . $script:Script

    function New-Entry {
        param([string]$Name, [string]$Version = '1.0', [string]$Scope = 'machine', [string]$Arch = 'x64',
              $Size, $SystemComponent, [string]$Parent, [string]$Publisher = 'Vendor', [string]$Location = '')
        [pscustomobject]@{
            DisplayName = $Name; DisplayVersion = $Version; Publisher = $Publisher; InstallLocation = $Location
            EstimatedSize = $Size; SystemComponent = $SystemComponent; ParentKeyName = $Parent; Scope = $Scope; Arch = $Arch
        }
    }

    # Default mocks: a small, healthy Windows PC.
    function Set-DefaultMocks {
        Mock Write-Host { }
        Mock Get-MtxIsAdmin { $true }
        Mock Get-MtxIs64Bit { $true }
        Mock Get-MtxFirmware { 'uefi' }
        Mock Get-MtxUninstallEntry {
            New-Entry -Name 'VLC media player' -Version '3.0.21' -Size 184320 -Publisher 'VideoLAN' -Location 'C:\Program Files\VideoLAN\VLC'
            New-Entry -Name 'Zoom Workplace' -Version '6.2.5' -Scope 'user'
        }
        Mock Get-MtxProfile { @() }
        Mock Get-MtxCim { @() }
        Mock Get-MtxCim -ParameterFilter { $ClassName -eq 'Win32_Printer' } {
            [pscustomobject]@{ Name = "HP LaserJet, B${ue}ro 1"; DriverName = 'HP Universal Printing PCL 6'; PortName = 'IP_192.168.1.50'; Default = $true }
            [pscustomobject]@{ Name = 'Microsoft Print to PDF'; DriverName = 'Microsoft Print To PDF'; PortName = 'PORTPROMPT:'; Default = $false }
        }
        Mock Get-MtxCim -ParameterFilter { $ClassName -eq 'Win32_LogicalDisk' -and $Filter -eq 'DriveType=4' } {
            [pscustomobject]@{ DeviceID = 'Z:'; ProviderName = '\\nas01\Buchhaltung' }
        }
        Mock Get-MtxCim -ParameterFilter { $ClassName -eq 'Win32_LogicalDisk' -and $Filter -eq 'DriveType=3' } {
            [pscustomobject]@{ DeviceID = 'C:'; Size = 64424509440; FreeSpace = 32716029952; FileSystem = 'NTFS' }
        }
        Mock Get-MtxCim -ParameterFilter { $ClassName -eq 'Win32_NetworkAdapter' } {
            [pscustomobject]@{ DeviceID = '1'; Name = 'Intel(R) 82574L'; NetConnectionID = 'Ethernet'; MACAddress = '00:0c:29:ab:cd:ef'; Manufacturer = 'Intel' }
            [pscustomobject]@{ DeviceID = '2'; Name = 'WAN Miniport'; NetConnectionID = $null; MACAddress = $null; Manufacturer = 'Microsoft' }
            [pscustomobject]@{ DeviceID = '3'; Name = 'Intel(R) Wi-Fi 6'; NetConnectionID = 'WLAN'; MACAddress = 'AA:BB:CC:00:11:22'; Manufacturer = 'Intel' }
        }
        Mock Get-MtxCim -ParameterFilter { $ClassName -eq 'Win32_NetworkAdapterConfiguration' } {
            [pscustomobject]@{ Index = 1; IPAddress = @('192.168.1.23', 'fe80::1'); DHCPEnabled = $true }
            [pscustomobject]@{ Index = 3; IPAddress = $null; DHCPEnabled = $true }
        }
        Mock Get-MtxCim -ParameterFilter { $ClassName -eq 'Win32_OperatingSystem' } {
            [pscustomobject]@{ Caption = 'Microsoft Windows 11 Pro'; Version = '10.0.22631'; Manufacturer = 'Microsoft Corporation'; OSArchitecture = '64-bit' }
        }
        Mock Get-MtxCim -ParameterFilter { $ClassName -eq 'Win32_ComputerSystem' } {
            [pscustomobject]@{ Manufacturer = 'VMware, Inc.'; Model = 'VMware20,1'; TotalPhysicalMemory = 4294967296 }
        }
        Mock Get-MtxCim -ParameterFilter { $ClassName -eq 'Win32_BIOS' } {
            [pscustomobject]@{ SerialNumber = 'VMware-56 4d' }
        }
        Mock Get-MtxCim -ParameterFilter { $ClassName -eq 'Win32_Processor' } {
            [pscustomobject]@{ Name = 'Intel(R) Core(TM) i5-10210U'; Manufacturer = 'GenuineIntel'; NumberOfCores = 2 }
        }
    }

    # A profile folder with real files in the test drive.
    function New-TestProfile {
        param([string]$User)
        $root = Join-Path $TestDrive ("Users-{0}" -f [guid]::NewGuid())
        $home1 = Join-Path $root $User
        New-Item -ItemType Directory -Path (Join-Path $home1 'Documents/Sub') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $home1 'Desktop') -Force | Out-Null
        [System.IO.File]::WriteAllBytes((Join-Path $home1 "Documents/Offerte_M${ue}ller.docx"), (New-Object byte[] (2MB)))
        [System.IO.File]::WriteAllBytes((Join-Path $home1 'Documents/Sub/a.txt'), (New-Object byte[] (1MB)))
        [System.IO.File]::WriteAllBytes((Join-Path $home1 'Desktop/n.txt'), (New-Object byte[] 10))
        $home1
    }
}

Describe 'Get-Inventory: apps' {
    BeforeEach { Set-DefaultMocks }

    It 'writes name, version, publisher, path, size in MB and scope/arch' {
        $rows = @(Get-MtxAppRows -Hostname 'PC1')
        $rows.Count | Should -Be 2
        $vlc = $rows | Where-Object Name -eq 'VLC media player'
        $vlc.Category  | Should -Be 'app'
        $vlc.Hostname  | Should -Be 'PC1'
        $vlc.Version   | Should -Be '3.0.21'
        $vlc.Publisher | Should -Be 'VideoLAN'
        $vlc.Path      | Should -Be 'C:\Program Files\VideoLAN\VLC'
        $vlc.SizeMB    | Should -Be '180'
        $vlc.Extra     | Should -Be 'scope=machine;arch=x64'
        ($rows | Where-Object Name -eq 'Zoom Workplace').Extra | Should -Be 'scope=user;arch=x64'
    }
    It 'leaves SizeMB empty when Windows has no size' {
        (@(Get-MtxAppRows -Hostname 'PC1') | Where-Object Name -eq 'Zoom Workplace').SizeMB | Should -Be ''
    }
    It 'skips entries without name, system components, patches and updates' {
        Mock Get-MtxUninstallEntry {
            New-Entry -Name ''
            New-Entry -Name 'Hidden Component' -SystemComponent 1
            New-Entry -Name 'Office Patch' -Parent 'Office16'
            New-Entry -Name 'Security Update for Microsoft Windows (KB5031455)'
            New-Entry -Name 'Update for Windows 10 for x64-based Systems (KB5001716)'
            New-Entry -Name 'Real App'
        }
        @(Get-MtxAppRows -Hostname 'PC1').Name | Should -Be @('Real App')
    }
    It 'lists an app once when it is in two uninstall keys, but keeps other versions' {
        Mock Get-MtxUninstallEntry {
            New-Entry -Name '7-Zip' -Version '24.08' -Arch 'x64'
            New-Entry -Name '7-zip' -Version '24.08' -Arch 'x86'
            New-Entry -Name '7-Zip' -Version '19.00' -Arch 'x86'
        }
        $rows = @(Get-MtxAppRows -Hostname 'PC1')
        $rows.Count | Should -Be 2
        $rows[0].Extra | Should -Be 'scope=machine;arch=x64'
    }
    It 'removes line breaks from fields and ; = from Extra values' {
        Mock Get-MtxUninstallEntry { New-Entry -Name "Two`r`nLines" -Publisher "A`nB" }
        $row = @(Get-MtxAppRows -Hostname 'PC1')[0]
        $row.Name      | Should -Be 'Two Lines'
        $row.Publisher | Should -Be 'A B'
        (New-MtxRow -Hostname 'h' -Category 'printer' -Name 'p' -Extra ([ordered]@{ port = 'a;b=c' })).Extra | Should -Be 'port=a b c'
    }
}

Describe 'Get-Inventory: user folders' {
    BeforeEach { Set-DefaultMocks }

    It 'measures size and file count of each existing folder, recursively' {
        $p = New-TestProfile -User 'mmueller'
        Mock Get-MtxProfile { [pscustomobject]@{ User = 'mmueller'; Path = $p; IsCurrent = $false } }.GetNewClosure()
        $rows = @(Get-MtxUserFolderRows -Hostname 'PC1')
        $rows.Name | Should -Be @('Desktop', 'Documents')
        $docs = $rows | Where-Object Name -eq 'Documents'
        $docs.SizeMB | Should -Be '3'
        $docs.Extra  | Should -Be 'user=mmueller;files=2'
        $docs.Path   | Should -Be (Join-Path $p 'Documents')
        ($rows | Where-Object Name -eq 'Desktop').SizeMB | Should -Be '0'
    }
    It 'without admin rights: only the current user, other profiles are skipped with a warning' {
        $mine  = New-TestProfile -User 'me'
        $other = New-TestProfile -User 'chef'
        Mock Get-MtxIsAdmin { $false }
        Mock Get-MtxFolderPath { Join-Path $UserProfile.Path $Name }
        Mock Get-MtxProfile {
            [pscustomobject]@{ User = 'me'; Path = $mine; IsCurrent = $true }
            [pscustomobject]@{ User = 'chef'; Path = $other; IsCurrent = $false }
        }.GetNewClosure()
        Mock Write-MtxLog { }
        $rows = @(Get-MtxUserFolderRows -Hostname 'PC1')
        ($rows.Extra -join ' ') | Should -Match 'user=me'
        ($rows.Extra -join ' ') | Should -Not -Match 'user=chef'
        Should -Invoke Write-MtxLog -ParameterFilter { $Level -eq 'WARN' -and $Message -match "chef" -and $Message -match 'admin' }
    }
    It 'with admin rights: all profiles' {
        $a = New-TestProfile -User 'a'
        $b = New-TestProfile -User 'b'
        Mock Get-MtxProfile {
            [pscustomobject]@{ User = 'a'; Path = $a; IsCurrent = $false }
            [pscustomobject]@{ User = 'b'; Path = $b; IsCurrent = $false }
        }.GetNewClosure()
        @(Get-MtxUserFolderRows -Hostname 'PC1').Count | Should -Be 4
    }
}

Describe 'Get-Inventory: printers, network, hardware' {
    BeforeEach { Set-DefaultMocks }

    It 'lists printers with driver, port and default flag' {
        $rows = @(Get-MtxPrinterRows -Hostname 'PC1')
        $rows[0].Name  | Should -Be "HP LaserJet, B${ue}ro 1"
        $rows[0].Extra | Should -Be 'driver=HP Universal Printing PCL 6;port=IP_192.168.1.50;default=true'
        $rows[1].Extra | Should -Match 'default=false$'
    }
    It 'lists mapped network drives with their UNC path' {
        $drive = @(Get-MtxNetworkRows -Hostname 'PC1') | Where-Object Name -eq 'Z:'
        $drive.Path  | Should -Be '\\nas01\Buchhaltung'
        $drive.Extra | Should -Be 'type=drive'
    }
    It 'lists physical adapters with MAC (upper case, hyphens), also without cable' {
        $rows = @(Get-MtxNetworkRows -Hostname 'PC1') | Where-Object { $_.Extra -match 'type=adapter' }
        $rows.Name | Should -Be @('Ethernet', 'WLAN')
        $rows[0].Extra | Should -Be 'type=adapter;mac=00-0C-29-AB-CD-EF;ip=192.168.1.23;dhcp=true'
        $rows[1].Extra | Should -Be 'type=adapter;mac=AA-BB-CC-00-11-22;dhcp=true'
    }
    It 'lists OS, model, RAM, CPU and the disk with free space' {
        $rows = @(Get-MtxHardwareRows -Hostname 'PC1')
        $rows.Name | Should -Be @('OS', 'Model', 'RAM', 'CPU', 'Disk')
        ($rows | Where-Object Name -eq 'OS').Version | Should -Be '10.0.22631'
        ($rows | Where-Object Name -eq 'OS').Extra   | Should -Be 'caption=Microsoft Windows 11 Pro;arch=64-bit;firmware=uefi'
        ($rows | Where-Object Name -eq 'RAM').SizeMB | Should -Be '4096'
        ($rows | Where-Object Name -eq 'CPU').Extra  | Should -Be 'model=Intel(R) Core(TM) i5-10210U;cores=2'
        $disk = $rows | Where-Object Name -eq 'Disk'
        $disk.Path   | Should -Be 'C:'
        $disk.SizeMB | Should -Be '61440'
        $disk.Extra  | Should -Be 'free_mb=31200;fs=NTFS'
    }
}

Describe 'Get-Inventory: whole run' {
    BeforeEach {
        Set-DefaultMocks
        $script:Out = Join-Path $TestDrive ("out-{0}" -f [guid]::NewGuid())
    }

    It 'writes a CSV that passes the contract checker, plus a log' {
        $code = Invoke-MtxMain -OutDir $Out -ComputerName 'KMU-PC01'
        $code | Should -Be 0
        $csv = Join-Path $Out 'inventory-KMU-PC01.csv'
        $r = & $Validator -Path $csv
        $r.Errors   | Should -BeNullOrEmpty
        $r.Valid    | Should -BeTrue
        $r.RowCount | Should -Be 12
        (Get-Content -LiteralPath (Join-Path $Out 'inventory.log') -Raw) | Should -Match 'OK: 12 rows'
    }
    It 'keeps umlauts and commas intact in the file' {
        Invoke-MtxMain -OutDir $Out -ComputerName 'KMU-PC01' | Out-Null
        $rows = Import-Csv -LiteralPath (Join-Path $Out 'inventory-KMU-PC01.csv') -Encoding UTF8
        ($rows | Where-Object Category -eq 'printer')[0].Name | Should -Be "HP LaserJet, B${ue}ro 1"
    }
    It 'returns 1 when a collector fails, and says which one' {
        Mock Get-MtxCim -ParameterFilter { $ClassName -eq 'Win32_Printer' } { throw 'WMI is broken' }
        $code = Invoke-MtxMain -OutDir $Out -ComputerName 'KMU-PC01'
        $code | Should -Be 1
        $log = Get-Content -LiteralPath (Join-Path $Out 'inventory.log') -Raw
        $log | Should -Match "Collector 'printer' failed: WMI is broken"
        $log | Should -Match 'incomplete'
    }
    It 'returns 1 and writes no CSV when nothing was collected' {
        foreach ($collector in 'Get-MtxAppRows', 'Get-MtxUserFolderRows', 'Get-MtxPrinterRows', 'Get-MtxNetworkRows', 'Get-MtxHardwareRows') {
            Mock $collector { }
        }
        $code = Invoke-MtxMain -OutDir $Out -ComputerName 'KMU-PC01'
        $code | Should -Be 1
        Test-Path (Join-Path $Out 'inventory-KMU-PC01.csv') | Should -BeFalse
    }
    It 'run as a script, it ends with exit code 1 on a machine it cannot read (Linux)' -Skip:($IsWindows -or $PSVersionTable.PSEdition -eq 'Desktop') {
        & pwsh -NoProfile -File $Script -OutDir $Out *> $null
        $LASTEXITCODE | Should -Be 1
    }
}
