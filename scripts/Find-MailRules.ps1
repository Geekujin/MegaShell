<#
.SYNOPSIS
    Searches mailbox rule names and descriptions for a keyword.
.DESCRIPTION
    The script prompts for a search term and connects to Exchange Online, 
    iterating through all active user mailboxes. It returns a list of mailboxes 
    and the rules that contain the search term in their Name or Description.

.VERSION
    1.1
#>

function Connect-O365Exchange {
    param(
        [string]$AdminUPN
    )
    
	$AdminUPN = $Config.Users.EntraAdmin
    # Check if a session is already established
    try {
        # Check if any Exchange Online cmdlet works (e.g., Get-AcceptedDomain)
        Get-AcceptedDomain -ErrorAction Stop | Out-Null
        Write-Host "Exchange Online session is already active." -ForegroundColor Green
        return $true
    }
    catch {
        # Attempt connection if no active session
        Write-Host "`nAttempting to connect to Exchange Online..." -ForegroundColor Yellow
        try {
            if ([string]::IsNullOrWhiteSpace($AdminUPN)) {
                $AdminUPN = Read-Host "Enter your admin User Principal Name (UPN)"
            }
            Connect-ExchangeOnline -DisableWAM -UserPrincipalName $AdminUPN -ShowProgress $false -ErrorAction Stop | Out-Null
            Write-Host "Successfully connected to Exchange Online." -ForegroundColor Green
            return $true
        }
        catch {
            Write-Error "Failed to connect to Exchange Online.`n"
            Write-Error $_.Exception.Message
            return $false
        }
    }
}

function Search-AllMailboxRules {
    $SearchWord = Read-Host "Enter the word you want to search for in rule names/descriptions"
    
    if ([string]::IsNullOrWhiteSpace($SearchWord)) {
        Write-Warning "No search word entered. Exiting script."
        return
    }
    
    $SearchWord = $SearchWord.Trim()
    Write-Host "`nSearching for rules containing: '$SearchWord'`n" -ForegroundColor Cyan
    
    # Get all active user mailboxes
    Write-Host "Fetching list of all active user mailboxes..." -ForegroundColor Yellow
    try {
        $Mailboxes = Get-Mailbox -RecipientTypeDetails UserMailbox -ResultSize Unlimited | 
                     Where-Object { $_.IsSoftDeleted -ne $true -and $_.IsInactiveMailbox -ne $true } | 
                     Select-Object PrimarySmtpAddress -ErrorAction Stop
    }
    catch {
        Write-Error "Failed to retrieve mailbox list. Check connection and permissions."
        Write-Error $_.Exception.Message
        return
    }

    Write-Host "Found $($Mailboxes.Count) active mailboxes to check." -ForegroundColor Green
    
    # Loop through all mailboxes and search rules adding output into $Results
    $ProgressCounter = 0
    $Results = foreach ($Mailbox in $Mailboxes) {
        $MailboxAddress = $Mailbox.PrimarySmtpAddress
        $ProgressCounter++
        
        Write-Progress -Activity "Searching Inbox Rules" -Status "Checking $($MailboxAddress)" -PercentComplete (($ProgressCounter / $Mailboxes.Count) * 100)

        # Fetch rules for the current mailbox
        try {
            $Rules = Get-InboxRule -Mailbox $MailboxAddress -ErrorAction SilentlyContinue –WarningAction SilentlyContinue
        }
        catch {
            Write-Verbose "Could not retrieve rules for $($MailboxAddress): $($_.Exception.Message)"
            continue
        }
        
        if ($Rules) {
            # Filter the rules for the search word (case-insensitive -like match)
            $FilteredRules = $Rules | Where-Object {
                $_.Name -like "*$SearchWord*" -or
                $_.Description -like "*$SearchWord*"
            }
            
            if ($FilteredRules) {
                $FilteredRules | ForEach-Object {
                    [PSCustomObject]@{
                        Mailbox         = $MailboxAddress
                        RuleName        = $_.Name
                        RuleDescription = $_.Description
                        Enabled         = $_.Enabled
                    }
                }
            }
        }
    }
    
    Write-Host "`nSearch complete.`n" -ForegroundColor Yellow
    
    if ($Results.Count -gt 0) {
        $UniqueMailboxCount = ($Results | Select-Object -Unique Mailbox).Count
        Write-Host "---"
        Write-Host "✅ Found $($Results.Count) rules containing '$SearchWord' across $($UniqueMailboxCount) mailboxes:" -ForegroundColor Green
        Write-Host "---"
        $Results | Format-Table -AutoSize
    } else {
        Write-Host "❌ No rules found containing '$SearchWord' in any active user mailbox." -ForegroundColor Red
    }
}

# --- SCRIPT EXECUTION START ---
if (Connect-O365Exchange) {
    Search-AllMailboxRules
}
Write-Host "`nDisconnecting from Exchange Online...`n" -ForegroundColor Yellow # <-- Final closing quote fixed
Disconnect-ExchangeOnline -Confirm:$false
# --- SCRIPT EXECUTION END ---