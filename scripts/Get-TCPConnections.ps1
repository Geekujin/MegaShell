<#
.SYNOPSIS
    Lists local listening TCP connections by port and process name
.DESCRIPTION
    Lists all local TCP connections filtered by listening status, then looks up
	the process name based on the PID and displays it in a table.
.NOTES
    Author: Geekujin
    Version: 1.0
	Created: 2025-11-03
#>

$connections = Get-NetTCPConnection | Where-Object { $_.State -eq 'Listen' }

$results = foreach ($conn in $connections) {
    $proc = Get-Process -Id $conn.OwningProcess -ErrorAction SilentlyContinue
    [PSCustomObject]@{
        Port         = $conn.LocalPort
        ProcessName  = if ($proc) { $proc.ProcessName } else { "Unknown (PID: $($conn.OwningProcess))" }
    }
}

$results | Sort-Object Port | Format-Table -AutoSize