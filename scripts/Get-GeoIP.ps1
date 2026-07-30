<#
.SYNOPSIS
    Displays Geographic Info for a given IP Address.
.DESCRIPTION
    Uses the HackerTarget API to display geo info about an IP address.
.PARAMETER IPv4 Address
	Mandatory parameter.
.EXAMPLE
	Get-GeoIP 8.8.8.8
		(Returns the Geolocation info for the above IP)
.NOTES
    Version: 1.0
#>

param(
	[Parameter(Mandatory=$true)]
    [string]$ip
)

Write-Host " "
curl https://api.hackertarget.com/geoip/?q=$ip -UseBasicParsing | Select-Object -Expand Content | FT
Write-Host " "