<#
.SYNOPSIS
	Outputs different types of Unicode emoji characters to the console.
.PARAMETER 
	Type
	Specifies which emoji type to display (e.g., 'Faces', 'Animals', 'All').
	If omitted, a list of available types is displayed.
#>
function Show-EmojiTypes {
    param(
        [Parameter(Mandatory=$false)]
        [string]$Type
    )

    # Define the primary emoji types and their ranges
    $EmojiTypes = @{
        'Faces'        = @{ Start = 0x1F600; End = 0x1F64F; Note = "Smileys & Emotion" }
        'People'       = @{ Start = 0x1F460; End = 0x1F4FF; Note = "People & Body (Part 1)" }
        'Animals'      = @{ Start = 0x1F400; End = 0x1F43F; Note = "Animals & Nature (Part 1)" }
        'Food'         = @{ Start = 0x1F340; End = 0x1F37F; Note = "Food & Drink" }
        'Travel'       = @{ Start = 0x1F680; End = 0x1F6FF; Note = "Travel & Places" }
        'Objects'      = @{ Start = 0x1F4A0; End = 0x1F4FF; Note = "Objects & Symbols" }
        'Symbols'      = @{ Start = 0x25A0; End = 0x27BF; Note = "Geometric & Misc Symbols" }
        # 'Signs'        = @{ Start = 0x1F200; End = 0x1F2FF; Note = "Japanese/Button Signs" } # Commented out due to display issues
        'Sports'       = @{ Start = 0x26F0; End = 0x26FF; Note = "Sports & Recreation" }
        'Supplemental' = @{ Start = 0x1F900; End = 0x1F9FF; Note = "Newer Emojis (V3+)" }
    }
    
    # Configure console for UTF-8 to ensure proper display
    $OutputEncoding = [System.Text.Encoding]::UTF8
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8

    # --- Logic to Display Options or Emojis ---
  
    if (-not $PSBoundParameters.ContainsKey('Type')) {
        Write-Host "`n--- Available Emoji Types ---" -ForegroundColor Yellow
        Write-Host "To display an emoji type, run: " -NoNewline
        Write-Host "Show-EmojiTypes " -ForegroundColor Yellow -NoNewline
        Write-Host "-Type " -ForegroundColor DarkGray -NoNewline
        Write-Host "<Name>"
        Write-Host "`nAvailable Names:" -ForegroundColor Cyan
        
        $EmojiTypes.Keys | Sort-Object | ForEach-Object {
            Write-Host "  - $_"
        }
        Write-Host "  - All (To display all types)"
        return
    }

    # Check for invalid -Type argument
    $ValidTypes = $EmojiTypes.Keys + "All"
    if ($Type -notin $ValidTypes) {
        Write-Host "[ERROR]: Invalid emoji type specified: '$Type'`n" -ForegroundColor Red
        Write-Host "Please use one of the following names:" -ForegroundColor Red
        Write-Host ""
        
        $EmojiTypes.Keys | Sort-Object | ForEach-Object {
            Write-Host "  - $_"
        }
        Write-Host "  - All"
        return
    }

    # Function to process and display a single type
    function Display-Type {
        param([string]$Name, [int]$StartCode, [int]$EndCode, [string]$Note)

        Write-Host ""
        Write-Host "--- $($Name.ToUpper()) EMOJI TYPE --- ($Note)" -ForegroundColor Green
        
        $Count = 0
        for ($i = $StartCode; $i -le $EndCode; $i++) {
            try {
                $emoji = [char]::ConvertFromUtf32($i)
                Write-Host "$emoji" -NoNewline
                
                # Newline every 20 characters for readability
                if (++$Count % 20 -eq 0) {
                    Write-Host ""
                } else {
                    Write-Host " " -NoNewline
                }
            } catch {} # Skip invalid Unicode code points
        }
        Write-Host ""
    }

    # 3. Display the requested type (All or Specific)
    if ($Type -eq 'All') {
        # Display all types
        foreach ($Key in $EmojiTypes.Keys | Sort-Object) {
            $T = $EmojiTypes[$Key]
            Display-Type -Name $Key -StartCode $T.Start -EndCode $T.End -Note $T.Note
        }
    } else {
        # Display the selected type
        $T = $EmojiTypes[$Type]
        Display-Type -Name $Type -StartCode $T.Start -EndCode $T.End -Note $T.Note
    }
    Write-Host "--- Script Finished ---"
}

# --- Execution ---
# This line calls the function, passing any arguments given to the script file.
Show-EmojiTypes @args