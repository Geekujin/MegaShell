<#
.SYNOPSIS
    Lists all scripts within the specified directory.
.DESCRIPTION
    Searches for PowerShell scripts in a specified folder and outputs the names 
	alongside the information from the synopsis.
.NOTES
    Author: Geekujin
    Version: 1.5
	Created: 2025-11-05
	Updated: 2025-11-25
#>

# Variables

# Define the script path. Defaults to current directory
$ScriptsPath = $PSScriptRoot 

# Get all .ps1 files in tdirectory
$Scripts = Get-ChildItem -Path $ScriptsPath -Filter "*.ps1" -ErrorAction SilentlyContinue

# Default max length of script name
$MaxNameLength = 12

$ScriptNameColor = "Yellow"
$SynopsisColor   = "DarkGreen"
$SeparatorColor = "DarkGray"


function Get-ScriptSynopsis {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Path
    )

    $Synopsis = "" # Initialize $Synopsis as an empty string (not $null)
    $ReadingSynopsis = $false
    
    # Check if the file exists before reading
    if (-not (Test-Path -Path $Path)) {
        return "" # Return empty string if path is invalid
    }

    try {
        $Content = Get-Content -Path $Path -TotalCount 30 -ErrorAction Stop
        
        foreach ($Line in $Content) {
            if ($Line -match '^\s*\.SYNOPSIS\s*$') {
                $ReadingSynopsis = $true
                continue 
            }
            
            if ($Line -match '^\s*\.(DESCRIPTION|EXAMPLE|PARAMETER|NOTES|LINK)\s*$') {
                break 
            }
            
            if ($ReadingSynopsis -and -not [string]::IsNullOrWhiteSpace($Line)) {
                $CleanLine = $Line.Trim() -replace '^#\s*|^\s*|^\s*<#\s*'
                $CleanLine = $CleanLine -replace '\s*#>$'
                
                if (-not [string]::IsNullOrWhiteSpace($CleanLine)) {
                    $Synopsis += $CleanLine.Trim() + " "
                }
            }
            
            if ($Line -match '^\s*#>\s*$') {
                 break
            }
        }
    }
    catch {
        # Catch errors like file access denied
        return "" 
    }
    
    # Ensure a clean, trimmed string is always returned
    return $Synopsis.Trim()
}

function Write-ColoredText {
    param(
        [string]$Text, 
        [string]$Color = "White"
    )
    # Use Write-Host only if the text is not null, otherwise do nothing
    if ($Text -ne $null) {
        Write-Host -Object $Text -ForegroundColor $Color -NoNewline
    }
}

# Main script
if (-not $Scripts) {
    Write-Host "ERROR: No PowerShell scripts found in '$ScriptsPath'." -ForegroundColor Red
    exit
}

# Process each script to extract the name and synopsis
$OutputData = $Scripts | ForEach-Object {
    $SynopsisText = Get-ScriptSynopsis -Path $_.FullName
    [PSCustomObject]@{
        ScriptName = $_.BaseName
        Synopsis   = $SynopsisText
    }
}

if ($OutputData) {
    # Find the maximum length among all script names and synopsis
    $MaxNameLength = ($OutputData.ScriptName | Measure-Object -Maximum -Property Length).Maximum
	$MaxSynopsisLength = ($OutputData.Synopsis | Measure-Object -Maximum -Property Length).Maximum
    
    # Ensure the padding accommodates the header text "Script Name"
    if ($MaxNameLength -lt "Script Name".Length) {
        $MaxNameLength = "Script Name".Length
    }
    # Add a buffer space (e.g., 3 characters) for visual separation
    $MaxNameLength += 3 
}


$HeaderPadding = $MaxNameLength - "Script Name".Length
$HeaderPaddingString = " " * $HeaderPadding


Write-Host "`nListing all PowerShell scripts in $ScriptsPath`n"
Write-ColoredText -Text "Script Name" -Color White
Write-ColoredText -Text "$HeaderPaddingString| " -Color $SeparatorColor
Write-ColoredText -Text "Synopsis" -Color White
Write-Host ""

# Calculate the TOTAL line length:
$TotalLineLength = $MaxNameLength + 2 + $MaxSynopsisLength 
Write-ColoredText -Text ("-" * $TotalLineLength) -Color $SeparatorColor
Write-Host ""


# Display each of the results
$OutputData | ForEach-Object {
    # Data retrieval
    $Name = $_.ScriptName
    $Syn  = $_.Synopsis

    $NameDisplay = if ([string]::IsNullOrEmpty($Name)) { "(No Name)" } else { $Name }
    $SynDisplay  = if ([string]::IsNullOrEmpty($Syn)) { "(No Synopsis Available)" } else { $Syn }
    
    $Padding = $MaxNameLength - $NameDisplay.Length
    $PaddingString = if ($Padding -gt 0) { " " * $Padding } else { " " } 
    
    Write-ColoredText -Text $NameDisplay -Color $ScriptNameColor
    Write-ColoredText -Text "$PaddingString| " -NoNewline  -Color $SeparatorColor
    Write-ColoredText -Text $SynDisplay -Color $SynopsisColor
    Write-Host ""
}
Write-ColoredText -Text ("=" * $TotalLineLength) -Color $SeparatorColor
Write-Host " "
Write-Host " "