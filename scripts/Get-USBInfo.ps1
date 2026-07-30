if (-not (Get-Command Get-PnpDevice -ErrorAction SilentlyContinue)) {
    throw 'Get-PnpDevice is unavailable. Run this script on Windows with the PnpDevice module installed.'
}

$Devices = Get-PnpDevice -PresentOnly -ErrorAction Stop |
    Where-Object {
        $_.InstanceId -match '(?i)^USB\\VID_[0-9A-F]{4}&PID_[0-9A-F]{4}'
    }

$Results = foreach ($Device in $Devices) {

    # HardwareID is an array. Join its entries into one searchable string.
    $HardwareIDText = $Device.HardwareID -join ' '

    $VendorID = $null
    $ProductID = $null
    $Revision = $null
    $Interface = $null

    if ($HardwareIDText -match '(?i)VID_([0-9A-F]{4})') {
        $VendorID = $Matches[1].ToUpperInvariant()
    }

    if ($HardwareIDText -match '(?i)PID_([0-9A-F]{4})') {
        $ProductID = $Matches[1].ToUpperInvariant()
    }

    if ($HardwareIDText -match '(?i)REV_([0-9A-F]{4})') {
        $Revision = $Matches[1].ToUpperInvariant()
    }

    if ($HardwareIDText -match '(?i)MI_([0-9A-F]{2})') {
        $Interface = $Matches[1].ToUpperInvariant()
    }

    [PSCustomObject]@{
        Class        = $Device.Class
        FriendlyName = $Device.FriendlyName
        VID          = $VendorID
        PID          = $ProductID
        Revision     = $Revision
        Interface    = $Interface
        HardwareID   = $Device.HardwareID -join '; '
        InstanceID   = $Device.InstanceId
        Status       = $Device.Status
    }
}

$Results |
    Sort-Object VID, PID, Interface, FriendlyName |
    Format-Table Class, FriendlyName, VID, PID -AutoSize