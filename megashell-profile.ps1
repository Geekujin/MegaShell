<#
.SYNOPSIS
    PowerShell profile used by me for both fun and profit.

.DESCRIPTION
    Profile to customise your PowerShell environment.Loads bespoke config and variables from profile_config.json file. 
	
.VERSION
    0.9
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
    $IntervalString = if ($UpdaterConfig.CheckInterval) { $UpdaterConfig.CheckInterval } else { '24:00:00' }
    $Configuration = @{
        Owner             = $UpdaterConfig.Owner
        Repository        = $UpdaterConfig.Repository
        Branch            = $UpdaterConfig.Branch
        ProfilePathInRepo = $UpdaterConfig.ProfilePathInRepo
        CheckInterval     = [TimeSpan]$IntervalString
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

    $Token = $Configuration.TokenVariable
	if (-not [string]::IsNullOrWhiteSpace($Token)) {
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

        # Update Updater.lastcheck without altering JSON formatting
		Set-JsonLastCheck -Path $ConfigFilePath -Section 'Updater'


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
    $IntervalString = if ($ConfigUpdater.CheckInterval) { $ConfigUpdater.CheckInterval } else { '24:00:00' }
    if (-not $ConfigUpdater) { return }

    $Configuration = @{
        Owner         = $ConfigUpdater.Owner
        Repository    = $ConfigUpdater.Repository
        Branch        = $ConfigUpdater.Branch
        PathInRepo    = $ConfigUpdater.ConfigPathInRepo
        CheckInterval = [TimeSpan]$IntervalString
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

	if ([string]::IsNullOrWhiteSpace($TokenVariable)) {
		Write-Warning "GitHub token not configured."
	return
	}

	if ([string]::IsNullOrWhiteSpace($Token)) {
	$Token = $TokenVariable
	}

	$Headers.Authorization = "Bearer $Token"
	
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
		Set-JsonLastCheck -Path $CurrentConfigPath -Section 'ConfigUpdater'

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
			# Validate JSON only
			$null = Get-Content -LiteralPath $TemporaryPath -Raw | ConvertFrom-Json

			# Update timestamp without changing formatting
			Set-JsonLastCheck -Path $TemporaryPath -Section 'ConfigUpdater'
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

function Set-JsonLastCheck {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$Section,

        [string]$Timestamp = ([DateTime]::UtcNow.ToString('o'))
    )

    $Content = Get-Content -LiteralPath $Path -Raw

    $SectionStart = $Content.IndexOf("`"$Section`"")

    if ($SectionStart -lt 0) {
        throw "Section '$Section' not found."
    }

    $LastCheckPos = $Content.IndexOf('"lastcheck"', $SectionStart)

    if ($LastCheckPos -lt 0) {
        throw "'lastcheck' not found in section '$Section'."
    }

    $ValueStart = $Content.IndexOf('"', $Content.IndexOf(':', $LastCheckPos)) + 1
    $ValueEnd   = $Content.IndexOf('"', $ValueStart)

    if ($ValueStart -lt 1 -or $ValueEnd -lt 0) {
        throw "Could not locate lastcheck value in section '$Section'."
    }

    $Content = $Content.Substring(0, $ValueStart) +
               $Timestamp +
               $Content.Substring($ValueEnd)

    Set-Content -LiteralPath $Path -Value $Content -Encoding UTF8
}

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
        Displays help for MegaShell profile functions.
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
        Write-Host "`n=== MegaShell Functions ===" -ForegroundColor Cyan
        
        $ProfilePath = $Global:Config.Settings.ProfilePath
        
        # Retrieve all functions loaded directly from the profile script file
		Write-Host "This is still on my toDo list, I'll write some help documentation soon"
        
        Write-Host "`nRun 'Profile-Help <FunctionName>' for detailed syntax.`n" -ForegroundColor DarkGray
    }
}



# === [Profile Setup] ===

try {
    $Global:Config = Get-ProfileConfig
} catch {
    Write-Host "`n[!] Profile initialization aborted: $($_.Exception.Message)`n" -ForegroundColor Red
    return
}

Update-MegaShellProfile
Update-ProfileConfig
Resolve-ConfigSecrets -Object $Global:Config # Replace SECRET placeholders with actual values
$env:PATH += "$($Config.Settings.ScriptRoot);" # Add the folder with PowerShell scripts to the PATH
$host.ui.RawUI.WindowTitle = $Config.Settings.WindowTitle # Rename the Titlebar/Tab


# === [Dot source external scripts] ===

if ($Global:Config.DotSourceFiles) {
	Write-Host "Dot-sourcing scripts...`n" -ForegroundColor DarkGray
    $DefaultRoot = $Global:Config.Settings.ScriptRoot

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

$MegaBanner = @"
 ██████   ██████                              █████████  █████               ████  ████ 
░░██████ ██████                              ███░░░░░███░░███               ░░███ ░░███ 
 ░███░█████░███   ██████   ███████  ██████  ░███    ░░░  ░███████    ██████  ░███  ░███ 
 ░███░░███ ░███  ███░░███ ███░░███ ░░░░░███ ░░█████████  ░███░░███  ███░░███ ░███  ░███ 
 ░███ ░░░  ░███ ░███████ ░███ ░███  ███████  ░░░░░░░░███ ░███ ░███ ░███████  ░███  ░███ 
 ░███      ░███ ░███░░░  ░███ ░███ ███░░███  ███    ░███ ░███ ░███ ░███░░░   ░███  ░███ 
 █████     █████░░██████ ░░███████░░████████░░█████████  ████ █████░░██████  █████ █████
░░░░░     ░░░░░  ░░░░░░   ░░░░░███ ░░░░░░░░  ░░░░░░░░░  ░░░░ ░░░░░  ░░░░░░  ░░░░░ ░░░░░ 
                          ███ ░███                                                      
                         ░░██████                                                       
                          ░░░░░░                                                         
						  
"@

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
    if ($Global:Config.Features.ExternalBanner) {
        Write-Host " "
		Write-ColorMappedArt -Text $BannerArt -Theme "Standard"
		Write-Host " "
    }
    else {
        Write-Host " "
		Write-ColorMappedArt -Text $MegaBanner -Theme "Standard"
		Write-Host " "
    }
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