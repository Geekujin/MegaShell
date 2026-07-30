<#
.SYNOPSIS
    Write multi-coloured text to the console, drop in substitute for Write-Host

.DESCRIPTION
    Prints each character using a different colour, as specified in the $Colors variable. Colours print in the same order as they are listed in the array.
	
.Version
    1.0
#>
param(
	[Parameter(Mandatory=$true)]
	[string]$Text
)

# Define the colors to cycle through (the 'rainbow')
$Colors = "Red", "Yellow", "Green", "Cyan", "Blue", "Magenta"
$ColorIndex = 0

# Split the input text into an array of characters
$Characters = $Text.ToCharArray()

# Loop through each character
foreach ($Character in $Characters) {
	# Get the colour based on the current index, using the modulus operator (%) to loop back
	$Color = $Colors[$ColorIndex % $Colors.Count]
	
	# Write the character with the selected colour, without a new line
	Write-Host -Object $Character -ForegroundColor $Color -NoNewline
	
	# Increment the index to move to the next colour
	$ColorIndex++
}

# Write a final newline to ensure the next prompt/output starts on a fresh line
Write-Host ""