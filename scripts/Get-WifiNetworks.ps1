<#
.SYNOPSIS
    Retrieves all Wifi network names and passwords from the computer
.DESCRIPTION
    Searches for and retrieves all SSID and associated passwords, storing them
	in a hashtable and displaying them in the console.
.NOTES
    Author: Geekujin
    Version: 1.0
	Created: 2025-11-25
#>

$NetworkNames = (netsh wlan show profiles) | Select-String "\:(.+)$" | ForEach-Object {
    $_.Matches.Groups[1].Value.Trim()
}

$Network = @()
$wifi = @{}
foreach ($name in $NetworkNames) {
    # Run the second command and extract the password for the current $name
    $pass = (netsh wlan show profile name="$name" key=clear) | 
            Select-String "Key Content\W+\:(.+)$" | 
            ForEach-Object {
                $_.Matches.Groups[1].Value.Trim()
            }
    
    # Check if a password was found before adding the object
    if ($pass) {
        $wifi.Add($name, $pass)
	} else {
		$pass = "n/a"
		$wifi.Add($name, $pass)
    }
}

Write-Host "`nWiFi network " -Foregroundcolor gray -nonewline
Write-Host "names " -Foregroundcolor white -nonewline
Write-Host "and " -Foregroundcolor gray -nonewline
Write-Host "passwords`n" -foregroundcolor Green
foreach ($Name in $NetworkNames) {
		Write-Host $Name -nonewline -foregroundcolor White
        Write-Host ": " -nonewline -foregroundcolor White
        Write-Host $Wifi["$Name"] -foregroundcolor Green
    }