[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$CsvPath,

    [Parameter(Mandatory = $true)]
    [datetime]$CutoffDate,

    [string]$OutputPath = "./out/package.xml",

    [string]$ApiVersion = "60.0",

    [string]$MappingPath = "../config/mapping.default.json",

    [switch]$IncludeOnOrAfter,

    [string[]]$IncludeUsers,

    [string[]]$ExcludeUsers,

    [string]$SummaryPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Resolve-ScriptRelativePath {
    param([string]$PathValue)

    if ([System.IO.Path]::IsPathRooted($PathValue)) {
        return $PathValue
    }

    return [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot $PathValue))
}

function Parse-AuditDate {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $null
    }

    # Salesforce export has a trailing timezone abbreviation (for example: EST).
    $normalized = $Value.Trim() -replace ' [A-Z]{3,4}$', ''
    try {
        return [datetime]::Parse($normalized, [System.Globalization.CultureInfo]::InvariantCulture)
    }
    catch {
        return $null
    }
}

function Add-TypeWildcard {
    param(
        [hashtable]$Map,
        [string]$MetadataType
    )

    if (-not $Map.ContainsKey($MetadataType)) {
        $Map[$MetadataType] = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    }
    [void]$Map[$MetadataType].Add('*')
}

function Test-DateMatch {
    param(
        [datetime]$AuditDate,
        [datetime]$Boundary,
        [switch]$Inclusive
    )

    if ($Inclusive) {
        return $AuditDate -ge $Boundary
    }
    return $AuditDate -gt $Boundary
}

$resolvedCsv = Resolve-Path $CsvPath
$resolvedMapping = Resolve-ScriptRelativePath -PathValue $MappingPath

if (-not (Test-Path $resolvedMapping)) {
    throw "Mapping file not found: $resolvedMapping"
}

$mapping = Get-Content -Raw -Path $resolvedMapping | ConvertFrom-Json
$rows = Import-Csv -Path $resolvedCsv

$includeUserSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
if ($IncludeUsers) {
    foreach ($item in $IncludeUsers) {
        if (-not [string]::IsNullOrWhiteSpace($item)) {
            [void]$includeUserSet.Add($item.Trim())
        }
    }
}

$excludeUserSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
if ($ExcludeUsers) {
    foreach ($item in $ExcludeUsers) {
        if (-not [string]::IsNullOrWhiteSpace($item)) {
            [void]$excludeUserSet.Add($item.Trim())
        }
    }
}

$filtered = New-Object System.Collections.Generic.List[object]
foreach ($row in $rows) {
    $auditDate = Parse-AuditDate -Value $row.Date
    if ($null -eq $auditDate) {
        continue
    }

    if (-not (Test-DateMatch -AuditDate $auditDate -Boundary $CutoffDate -Inclusive:$IncludeOnOrAfter.IsPresent)) {
        continue
    }

    $userName = if ($null -eq $row.User) { "" } else { $row.User.ToString().Trim() }

    if ($includeUserSet.Count -gt 0 -and -not $includeUserSet.Contains($userName)) {
        continue
    }

    if ($excludeUserSet.Count -gt 0 -and $excludeUserSet.Contains($userName)) {
        continue
    }

    $filtered.Add($row)
}

if ($filtered.Count -eq 0) {
    throw "No Setup Audit Trail rows matched your filters."
}

$typeMap = @{}

foreach ($row in $filtered) {
    $section = if ($null -eq $row.Section) { "" } else { $row.Section.ToString().Trim() }
    $action = if ($null -eq $row.Action) { "" } else { $row.Action.ToString().Trim() }

    foreach ($rule in $mapping.sectionRegexMappings) {
        if ($section -match $rule.sectionRegex) {
            foreach ($typeName in $rule.types) {
                Add-TypeWildcard -Map $typeMap -MetadataType $typeName
            }
        }
    }

    foreach ($rule in $mapping.conditionalMappings) {
        if ($section -match $rule.sectionRegex -and $action -match $rule.actionRegex) {
            foreach ($typeName in $rule.types) {
                Add-TypeWildcard -Map $typeMap -MetadataType $typeName
            }
        }
    }
}

if ($typeMap.Count -eq 0) {
    throw "No metadata-bearing sections were detected in the filtered rows."
}

$targetPath = if ([System.IO.Path]::IsPathRooted($OutputPath)) {
    $OutputPath
}
else {
    [System.IO.Path]::GetFullPath((Join-Path (Get-Location) $OutputPath))
}

$targetDir = Split-Path -Path $targetPath -Parent
if (-not (Test-Path $targetDir)) {
    New-Item -Path $targetDir -ItemType Directory -Force | Out-Null
}

$lines = New-Object System.Collections.Generic.List[string]
[void]$lines.Add('<?xml version="1.0" encoding="UTF-8"?>')
[void]$lines.Add('<Package xmlns="http://soap.sforce.com/2006/04/metadata">')

foreach ($typeName in ($typeMap.Keys | Sort-Object)) {
    [void]$lines.Add('  <types>')
    foreach ($member in ($typeMap[$typeName] | Sort-Object)) {
        [void]$lines.Add("    <members>$member</members>")
    }
    [void]$lines.Add("    <name>$typeName</name>")
    [void]$lines.Add('  </types>')
}

[void]$lines.Add("  <version>$ApiVersion</version>")
[void]$lines.Add('</Package>')

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllLines($targetPath, $lines, $utf8NoBom)

$summary = [ordered]@{
    csvPath = $resolvedCsv.Path
    mappingPath = $resolvedMapping
    cutoffDate = $CutoffDate.ToString("s")
    inclusive = $IncludeOnOrAfter.IsPresent
    filteredRows = $filtered.Count
    metadataTypes = @($typeMap.Keys | Sort-Object)
    outputPath = $targetPath
}

if (-not [string]::IsNullOrWhiteSpace($SummaryPath)) {
    $summaryTarget = if ([System.IO.Path]::IsPathRooted($SummaryPath)) {
        $SummaryPath
    }
    else {
        [System.IO.Path]::GetFullPath((Join-Path (Get-Location) $SummaryPath))
    }

    $summaryDir = Split-Path -Path $summaryTarget -Parent
    if (-not (Test-Path $summaryDir)) {
        New-Item -Path $summaryDir -ItemType Directory -Force | Out-Null
    }

    ($summary | ConvertTo-Json -Depth 5) | Out-File -FilePath $summaryTarget -Encoding utf8
    Write-Host "Summary written: $summaryTarget"
}

Write-Host "Filtered rows after cutoff: $($filtered.Count)"
Write-Host "Manifest written: $targetPath"
Write-Host "Included metadata types: $((($typeMap.Keys | Sort-Object) -join ', '))"
