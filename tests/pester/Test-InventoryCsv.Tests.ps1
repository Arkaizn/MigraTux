# Pester 5 tests for collect/Test-InventoryCsv.ps1. Run: tests/run.sh pester
BeforeAll {
    $script:Validator = Join-Path $PSScriptRoot '../../collect/Test-InventoryCsv.ps1'
    $script:Fixture   = Join-Path $PSScriptRoot '../fixtures/inventory-sample.csv'
    $script:Header    = '"Hostname","Category","Name","Version","Publisher","Path","SizeMB","Extra"'
    # Windows PowerShell 5.1 writes a BOM with 'UTF8'; PowerShell 7 needs 'utf8BOM'.
    $script:BomEncoding = if ($PSVersionTable.PSEdition -eq 'Desktop') { 'UTF8' } else { 'utf8BOM' }

    # Write lines as UTF-8 (with BOM unless -NoBom) and return the path.
    function New-Csv([string[]]$Lines, [switch]$NoBom) {
        $file = Join-Path $TestDrive ("t{0}.csv" -f [guid]::NewGuid())
        $enc  = [System.Text.UTF8Encoding]::new(-not $NoBom)
        [System.IO.File]::WriteAllText($file, ($Lines -join "`r`n") + "`r`n", $enc)
        $file
    }
    # All errors as one string, so Should -Match sees every message.
    function Get-Errors([string[]]$Rows, [switch]$NoBom) {
        (& $Validator -Path (New-Csv (@($Header) + $Rows) -NoBom:$NoBom)).Errors -join "`n"
    }
}

Describe 'Test-InventoryCsv' {
    Context 'valid input' {
        It 'accepts the sample fixture' {
            $r = & $Validator -Path $Fixture
            $r.Errors   | Should -BeNullOrEmpty
            $r.Valid    | Should -BeTrue
            $r.RowCount | Should -Be 26
        }
        It 'accepts a file written with Export-Csv the way the contract says' {
            $file = Join-Path $TestDrive 'export.csv'
            @(
                [pscustomobject]@{ Hostname = 'PC1'; Category = 'app'; Name = 'VLC media player'; Version = '3.0.21'; Publisher = 'VideoLAN'; Path = 'C:\Program Files\VideoLAN\VLC'; SizeMB = 180; Extra = 'scope=machine;arch=x64' }
                [pscustomobject]@{ Hostname = 'PC1'; Category = 'userfolder'; Name = 'Documents'; Version = ''; Publisher = ''; Path = 'C:\Users\a\Documents'; SizeMB = 12; Extra = '' }
            ) | Export-Csv -LiteralPath $file -NoTypeInformation -Encoding $BomEncoding
            (& $Validator -Path $file).Valid | Should -BeTrue
        }
        It 'accepts LF line endings and empty optional fields' {
            $file = Join-Path $TestDrive 'lf.csv'
            [System.IO.File]::WriteAllText($file, "$Header`n`"PC1`",`"printer`",`"P1`",`"`",`"`",`"`",`"`",`"`"`n", [System.Text.UTF8Encoding]::new($true))
            (& $Validator -Path $file).Valid | Should -BeTrue
        }
        It 'keeps umlauts and commas inside quoted fields' {
            Get-Errors '"PC1","printer","HP LaserJet, Büro 1","","","","",""' | Should -BeNullOrEmpty
        }
    }

    Context 'invalid input' {
        It 'reports a missing file' {
            $r = & $Validator -Path (Join-Path $TestDrive 'nope.csv')
            $r.Valid  | Should -BeFalse
            $r.Errors | Should -Match 'File not found'
        }
        It 'requires a BOM' {
            Get-Errors '"PC1","app","X","","","","",""' -NoBom | Should -Match 'BOM'
        }
        It 'rejects the #TYPE line' {
            $r = & $Validator -Path (New-Csv @('#TYPE System.Management.Automation.PSCustomObject', $Header))
            $r.Errors | Should -Match 'NoTypeInformation'
        }
        It 'rejects a semicolon delimiter' {
            $r = & $Validator -Path (New-Csv @('"Hostname";"Category";"Name";"Version";"Publisher";"Path";"SizeMB";"Extra"'))
            $r.Errors | Should -Match 'header must be exactly'
        }
        It 'rejects a wrong column order' {
            $r = & $Validator -Path (New-Csv @('"Category","Hostname","Name","Version","Publisher","Path","SizeMB","Extra"'))
            $r.Errors | Should -Match 'header must be exactly'
        }
        It 'rejects a header with no rows' {
            (& $Validator -Path (New-Csv @($Header))).Errors | Should -Match 'No data rows'
        }
        It 'rejects an unknown category with its line number' {
            Get-Errors '"PC1","software","X","","","","",""' | Should -Match "Line 2: Category 'software'"
        }
        It 'rejects an upper-case category' {
            Get-Errors '"PC1","App","X","","","","",""' | Should -Match 'Category'
        }
        It 'rejects an empty Name' {
            Get-Errors '"PC1","app","","","","","",""' | Should -Match 'Name is empty'
        }
        It 'rejects a decimal SizeMB' {
            Get-Errors '"PC1","app","X","","","","12,5",""' | Should -Match 'SizeMB'
        }
        It 'rejects two hostnames in one file' {
            Get-Errors '"PC1","app","X","","","","",""', '"PC2","app","Y","","","","",""' | Should -Match "Line 3: Hostname 'PC2'"
        }
        It 'rejects an empty Hostname' {
            Get-Errors '"","app","X","","","","",""' | Should -Match 'Hostname is empty'
        }
        It 'rejects a malformed Extra' {
            Get-Errors '"PC1","app","X","","","","","Scope=machine"' | Should -Match 'Extra'
            Get-Errors '"PC1","app","X","","","","","scope"'         | Should -Match 'Extra'
        }
        It 'rejects a line break inside a field' {
            Get-Errors "`"PC1`",`"app`",`"X`",`"`",`"`",`"`",`"`",`"a=1`r`nb=2`"" | Should -Match 'line break'
        }
    }
}
