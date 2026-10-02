param(
    [Parameter(Mandatory = $true)]
    [string]$ResourceGroupName,

    [Parameter(Mandatory = $true)]
    [string]$CsvPath,

    [switch]$Delete,

    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Write-Host "AzureAppsDecommissionPublic" -ForegroundColor Cyan
Write-Host "This script can delete Azure resources. Use with care and validate the target environment first." -ForegroundColor Yellow

# Validate current Azure context
$context = Get-AzContext
if (-not $context) {
    throw "Not authenticated to Azure. Run Connect-AzAccount before executing this script."
}

Write-Host "Connected to subscription: $($context.Subscription.Name) ($($context.Subscription.Id))" -ForegroundColor Cyan

# Validate CSV file
if (-not (Test-Path -Path $CsvPath)) {
    throw "CSV file not found: $CsvPath"
}

try {
    $webApps = @(Import-Csv -Path $CsvPath | Where-Object { $_.AppName -and $_.AppName.Trim() } | Select-Object -ExpandProperty AppName)
}
catch {
    throw "Failed to read CSV file '$CsvPath'. Ensure it contains a column named 'AppName'."
}

if ($webApps.Count -eq 0) {
    throw "No valid AppName values were found in '$CsvPath'."
}

$deletionPlan = @()

foreach ($app in $webApps) {
    Write-Host "`nLooking up: $app" -ForegroundColor Cyan

    $webAppResource = Get-AzWebApp -ResourceGroupName $ResourceGroupName -Name $app -ErrorAction SilentlyContinue

    if (-not $webAppResource) {
        Write-Host "  [WARNING] Web App '$app' not found in resource group '$ResourceGroupName'. Skipping." -ForegroundColor Magenta
        continue
    }

    $webAppResourceId = $webAppResource.Id
    Write-Host "  Resource ID: $webAppResourceId" -ForegroundColor Gray

    $privateEndpoints = Get-AzPrivateEndpoint -ResourceGroupName $ResourceGroupName | Where-Object {
        $_.PrivateLinkServiceConnections.PrivateLinkServiceId -eq $webAppResourceId
    }

    foreach ($pe in $privateEndpoints) {
        $deletionPlan += [PSCustomObject]@{
            Type          = 'Private Endpoint'
            Name          = $pe.Name
            ResourceGroup = $ResourceGroupName
        }

        foreach ($nicRef in $pe.NetworkInterfaces) {
            $nicName = ($nicRef.Id -split '/')[-1]
            $deletionPlan += [PSCustomObject]@{
                Type          = 'NIC'
                Name          = $nicName
                ResourceGroup = $ResourceGroupName
            }
        }
    }

    $deletionPlan += [PSCustomObject]@{
        Type          = 'Web App'
        Name          = $app
        ResourceGroup = $ResourceGroupName
    }
}

if ($deletionPlan.Count -eq 0) {
    Write-Host "`nNo resources found to delete. Exiting." -ForegroundColor Yellow
    exit 0
}

Write-Host "`n========================================" -ForegroundColor White
Write-Host "  RESOURCES QUEUED FOR DELETION" -ForegroundColor White
Write-Host "========================================" -ForegroundColor White

foreach ($item in $deletionPlan) {
    $color = switch ($item.Type) {
        'Private Endpoint' { 'Yellow' }
        'NIC' { 'Yellow' }
        'Web App' { 'Red' }
        default { 'White' }
    }

    Write-Host "  [$($item.Type)] $($item.Name)" -ForegroundColor $color
}

Write-Host "========================================" -ForegroundColor White
Write-Host "  Total: $($deletionPlan.Count) resource(s)" -ForegroundColor White
Write-Host "========================================`n" -ForegroundColor White

if (-not $Delete) {
    Write-Host "Dry run mode only. Nothing was deleted." -ForegroundColor Green
    exit 0
}

if (-not $Force) {
    $confirm = Read-Host "Type 'delete' to permanently delete all resources listed above, or anything else to cancel"
    if ($confirm -ne 'delete') {
        Write-Host "`nCancelled. Nothing was deleted." -ForegroundColor Yellow
        exit 0
    }
}

foreach ($item in $deletionPlan) {
    try {
        switch ($item.Type) {
            'Private Endpoint' {
                Write-Host "Deleting Private Endpoint: $($item.Name)" -ForegroundColor Yellow
                Remove-AzPrivateEndpoint -ResourceGroupName $item.ResourceGroup -Name $item.Name -Force
            }

            'NIC' {
                Write-Host "Deleting NIC: $($item.Name)" -ForegroundColor Yellow
                Remove-AzNetworkInterface -ResourceGroupName $item.ResourceGroup -Name $item.Name -Force
            }

            'Web App' {
                Write-Host "Deleting Web App: $($item.Name)" -ForegroundColor Red
                Remove-AzWebApp -ResourceGroupName $item.ResourceGroup -Name $item.Name -Force
            }
        }
    }
    catch {
        Write-Host "  [ERROR] Failed to delete $($item.Type) '$($item.Name)': $_" -ForegroundColor Red
    }
}

Write-Host "`nDeletion complete." -ForegroundColor Green
