<#
.SYNOPSIS
    Interactive Manager for PowerShell SecretStore.
.DESCRIPTION
    Provides a text-based menu to create, list, and delete Vaults and Secrets.
    Handles module installation and initial setup automatically.
    Checks if required modules are present before running.
.NOTES
    Requires modules: Microsoft.PowerShell.SecretStore, SecretManagement
#>

function Initialize-SecretManagement {
    Write-Host "Checking requirements..." -ForegroundColor Cyan

    # Check/Install Modules
    if (-not (Get-Module -ListAvailable -Name Microsoft.PowerShell.SecretStore)) {
        Write-Warning "Module 'Microsoft.PowerShell.SecretStore' is missing."
        $choice = Read-Host "Install required modules now? (Y/N)"
        if ($choice -eq 'Y') {
            try {
                Install-Module Microsoft.PowerShell.SecretStore -Force -Scope CurrentUser -ErrorAction Stop
                Install-Module SecretManagement -Force -Scope CurrentUser -ErrorAction Stop
                Write-Host "Modules installed successfully." -ForegroundColor Green
            } catch {
                Write-Error "Failed to install modules. Check internet connection or permissions."
                exit
            }
        } else {
            Write-Error "Cannot proceed without modules."
            exit
        }
    }

    # Check/Create Default Vault
    $vaults = Get-SecretVault -ErrorAction SilentlyContinue
    if (-not $vaults) {
        Write-Warning "No Secret Vaults found."
        $choice = Read-Host "Create default local vault 'LocalStore'? (Y/N)"
        if ($choice -eq 'Y') {
            try {
                Register-SecretVault -Name LocalStore -ModuleName Microsoft.PowerShell.SecretStore -DefaultVault
                Write-Host "Vault 'LocalStore' created successfully." -ForegroundColor Green
                
                # Prompt to configure the vault immediately (password setup)
                Write-Host "Initializing vault... (You may be prompted to set a password)" -ForegroundColor Gray
                Set-SecretStoreConfiguration -Scope CurrentUser -Authentication Password -Interaction Prompt
            } catch {
                Write-Error "Failed to create vault: $($_.Exception.Message)"
            }
        }
    }
}

function Show-Menu {
    Clear-Host
    Write-Host "=== 🔒 Secret Management Console ===" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "--- Secrets ---" -ForegroundColor Yellow
    Write-Host "1. List All Secrets"
    Write-Host "2. Get/View a Secret"
    Write-Host "3. Add / Update a Secret"
    Write-Host "4. Delete a Secret"
    Write-Host ""
    Write-Host "--- Vaults ---" -ForegroundColor Yellow
    Write-Host "5. List Vaults"
    Write-Host "6. Register New Vault"
    Write-Host "7. Unregister (Delete) Vault"
    Write-Host "8. Reset/Unlock Vault (Forgot Password)"
    Write-Host ""
    Write-Host "Q. Quit"
    Write-Host "===================================="
    Write-Host ""
}

function Get-UserSelection {
    return (Read-Host "Select an option").ToUpper()
}

function Pause-Script {
    Write-Host ""
    Read-Host "Press Enter to continue..."
}

# --- Actions ---
function Action-ListSecrets {
    Write-Host "`n--- Current Secrets ---" -ForegroundColor Green
    try {
        # Check if vault is unlocked first
        if (Get-SecretVault) {
            Get-SecretInfo | Format-Table -AutoSize
        } else {
            Write-Warning "No active vault found."
        }
    } catch {
        Write-Warning "Could not list secrets. Vault might be locked or requires a password."
        Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    }
    Pause-Script
}

function Action-GetSecret {
    $name = Read-Host "Enter Secret Name"
    if ([string]::IsNullOrWhiteSpace($name)) { return }

    try {
        $secret = Get-Secret -Name $name -AsPlainText -ErrorAction Stop
        Write-Host "`nValue for '$name':" -ForegroundColor Green
        Write-Host $secret -ForegroundColor White -BackgroundColor Black
        
        $copy = Read-Host "`nCopy to clipboard? (Y/N)"
        if ($copy -eq 'Y') { 
            Set-Clipboard -Value $secret 
            Write-Host "Copied!" -ForegroundColor Gray
        }
    } catch {
        Write-Error "Secret not found or access denied."
    }
    Pause-Script
}

function Action-SetSecret {
    $name = Read-Host "Enter Secret Name (Key)"
    if ([string]::IsNullOrWhiteSpace($name)) { return }
    
    $useSecure = Read-Host "Hide input with asterisks? (Y/N)"
    
    try {
        if ($useSecure -eq 'Y') {
            $val = Read-Host "Enter Value" -AsSecureString
            Set-Secret -Name $name -Secret $val
        } else {
            $val = Read-Host "Enter Value"
            Set-Secret -Name $name -Secret $val
        }
        Write-Host "Secret '$name' saved successfully." -ForegroundColor Green
    } catch {
        Write-Error "Failed to save secret: $($_.Exception.Message)"
    }
    Pause-Script
}

function Action-DeleteSecret {
    $name = Read-Host "Enter Secret Name to DELETE"
    if ([string]::IsNullOrWhiteSpace($name)) { return }

    $confirm = Read-Host "Are you sure? (Y/N)"
    if ($confirm -eq 'Y') {
        try {
            Remove-Secret -Name $name -ErrorAction Stop
            Write-Host "Deleted '$name'." -ForegroundColor Green
        } catch {
            Write-Error "Failed to delete: $($_.Exception.Message)"
        }
    }
    Pause-Script
}

function Action-ListVaults {
    Get-SecretVault | Format-Table -AutoSize
    Pause-Script
}

function Action-RegisterVault {
    $name = Read-Host "Enter new Vault Name"
    # Defaulting to SecretStore module for simplicity
    try {
        Register-SecretVault -Name $name -ModuleName Microsoft.PowerShell.SecretStore
        Write-Host "Vault '$name' registered." -ForegroundColor Green
    } catch {
        Write-Error "Failed to register vault."
    }
    Pause-Script
}

function Action-UnregisterVault {
    $name = Read-Host "Enter Vault Name to DELETE"
    try {
        Unregister-SecretVault -Name $name -ErrorAction Stop
        Write-Host "Vault '$name' removed." -ForegroundColor Green
    } catch {
        Write-Error "Failed to remove vault."
    }
    Pause-Script
}

function Action-ResetVault {
    Write-Host "`n⚠️  DANGER ZONE ⚠️" -ForegroundColor Red
    Write-Warning "This is useful if you forgot your vault password."
    Write-Warning "Resetting the vault will PERMANENTLY DELETE ALL SECRETS inside it."
    $choice = Read-Host "Type 'RESET' to confirm wiping the local store configuration"
    
    if ($choice -eq 'RESET') {
        try {
            Reset-SecretStore
            Write-Host "Vault reset complete. Configuration cleared." -ForegroundColor Green
        } catch {
            Write-Error "Reset failed: $($_.Exception.Message)"
        }
    }
    Pause-Script
}

# --- Main Loop ---
Initialize-SecretManagement

do {
    Show-Menu
    $selection = Get-UserSelection

    switch ($selection) {
        '1' { Action-ListSecrets }
        '2' { Action-GetSecret }
        '3' { Action-SetSecret }
        '4' { Action-DeleteSecret }
        '5' { Action-ListVaults }
        '6' { Action-RegisterVault }
        '7' { Action-UnregisterVault }
        '8' { Action-ResetVault }
        'Q' { Write-Host "Goodbye!" -ForegroundColor Cyan; break }
        default { Write-Warning "Invalid selection." ; Start-Sleep -Seconds 1 }
    }
} while ($selection -ne 'Q')