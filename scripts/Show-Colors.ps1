<#
.SYNOPSIS
    Shows a full MS PowerShell terminal colour chart with key.
.DESCRIPTION
    Useful for checking the names of colours, or which colours can be used 
	together in foreground/background combinations.
.NOTES
     Author: Geekujin
    Version: 2.0
	Created: 2025-08-15
	Updated: 2025-11-24
	  About: Updated version which is a complete rewrite of previous script.
			 Now displays the colour chart in a compact table with a key.
#>


# [VARIABLES]
#Used for formatting the table width
$cellWidth = 3

# Store colour names in an array
$colors = [enum]::GetValues([System.ConsoleColor])

# Map colors to hex codes (0-F) in a hash table
$hexMap = @{}
for ($i = 0; $i -lt $colors.Count; $i++) {
    $hexMap[$colors[$i]] = "{0:X}" -f $i
}

# [FUNCTIONS] 
# Centre text in each table cell
function CenterText($text, $width) {
    $padding = [Math]::Max(0, ($width - $text.Length) / 2)
    return (" " * [Math]::Floor($padding)) + $text + (" " * [Math]::Ceiling($padding))
}

function Show-ColorChart {
	Write-Host ("    " + ($colors | ForEach-Object { "{0,2}" -f $hexMap[$_] }) -join " ") # Print column headers
	Write-Host ("   +" + ("-" * ($colors.Count * $cellWidth)) + "+") # Print top border
	
	# Print rows with row headers
	for ($row = 0; $row -lt $colors.Count; $row++) {
		$bgcolor = $colors[$row]
		Write-Host (" {0} |" -f $hexMap[$bgcolor]) -NoNewLine
		foreach ($fgcolor in $colors) {
			Write-Host (CenterText "x" $cellWidth) -ForegroundColor $fgcolor -BackgroundColor $bgcolor -NoNewLine
		}
		Write-Host "|"
	}
	
	Write-Host ("   +" + ("-" * ($colors.Count * $cellWidth)) + "+") # Print bottom border
}

function Show-Key {
	$counter = 0
	$maxWidth = ($colors | ForEach-Object { $_.ToString().Length } | Measure-Object -Maximum).Maximum
	Write-Host "`nKey:`n"
	foreach ($bgcolor in $colors) {
		# Change text colour to black for lighter backgrounds
		$textColor = if ($bgcolor -in @("White","Yellow","Gray","Cyan", "Green")) { "Black" } else { "White" }
		$label = ("{0,-$maxWidth}" -f $bgcolor) # Adds padding to align the key
		Write-Host "|$($hexMap[$bgcolor])|" -ForegroundColor $textColor -BackgroundColor $bgcolor -NoNewLine
		Write-Host " - $label  " -NoNewLine
		$counter++
		if ($counter % 4 -eq 0) { Write-Host "" } # Starts a new line for every 4 colours
	}
}
	
# [MAIN SCRIPT]
Write-Host "`n`n"
Write-Host "    All available colour combinations in the terminal" -foregroundcolor White
Write-Host "`n"
Show-ColorChart
Write-Host " "
Show-Key