# --- CONFIGURATION ---
$ApiKey = $Config.KnowBe4.ReportingAPI

$Region = $Config.KnowBe4.Region
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

function Get-PhishingInfo {
	Try {
		# Make the API Call
		$PhishResponse = Invoke-RestMethod -Uri $BaseUrl/phishing/security_tests -Headers $Headers -Method Get -ErrorAction Stop
		
		If ($null -ne $PhishResponse) {
			$MostRecentPhish = $PhishResponse | 
                Select-Object *, @{N='SortDate'; E={ [datetime]$_.started_at }} | 
                Sort-Object SortDate -Descending | 
                Select-Object -First 1
			
			return $MostRecentPhish | Select-Object campaign_id, name, status, started_at, delivered_count, clicked_count, replied_count, data_entered_count, reported_count
		}
		Else {
			Write-Warning "Risk score not found in the response. Showing full response properties:"
			return $Null
		}
	}
	Catch {
		Write-Error "Failed to retrieve data. Error details:"
		Write-Error $_.Exception.Message
		
		# Check if it is a 401 Unauthorized (usually wrong API Key)
		If ($_.Exception.Response.StatusCode.value__ -eq 401) {
			Write-Host "Tip: Double-check that your API Token is correct and the Reporting API is enabled in Account Settings." -ForegroundColor Yellow
		}
	}
}


function Get-TrainingInfo {
	# Get training data
	Try {
		# Make the API Call
		$TrainResponse = Invoke-RestMethod -Uri $BaseUrl/training/campaigns -Headers $Headers -Method Get -ErrorAction Stop
		
		If ($null -ne $TrainResponse) {
			$MostRecentTrain = $TrainResponse | 
                Select-Object *, @{N='SortDate'; E={ [datetime]$_.start_date }} | 
                Sort-Object SortDate -Descending | 
                Select-Object -First 1
			
			return $MostRecentTrain | Select-Object campaign_id, name, status, start_date, end_date
		}
		Else {
			Write-Warning "Risk score not found in the response. Showing full response properties:"
			return $Null
		}
	}
	Catch {
		Write-Error "Failed to retrieve data. Error details:"
		Write-Error $_.Exception.Message
		
		# Check if it is a 401 Unauthorized (usually wrong API Key)
		If ($_.Exception.Response.StatusCode.value__ -eq 401) {
			Write-Host "Tip: Double-check that your API Token is correct and the Reporting API is enabled in Account Settings." -ForegroundColor Yellow
		}
	}
}

$LastPhish = Get-PhishingInfo
$LastTrain = Get-TrainingInfo
Write-Host "`n--- MOST RECENT PHISHING CAMPAIGN ---" -ForegroundColor Green
$LastPhish | Format-List
Write-Host "--- MOST RECENT TRAINING CAMPAIGN ---" -ForegroundColor Green
$LastTrain | Format-List
$LastPhish.name