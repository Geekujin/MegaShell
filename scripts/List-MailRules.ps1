<#
.SYNOPSIS
    Connects to Exchange Online and lists a user's enabled inbox rules.
.DESCRIPTION
    Connects to Microsoft Exchange Online and checks a specified users mailbox
	for enabled rules, displaying them in the console.
.PARAMETER email address
    Optional parameter. Launches the search directly on the specified mailbox
	Omitting the parameter opens the script in interactive mode.
.EXAMPLE
    PS> Get-MailRules bill.gates@microsoft.com
        Checking for mailbox 'bill.gates@microsoft.com'
.NOTES
    Author: Geekujin
    Version: 2.0
	Created: 2025-07-03
#>

# FUNCTION TO CREATE OPTIONS MENU
function Show-MainMenu {
	param (
		[string]$menuTitle = "Main Menu"
	)
	do
	{
		Clear-Host
		$scriptTitle = "Marc's inbox rule checker" 
		Write-Host ""
		Write-Host " "$scriptTitle
		Write-Host " "("=" * $scriptTitle.Length)
		Write-Host "`n"
		Write-Host $menuTitle
		Write-Host ("-" * $menuTitle.Length)
		Write-Host "[" -NoNewLine; Write-Host "1" -ForegroundColor Green -NoNewLine; Write-Host "] Select mailbox"
		Write-Host "[" -NoNewLine; Write-Host "2" -ForegroundColor Yellow -NoNewLine; Write-Host "] Quit without disconnecting"
		Write-Host "[" -NoNewLine; Write-Host "3" -ForegroundColor Red -NoNewLine; Write-Host "] Disconnect from Exchange and exit"
		Write-Host ""		
				
		$menuOption = Read-Host "Please select an option"
		switch($menuOption)
		{
			"1" {
				Write-Host " "
				$emailInput = Read-Host "Enter the email address to check"
				Write-Host " "
				Get-Rules -TargetMailbox $emailInput
			} "2" {
				Write-Host " "
				Write-Host "Exiting..."
				Write-Host " "
				Exit
			} "3" {
				Write-Host " "
				Write-Host "Disconnecting from Exchange Online...`n"
				Disconnect-ExchangeOnline -Confirm:$false
				return
			}
			default {
				Write-Host " "
				Write-Host "Invalid selection. Please try again."
				Start-Sleep -Seconds 2
			}
		}
	}
	 until (($menuOption -eq "2") -or ($menuOption -eq "3"))

}

function Get-Rules {
	param(
	[string]$TargetMailbox
	)
	
	if (-not (Test-ValidEmail $TargetMailbox)) {
		Write-Warning "Invalid email address provided: '$($TargetMailbox)'"
		Write-Host " "
		Pause
		return
	}
	
	try {
		Write-Host "Checking for mailbox '$($TargetMailbox)'.`n"
		Start-Sleep -Seconds 1
		$allRules = Get-InboxRule -IncludeHidden -Mailbox $TargetMailbox -ErrorAction Stop 
	}
	catch {
		Write-Warning "Could not find mailbox '$($TargetMailbox)'. Please check the address and try again.`n"
		Pause
		return
	}
	
	$enabledRules = $allRules | Where-Object { $_.Enabled -eq $true }
	
	if (-not $enabledRules) {
		Write-Host "Mailbox '$($TargetMailbox)' found but no enabled rules.`n"
		Pause
		return
	}
	Clear-Host
	Write-Host "`nFound enabled inbox rules in '$($TargetMailbox)':`n "

	
	$selectedRules = $enabledRules | Select Name, Enabled, Priority, Description
	$selectedRules  | Format-Table -AutoSize
		
	$exportChoice = "N"
	Write-Host "Export results to .csv file? [Y] Yes " -ForegroundColor White -NoNewLine
	Write-Host "[N] No " -ForegroundColor Yellow -NoNewLine
	Write-Host '(default is "N"):' -ForegroundColor White -NoNewLine
	$exportChoice = Read-Host
	
	
	if ($exportChoice -match '^[Yy]$') {
		$fileName = "EnabledInboxRules-" + $($TargetMailbox.Replace('@','_')) + ".csv"
		$exportDefaultPath = (Get-Location).Path
		Write-Host " "
		Write-Host "Default export path: $exportDefaultPath"
		Write-Host "File name: $fileName"
		Write-Host " "
		$exportPath = Read-Host "Enter file path for the CSV export or press enter to use default"
		
		if ([string]::IsNullOrWhiteSpace($exportPath)) {
			$exportPath = $exportDefaultPath
		}
		
		if (-not (Test-Path $exportPath)) {
			Write-Host " "
			Write-Host "Invalid path: '$exportPath'"
			$exportPath = Read-Host "Please enter a valid path"
			if (-not (Test-Path $exportPath)) {
				Write-Host " "
				Write-Host "Path Still invalid. Falling back to default."
				Start-Sleep -Seconds 1
				Write-Host " "
				$exportPath = $exportDefaultPath
			}
		}
		
		$fullPath = Join-Path -Path $exportPath -ChildPath $fileName
		
		try {
			$selectedRules | Export-CSV -Path $fullPath -NoTypeInformation
			Write-Host "Export successful:`n`n  $fullPath"
			Start-Sleep -Seconds 1
			
		}
		catch {
			$selectedRules | Export-CSV -Path $fullPath -NoTypeInformation
			Write-Error "Export failed. The error was: $($_.Exception.Message)"
		}
		
		Write-Host " "
		Write-Host "Returning to Main Menu..."
				Start-Sleep -Seconds 2
		
	}
}

function Test-ValidEmail {
	param ([string]$emailToValidate)
	return $emailToValidate -match '^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$'
}

# INITIALISE MAILBOX VARIABLE AS NULL
$mailbox = ""
	
# CONNECT TO EXCHANGE ONLINE AND PROMPT FOR CREDENTIALS IF REQUIRED
try {
	Get-AcceptedDomain -ErrorAction Stop > $null
}
catch {
	try {
		Write-Host "`nAttempting to authenticate with Exchange...`n"
		Connect-ExchangeOnline -UserPrincipalName $AdminUPN -ShowBanner:$false -ErrorAction Stop > $null
	}
	catch {
		Write-Host " "
		Write-Warning "No Admin credentials found."
		Write-Host " "
		$AdminUPN = Read-Host "Enter your admin User Principal Name (UPN)"
		Connect-ExchangeOnline -ShowBanner:$false -UserPrincipalName $AdminUPN
	}
}
#Connect-ExchangeOnline -UserPrincipalName $AdminUPN

# PROMPT FOR THE MAILBOX TO INSPECT
if ($args.Count -ge 1 -and $args[0]) {
	$mailboxArgument = $args[0]
	if (Test-ValidEmail $mailboxArgument) {
		Get-Rules -TargetMailbox $mailboxArgument
		Show-MainMenu
	} else {
		Write-Host " "
		Write-Host "Invalid email format '$mailboxArgument'. Launching menu..."
		Start-Sleep -Seconds 2
		Show-MainMenu
	}
} else {
	Show-MainMenu
}
