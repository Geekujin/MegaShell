<#
.SYNOPSIS
    Retrieves all new Entra accounts from past X days.
.DESCRIPTION
    Connects to Microsoft Entra and checks for account creation date
	within the number of days specified.
.PARAMETER <number of days>
	The number of previous days to search.
	Omitting the parameter opens the script in interactive mode.
.NOTES
    Author: Geekujin
    Version: 1.0
	Created: 2024-10-04
#>

param(
    [string]$daysBack
)

$scriptTitle = "New Entra accounts checker" 

Write-Host " "
Write-Host ""
Write-Host " "$scriptTitle
Write-Host " "("=" * $scriptTitle.Length)
Write-Host " "
if ([string]::IsNullOrEmpty($daysBack)) {
	$daysBack = Read-Host "Enter number of days to go back:"
	Write-Host " "
}

if ([string]::IsNullOrEmpty($daysBack)) {
    Write-Host "ERROR: Number of days to check is required and was not provided." -ForegroundColor Red
    return
}

$startDate = (Get-Date).AddDays(-$daysBack).ToString("yyyy-MM-ddTHH:mm:ssZ")

$users = Get-MgUser -Filter "createdDateTime ge $startDate" -All -Property DisplayName, JobTitle, AccountEnabled, UserType

# SET COLUMN WIDTHS
$displayNameWidth = 35
$jobTitleWidth = 30
$enabledWidth = 7
$typeWidth = 8

Write-Host ""
Write-Host "Retrieving Entra accounts created in past $daysBack days."
Write-Host ""
$header = "{0,-$displayNameWidth} {1,-$jobTitleWidth} {2,-$enabledWidth} {3,-$typeWidth}" -f "Name", "Job Title", "Enabled", "Type"
Write-Host $header -ForegroundColor White

$separator = "{0,-$displayNameWidth} {1,-$jobTitleWidth} {2,-$enabledWidth} {3,-$typeWidth}" -f ('='*$displayNameWidth), ('='*$jobTitleWidth), ('='*$enabledWidth), ('='*$typeWidth)
Write-Host $separator -ForegroundColor Yellow

$users | ForEach-Object {
    $foreColor = "White"
	$backColor = $Host.UI.RawUI.BackgroundColor
	
    if ($_.UserType -eq 'Guest') {
        $foreColor = "White"
		$backColor = "DarkRed"
    }

	if ($_.AccountEnabled -eq $false) {
		$foreColor = "White"
		$backColor = "DarkGray"
	}

	# TRUNCATE TEXT IF BIGGER THAN COLUMN WIDTH
    $displayName = $_.DisplayName
    if ($displayName.Length -gt $displayNameWidth) {
        $displayName = $displayName.Substring(0, $displayNameWidth - 3) + "..."
    }


    $jobTitle = $_.JobTitle
    if ($jobTitle -and $jobTitle.Length -gt $jobTitleWidth) {
        $jobTitle = $jobTitle.Substring(0, $jobTitleWidth - 3) + "..."
    }

	
    $output = "{0,-$displayNameWidth} {1,-$jobTitleWidth} {2,-$enabledWidth} {3,-$typeWidth}" -f $displayName, $jobTitle, $_.AccountEnabled, $_.UserType
    
    Write-Host $output -ForegroundColor $foreColor -BackgroundColor $backColor
}
Write-Host ""
Write-Host "Key:`n"
Write-Host "  " -BackgroundColor DarkGray -NoNewLine
Write-Host ": Disabled accounts." -NoNewLine
Write-Host " " -NoNewLine
Write-Host "  " -BackgroundColor DarkRed -NoNewLine
Write-Host ": Guest accounts."
Write-Host "`n"