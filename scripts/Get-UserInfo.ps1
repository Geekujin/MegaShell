<#
.SYNOPSIS
    Connects to Microsoft Graph and lists details about a user.
.DESCRIPTION
    Outputs the name, UPN, Job Title, Manager, Account Creation and Last Password
	change dates for a specified user.
.PARAMETER User Principal Name
	UPN should be user.name@domain.tld
	Omitting the parameter opens the script in interactive mode.
.EXAMPLE
	PS> Get-UserInfo joe.bloggs@contoso.com
.NOTES
    Author: Geekujin
    Version: 1.0
	Created: 2025-11-05
#>

param(
    [string]$UserID
)

# Prompt for the User ID (UPN) if not provided as parameter
if ([string]::IsNullOrEmpty($UserID)) {
	$UserID = Read-Host -Prompt "Enter the User Principal Name (UPN) (e.g., user@domain.com)"
}

# If $UserID is still null, display error and exit the script
if ([string]::IsNullOrEmpty($UserID)) {
    Write-Host "ERROR: User ID is required and was not provided." -ForegroundColor Red
    return
}

# Connect to Microsoft Graph, with error handling
# User.Read.All is required to fetch user details
Write-Host "Connecting to Microsoft Graph..."
Write-Host
try {
	Connect-MgGraph -Scopes "User.Read.All" -NoWelcome -ErrorAction Stop
	Write-Host "Connection successful." -ForegroundColor Green
}
catch {
	Write-Host "ERROR: Failed to connect to Microsoft Graph or consent was denied." -ForegroundColor Red
	Write-Host "Ensure the Microsoft.Graph module is installed and you have the necessary permissions." -ForegroundColor Red
	return
}

# Get user details, with error handling
Write-Host " "
Write-Host "Fetching details for: $UserID..."
$user = $null
try {
	$User = Get-MgUser -UserId $UserID -Property DisplayName, JobTitle, Manager, CreatedDateTime, LastPasswordChangeDateTime, UserPrincipalName, Mail, Department, AccountEnabled, UserType -ExpandProperty Manager -ErrorAction stop 2>$null
}
catch {
	Write-Host " "
	Write-Host "ERROR: User with UPN '$UserID' was not found in Microsoft 365." -ForegroundColor Red
    return # Exit the script
}

# Get the Manager's Display Name, or display "N/A" if not set
$ManagerName = "N/A"

# Check if the Manager property exists, and fetch the manager's name from the nested AdditionalProperties dictionary
if ($User.Manager -ne $null -and $User.Manager.AdditionalProperties.ContainsKey('displayName')) {
    $ManagerName = $User.Manager.AdditionalProperties.displayName
}

# Create the object to contain the requested information
$OutputObject = [PSCustomObject]@{
    Name                   = $User.DisplayName
    JobTitle               = $User.JobTitle
	Department			   = $User.Department
    Manager                = $ManagerName
    Email                  = $User.UserPrincipalName
    Created				   = $User.CreatedDateTime
	UserType              = $User.UserType
	Enabled				   = $User.AccountEnabled
    LastPasswordChangeDate = $User.LastPasswordChangeDateTime
}

# Display the result and disconnect from Microsoft Graph
$OutputObject | Format-List