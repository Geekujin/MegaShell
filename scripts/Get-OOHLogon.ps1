<#
.SYNOPSIS
    Searches past 30 days day-by-day to minimize memory usage.
	
#>

Connect-MgGraph -Scopes "AuditLog.Read.All" -NoWelcome

$daysBack = 30
$startDate = (Get-Date).AddDays(-$daysBack).Date # Midnight 30 days ago
$endDate = (Get-Date).Date.AddDays(1) # Midnight tomorrow (to cover today)

$officeHoursStart = 6
$officeHoursEnd = 18

# Use a Generic List for performance (faster than += arrays)
$allSuspiciousLogs = [System.Collections.Generic.List[PSObject]]::new()

# Loop through each day
for ($i = 0; $i -lt $daysBack + 1; $i++) {
    $currentDayStart = $startDate.AddDays($i)
    $currentDayEnd = $currentDayStart.AddDays(1)
    
    # Write progress to screen
    Write-Progress -Activity "Fetching Logs" -Status "Processing $($currentDayStart.ToString('yyyy-MM-dd'))" -PercentComplete (($i / ($daysBack + 1)) * 100)

    # Convert to ISO strings for Graph Filter
    $filterStart = $currentDayStart.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    $filterEnd = $currentDayEnd.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')

    # Fetch only 24 hours of logs
    $dailyLogs = Get-MgAuditLogSignIn -Filter "createdDateTime ge $filterStart and createdDateTime lt $filterEnd" -All

    # Filter immediately to free up memory
    $suspicious = $dailyLogs | Where-Object {
        $localTime = $_.CreatedDateTime.ToLocalTime()
        $isWeekend = ($localTime.DayOfWeek -eq 'Saturday' -or $localTime.DayOfWeek -eq 'Sunday')
        $isOutsideHours = ($localTime.Hour -lt $officeHoursStart -or $localTime.Hour -ge $officeHoursEnd)
        $isWeekend -or $isOutsideHours
    }

    if ($suspicious) {
        $allSuspiciousLogs.AddRange($suspicious)
    }
}

Write-Progress -Activity "Fetching Logs" -Completed

# Display results
$allSuspiciousLogs | Select-Object CreatedDateTime, UserPrincipalName, AppDisplayName, IpAddress, ClientAppUsed | Out-GridView