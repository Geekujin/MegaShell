<#
.SYNOPSIS
    Displays information for a given IP Address.
.DESCRIPTION
    Uses the IPInfo API to display information about an IP address, including
	geolocation, hostname and ISP.
.PARAMETER IPv4 Address
	Mandatory parameter.
.NOTES
    Author: Geekujin
    Version: 1.0
	Created: 2023-03-23
#>

param(
	[Parameter(Mandatory=$true)]
    [string]$ip
)

Write-Host " "
Invoke-RestMethod https://ipinfo.io/$ip
Write-Host " "
#  