<#
.SYNOPSIS
	Return devices from Entra and Defender, along with their last checkin dates and export to CSV
.DESCRIPTION
	Script is still being tested, also currently returns all devices, not just computers and servers
.NOTES
	Version: 0.1
#>

$TenantId = $Config.DeviceCheckinReport.TenantID
$ClientId = $Config.DeviceCheckinReport.ClientID
$ClientSecret = $Config.DeviceCheckinReport.ReportingSecret

$StaleDays = 21
$CutoffDate = (Get-Date).AddDays(-$StaleDays)

# ============================================================
# Get Token Function
# ============================================================

function Get-AppToken {

    param(
        [string]$Scope
    )

    $Body = @{
        grant_type    = "client_credentials"
        client_id     = $ClientId
        client_secret = $ClientSecret
        scope         = $Scope
    }

    Invoke-RestMethod `
        -Method Post `
        -Uri "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token" `
        -Body $Body
}

# ============================================================
# Defender Token
# ============================================================

Write-Host ""
Write-Host "Getting Defender token..." -ForegroundColor Cyan

$DefenderToken = Get-AppToken `
    -Scope "fc780465-2017-40d4-a0c5-307022471b92/.default"

$DefenderHeaders = @{
    Authorization = "Bearer $($DefenderToken.access_token)"
}

# ============================================================
# Graph Token
# ============================================================

Write-Host "Getting Graph token..." -ForegroundColor Cyan

$GraphToken = Get-AppToken `
    -Scope "https://graph.microsoft.com/.default"

$GraphHeaders = @{
    Authorization = "Bearer $($GraphToken.access_token)"
}

# ============================================================
# Get Entra Devices
# ============================================================

Write-Host ""
Write-Host "Collecting Entra devices..." -ForegroundColor Cyan

$EntraDevices = @()
$GraphUri = "https://graph.microsoft.com/v1.0/devices?`$top=999"

do {

    $Response = Invoke-RestMethod `
        -Method Get `
        -Uri $GraphUri `
        -Headers $GraphHeaders

    $EntraDevices += $Response.value

    Write-Host "Entra Devices Collected: $($EntraDevices.Count)"

    $GraphUri = $Response.'@odata.nextLink'

} while ($GraphUri)

# ============================================================
# Build Entra Lookup
# ============================================================

$EntraLookup = @{}

foreach ($Device in $EntraDevices) {

    if ($Device.deviceId) {

        $EntraLookup[$Device.deviceId.ToLower()] = $Device
    }
}

# ============================================================
# Get Defender Devices
# ============================================================

Write-Host ""
Write-Host "Collecting Defender devices..." -ForegroundColor Cyan

$DefenderDevices = @()
$DefenderUri = "https://api.security.microsoft.com/api/machines"

do {

    $Response = Invoke-RestMethod `
        -Method Get `
        -Uri $DefenderUri `
        -Headers $DefenderHeaders

    $DefenderDevices += $Response.value

    Write-Host "Defender Devices Collected: $($DefenderDevices.Count)"

    $DefenderUri = $Response.'@odata.nextLink'

} while ($DefenderUri)

# ============================================================
# Build Report
# ============================================================

Write-Host ""
Write-Host "Building report..." -ForegroundColor Cyan

$Report = New-Object System.Collections.ArrayList

$Total = $DefenderDevices.Count
$Counter = 0

foreach ($Machine in $DefenderDevices) {

    $Counter++

    $Percent = [System.Math]::Round(
        (($Counter / $Total) * 100),
        0
    )

    Write-Progress `
        -Activity "Processing Devices" `
        -Status "$Counter of $Total" `
        -PercentComplete $Percent

    $AADDeviceId = $Machine.aadDeviceId

    $EntraDevice = $null

    if ($AADDeviceId) {

        $LookupKey = $AADDeviceId.ToLower()

        if ($EntraLookup.ContainsKey($LookupKey)) {

            $EntraDevice = $EntraLookup[$LookupKey]
        }
    }

    $DefenderLastSeen = $null
    $EntraLastSignIn = $null

    if ($Machine.lastSeen) {
        $DefenderLastSeen = [datetime]$Machine.lastSeen
    }

    if ($EntraDevice.approximateLastSignInDateTime) {
        $EntraLastSignIn = [datetime]$EntraDevice.approximateLastSignInDateTime
    }

    $DefenderAgeDays = $null
    $EntraAgeDays = $null

    if ($DefenderLastSeen) {
        $DefenderAgeDays = [System.Math]::Round(
            ((Get-Date) - $DefenderLastSeen).TotalDays,
            0
        )
    }

    if ($EntraLastSignIn) {
        $EntraAgeDays = [System.Math]::Round(
            ((Get-Date) - $EntraLastSignIn).TotalDays,
            0
        )
    }

    $DefenderStale = $true

    if ($DefenderLastSeen) {
        $DefenderStale = ($DefenderLastSeen -lt $CutoffDate)
    }

    $EntraStale = $true

    if ($EntraLastSignIn) {
        $EntraStale = ($EntraLastSignIn -lt $CutoffDate)
    }
	
	$DeviceName = $Machine.computerDnsName
			if ([string]::IsNullOrWhiteSpace($DeviceName)) {
				if ($EntraDevice.displayName) {
					$DeviceName = $EntraDevice.displayName
				}
			}
			if ([string]::isNullOrWhiteSpace($DeviceName)) {
				$DeviceName = "Unknown"
			}
    [void]$Report.Add(
		
        [PSCustomObject]@{

			DeviceName = $DeviceName
			DeviceId = $Machine.id
			EntraDeviceId = $Machine.aadDeviceId

            DefenderLastSeen = $DefenderLastSeen
            DefenderAgeDays = $DefenderAgeDays
            DefenderOlderThan21Days = $DefenderStale

            EntraLastSignIn = $EntraLastSignIn
            EntraAgeDays = $EntraAgeDays
            EntraOlderThan21Days = $EntraStale

            HealthStatus = $Machine.healthStatus
            RiskScore = $Machine.riskScore
            OSPlatform = $Machine.osPlatform
        }
    )
}

Write-Progress `
    -Activity "Processing Devices" `
    -Completed

# ============================================================
# Export Report
# ============================================================

$CsvPath = "C:\Users\Marc.Jones\DeviceStalenessReport.csv"

$Report |
    Sort-Object DeviceName |
    Export-Csv `
        -Path $CsvPath `
        -NoTypeInformation

# ============================================================
# Summary
# ============================================================

$DefenderStaleCount = ($Report | Where-Object {
    $_.DefenderOlderThan21Days -eq $true
}).Count

$EntraStaleCount = ($Report | Where-Object {
    $_.EntraOlderThan21Days -eq $true
}).Count

Write-Host ""
Write-Host "==========================================" -ForegroundColor Green
Write-Host "Report Complete" -ForegroundColor Green
Write-Host "==========================================" -ForegroundColor Green
Write-Host ""
Write-Host "Total Devices      : $($Report.Count)"
Write-Host "Defender >21 Days  : $DefenderStaleCount"
Write-Host "Entra >21 Days     : $EntraStaleCount"
Write-Host ""
Write-Host "CSV Exported To:"
Write-Host $CsvPath -ForegroundColor Yellow
Write-Host ""

$Report | Out-GridView