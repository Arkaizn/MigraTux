# Pester 5 tests for collect/Backup-ToServer.ps1. Run: tests/run.sh pester
# The "server share" is a folder in the test drive; free space and the share
# login are mocks. The real thing is tested by hand: docs/testing/M2-backup.md.
# Keep this file ASCII-only (umlauts are built with [char]).
BeforeAll {
    $script:Script = Join-Path $PSScriptRoot '../../collect/Backup-ToServer.ps1'
    $script:ue = [string][char]0xFC
    $script:ae = [string][char]0xE4
    $script:BomEncoding = if ($PSVersionTable.PSEdition -eq 'Desktop') { 'UTF8' } else { 'utf8BOM' }
    . $script:Script

    function New-Row {
        param([string]$Category, [string]$Name, [string]$Path = '', [string]$Extra = '')
        [pscustomobject]@{ Hostname = 'KMU-PC01'; Category = $Category; Name = $Name; Version = ''; Publisher = ''; Path = $Path; SizeMB = ''; Extra = $Extra }
    }

    # A fresh PC (user folders with files), inventory CSV and empty share.
    function New-Scene {
        $script:Base  = Join-Path $TestDrive ("scene-{0}" -f [guid]::NewGuid())
        $script:Docs  = Join-Path $Base 'Users/mmueller/Documents'
        $script:Desk  = Join-Path $Base 'Users/mmueller/Desktop'
        $script:Share = Join-Path $Base 'share'
        New-Item -ItemType Directory -Path (Join-Path $Docs "Unter Ordner"), $Desk, $Share, (Join-Path $Base 'out') -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $Docs "Offerte_M${ue}ller.docx") -Value "Offerte f${ue}r M${ue}ller"
        Set-Content -LiteralPath (Join-Path $Docs "Unter Ordner/Bericht 2025.txt") -Value 'Bericht'
        Set-Content -LiteralPath (Join-Path $Desk 'Notiz.txt') -Value 'Notiz'
        $script:Inventory = Join-Path $Base 'out/inventory-KMU-PC01.csv'
        $script:Rows = @(
            New-Row -Category 'app' -Name 'VLC media player'
            New-Row -Category 'userfolder' -Name 'Documents' -Path $Docs -Extra 'user=mmueller;files=2'
            New-Row -Category 'userfolder' -Name 'Desktop' -Path $Desk -Extra 'user=mmueller;files=1'
        )
        Save-Inventory
        $script:HostDir = Join-Path $Share 'KMU-PC01'
    }
    function Save-Inventory {
        $Rows | Export-Csv -LiteralPath $Inventory -NoTypeInformation -Encoding $BomEncoding
    }
    function Invoke-Backup {
        Invoke-MtxBackup -InventoryPath $Inventory -Destination $Share -MarginPercent 10
    }
    function Get-ManifestLines {
        @([System.IO.File]::ReadAllLines((Join-Path $HostDir 'manifest.sha256'), [System.Text.Encoding]::UTF8))
    }
}

Describe 'Backup-ToServer: normal run' {
    BeforeEach {
        Mock Write-Host { }
        Mock Get-MtxFreeBytes { 50GB }
        New-Scene
    }

    It 'copies every file into data/<user>/<Folder>/ and returns 0' {
        Invoke-Backup | Should -Be 0
        Get-Content -LiteralPath (Join-Path $HostDir "data/mmueller/Documents/Offerte_M${ue}ller.docx") | Should -Be "Offerte f${ue}r M${ue}ller"
        Test-Path -LiteralPath (Join-Path $HostDir 'data/mmueller/Documents/Unter Ordner/Bericht 2025.txt') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $HostDir 'data/mmueller/Desktop/Notiz.txt') | Should -BeTrue
    }
    It 'copies the inventory CSV and the log next to the data' {
        Invoke-Backup | Out-Null
        (Get-FileHash -LiteralPath (Join-Path $HostDir 'inventory-KMU-PC01.csv')).Hash | Should -Be (Get-FileHash -LiteralPath $Inventory).Hash
        (Get-Content -LiteralPath (Join-Path $HostDir 'backup.log') -Raw) | Should -Match 'OK: 3 files'
    }
    It 'writes one manifest line per file: lower-case SHA-256, two spaces, path with forward slashes' {
        Invoke-Backup | Out-Null
        $lines = Get-ManifestLines
        $lines.Count | Should -Be 3
        foreach ($line in $lines) { $line | Should -Match '^[0-9a-f]{64}  data/mmueller/(Documents|Desktop)/[^\\]+$' }
        $hash = (Get-FileHash -LiteralPath (Join-Path $Docs "Offerte_M${ue}ller.docx") -Algorithm SHA256).Hash.ToLower()
        $lines | Should -Contain "$hash  data/mmueller/Documents/Offerte_M${ue}ller.docx"
    }
    It 'writes the manifest as UTF-8 without BOM and with LF line ends' {
        Invoke-Backup | Out-Null
        $bytes = [System.IO.File]::ReadAllBytes((Join-Path $HostDir 'manifest.sha256'))
        $bytes[0] | Should -Not -Be 0xEF
        $bytes | Should -Not -Contain 13
        $bytes[-1] | Should -Be 10
    }
    It 'the manifest is accepted by sha256sum -c on Linux' -Skip:(-not (Get-Command sha256sum -ErrorAction SilentlyContinue)) {
        Invoke-Backup | Out-Null
        Push-Location $HostDir
        try {
            $out = & sha256sum -c manifest.sha256 2>&1
            $LASTEXITCODE | Should -Be 0
            # sha256sum prints the umlaut name escaped or not, depending on the locale.
            @($out | Where-Object { $_ -match ': OK$' }).Count | Should -Be 3
        } finally { Pop-Location }
    }
    It 'does not change the source files' {
        $before = (Get-FileHash -LiteralPath (Join-Path $Desk 'Notiz.txt')).Hash
        Invoke-Backup | Out-Null
        (Get-FileHash -LiteralPath (Join-Path $Desk 'Notiz.txt')).Hash | Should -Be $before
        @(Get-ChildItem -LiteralPath $Desk -File).Count | Should -Be 1
    }
    It 'handles many files with umlauts in the names (pitch scenario)' {
        $many = Join-Path $Docs "Auftr${ae}ge"
        New-Item -ItemType Directory -Path $many | Out-Null
        1..300 | ForEach-Object { Set-Content -LiteralPath (Join-Path $many "Auftrag_${_}_M${ue}ller.txt") -Value "Auftrag $_" }
        Invoke-Backup | Should -Be 0
        (Get-ManifestLines).Count | Should -Be 303
        @(Get-ChildItem -LiteralPath (Join-Path $HostDir "data/mmueller/Documents/Auftr${ae}ge") -File).Count | Should -Be 300
    }
    It 'skips a folder that no longer exists and still succeeds' {
        $script:Rows += New-Row -Category 'userfolder' -Name 'Pictures' -Path (Join-Path $Base 'Users/mmueller/Pictures') -Extra 'user=mmueller;files=0'
        Save-Inventory
        Invoke-Backup | Should -Be 0
        (Get-ManifestLines).Count | Should -Be 3
    }
    It 'keeps the folders of two users apart' {
        $other = Join-Path $Base 'Users/chef/Documents'
        New-Item -ItemType Directory -Path $other -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $other 'Notiz.txt') -Value 'Chef'
        $script:Rows += New-Row -Category 'userfolder' -Name 'Documents' -Path $other -Extra 'user=chef;files=1'
        Save-Inventory
        Invoke-Backup | Should -Be 0
        Get-Content -LiteralPath (Join-Path $HostDir 'data/chef/Documents/Notiz.txt') | Should -Be 'Chef'
        (Get-ManifestLines).Count | Should -Be 4
    }
}

Describe 'Backup-ToServer: low disk space on the server (pitch scenario)' {
    BeforeEach {
        Mock Write-Host { }
        New-Scene
    }

    It 'stops with exit code 3 and copies nothing' {
        Mock Get-MtxFreeBytes { 50MB }
        Invoke-Backup | Should -Be 3
        Test-Path -LiteralPath $HostDir | Should -BeFalse
    }
    It 'says clearly what is wrong' {
        Mock Get-MtxFreeBytes { 50MB }
        Invoke-Backup | Out-Null
        $log = Get-Content -LiteralPath (Join-Path $Base 'out/backup.log') -Raw
        $log | Should -Match 'NOT ENOUGH SPACE on the server'
        $log | Should -Match 'Nothing was copied'
    }
    It 'Test-MtxSpace: data + margin percent + 100 MB must fit' {
        Test-MtxSpace -NeededBytes 1000MB -FreeBytes 1200MB -MarginPercent 10 | Should -BeTrue
        Test-MtxSpace -NeededBytes 1000MB -FreeBytes 1199MB -MarginPercent 10 | Should -BeFalse
        Test-MtxSpace -NeededBytes 0 -FreeBytes 100MB -MarginPercent 10 | Should -BeTrue
        Test-MtxSpace -NeededBytes 0 -FreeBytes 99MB -MarginPercent 10 | Should -BeFalse
    }
    It 'Get-MtxFreeBytes reads the free space of a local folder' {
        Get-MtxFreeBytes -Path $Share | Should -BeGreaterThan 0
    }
}

Describe 'Backup-ToServer: failures' {
    BeforeEach {
        Mock Write-Host { }
        Mock Get-MtxFreeBytes { 50GB }
        New-Scene
    }

    It 'returns 4 and writes no manifest when a copy differs from its source' {
        $share = $Share
        Mock Get-MtxFileHash -ParameterFilter { $Path.StartsWith($share) -and $Path -like '*Notiz.txt' } { 'damaged-on-the-way' }.GetNewClosure()
        Invoke-Backup | Should -Be 4
        Test-Path -LiteralPath (Join-Path $HostDir 'manifest.sha256') | Should -BeFalse
        (Get-Content -LiteralPath (Join-Path $Base 'out/backup.log') -Raw) | Should -Match '1 of 3 files FAILED'
    }
    It 'removes the manifest of an older run when the new run fails' {
        Invoke-Backup | Should -Be 0
        Test-Path -LiteralPath (Join-Path $HostDir 'manifest.sha256') | Should -BeTrue
        Mock Get-MtxFileHash { throw 'disk error' }
        Invoke-Backup | Should -Be 4
        Test-Path -LiteralPath (Join-Path $HostDir 'manifest.sha256') | Should -BeFalse
    }
    It 'returns 1 for an inventory that breaks the contract, and copies nothing' {
        Set-Content -LiteralPath $Inventory -Value 'Hostname;Category' -Encoding $BomEncoding
        Invoke-Backup | Should -Be 1
        Test-Path -LiteralPath $HostDir | Should -BeFalse
    }
    It 'returns 1 when the destination does not exist' {
        Invoke-MtxBackup -InventoryPath $Inventory -Destination (Join-Path $Base 'nope') -MarginPercent 10 | Should -Be 1
    }
    It 'returns 1 without arguments' {
        Invoke-MtxBackup -InventoryPath '' -Destination '' -MarginPercent 10 | Should -Be 1
    }
    It 'logs in to the share when user and password are given' {
        Mock Connect-MtxShare { $true }
        Invoke-MtxBackup -InventoryPath $Inventory -Destination $Share -User 'migratux' -Password 'pw' -MarginPercent 10 | Should -Be 0
        Should -Invoke Connect-MtxShare -Times 1 -ParameterFilter { $User -eq 'migratux' -and $Password -eq 'pw' }
    }
    It 'returns 1 and copies nothing when the share login fails' {
        Mock Connect-MtxShare { $false }
        Invoke-MtxBackup -InventoryPath $Inventory -Destination $Share -User 'migratux' -Password 'wrong' -MarginPercent 10 | Should -Be 1
        Test-Path -LiteralPath $HostDir | Should -BeFalse
    }
    It 'run as a script, the exit code reaches the caller' -Skip:($PSVersionTable.PSEdition -eq 'Desktop') {
        & pwsh -NoProfile -File $Script -InventoryPath $Inventory -Destination (Join-Path $Base 'nope') *> $null
        $LASTEXITCODE | Should -Be 1
    }
}
