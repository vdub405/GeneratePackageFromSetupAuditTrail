Describe 'Generate-SetupAuditPackage' {
    BeforeAll {
        $script:ToolRoot = Split-Path -Parent $PSScriptRoot
        $script:ScriptPath = Join-Path $script:ToolRoot 'scripts/Generate-SetupAuditPackage.ps1'
        $script:TempRoot = Join-Path $script:ToolRoot 'tests/.tmp'

        if (Test-Path $script:TempRoot) {
            Remove-Item $script:TempRoot -Recurse -Force
        }
        New-Item -ItemType Directory -Path $script:TempRoot -Force | Out-Null
    }

    It 'creates package xml for rows after cutoff date' {
        $csvPath = Join-Path $script:TempRoot 'sat.csv'
        @'
Date,User,Source Namespace Prefix,Action,Section,Delegate User
"7/9/2026, 7:05:31 AM EST",vicki@example.com,,Created custom app Tower,Custom Apps,
"7/8/2026, 1:09:00 PM EST",Automated Process,,Account matching rule,Matching Rule,
'@ | Out-File -FilePath $csvPath -Encoding utf8

        $outPath = Join-Path $script:TempRoot 'package.xml'
        & $script:ScriptPath -CsvPath $csvPath -CutoffDate '2026-07-08' -OutputPath $outPath -ApiVersion '60.0'

        (Test-Path $outPath) | Should Be $true
        $content = Get-Content -Raw -Path $outPath
        $content | Should Match '<name>CustomApplication</name>'
    }

    It 'includes cutoff date when IncludeOnOrAfter is used' {
        $csvPath = Join-Path $script:TempRoot 'sat2.csv'
        @'
Date,User,Source Namespace Prefix,Action,Section,Delegate User
"7/8/2026, 12:00:00 AM EST",vicki@example.com,,Created custom app Tower,Custom Apps,
'@ | Out-File -FilePath $csvPath -Encoding utf8

        $outPath = Join-Path $script:TempRoot 'package2.xml'
        & $script:ScriptPath -CsvPath $csvPath -CutoffDate '2026-07-08' -OutputPath $outPath -IncludeOnOrAfter

        (Test-Path $outPath) | Should Be $true
    }
}
