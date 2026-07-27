# setup-audit-package-gen

Generate a conservative Salesforce package.xml from Setup Audit Trail CSV exports.

## What It Does

This tool reads a Setup Audit Trail CSV file, filters rows by date (and optional users), maps Setup sections/actions to Salesforce metadata types, and generates a package.xml with wildcard members.

Use it when you need a repeatable retrieval manifest after a known change window.

## Why Conservative Wildcards

Setup Audit Trail text is not a one-to-one mapping to metadata member names in every case. This tool intentionally outputs wildcard members per impacted metadata type to minimize missed retrievals.

## Project Structure

- scripts/Generate-SetupAuditPackage.ps1: Main generator script
- config/mapping.default.json: Section/action to metadata-type mapping rules
- tests/Generate-SetupAuditPackage.Tests.ps1: Pester tests

## Prerequisites

- PowerShell 5.1+ or PowerShell 7+
- Salesforce Setup Audit Trail CSV export
- Salesforce CLI (`sf`) if you want to retrieve right after generation

## Parameters

- CsvPath (required): path to Setup Audit CSV
- CutoffDate (required): date boundary used for filtering
- OutputPath (optional): destination package.xml path (default: ./out/package.xml)
- ApiVersion (optional): metadata API version (default: 60.0)
- MappingPath (optional): mapping rules file (default: ../config/mapping.default.json)
- IncludeOnOrAfter (optional switch): include rows where Date equals cutoff
- IncludeUsers (optional): only include these users
- ExcludeUsers (optional): exclude these users
- SummaryPath (optional): write a JSON summary report

## Quick Start

From this folder:

```powershell
./scripts/Generate-SetupAuditPackage.ps1 \
  -CsvPath ../../pathtocsv.csv \
  -CutoffDate 'YYYY-MM-DD' \
  -OutputPath ../../path/to/package.xml \
  -ApiVersion '' \
  -SummaryPath ./out/summary.json
```

Retrieve from org with Salesforce CLI:

```powershell
sf project retrieve start \
  --manifest ../../path/to/package.xml \
  --target-org org \
  --output-dir path/to/retrieved
```

## Mapping Customization

Edit config/mapping.default.json to tune what metadata types are included for each Setup section/action pattern.

### mapping.default.json shape

```json
{
  "sectionRegexMappings": [
    {
      "sectionRegex": "^Lightning Pages$",
      "types": ["FlexiPage"]
    }
  ],
  "conditionalMappings": [
    {
      "sectionRegex": "^Manage Users$",
      "actionRegex": "^(Changed|Created) profile ",
      "types": ["Profile"]
    }
  ]
}
```

## Notes

- This tool is intentionally metadata-type broad to avoid missing changed components.
- You can run a second pass by narrowing mapping rules for segments.
