<#
.SYNOPSIS
    PowerShell profile used by me for both fun and profit.

.DESCRIPTION
    Profile to customise your PowerShell environment.Loads bespoke config and variables from profile_config.json file. 
	
.DETAILS
	Each function in the script has brief comments explaining its useage. The profile_config.json can be used for storing different variables such as folder paths, usernames and other info. When used with Windows secrets vaults it can also be used to store references to sensitive info such as API keys and passwords, although these vaults are unique per-device.
		
	Use command 'Reload' if changes are made to this file or the config file whilst terminal is open.
	
.NOTES
    Version: 0.5
#>


Write-Host "`nLoading profile...`n" -ForeGroundColor DarkGray

# === [GLOBAL CONFIGURATION] ===

# Assign a path to the global configuration file
$ConfigFilePath = "$PSScriptRoot\profile_config.json"

# Sets the script encoding to UTF8 for handling emoji
$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8


# === [Functions] ===

# Internal Helper functions
function Get-ProfileConfig {
    [CmdletBinding()]
    param(
        [string]$Path = $ConfigFilePath
    )
    
    if (-not (Test-Path $Path)) {
        throw "FATAL: Config file not found at: $Path"
    }
    
    try {
        return (Get-Content -Path $Path | ConvertFrom-Json)
    } catch {
        throw "FATAL: Failed to parse JSON: $($_.Exception.Message)"
    }
}

function Resolve-ConfigSecrets { # Finds SECRET: placeholders in config file and loads them into the profile
    param(
		[PSCustomObject]$Object,
		[string]$VaultName = $Global:Config.Settings.VaultName # Load Vault name from the config file
	)
	
	if ([string]::IsNullOrWhiteSpace($VaultName)) { $VaultName = "LocalStore" } # Revert to default if no Vault Name found

    # Loop through all properties of the config object
    foreach ($prop in $Object.PSObject.Properties) {
        $Value = $prop.Value

        # If property is a String and starts with "SECRET:"
        if ($Value -is [string] -and $Value.StartsWith("SECRET:")) {
            $SecretName = $Value.Substring(7) # Remove "SECRET:"
			
            try {
                # Replace the placeholder with the real secret
                $RealSecret = Get-Secret -Name $SecretName -Vault $VaultName -AsPlainText -ErrorAction Stop
                $prop.Value = $RealSecret
            } catch {
                Write-Host "`n WARNING" -ForegroundColor Yellow
                Write-Host "     Access to Vault '$VaultName' is required for: $SecretName" -ForegroundColor Gray
                Write-Host "     Please enter your vault password in the prompt...`n" -ForegroundColor Gray
				
				try {
					$Pass = Read-Host "     Enter Vault Password" -AsSecureString
					Unlock-SecretStore -Password $Pass -ErrorAction Stop
					Write-Host "`n     Access Granted. Resuming...`n" -ForegroundColor Green
					$RealSecret = Get-Secret -Name $SecretName -Vault $VaultName -AsPlainText -ErrorAction Stop
                    $prop.Value = $RealSecret
				}
				catch {
                    Write-Error "Failed to resolve secret '$SecretName'. Error: $($_.Exception.Message)"
                }
            }
        }
        # If property is a nested object/JSON section, recurse into it
        elseif ($Value -is [PSCustomObject]) {
            Resolve-ConfigSecrets -Object $Value -VaultName $VaultName
        }
    }
}

function Write-ProfileLog {
    param([string]$Message, [string]$Level = 'INFO')
    
    $LogDir = $Global:Config.FilePaths.LogDirectory
    
    # Fails gracefully if the path is empty or doesn't exist
    if ([string]::IsNullOrWhiteSpace($LogDir) -or -not (Test-Path -LiteralPath $LogDir)) { 
        return 
    }
    
    $LogFile = Join-Path $LogDir "MegaShell_Profile.log"
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    
    try {
        "[$Timestamp] [$Level] $Message" | Out-File -FilePath $LogFile -Append -Encoding UTF8 -ErrorAction SilentlyContinue
    } catch {}
}
function Update-MegaShellProfile { # Checks for updates to the profile and updates it if a newer version is available
    <#
    .SYNOPSIS
        Updates the PowerShell profile.
    .DESCRIPTION
        This function checks for updates to the PowerShell profile via the GitHub Repository stored in the configuration and updates it if a newer version is available.
    #>
    [CmdletBinding()]
    param([switch]$Force, [switch]$NoReload)

    if ($env:POWERSHELL_PROFILE_RELOADING -eq '1') { return }

    # Map settings from the JSON Updater block
    $UpdaterConfig = $Global:Config.Updater
    $Configuration = @{
        Owner             = $UpdaterConfig.Owner
        Repository        = $UpdaterConfig.Repository
        Branch            = $UpdaterConfig.Branch
        ProfilePathInRepo = $UpdaterConfig.ProfilePathInRepo
        CheckInterval     = [TimeSpan]::Parse($UpdaterConfig.CheckInterval)
        TokenVariable     = $UpdaterConfig.GitHubToken
    }

    $ProfileDirectory = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $PROFILE }
    $CurrentProfile = Join-Path $ProfileDirectory $Configuration.ProfilePathInRepo
    $TemporaryPath = Join-Path $ProfileDirectory (".powershell-profile-{0}.tmp" -f [Guid]::NewGuid().ToString('N'))

    function Get-GitBlobHash {
        param([Parameter(Mandatory)][byte[]]$Bytes)
        $Header = [System.Text.Encoding]::UTF8.GetBytes("blob $($Bytes.Length)`0")
        $BlobData = [byte[]]::new($Header.Length + $Bytes.Length)
        [System.Buffer]::BlockCopy($Header, 0, $BlobData, 0, $Header.Length)
        [System.Buffer]::BlockCopy($Bytes, 0, $BlobData, $Header.Length, $Bytes.Length)
        $Sha1 = [System.Security.Cryptography.SHA1]::Create()
        try { return ([System.BitConverter]::ToString($Sha1.ComputeHash($BlobData))).Replace('-', '').ToLowerInvariant() }
        finally { $Sha1.Dispose() }
    }

    if (-not (Test-Path -LiteralPath $ProfileDirectory)) {
        New-Item -ItemType Directory -Path $ProfileDirectory -Force | Out-Null
    }

    # Check the lastcheck value from the JSON config
    if (-not $Force -and -not [string]::IsNullOrWhiteSpace($UpdaterConfig.lastcheck)) {
        try {
            $LastCheckedUtc = [DateTime]::Parse($UpdaterConfig.lastcheck, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::RoundtripKind)
            if (([DateTime]::UtcNow - $LastCheckedUtc) -lt $Configuration.CheckInterval) { return }
        } catch {}
    }

    $Headers = @{
        Accept                 = 'application/vnd.github+json'
        'User-Agent'           = 'PowerShell-Profile-Updater'
        'X-GitHub-Api-Version' = '2022-11-28'
    }

    $TokenVariable = $Configuration.TokenVariable
    if (-not [String]::IsNullOrWhiteSpace($TokenVariable) -and -not [String]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable($TokenVariable))) {
        $Token = [Environment]::GetEnvironmentVariable($TokenVariable)
        $Headers.Authorization = "Bearer $Token"
    }

    $EncodedRepositoryPath = ($Configuration.ProfilePathInRepo -split '/') | ForEach-Object { [Uri]::EscapeDataString($_) }
    $EncodedRepositoryPath = $EncodedRepositoryPath -join '/'
    $ApiUri = ('https://api.github.com/repos/{0}/{1}/contents/{2}?ref={3}' -f [Uri]::EscapeDataString($Configuration.Owner), [Uri]::EscapeDataString($Configuration.Repository), $EncodedRepositoryPath, [Uri]::EscapeDataString($Configuration.Branch))

    try {
        $RemoteFile = Invoke-RestMethod -Uri $ApiUri -Headers $Headers -Method Get -ErrorAction Stop

        if ($RemoteFile.type -ne 'file') { throw "The configured GitHub path is not a file." }
        if ([String]::IsNullOrWhiteSpace($RemoteFile.sha)) { throw "GitHub did not return a blob hash for the profile." }
        if ([String]::IsNullOrWhiteSpace($RemoteFile.download_url)) { throw "GitHub did not return a download URL for the profile." }

        $RemoteHash = $RemoteFile.sha.ToLowerInvariant()
        $LocalHash = $null

        if (Test-Path -LiteralPath $CurrentProfile) {
            $LocalBytes = [System.IO.File]::ReadAllBytes($CurrentProfile)
            $LocalHash = Get-GitBlobHash -Bytes $LocalBytes
        }

        # Update the JSON file safely by reading a fresh copy from disk to avoid saving vault secrets
        $RawConfig = Get-Content -Path $ConfigFilePath -Raw | ConvertFrom-Json
        $RawConfig.Updater.lastcheck = [DateTime]::UtcNow.ToString('o')
        $RawConfig | ConvertTo-Json -Depth 10 | Set-Content -Path $ConfigFilePath -Encoding UTF8

        if ($LocalHash -eq $RemoteHash) {
            return
        }

        Write-Host "A newer version of your MegaShell profile is available." -ForegroundColor Cyan
        $userChoice = Read-Host "Do you want to update it now? (Y/N)"
        
        if ($userChoice -notmatch "^[Yy]") {
            Write-Host "Update cancelled by user." -ForegroundColor Yellow
            return
        }

        $DownloadHeaders = @{ 'User-Agent' = 'PowerShell-Profile-Updater' }
        if ($Headers.ContainsKey('Authorization')) { $DownloadHeaders.Authorization = $Headers.Authorization }

        Invoke-WebRequest -Uri $RemoteFile.download_url -Headers $DownloadHeaders -OutFile $TemporaryPath -ErrorAction Stop

        $DownloadedBytes = [System.IO.File]::ReadAllBytes($TemporaryPath)
        $DownloadedHash = Get-GitBlobHash -Bytes $DownloadedBytes

        if ($DownloadedHash -ne $RemoteHash) {
            throw "The downloaded profile failed hash verification. Expected $RemoteHash but received $DownloadedHash."
        }

        $Tokens = $null
        $ParseErrors = $null
        [System.Management.Automation.Language.Parser]::ParseFile($TemporaryPath, [ref]$Tokens, [ref]$ParseErrors) | Out-Null

        if ($ParseErrors.Count -gt 0) {
            $ErrorText = $ParseErrors | ForEach-Object { "Line $($_.Extent.StartLineNumber): $($_.Message)" }
            throw ("The downloaded profile contains syntax errors:`n" + ($ErrorText -join [Environment]::NewLine))
        }

        $Timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
        $BackupPath = "$CurrentProfile.$Timestamp.bak"

        if (Test-Path -LiteralPath $CurrentProfile) {
            Copy-Item -LiteralPath $CurrentProfile -Destination $BackupPath -Force -ErrorAction Stop
        }

        Move-Item -LiteralPath $TemporaryPath -Destination $CurrentProfile -Force -ErrorAction Stop
        Write-Host "PowerShell profile updated successfully." -ForegroundColor Green
        
        # --- NEW LOG ENTRY ---
        Write-ProfileLog -Message "Profile updated successfully from GitHub (Hash: $RemoteHash)."

        if ($NoReload) {
            Write-Host "Open a new PowerShell session or run 'Reload-Profile' to load the updated profile." -ForegroundColor Yellow
            return
        }

        Write-Host 'Reloading the updated profile...' -ForegroundColor Cyan

        try {
            $env:POWERSHELL_PROFILE_RELOADING = '1'
            Reload-Profile
        }
        finally {
            Remove-Item Env:\POWERSHELL_PROFILE_RELOADING -ErrorAction SilentlyContinue
        }
    }
    catch {
        Write-Warning "PowerShell profile update failed: $($_.Exception.Message)"
        
        # --- NEW LOG ENTRY ---
        Write-ProfileLog -Message "Profile update failed: $($_.Exception.Message)" -Level 'ERROR'
    }
    finally {
        Remove-Item -LiteralPath $TemporaryPath -Force -ErrorAction SilentlyContinue
    }
}

function Update-ProfileConfig {
    <#
    .SYNOPSIS
        Updates the profile configuration file.
    .DESCRIPTION
        Checks for updates to the profile_config.json file from a private GitHub repository.
        Requires a valid GITHUB_TOKEN environment variable for authentication.
    #>
    [CmdletBinding()]
    param([switch]$Force)

    # Prevent an update-triggered reload from looping
    if ($env:POWERSHELL_PROFILE_RELOADING -eq '1') { return }

    # Get updater settings from the currently loaded global config
    $ConfigUpdater = $Global:Config.ConfigUpdater
    if (-not $ConfigUpdater) { return }

    $Configuration = @{
        Owner         = $ConfigUpdater.Owner
        Repository    = $ConfigUpdater.Repository
        Branch        = $ConfigUpdater.Branch
        PathInRepo    = $ConfigUpdater.ConfigPathInRepo
        CheckInterval = [TimeSpan]::Parse($ConfigUpdater.CheckInterval)
        TokenVariable = $ConfigUpdater.GitHubToken
    }

    $ConfigDirectory = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $PROFILE }
    $CurrentConfigPath = Join-Path $ConfigDirectory "profile_config.json"
    $TemporaryPath = Join-Path $ConfigDirectory (".profile_config-{0}.tmp" -f [Guid]::NewGuid().ToString('N'))

    function Get-GitBlobHash {
        param([Parameter(Mandatory)][byte[]]$Bytes)
        $Header = [System.Text.Encoding]::UTF8.GetBytes("blob $($Bytes.Length)`0")
        $BlobData = [byte[]]::new($Header.Length + $Bytes.Length)
        [System.Buffer]::BlockCopy($Header, 0, $BlobData, 0, $Header.Length)
        [System.Buffer]::BlockCopy($Bytes, 0, $BlobData, $Header.Length, $Bytes.Length)
        $Sha1 = [System.Security.Cryptography.SHA1]::Create()
        try { return ([System.BitConverter]::ToString($Sha1.ComputeHash($BlobData))).Replace('-', '').ToLowerInvariant() }
        finally { $Sha1.Dispose() }
    }

    # Cooldown check based on the config file's own timestamp
    if (-not $Force -and -not [string]::IsNullOrWhiteSpace($ConfigUpdater.lastcheck)) {
        try {
            $LastCheckedUtc = [DateTime]::Parse($ConfigUpdater.lastcheck, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::RoundtripKind)
            if (([DateTime]::UtcNow - $LastCheckedUtc) -lt $Configuration.CheckInterval) { return }
        } catch {}
    }

    $Headers = @{
        Accept                 = 'application/vnd.github+json'
        'User-Agent'           = 'PowerShell-Config-Updater'
        'X-GitHub-Api-Version' = '2022-11-28'
    }

    # Strict token check (required for private repos)
    $TokenVariable = $Configuration.TokenVariable
    if (-not [String]::IsNullOrWhiteSpace($TokenVariable) -and -not [String]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable($TokenVariable))) {
        $Token = [Environment]::GetEnvironmentVariable($TokenVariable)
        $Headers.Authorization = "Bearer $Token"
    } else {
        Write-Warning "GitHub token not found in environment variable '$TokenVariable'. Cannot check private config repository."
        return
    }

    $EncodedRepositoryPath = ($Configuration.PathInRepo -split '/') | ForEach-Object { [Uri]::EscapeDataString($_) }
    $EncodedRepositoryPath = $EncodedRepositoryPath -join '/'
    $ApiUri = ('https://api.github.com/repos/{0}/{1}/contents/{2}?ref={3}' -f [Uri]::EscapeDataString($Configuration.Owner), [Uri]::EscapeDataString($Configuration.Repository), $EncodedRepositoryPath, [Uri]::EscapeDataString($Configuration.Branch))

    try {
        $RemoteFile = Invoke-RestMethod -Uri $ApiUri -Headers $Headers -Method Get -ErrorAction Stop

        if ($RemoteFile.type -ne 'file') { throw "The configured GitHub path is not a file." }
        if ([String]::IsNullOrWhiteSpace($RemoteFile.sha)) { throw "GitHub did not return a blob hash." }
        if ([String]::IsNullOrWhiteSpace($RemoteFile.download_url)) { throw "GitHub did not return a download URL." }

        $RemoteHash = $RemoteFile.sha.ToLowerInvariant()
        $LocalHash = $null

        if (Test-Path -LiteralPath $CurrentConfigPath) {
            $LocalBytes = [System.IO.File]::ReadAllBytes($CurrentConfigPath)
            $LocalHash = Get-GitBlobHash -Bytes $LocalBytes
        }

        # Update the timestamp on the CURRENT file just in case no remote update is needed
        $RawConfig = Get-Content -Path $CurrentConfigPath -Raw | ConvertFrom-Json
        $RawConfig.ConfigUpdater.lastcheck = [DateTime]::UtcNow.ToString('o')
        $RawConfig | ConvertTo-Json -Depth 10 | Set-Content -Path $CurrentConfigPath -Encoding UTF8

        if ($LocalHash -eq $RemoteHash) { return }

        Write-Host "A newer version of your profile configuration is available." -ForegroundColor Cyan
        $userChoice = Read-Host "Do you want to update it now? (Y/N)"
        
        if ($userChoice -notmatch "^[Yy]") {
            Write-Host "Update cancelled by user." -ForegroundColor Yellow
            return
        }

        Invoke-WebRequest -Uri $RemoteFile.download_url -Headers $Headers -OutFile $TemporaryPath -ErrorAction Stop

        $DownloadedBytes = [System.IO.File]::ReadAllBytes($TemporaryPath)
        $DownloadedHash = Get-GitBlobHash -Bytes $DownloadedBytes

        if ($DownloadedHash -ne $RemoteHash) {
            throw "The downloaded config failed hash verification. Expected $RemoteHash but received $DownloadedHash."
        }

        # Strict JSON Validation: Ensures the downloaded file isn't corrupted or empty
        try {
            $NewConfigObj = Get-Content -LiteralPath $TemporaryPath -Raw | ConvertFrom-Json
            
            # Apply the current UTC timestamp to the downloaded file so it doesn't trigger again immediately
            $NewConfigObj.ConfigUpdater.lastcheck = [DateTime]::UtcNow.ToString('o')
            
            # Re-save it back to the temporary path cleanly
            $NewConfigObj | ConvertTo-Json -Depth 10 | Set-Content -Path $TemporaryPath -Encoding UTF8
        } catch {
            throw "The downloaded config file contains invalid JSON syntax."
        }

        $Timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
        $BackupPath = "$CurrentConfigPath.$Timestamp.bak"

        if (Test-Path -LiteralPath $CurrentConfigPath) {
            Copy-Item -LiteralPath $CurrentConfigPath -Destination $BackupPath -Force -ErrorAction Stop
        }

        Move-Item -LiteralPath $TemporaryPath -Destination $CurrentConfigPath -Force -ErrorAction Stop
        Write-Host "Profile configuration updated successfully." -ForegroundColor Green
        Write-ProfileLog -Message "Config updated successfully from private GitHub repository (Hash: $RemoteHash)."

        Write-Host "Reloading profile to apply new configuration..." -ForegroundColor Cyan
        try {
            $env:POWERSHELL_PROFILE_RELOADING = '1'
            Reload-Profile
        }
        finally {
            Remove-Item Env:\POWERSHELL_PROFILE_RELOADING -ErrorAction SilentlyContinue
        }
    }
    catch {
        Write-Warning "Profile configuration update failed: $($_.Exception.Message)"
        Write-ProfileLog -Message "Config update failed: $($_.Exception.Message)" -Level 'ERROR'
    }
    finally {
        Remove-Item -LiteralPath $TemporaryPath -Force -ErrorAction SilentlyContinue
    }
}


Update-MegaShellProfile
Update-ProfileConfig

function Get-Network { # Returns the current active network name
    try {
        $NetProfile = Get-NetConnectionProfile | Where-Object {
            $_.IPv4Connectivity -eq 'Internet' -or $_.IPv6Connectivity -eq 'Internet'
        }

        # If found, return the name immediately
        if ($NetProfile) {
            return $NetProfile.Name
        }
        
        # Fallback if no internet profile found
        Write-Warning "Could not determine active Internet connection. Defaulting to 'Unknown'."
        return "Unknown"

    } catch {
        Write-Error "An error occurred during network detection: $($_.Exception.Message)"
        return "Unknown"
    }
}

function Get-ExternalIP { # Returns the current external IP address
    try {
        # Gets IP from external site which returns only plaintext IPv4
        $ExternalIP = (Invoke-RestMethod -Uri 'https://icanhazip.com' -ErrorAction Stop).Trim()
        return $ExternalIP
    }
    catch {
        Write-Error "Failed to retrieve external IP address: $($_.Exception.Message)"
        return $null
    }
}

function Get-InternalIP { # Returns the current internal IP address
    # Get all valid IPv4 addresses (excluding Loopback and APIPA)
	$VpnPattern = "VPN|WireGuard|TAP|Tun|Fortinet"
	
    $InternalIPs = Get-NetIPAddress -AddressFamily IPv4 | Where-Object {
        $_.IPAddress -ne '127.0.0.1' -and $_.IPAddress -notlike '169.254.*'
    } | ForEach-Object {
		$adapter = Get-NetAdapter -InterfaceIndex $_.InterfaceIndex -ErrorAction SilentlyContinue
        [PSCustomObject]@{
            IP   = $_.IPAddress
            Name = $_.InterfaceAlias
            Desc = $adapter.InterfaceDescription
        }
    }
	
	$VirtualIP = ($InternalIPs | Where-Object {
		$_.Desc -match "Fortinet|VPN"
	} | Select-Object -first 1).IP
	
	$PhysicalIP = ($internalIPs | Where-Object { 
        $_.IP -ne $VirtualIP -and 
        $_.Name -notmatch "vEthernet|Default Switch" -and
        $_.Desc -notmatch "Hyper-V|Virtual"
    } | Select-Object -First 1).IP
	
    # Return as an object
    [PSCustomObject]@{
        PhysicalIP = $PhysicalIP
        VirtualIP      = $VirtualIP
    }
}

function Prompt { # Customise command prompt
	# Check if running as administrator
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    
    $Machine = hostname
	$CurrDirectory = (Get-Location).Path
    $Time = Get-Date -Format "HH:mm:ss"

    # Build the prompt string
    $promptString1 = "[$Time] - "
	$promptString2 = "("
	$promptString3 = $CurrDirectory
	$promptString4 = ")"
	$promptString5 = $Machine


    # Optionally display extra info
	Write-Host ""
	Write-Host $promptString1 -Foregroundcolor Blue -NoNewline
	Write-Host $promptString2 -Foregroundcolor Blue -NoNewline
	Write-Host $promptString3 -Foregroundcolor Green -NoNewline
	Write-Host $promptString4 -Foregroundcolor Blue
	Write-Host $PromptString5 -Foregroundcolor Yellow -NoNewline

    # Return the actual prompt symbol
    return "$> "

}

function Get-TimeOfDay { # Returns Morning, Afternoon or Night
    $hour = (Get-Date).Hour

    if ($hour -ge 5 -and $hour -lt 12) {
        return "morning"
    } elseif ($hour -ge 12 -and $hour -lt 16) {
        return "afternoon"
    } elseif ($hour -ge 16 -and $hour -lt 22) {
        return "evening"
    } else {
        return "night"
    }
}

function Write-ColorMappedArt { # Maps specific colours to specific characters
    param(
        [string]$Text,
        [ConsoleColor]$DefaultColor = "Gray",
		[string]$Theme = "Standard"
    )

	if ($Global:ArtThemes.ContainsKey($Theme)) {
        $ColorMap = $Global:ArtThemes[$Theme]
    } else {
        Write-Warning "Theme '$Theme' not found. Using Standard."
        $ColorMap = $Global:ArtThemes["Standard"]
    }
	
    $Text.ToCharArray() | ForEach-Object {
        $CharStr = $_.ToString()

        # Handle Newlines (Write-Host -NoNewline suppresses them otherwise)
        if ($CharStr -eq "`n") {
            Write-Host ""
            return
        }
        if ($CharStr -eq "`r") { return } # Skip carriage returns

        # Check map and print
        if ($ColorMap.ContainsKey($CharStr)) {
            Write-Host $CharStr -NoNewline -ForegroundColor $ColorMap[$CharStr]
        } else {
            Write-Host $CharStr -NoNewline -ForegroundColor $DefaultColor
        }
    }
    # Final newline to reset
    Write-Host ""
}

function Write-Rainbow { # Write to terminal using a different colour for each character
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
        # Get the color based on the current index, using the modulus operator (%) to loop back
        $Color = $Colors[$ColorIndex % $Colors.Count]
        
        # Write the character with the selected color, without a new line
        Write-Host -Object $Character -ForegroundColor $Color -NoNewline
        
        # Increment the index to move to the next color
        $ColorIndex++
    }

    # Write a final newline to ensure the next prompt/output starts on a fresh line
    Write-Host ""
}

function Get-DateWithOrdinal { # Gets current date with st, nd, rd, th etc.
    $date = Get-Date
    $day = $date.Day
    switch ($day % 10) {
        1 { $suffix = if ($day -eq 11) { "th" } else { "st" } }
        2 { $suffix = if ($day -eq 12) { "th" } else { "nd" } }
        3 { $suffix = if ($day -eq 13) { "th" } else { "rd" } }
        default { $suffix = "th" }
    }
    "$($date.ToString('dddd')) the $day$suffix of $($date.ToString('MMMM')) $($date.Year)"
}

function Show-Network {
	# Box shape
	$TL = "┍"; $TR = "┐"; $BL = "└"; $BR = "┘"; $H = "─"; $V = "│"
	
	# Box and text colors
	$BoxColor 		= "DarkGray"
	$InfoColor 		= "Gray"
	$LabelColor 	= "DarkCyan"
	$TitleColor 	= "Cyan"
	$SubTitleColor 	= "Magenta"
	$BreakColor 	= "DarkGray"
	
	# Characters for spacing and dividing items
	$Break = " | "
	$Space = " "
	
	# Define variables
	$NetTitle		= "NET: "
	$NetNameLabel	= "📡 "
	$NetNameInfo	= $Net
	$NetExtLabel	= "🌍 "
	$NetExtInfo		= $ExtIP
	$NetIntLabel	= "🏠 "
	$NetIntInfo		= $LANIP
	$NetVPNLabel	= "🔒 "
	if ($VPNIP) {
		$NetVPNInfo	= $VPNIP
	} else {
		$NetVPNInfo	= "n/a"
	}
	
	# Calculate length of text
	$NetContentLength = $Space.Length + $NetTitle.Length + $NetNameLabel.Length + $NetNameInfo.Length + $Break.Length + `
						$NetExtLabel.Length + $NetExtInfo.Length + $Break.Length + `
						$NetIntLabel.Length + $NetIntInfo.Length + $Break.Length + `
						$NetVPNLabel.Length + $NetVPNInfo.Length + $Space.Length
	
	# Draw the top of the box
	Write-Host $TL$($H * $NetContentLength)$TR -ForegroundColor $BoxColor
	Write-Host $V -NoNewline -ForegroundColor $BoxColor
	
	# Write content
	Write-Host $Space -NoNewline -Foregroundcolor $BreakColor
	Write-Host $NetTitle -NoNewline -Foregroundcolor $TitleColor
	Write-Host $NetNameLabel -NoNewline -Foregroundcolor $LabelColor
	Write-Host $NetNameInfo -NoNewline -Foregroundcolor $InfoColor
	Write-Host $Break -NoNewline -Foregroundcolor $BreakColor
	Write-Host $NetExtLabel -NoNewline -Foregroundcolor $LabelColor
	Write-Host $NetExtInfo -NoNewline -Foregroundcolor $InfoColor
	Write-Host $Break -NoNewline -Foregroundcolor $BreakColor
	Write-Host $NetIntLabel -NoNewline -Foregroundcolor $LabelColor
	Write-Host $NetIntInfo -NoNewline -Foregroundcolor $InfoColor
	Write-Host $Break -NoNewline -Foregroundcolor $BreakColor
	Write-Host $NetVPNLabel -NoNewline -Foregroundcolor $LabelColor
	Write-Host $NetVPNInfo -NoNewline -Foregroundcolor $InfoColor
	Write-Host $Space -NoNewline -Foregroundcolor $BreakColor
	
	# Draw bottom of box
	Write-Host $V -ForegroundColor $BoxColor
	Write-Host $BL$($H * $NetContentLength)$BR -ForegroundColor $BoxColor
	
}

function Show-Weather {
	Write-Host "Weather" -ForegroundColor Cyan
	Write-Host " $($Weather.Condition_Text)" -NoNewLine -ForegroundColor White
	Write-Host " $($Weather.Condition_Emoji)" -NoNewLine -ForegroundColor DarkCyan
	Write-Host $Spacer -NoNewLine -ForegroundColor DarkGray
	Write-Host " $($Weather.Temperature_C)°C" -NoNewLine -ForegroundColor White
	Write-Host " $($Weather.Temperature_Emoji)" -NoNewLine -ForegroundColor DarkCyan
	Write-Host $Spacer -NoNewLine -ForegroundColor DarkGray
	Write-Host "UV Index: " -NoNewLine -ForegroundColor DarkCyan
	Write-Host "$($Weather.UVIndex_Text) " -NoNewLine -ForegroundColor White
	Write-Host "$($Weather.UVIndex_Emoji)" -NoNewLine -ForegroundColor White
	Write-Host $Spacer -NoNewLine -ForegroundColor DarkGray
	Write-Host "Air Quality: " -NoNewLine -ForegroundColor DarkCyan
	Write-Host "$($Weather.AirQuality_Text) " -NoNewLine -ForegroundColor White
	Write-Host "$($Weather.AirQuality_Emoji)" -ForegroundColor White
	Write-Host " "
}

function Get-Weather {
    [CmdletBinding()]
    param([hashtable]$LocationMap)

    # --- Helper Functions ---

    function Get-TemperatureEmoji {
        param([double]$Temp)

        if ($Temp -le 0)  { return "🥶" } # Freezing
        if ($Temp -le 10) { return "🧥" } # Coat needed
        if ($Temp -le 18) { return "🌥️" } # Cool
        if ($Temp -le 25) { return "😎" } # Nice / Warm
        if ($Temp -le 30) { return "🥵" } # Hot
        return "🔥"                       # Extreme
    }

    function Get-WeatherDescription {
        param([int]$Code)
        
        $Map = @{
            0 = @{T="Clear"; E="☀️"}; 1 = @{T="Mainly clear"; E="🌤️"}; 2 = @{T="Partly cloudy"; E="⛅"}; 3 = @{T="Overcast"; E="☁️"};
            45 = @{T="Fog"; E="🌫️"}; 48 = @{T="Depositing rime fog"; E="🌫️"}; 51 = @{T="Light drizzle"; E="🌧"};
            53 = @{T="Moderate drizzle"; E="🌧"}; 55 = @{T="Dense drizzle"; E="🌧️"}; 61 = @{T="Slight rain"; E="🌧️"};
            63 = @{T="Moderate rain"; E="🌧️"}; 65 = @{T="Heavy rain"; E="🌧️"}; 71 = @{T="Slight snow"; E="🌨️"};
            73 = @{T="Moderate snow"; E="🌨️"}; 75 = @{T="Heavy snow"; E="🌨️"}; 
            80 = @{T="Slight showers"; E="🌧️"}; 95 = @{T="Thunderstorms"; E="⛈️"}
        }

        if ($Map.ContainsKey($Code)) { 
            return [PSCustomObject]@{ Text = $Map[$Code].T; Emoji = $Map[$Code].E }
        }
        return [PSCustomObject]@{ Text = "Unknown (Code $Code)"; Emoji = "❓" }
    }

    function Get-AirQualityScore {
        param([double]$Value)
        if ($Value -le 20)  { return [PSCustomObject]@{ Text="Good"; Emoji="🟩" } }
        if ($Value -le 40)  { return [PSCustomObject]@{ Text="Fair"; Emoji="🟨" } }
        if ($Value -le 60)  { return [PSCustomObject]@{ Text="Moderate"; Emoji="🟧" } }
        if ($Value -le 80)  { return [PSCustomObject]@{ Text="Poor"; Emoji="🟥" } }
        if ($Value -le 100) { return [PSCustomObject]@{ Text="Very Poor"; Emoji="🆘" } }
        return [PSCustomObject]@{ Text="Extremely Poor"; Emoji="⚠️" }
    }

    function Get-UVIndexScore {
        param([double]$Value)
        if ($Value -le 2)  { return [PSCustomObject]@{ Text="Low"; Emoji="🟢" } }
        if ($Value -le 5)  { return [PSCustomObject]@{ Text="Moderate"; Emoji="🟡" } }
        if ($Value -le 10) { return [PSCustomObject]@{ Text="High"; Emoji="🟠" } }
        return [PSCustomObject]@{ Text="Extreme"; Emoji="🔴" }
    }

    # --- Core Data Retrieval Functions ---

    function Get-Forecast {
        [CmdletBinding()]
        param (
            [Parameter(Mandatory=$true)] [double]$Latitude,
            [Parameter(Mandatory=$true)] [double]$Longitude
        )

        $Uri = "https://api.open-meteo.com/v1/forecast?latitude=$Latitude&longitude=$Longitude&current_weather=true&temperature_unit=celsius&wind_speed_unit=kmh&timezone=auto&forecast_days=1"

        try {
            $Data = Invoke-RestMethod -Uri $Uri -Method Get -ErrorAction Stop
            $Current = $Data.current_weather
            
            $DescObj = Get-WeatherDescription -Code $Current.weathercode
            $TempEmoji = Get-TemperatureEmoji -Temp $Current.temperature

            [PSCustomObject]@{
                Temperature = $Current.temperature
                TempEmoji   = $TempEmoji
                CondText    = $DescObj.Text
                CondEmoji   = $DescObj.Emoji
            }
        } catch {
            Write-Error "Failed to retrieve forecast: $($_.Exception.Message)"
        }
    }

    function Get-AirQuality {
        [CmdletBinding()]
        param (
            [Parameter(Mandatory=$true)] [double]$Latitude,
            [Parameter(Mandatory=$true)] [double]$Longitude
        )
        
        $Uri = "https://air-quality-api.open-meteo.com/v1/air-quality?latitude=$Latitude&longitude=$Longitude&current=european_aqi,uv_index&forecast_days=1"

        try {
            $Data = Invoke-RestMethod -Uri $Uri -Method Get -ErrorAction Stop
            
            $AQIObj = Get-AirQualityScore -Value $Data.current.european_aqi
            $UVObj  = Get-UVIndexScore -Value $Data.current.uv_index

            [PSCustomObject]@{
                AQI_Val   = $Data.current.european_aqi
                AQI_Text  = $AQIObj.Text
                AQI_Emoji = $AQIObj.Emoji
                UV_Val    = $Data.current.uv_index
                UV_Text   = $UVObj.Text
                UV_Emoji  = $UVObj.Emoji
            }
        } catch {
            Write-Error "Failed to retrieve air quality: $($_.Exception.Message)"
        }
    }

    # --- Main Orchestrator Logic ---

    # 1. Network Detection
    $NetProfile = Get-NetConnectionProfile | Where-Object { $_.IPv4Connectivity -eq 'Internet' -or $_.IPv6Connectivity -eq 'Internet' }
    $NetworkName = if ($NetProfile) { $NetProfile.Name } else { "M80" }
    
    # 2. Location Lookup
    if (-not $LocationMap.ContainsKey($NetworkName)) {
        Write-Warning "Network '$NetworkName' not mapped. Defaulting to 'M80'."
        $NetworkName = "M80"
    }
    $Loc = $LocationMap[$NetworkName]

    # 3. Retrieve Data
    $Forecast = Get-Forecast -Latitude $Loc.Latitude -Longitude $Loc.Longitude
    $AirData  = Get-AirQuality -Latitude $Loc.Latitude -Longitude $Loc.Longitude

    # 4. Return Unified Object
    [PSCustomObject]@{
        Location         = $Loc.Name
        Network          = $NetworkName
        
        # Temperature
        Temperature_C    = $Forecast.Temperature
        Temperature_Emoji= $Forecast.TempEmoji

        # Conditions
        Condition_Text   = $Forecast.CondText
        Condition_Emoji  = $Forecast.CondEmoji
        
        # Air Quality
        AirQuality_AQI   = $AirData.AQI_Val
        AirQuality_Text  = $AirData.AQI_Text
        AirQuality_Emoji = $AirData.AQI_Emoji
        
        # UV Index
        UVIndex_Numeric  = $AirData.UV_Val
        UVIndex_Text     = $AirData.UV_Text
        UVIndex_Emoji    = $AirData.UV_Emoji
    }
}

function Show-MOTD { # Displays a random message from a motd.txt file
    <#
    .SYNOPSIS
        Displays a random message from a motd.txt file.

    .DESCRIPTION
        Messages in motd.txt should be one per line.
    #>

    # Set the path of the file containing your messages
    $MOTDFile = "$($Config.FilePaths.Variables)motd.txt"

    $TextColor = "White"
    $SourceColor = "DarkYellow"


    # Check if the file exists
    if (Test-Path $MOTDFile) {
        $Lines = Get-Content $MOTDFile | Where-Object { $_.Trim() -ne "" }
        if ($Lines.Count -gt 0) {
            $RandomLine = Get-Random -InputObject $Lines

            # Check if the line matches the format of "Quote! - Source, else treat as a message
            if ($RandomLine -match '^"(.+)"\s*-\s*(.+)$') {
                $quote = $matches[1]
                $source = $matches[2]

                Write-Host "Message of the Day" -ForegroundColor Cyan
                Write-Host "`"$quote`"" -ForegroundColor White
                Write-Host " - $source`n" -ForegroundColor $SourceColor
            } else {
                Write-Host "Message of the Day" -ForegroundColor Cyan
                Write-Host "$RandomLine`n" -ForegroundColor White
            }
        } else {
            Write-Warning "No content found in the file."
        }
    } else {
        Write-Warning "File not found at $MOTDFile`n"
    }
}

# Functions that users can call directly
function Reload-Profile { # Reloads the PowerShell profile
    <#
    .SYNOPSIS
        Reloads the PowerShell profile.
    .DESCRIPTION
        This function reloads the PowerShell profile by sourcing the profile script. 
        Useful after updating the profile or making changes to the configuration.
    #>
    Clear-Host
    try {
        . $Global:Config.Settings.Profilepath
        Write-Host "`nProfile reloaded successfully." -ForegroundColor Cyan
        Write-ProfileLog -Message "Profile reloaded successfully."
    } catch {
        Write-Host "`nError loading profile: $($_.Exception.Message)" -ForegroundColor Red
        Write-ProfileLog -Message "Error loading profile: $($_.Exception.Message)" -Level 'ERROR'
    }
}

function Profile-Help {
    <#
    .SYNOPSIS
        Displays help for CyberShell profile functions.
    .DESCRIPTION
        Run without parameters to see a list of all public custom profile functions.
        Pass a function name to view its full PowerShell help documentation.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Position=0)]
        [string]$FunctionName
    )

    if (-not [string]::IsNullOrWhiteSpace($FunctionName)) {
        Get-Help $FunctionName -Detailed
    } else {
        Write-Host "`n=== CyberShell Functions ===" -ForegroundColor Cyan
        
        $ProfilePath = $Global:Config.Settings.ProfilePath
        
        # Retrieve all functions loaded directly from the profile script file
        $ProfileFunctions = Get-Command -CommandType Function | Where-Object { $_.ScriptBlock.File -eq $ProfilePath }
        
        foreach ($Func in $ProfileFunctions) {
            $Help = Get-Help $Func.Name -ErrorAction SilentlyContinue
            
            # Only display the function if a Synopsis exists
            if ($Help -and -not [string]::IsNullOrWhiteSpace($Help.Synopsis)) {
                Write-Host (" {0,-30} " -f $Func.Name) -ForegroundColor Green -NoNewline
                Write-Host $Help.Synopsis.Trim() -ForegroundColor Gray
            }
        }
        
        Write-Host "`nRun 'Profile-Help <FunctionName>' for detailed syntax.`n" -ForegroundColor DarkGray
    }
}
function Show-Networks { # Show a row of network info: Network name, External IP, and VPN IP if connected
    <#
    .SYNOPSIS
        Displays network information.
    .DESCRIPTION
        This function shows the network name, internal and external IPs, and the VPN IP if connected.
    #>
    Write-Host "Network" -ForegroundColor Cyan
    Write-Host " 📡 Name: " -NoNewLine -ForegroundColor DarkCyan
    Write-Host "$Net" -NoNewLine -ForegroundColor White

    Write-Host $Spacer -NoNewLine -ForegroundColor DarkGray
    Write-Host "🌍 Ext: " -NoNewLine -ForegroundColor DarkCyan
    Write-Host "$ExtIP" -NoNewLine -ForegroundColor White

    Write-Host $Spacer -NoNewLine -ForegroundColor DarkGray
    Write-Host "🏠 LAN: " -NoNewLine -ForegroundColor DarkCyan
    Write-Host "$LANIP" -NoNewLine -ForegroundColor White
    # Only show VPN if it exists
    if ($VpnIP) {
        Write-Host $Spacer -NoNewLine -ForegroundColor DarkGray
        Write-Host "🔒 VPN: " -NoNewLine -ForegroundColor DarkCyan
        Write-Host "$VpnIP" -ForegroundColor White
    } else {
        Write-Host " " # Just finish the line
    }
    Write-Host " "
}

function Connect-M365Service { # Easily connect to any 365 Service
    <#
    .SYNOPSIS
        Connects to a Microsoft 365 service.
    .DESCRIPTION
        This function provides a simple way to connect to various Microsoft 365 services.
        Run Connect-M365Service -Service <ServiceName> to connect. Use -InstallMissingModules to automatically install required modules if they are not present.
        Running without parameters will display a list of available services and their connection status.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet(
            'ExchangeOnline',
            'Purview',
            'Graph',
            'Teams',
            'SharePointOnline',
            'All'
        )]
        [string[]]$Service,

        [string]$UserPrincipalName = $script:config.users.entraadmin,

        [ValidatePattern('^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$')]
        [string]$TenantId,

        [string[]]$GraphScopes = @('User.Read'),

        [ValidatePattern('^https://[A-Za-z0-9-]+-admin\.sharepoint\.com/?$')]
        [string]$SharePointAdminUrl,

        [switch]$UseDeviceCode,

        [switch]$InstallMissingModules,

        [switch]$ForceReconnect
    )

    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    $serviceDefinitions = [ordered]@{
        ExchangeOnline = @{
            Module  = 'ExchangeOnlineManagement'
            Command = 'Connect-ExchangeOnline'
        }
        Purview = @{
            Module  = 'ExchangeOnlineManagement'
            Command = 'Connect-IPPSSession'
        }
        Graph = @{
            Module  = 'Microsoft.Graph.Authentication'
            Command = 'Connect-MgGraph'
        }
        Teams = @{
            Module  = 'MicrosoftTeams'
            Command = 'Connect-MicrosoftTeams'
        }
        SharePointOnline = @{
            Module  = 'Microsoft.Online.SharePoint.PowerShell'
            Command = 'Connect-SPOService'
        }
    }

    function Import-RequiredM365Module {
        param(
            [Parameter(Mandatory = $true)]
            [string]$ModuleName,

            [Parameter(Mandatory = $true)]
            [string]$RequiredCommand
        )

        $availableModule = Get-Module -ListAvailable -Name $ModuleName |
            Sort-Object Version -Descending |
            Select-Object -First 1

        if (-not $availableModule) {
            if (-not $InstallMissingModules) {
                throw "The '$ModuleName' module is not installed. Install it with: Install-Module -Name '$ModuleName' -Scope CurrentUser, or rerun with -InstallMissingModules."
            }

            Write-Host "Installing module $ModuleName..." -ForegroundColor Cyan
            Install-Module -Name $ModuleName -Scope CurrentUser -Repository PSGallery -AllowClobber -Force
        }

        Write-Verbose "Importing module $ModuleName."
        Import-Module -Name $ModuleName -ErrorAction Stop

        if (-not (Get-Command -Name $RequiredCommand -ErrorAction SilentlyContinue)) {
            throw "Module '$ModuleName' was imported, but '$RequiredCommand' is unavailable."
        }
    }

    function New-ConnectionResult {
        param(
            [Parameter(Mandatory = $true)]
            [string]$ServiceName,

            [Parameter(Mandatory = $true)]
            [ValidateSet('Connected', 'Failed')]
            [string]$Status,

            [string]$Details
        )

        return [pscustomobject]@{
            Service = $ServiceName
            Status  = $Status
            Details = $Details
        }
    }

    $requestedServices = if ($Service -contains 'All') {
        @(
            'ExchangeOnline'
            'Purview'
            'Graph'
            'Teams'
            'SharePointOnline'
        )
    }
    else {
        @($Service | Select-Object -Unique)
    }

    if (
        $requestedServices -contains 'SharePointOnline' -and
        [string]::IsNullOrWhiteSpace($SharePointAdminUrl)
    ) {
        throw "-SharePointAdminUrl is required for SharePoint Online. Example: -SharePointAdminUrl 'https://contoso-admin.sharepoint.com'"
    }

    $requiredModules = foreach ($serviceName in $requestedServices) {
        $definition = $serviceDefinitions[$serviceName]
        [pscustomobject]@{
            Module  = $definition.Module
            Command = $definition.Command
        }
    }

    $modulesToImport = $requiredModules |
        Group-Object Module |
        ForEach-Object {
            [pscustomobject]@{
                Module   = $_.Name
                Commands = @($_.Group.Command | Select-Object -Unique)
            }
        }

    foreach ($moduleItem in $modulesToImport) {
        foreach ($requiredCommand in $moduleItem.Commands) {
            Import-RequiredM365Module -ModuleName $moduleItem.Module -RequiredCommand $requiredCommand
        }
    }

    $results = [System.Collections.Generic.List[object]]::new()

    foreach ($serviceName in $requestedServices) {
        try {
            switch ($serviceName) {
                'ExchangeOnline' {
                    if ($ForceReconnect -and (Get-Command Disconnect-ExchangeOnline -ErrorAction SilentlyContinue)) {
                        Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue
                    }

                    $parameters = @{
                        ShowBanner = $false
                        ErrorAction = 'Stop'
						DisableWAM = $true
                    }

                    if (-not [string]::IsNullOrWhiteSpace($UserPrincipalName)) {
                        $parameters.UserPrincipalName = $UserPrincipalName
                    }

                    Write-Host 'Connecting to Exchange Online...' -ForegroundColor Cyan
                    Connect-ExchangeOnline @parameters

                    $results.Add((New-ConnectionResult -ServiceName $serviceName -Status Connected -Details 'Exchange Online PowerShell connection established.'))
                }

                'Purview' {
                    $parameters = @{
                        ShowBanner = $false
                        ErrorAction = 'Stop'
						DisableWAM = $true
                    }

                    if (-not [string]::IsNullOrWhiteSpace($UserPrincipalName)) {
                        $parameters.UserPrincipalName = $UserPrincipalName
                    }

                    Write-Host 'Connecting to Microsoft Purview...' -ForegroundColor Cyan
                    Connect-IPPSSession @parameters

                    $results.Add((New-ConnectionResult -ServiceName $serviceName -Status Connected -Details 'Security and Compliance PowerShell connection established.'))
                }

                'Graph' {
                    if ($ForceReconnect -and (Get-MgContext -ErrorAction SilentlyContinue)) {
                        Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
                    }

                    $parameters = @{
                        Scopes       = $GraphScopes
                        ContextScope = 'Process'
                        NoWelcome    = $true
                        ErrorAction  = 'Stop'
                    }

                    if (-not [string]::IsNullOrWhiteSpace($TenantId)) {
                        $parameters.TenantId = $TenantId
                    }

                    if ($UseDeviceCode) {
                        $parameters.UseDeviceCode = $true
                    }

                    Write-Host 'Connecting to Microsoft Graph...' -ForegroundColor Cyan
                    Connect-MgGraph @parameters
                    $graphContext = Get-MgContext

                    $details = "Connected as $($graphContext.Account); tenant $($graphContext.TenantId)."
                    $results.Add((New-ConnectionResult -ServiceName $serviceName -Status Connected -Details $details))
                }

                'Teams' {
                    if ($ForceReconnect -and (Get-Command Disconnect-MicrosoftTeams -ErrorAction SilentlyContinue)) {
                        Disconnect-MicrosoftTeams -ErrorAction SilentlyContinue | Out-Null
                    }

                    $parameters = @{
                        ErrorAction = 'Stop'
                    }

                    if (-not [string]::IsNullOrWhiteSpace($TenantId)) {
                        $parameters.TenantId = $TenantId
                    }

                    if (-not [string]::IsNullOrWhiteSpace($UserPrincipalName)) {
                        $parameters.AccountId = $UserPrincipalName
                    }

                    Write-Host 'Connecting to Microsoft Teams...' -ForegroundColor Cyan
                    Connect-MicrosoftTeams @parameters | Out-Null

                    $results.Add((New-ConnectionResult -ServiceName $serviceName -Status Connected -Details 'Microsoft Teams PowerShell connection established.'))
                }

                'SharePointOnline' {
                    if ($ForceReconnect -and (Get-Command Disconnect-SPOService -ErrorAction SilentlyContinue)) {
                        Disconnect-SPOService -ErrorAction SilentlyContinue
                    }

                    Write-Host 'Connecting to SharePoint Online...' -ForegroundColor Cyan
                    Connect-SPOService -Url $SharePointAdminUrl -ErrorAction Stop

                    $results.Add((New-ConnectionResult -ServiceName $serviceName -Status Connected -Details "Connected to $SharePointAdminUrl."))
                }
            }
        }
        catch {
            $results.Add((New-ConnectionResult -ServiceName $serviceName -Status Failed -Details $_.Exception.Message))
            Write-Error -Message "Failed to connect to $serviceName. $($_.Exception.Message)" -ErrorAction Continue
        }
    }

    Write-Host ''
    Write-Host 'Microsoft 365 connection results' -ForegroundColor Cyan
    $results | Format-Table -AutoSize

    return $results
}


# === [Profile Setup] ===

try {
    $Global:Config = Get-ProfileConfig
} catch {
    Write-Host "`n[!] Profile initialization aborted: $($_.Exception.Message)`n" -ForegroundColor Red
    return
}

Resolve-ConfigSecrets -Object $Global:Config # Replace SECRET placeholders with actual values
$env:PATH += "$($Config.Settings.ScriptRoot);" # Add the folder with PowerShell scripts to the PATH
$host.ui.RawUI.WindowTitle = $Config.Settings.WindowTitle # Rename the Titlebar/Tab


# === [Dot source external scripts] ===

if ($Global:Config.DotSourceFiles) {
	Write-Host "Dot-sourcing scripts...`n" -ForegroundColor DarkGray
    $DefaultRoot = $Global:Config.FilePaths.ScriptRoot

    foreach ($Entry in $Global:Config.DotSourceFiles) {
        
        # Logic: If it's a full path (e.g. C:\...), use it. 
        # Otherwise, combine it with the ScriptRoot.
        if ([System.IO.Path]::IsPathRooted($Entry)) {
            $FullPath = $Entry
        } else {
            $FullPath = Join-Path -Path $DefaultRoot -ChildPath $Entry
        }
		$FileName = Split-Path -Path $FullPath -Leaf
		
        # Attempt to load
        if (Test-Path $FullPath) {
            try {
                . $FullPath
				Write-Host " [+] Loaded module: $FileName" -ForegroundColor DarkGray
            } catch {
                Write-Error "[!] Failed to load '$FullPath': $($_.Exception.Message)"
            }
        } else {
            Write-Warning "[?] Script not found: $FullPath"
        }
    }
	Write-Host "`nFinished loading files.`n" -ForegroundColor DarkGray
}


# === [Variables] ===

# Banner variables
$BannerFolder = $Config.Banners.Folder
$BannerFile = $Config.Banners.File
$BannerPath = Join-Path -Path $bannerFolder -ChildPath $BannerFile
$BannerArt = Get-Content -Path $BannerPath -Raw

# Hashtable of ArtColors from config json
$Global:ArtThemes = @{}
if ($Global:Config.ArtThemes) {
    foreach ($themeProp in $Global:Config.ArtThemes.PSObject.Properties) {
        $themeName = $themeProp.Name
        $themeMap  = @{}
		
	foreach ($charProp in $themeProp.Value.PSObject.Properties) {
            $themeMap[$charProp.Name] = $charProp.Value
        }
	
	$Global:ArtThemes[$themeName] = $themeMap
	
	}
}

# Hashtable mapping the Network name to Lat/Long and friendly name
$Global:LocationMap = @{}
if ($Config.NetworkLocations) {
    foreach ($entry in $Config.NetworkLocations.PSObject.Properties.Value) {
        $Global:LocationMap[$entry.Name] = @{
            Latitude  = $entry.Latitude
            Longitude = $entry.Longitude
            Name      = $entry.Location
        }
    }
}

# Prompt variables
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$Machine = hostname
$CurrDirectory = (Get-Location).Path

# Time and date variables
$LongDate = Get-DateWithOrdinal
$Time = Get-Date -Format "HH:mm:ss"
$Greeting = Get-TimeOfDay

# Weather variables
$Weather = Get-Weather -LocationMap $LocationMap -ErrorAction SilentlyContinue
$UVIndex = 
$AirQuality = $($Weather.UVIndex_Score)

# Network variables - for use in Show-Networks function
$ExtIP = Get-ExternalIP
$IntIP = Get-InternalIP
$LANIP = $IntIP.PhysicalIP
$VPNIP = $IntIP.VirtualIP
$Net = Get-Network

# Misc variables
$Spacer = "  |  " # Used for spacing items in horizontal bars



# ==== [Aliases] ====

if ($Global:Config.Aliases) {
	Write-Host "Mapping aliases...`n" -ForegroundColor DarkGray
    foreach ($alias in $Global:Config.Aliases.PSObject.Properties) {
        $Name = $alias.Name
        $Value = $alias.Value

        try {
            Set-Alias -Name $Name -Value $Value -Scope Global -Force -ErrorAction Stop
            
            Write-Host " [+] Alias set: $Name -> $Value" -ForegroundColor DarkGray
        } catch {
            Write-Error " [!] Failed to set alias '$Name': $($_.Exception.Message)"
        }
    }
	Write-Host "`nFinished mapping aliases.`n" -ForegroundColor DarkGray
}


# === [Main Script Execution] ===
Start-Sleep -Seconds 2
Clear-Host
if ($Global:Config.Features.ShowBanner) {
    Write-Host " "
    Write-ColorMappedArt -Text $BannerArt -Theme "Standard"
    Write-Host " "
}

if ($Global:Config.Features.ShowNetworkInfo) {
    Show-Network
    Write-Host " "
}
if ($Global:Config.Features.ShowDateTime) {
    Write-Host " Good $($Greeting) $($Global:Config.Settings.Name), it is $LongDate."
}

if ($Global:Config.Features.ShowWeather) {
Write-Host " Weather conditions at $($Weather.Location): " -NoNewLine
Write-Host "$($Weather.Condition_Emoji) $($Weather.Condition_Text)" -ForegroundColor White
Write-Host " it is $($Weather.Temperature_C)°C with a UV index of $($Weather.UVIndex_Text). Air quality is $($Weather.AirQuality_Text)."
Write-Host " "
}

if ($Global:Config.Features.ShowMOTD) {
    Show-MOTD
}