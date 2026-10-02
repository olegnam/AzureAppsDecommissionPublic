param(
    [Parameter(Mandatory = $true)]
    [string]$ResourceGroupName,

    [Parameter(Mandatory = $true)]
    [string]$CsvPath,

    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Write-Host "AzureAppsDecommissionPublic - DELETE MODE" -ForegroundColor Red
Write-Host "WARNING: This will permanently delete Azure resources. This action cannot be undone." -ForegroundColor Red

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
Write-Host "  RESOURCES QUEUED FOR PERMANENT DELETION" -ForegroundColor Red
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
Write-Host "========================================`n" -ForegroundColor Red

if (-not $Force) {
    Write-Host "FINAL WARNING: You are about to permanently delete the resources listed above." -ForegroundColor Red
    Write-Host "This action CANNOT be undone. Azure Web Apps can be restored for up to 30 days," -ForegroundColor Red
    Write-Host "but Private Endpoints and NICs cannot be restored." -ForegroundColor Red
    Write-Host "`n" -ForegroundColor Red
    
    $confirm = Read-Host "Type 'DELETE' (in all caps) to permanently delete all resources, or anything else to cancel"
    if ($confirm -ne 'DELETE') {
        Write-Host "`nCancelled. Nothing was deleted." -ForegroundColor Yellow
        exit 0
    }
}

Write-Host "`nProceeding with deletion..." -ForegroundColor Red
Write-Host "This operation cannot be stopped once started." -ForegroundColor Red

foreach ($item in $deletionPlan) {
    try {
        switch ($item.Type) {
            'Private Endpoint' {
                Write-Host "Deleting Private Endpoint: $($item.Name)" -ForegroundColor Yellow
                Remove-AzPrivateEndpoint -ResourceGroupName $item.ResourceGroup -Name $item.Name -Force
                Write-Host "  [SUCCESS] Deleted" -ForegroundColor Green
            }

            'NIC' {
                Write-Host "Deleting NIC: $($item.Name)" -ForegroundColor Yellow
                Remove-AzNetworkInterface -ResourceGroupName $item.ResourceGroup -Name $item.Name -Force
                Write-Host "  [SUCCESS] Deleted" -ForegroundColor Green
            }

            'Web App' {
                Write-Host "Deleting Web App: $($item.Name)" -ForegroundColor Red
                Remove-AzWebApp -ResourceGroupName $item.ResourceGroup -Name $item.Name -Force
                Write-Host "  [SUCCESS] Deleted" -ForegroundColor Green
            }
        }
    }
    catch {
        Write-Host "  [ERROR] Failed to delete $($item.Type) '$($item.Name)': $_" -ForegroundColor Red
    }
}

Write-Host "`n" -ForegroundColor Red
Write-Host "========================================" -ForegroundColor Red
Write-Host "Deletion complete." -ForegroundColor Red
Write-Host "========================================" -ForegroundColor Red
