# --- CONFIGURATION ---
$ApiKey = $Config.KnowBe4.ReportingAPI
$Region = $Config.KnowBe4.Region 
$PhishCampaignID = $Config.KnowBe4.PhishCampaign
$TrainCampaignID = $Config.KnowBe4.TrainCampaign
# ---------------------

# Determine Base URL based on region
Switch ($Region) {
    "US" { $BaseURL = "https://us.api.knowbe4.com/v1" }
    "EU" { $BaseURL = "https://eu.api.knowbe4.com/v1" }
    "CA" { $BaseURL = "https://ca.api.knowbe4.com/v1" }
    "UK" { $BaseURL = "https://uk.api.knowbe4.com/v1" }
    "DE" { $BaseURL = "https://de.api.knowbe4.com/v1" }
    Default { Write-Error "Invalid Region. Please set `$Region` to 'US', 'EU', 'CA', 'UK', or 'DE'."; exit }
}

# Construct the headers
$Headers = @{
    "Authorization" = "Bearer $ApiKey"
    "Accept"        = "application/json"
}

# --- FUNCTIONS ---
function Get-KB4Endpoint { 
    param (
        [string]$Uri
    )
    Try {
        return Invoke-RestMethod -Uri $Uri -Headers $Headers -Method Get -ErrorAction Stop
    }
    catch {
        Write-Warning "Failed to fetch data from $Uri. Error: $($_.Exception.Message)"
        return $null
    }
}

function Get-AccountInfo {
    $AccountUri = "$BaseURL/account"
    return Get-KB4Endpoint -Uri $AccountUri
}

function Get-TrainingInfo {
    $TrainingUri = "$BaseURL/training/campaigns/$TrainCampaignID"
    return Get-KB4Endpoint -Uri $TrainingUri
}

function Get-PhishingInfo {
    $PhishingUri = "$BaseURL/phishing/campaigns/$PhishCampaignID"
    return Get-KB4Endpoint -Uri $PhishingUri
}

# --- EXECUTION ---
$AccountData  = Get-AccountInfo
$TrainingData = Get-TrainingInfo
$PhishingData = Get-PhishingInfo

# --- OBJECT CREATION ---
$KB4Object = [PSCustomObject]@{
    Timestamp = (Get-Date)
    Account   = [PSCustomObject]@{
        Organization = $AccountData.organization_name
        RiskScore    = $AccountData.current_risk_score
        UserCount    = $AccountData.number_of_users
        SeatCount    = $AccountData.number_of_seats
        Type         = $AccountData.subscription_level
    }
    Training  = [PSCustomObject]@{
        Name       = $TrainingData.name
        Ends       = $TrainingData.end_date
        Completion = $TrainingData.completion_percentage
    }
    Phishing  = [PSCustomObject]@{
        Name       = $PhishingData.name
        Status     = $PhishingData.status
        PhishProne = $PhishingData.last_phish_prone_percentage
    }
}

# Return the final object
$KB4Object.PSObject.Properties | ForEach-Object {
	Write-Host "`n$($_.Name):"
	
	$_.Value.PSObject.Properties | Foreach-Object {
		Write-Host "    $($_.Name): $($_.Value)"
	}
}
