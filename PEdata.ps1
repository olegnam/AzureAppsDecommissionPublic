param(
    [Parameter(Mandatory = $true)]
    [string]$ResourceGroupName,

    [Parameter(Mandatory = $true)]
    [string]$CsvPath,

    [string]$OutputPath = $null
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Set default output path if not provided
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path $PSScriptRoot "private-endpoint-audit_$(Get-Date -Format 'yyyyMMdd_HHmmss').json"
}

Write-Host "AzureAppsDecommissionPublic - Private Endpoint Audit" -ForegroundColor Cyan
Write-Host "This script exports Private Endpoint configurations to JSON for restoration purposes." -ForegroundColor Gray

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

$auditResults = @()

foreach ($app in $webApps) {
    Write-Host "`nAuditing: $app" -ForegroundColor Cyan

    $webAppResource = Get-AzWebApp -ResourceGroupName $ResourceGroupName -Name $app -ErrorAction SilentlyContinue

    if (-not $webAppResource) {
        Write-Host "  [WARNING] Web App '$app' not found. Skipping." -ForegroundColor Magenta
        continue
    }

    $webAppResourceId = $webAppResource.Id
    Write-Host "  Resource ID: $webAppResourceId" -ForegroundColor Gray

    $privateEndpoints = Get-AzPrivateEndpoint -ResourceGroupName $ResourceGroupName | Where-Object {
        $_.PrivateLinkServiceConnections.PrivateLinkServiceId -eq $webAppResourceId
    }

    if (-not $privateEndpoints) {
        Write-Host "  No private endpoints found." -ForegroundColor Gray
        $auditResults += [PSCustomObject]@{
            WebAppName               = $app
            WebAppResourceId         = $webAppResourceId
            PrivateEndpoints         = @()
            AuditTimestamp           = (Get-Date -Format 'o')
        }
        continue
    }

    $peList = @()

    foreach ($pe in $privateEndpoints) {
        Write-Host "  Found PE: $($pe.Name)" -ForegroundColor Yellow

        $nicDetails = foreach ($nicRef in $pe.NetworkInterfaces) {
            $nicName = ($nicRef.Id -split '/')[-1]
            $nic = Get-AzNetworkInterface -ResourceGroupName $ResourceGroupName -Name $nicName -ErrorAction SilentlyContinue

            if ($nic) {
                [PSCustomObject]@{
                    NicName              = $nic.Name
                    NicId                = $nic.Id
                    PrivateIPAddress     = $nic.IpConfigurations[0].PrivateIpAddress
                    PrivateIPAllocMethod = $nic.IpConfigurations[0].PrivateIpAllocationMethod
                    SubnetId             = $nic.IpConfigurations[0].Subnet.Id
                    DNSSettings          = $nic.DnsSettings
                }
            }
        }

        $dnsZoneDetails = if ($pe.PrivateDnsZoneGroups) {
            foreach ($zoneGroup in $pe.PrivateDnsZoneGroups) {
                foreach ($zoneConfig in $zoneGroup.PrivateDnsZoneConfigs) {
                    [PSCustomObject]@{
                        ZoneGroupName    = $zoneGroup.Name
                        ZoneName         = $zoneConfig.Name
                        PrivateDnsZoneId = $zoneConfig.PrivateDnsZoneId
                    }
                }
            }
        } else { @() }

        $peList += [PSCustomObject]@{
            PrivateEndpointName      = $pe.Name
            PrivateEndpointId        = $pe.Id
            Location                 = $pe.Location
            SubnetId                 = $pe.Subnet.Id
            PrivateLinkServiceId     = $pe.PrivateLinkServiceConnections[0].PrivateLinkServiceId
            GroupIds                 = $pe.PrivateLinkServiceConnections[0].GroupIds
            ConnectionState          = $pe.PrivateLinkServiceConnections[0].PrivateLinkServiceConnectionState.Status
            NetworkInterfaces        = @($nicDetails)
            PrivateDnsZoneGroups     = @($dnsZoneDetails)
        }
    }

    $auditResults += [PSCustomObject]@{
        WebAppName       = $app
        WebAppResourceId = $webAppResourceId
        PrivateEndpoints = $peList
        AuditTimestamp   = (Get-Date -Format 'o')
    }
}

if ($auditResults.Count -eq 0) {
    Write-Host "`nNo data found to export." -ForegroundColor Yellow
    exit 0
}

try {
    $auditResults | ConvertTo-Json -Depth 10 | Out-File -FilePath $OutputPath -Encoding UTF8
    Write-Host "`nAudit complete. Output saved to: $OutputPath" -ForegroundColor Green
    Write-Host "Keep this file secure—it contains infrastructure topology details." -ForegroundColor Yellow
}
catch {
    throw "Failed to write audit output to $OutputPath : $_"
}
