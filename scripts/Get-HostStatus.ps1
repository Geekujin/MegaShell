<#
.SYNOPSIS
    Pings machines every 10s and displays their online status.
.DESCRIPTION
    Iterates through a list of machine names or IP addresses and pings them.
	Edit the $Servers variable to point to a txt file containing the machines,
	or use an array instead.
	Status is shown as online or offline in a table.
.NOTES
    Author: Geekujin
    Version: 1.0
	Created: 2020-08-08
#>

# Enter the filepath to the file containing the hostnames. Each host should be on a separate line.
[Array] $Hosts = Get-Content -Path "C:\PATH\TO\hostnames.txt"

#Tests the connection to see if response received. If not, reports as offline, else shows as online
$i = 1
Write-Host " "
While ($i -lt 9999) {
Write-Host "Test $i" -noNewLine -BackgroundColor Black -ForegroundColor Yellow
Write-Host ": " (Get-Date -Format "dd-MM-yy HH:mm:ss") -BackgroundColor Black -ForegroundColor Yellow
Foreach($h in $Hosts)
{
if(!(Test-Connection -Cn $h -Buffersize 16 -Count 1 -ea 0 -quiet))

	{
	Write-Host "OFFLINE" -BackgroundColor Red -nonewline
	Write-Host " $h"
	}
ELSE 	
	{
	Write-Host "ONLINE " -Backgroundcolor DarkGreen -nonewline
	Write-Host " $h"
	}
} # end foreach
Write-Host " " 
$i++
Start-Sleep -Second 10
}