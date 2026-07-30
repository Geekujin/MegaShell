# =====================================================
# Configuration
# =====================================================
$TenantId = $Config.DVSA.TenantID
$ClientId = $Config.DVSA.ClientID
$ClientSecret = $Config.DVSA.ClientSecret

$TokenUrl = "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token"

$TokenBody = @{
    grant_type    = "client_credentials"
    client_id     = $ClientId
    client_secret = $ClientSecret
    scope         = "https://tapi.dvsa.gov.uk/.default"
}

$TokenResponse = Invoke-RestMethod `
    -Uri $TokenUrl `
    -Method Post `
    -ContentType "application/x-www-form-urlencoded" `
    -Body $TokenBody

$AccessToken = $TokenResponse.access_token
$APIKey = $Config.MOT.APIKey

# =====================================================
# Headers
# =====================================================
$Headers = @{
    Authorization = "Bearer $AccessToken"
    "X-API-Key"   = $ApiKey
}

# =====================================================
# Prompt User
# =====================================================
$Registration = Read-Host "Enter Registration Number"
$Registration = $Registration.ToUpper()

# =====================================================
# Call MOT API
# =====================================================

$Uri = "https://history.mot.api.gov.uk/v1/trade/vehicles/registration/$Registration"

try {

    Write-Host ""
    Write-Host "Looking up vehicle $Registration..." -ForegroundColor Cyan
    Write-Host ""

    $Vehicle = Invoke-RestMethod `
        -Uri $Uri `
        -Method Get `
        -Headers $Headers

    # =================================================
    # Vehicle Information
    # =================================================

    Write-Host "====================================================" -ForegroundColor Green
    Write-Host "Vehicle Details" -ForegroundColor Green
    Write-Host "====================================================" -ForegroundColor Green
	Write-Host "      "
	Write-Host $Vehicle.registration -BackgroundColour White -ForegroundColor Green

    Write-Host ("Registration      : {0}" -f $Vehicle.registration)
    Write-Host ("Make              : {0}" -f $Vehicle.make)
    Write-Host ("Model             : {0}" -f $Vehicle.model)
    Write-Host ("Fuel Type         : {0}" -f $Vehicle.fuelType)
    Write-Host ("Engine Size       : {0}cc" -f $Vehicle.engineSize)
    Write-Host ("Manufacture Date  : {0}" -f $Vehicle.manufactureDate)
    Write-Host ("Primary Colour    : {0}" -f $Vehicle.primaryColour)

    if ($Vehicle.PSObject.Properties.Name -contains "secondaryColour") {
        Write-Host ("Secondary Colour  : {0}" -f $Vehicle.secondaryColour)
    }

    Write-Host ""

    # =================================================
    # Latest Two MOTs
    # =================================================

    $RecentTests = $Vehicle.motTests | Select-Object -First 2

    $Counter = 1

    foreach ($Test in $RecentTests) {

        Write-Host "====================================================" -ForegroundColor Yellow
        Write-Host "MOT Test #$Counter" -ForegroundColor Yellow
        Write-Host "====================================================" -ForegroundColor Yellow

        Write-Host ("Completed Date    : {0}" -f $Test.completedDate)
        Write-Host ("Test Result       : {0}" -f $Test.testResult)
        Write-Host ("Expiry Date       : {0}" -f $Test.expiryDate)
        Write-Host ("Odometer          : {0} {1}" -f $Test.odometerValue, $Test.odometerUnit)

        Write-Host ""

        if ($Test.defects.Count -gt 0) {

            Write-Host "Defects / Advisories:" -ForegroundColor Red

            foreach ($Defect in $Test.defects) {

                Write-Host ""
                Write-Host ("Dangerous : {0}" -f $Defect.dangerous)
                Write-Host ("Type      : {0}" -f $Defect.type)
                Write-Host ("Text      : {0}" -f $Defect.text)
            }
        }
        else {

            Write-Host "No defects recorded." -ForegroundColor Green
        }

        Write-Host ""
        $Counter++
    }

}
catch {

    Write-Host ""
    Write-Host "Error retrieving MOT data" -ForegroundColor Red
    Write-Host $_.Exception.Message

}