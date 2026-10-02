# AzureAppsDecommissionPublic

PowerShell utility for auditing and decommissioning Azure Web Apps and their associated Private Endpoints.

Warning:
This repository contains automation that can delete Azure resources. It is intended for controlled, validated environments only. Always test in a non-production subscription first and review the deletion plan before running a delete.

## Overview

This tool:
- reads a CSV list of app names
- finds matching Azure Web Apps in a target resource group
- identifies Private Endpoints and NICs associated with those apps
- lists the full planned deletion set
- defaults to dry-run behavior
- requires explicit delete mode and confirmation before deletion

## Prerequisites

- Azure PowerShell module `Az`
- An authenticated Azure session

Example:

```powershell
Install-Module -Name Az -Scope CurrentUser
Connect-AzAccount
Set-AzContext -SubscriptionId "<your-subscription-id>"
```

## Usage

### Dry run (default)

```powershell
.\drydeletewebapps.ps1 -ResourceGroupName "my-resource-group" -CsvPath ".\apps-to-delete.csv"
```

This will only display the resources that would be deleted and exits without making changes.

### Delete resources

```powershell
.\drydeletewebapps.ps1 -ResourceGroupName "my-resource-group" -CsvPath ".\apps-to-delete.csv" -Delete
```

This will show the deletion plan and then prompt for confirmation:

```powershell
type 'delete'
```

### Force delete without interactive confirmation

Use only when you are absolutely certain:

```powershell
.\drydeletewebapps.ps1 -ResourceGroupName "my-resource-group" -CsvPath ".\apps-to-delete.csv" -Delete -Force
```

## Input file format

The CSV must contain a column named `AppName`:

```csv
AppName
my-web-app-1
my-web-app-2
my-web-app-3
```

## Security notes

- Do not commit `apps-to-delete.csv` or generated JSON output files
- Do not run this against production resources without validation
- Review the deletion plan before using `-Delete`
- Use a non-production subscription for testing first

## Files in this repository

- `drydeletewebapps.ps1` — audit and delete utility
- `LICENSE` — MIT license
- `SECURITY.md` — security guidance
- `.gitignore` — excludes local and generated files
- `CONTRIBUTING.md` — contribution guidance

## License

This project is licensed under the MIT License. See the `LICENSE` file for details.
