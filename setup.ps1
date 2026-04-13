<#
.SYNOPSIS
    Sets up a Windows machine based on the needs for demoing at a booth.

.DESCRIPTION
    This script automates the installation and configuration of a complete
    development environment including VS Code, GitHub tooling, and related utilities.
    It handles software installation, extension setup, and environment configuration.

.EXAMPLE
    .\setup.ps1
    Installs and configures the complete development environment

.NOTES
    Requires:
    - Windows 10/11
    - winget package manager
    - Administrative privileges
    - Internet connection
#>

# ----------------------------------------
# Constants
# ----------------------------------------

$configPath = Join-Path $PSScriptRoot "config.json"
$script:failedItems = @()

# ----------------------------------------
# Logging Helpers
# ----------------------------------------

function Write-Info    { param([string]$Message) Write-Host "ℹ️  $Message" -ForegroundColor Blue }
function Write-Success { param([string]$Message) Write-Host "✅ $Message" -ForegroundColor Green }
function Write-Warn    { param([string]$Message) Write-Host "⚠️  $Message" -ForegroundColor Yellow }
function Write-Err     { param([string]$Message) Write-Host "❌ $Message" -ForegroundColor Red }

function Try-Install {
    param(
        [string]$Description,
        [scriptblock]$Action
    )

    try {
        & $Action
        if ($LASTEXITCODE -ne 0 -and $null -ne $LASTEXITCODE) {
            $script:failedItems += $Description
            Write-Err "Failed: $Description"
        }
    }
    catch {
        $script:failedItems += $Description
        Write-Err "Failed: $Description - $_"
    }
}

function Write-Summary {
    if ($script:failedItems.Count -gt 0) {
        Write-Host ""
        Write-Warn "The following items failed to install:"
        foreach ($item in $script:failedItems) {
            Write-Warn "  - $item"
        }
        Write-Host ""
    }
}

# ----------------------------------------
# Bootstrap
# ----------------------------------------

function Test-Prerequisites {
    # Check for admin privileges
    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if ($isAdmin) {
        Write-Success "Running with Administrator privileges"
    } else {
        Write-Warn "Not running with Administrator privileges. Some operations may fail."
        Write-Warn "Consider restarting with 'Run as Administrator'"
    }

    # Verify config.json exists
    if (-not (Test-Path $configPath)) {
        Write-Err "Config file not found: $configPath"
        return $false
    }
    Write-Success "config.json found"

    # Verify winget is available
    try {
        $wingetVersion = winget --version
        Write-Success "winget is available (version: $wingetVersion)"
    }
    catch {
        Write-Err "winget not found. Please install App Installer from Microsoft Store."
        return $false
    }

    return $true
}

function Import-Config {
    $script:config = Get-Content -Raw -Path $configPath | ConvertFrom-Json
}

# ----------------------------------------
# Function Definitions
# ----------------------------------------

function Install-Packages {
    Write-Info "Installing packages via winget..."

    foreach ($package in $config.winget_packages) {
        Try-Install -Description "winget: $($package.name)" -Action {
            winget install --id $package.id -e --accept-source-agreements --accept-package-agreements --silent 2>&1
        }
    }

    # Refresh PATH so newly installed tools are available
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
}

function Install-EditorExtensions {
    param(
        [string]$Name,
        [string]$Command
    )

    $commandExists = Get-Command $Command -ErrorAction SilentlyContinue
    if ($null -eq $commandExists) {
        Write-Warn "$Name is not available in PATH. Can't install extensions."
        return
    }

    Write-Info "Installing $Name extensions..."
    foreach ($ext in $config.vs_code_extensions) {
        Try-Install -Description "$Name extension: $ext" -Action {
            & $Command --install-extension $ext 2>&1
        }
    }
}

function Install-GHExtensions {
    $ghExists = Get-Command gh -ErrorAction SilentlyContinue
    if ($null -eq $ghExists) {
        Write-Warn "GitHub CLI is not available in PATH. Can't install extensions."
        return
    }

    Write-Info "Installing GitHub CLI extensions..."
    foreach ($ext in $config.gh_cli_extensions) {
        Try-Install -Description "gh extension: $ext" -Action {
            gh extension install $ext 2>&1
        }
    }
}

function Set-VLCConfiguration {
    Write-Info "Configuring VLC settings..."
    $vlcConfigPath = "$env:APPDATA\vlc\vlcrc"

    if (Test-Path $vlcConfigPath) {
        if (Select-String -Path $vlcConfigPath -Pattern "Setup-script-configured=true" -Quiet) {
            Write-Info "VLC settings already configured, skipping..."
            return
        }
    } else {
        New-Item -Path (Split-Path $vlcConfigPath) -ItemType Directory -Force | Out-Null
        New-Item -Path $vlcConfigPath -ItemType File -Force | Out-Null
    }

    Add-Content -Path $vlcConfigPath -Value "# Setup-script-configured=true"
    Add-Content -Path $vlcConfigPath -Value $config.vlc_settings

    Write-Success "VLC settings configured - please restart VLC"
}

function Set-EditorTheme {
    param(
        [string]$Name,
        [string]$SettingsDir
    )

    Write-Info "Setting $Name theme..."
    $settingsPath = "$env:APPDATA\$SettingsDir\User\settings.json"

    if (-not (Test-Path $settingsPath)) {
        New-Item -Path (Split-Path $settingsPath) -ItemType Directory -Force | Out-Null
        "{}" | Out-File -FilePath $settingsPath -Encoding UTF8
    }

    $settings = Get-Content -Path $settingsPath | ConvertFrom-Json
    $settings | Add-Member -NotePropertyName "workbench.colorTheme" -NotePropertyValue $config.vscode_theme -Force
    $settings | ConvertTo-Json -Depth 10 | Out-File -FilePath $settingsPath -Force -Encoding UTF8
}

function Configure-Editors {
    foreach ($editor in $config.vscode_editors) {
        Install-EditorExtensions -Name $editor.name -Command $editor.command
        Set-EditorTheme -Name $editor.name -SettingsDir $editor.windows_settings_dir
    }
}

function Authenticate-GH {
    $ghExists = Get-Command gh -ErrorAction SilentlyContinue
    if ($null -eq $ghExists) {
        Write-Warn "GitHub CLI not found, skipping authentication."
        return
    }

    if (-not (gh auth status 2>&1 | Out-Null; $LASTEXITCODE -eq 0)) {
        Write-Info "Please authenticate with GitHub..."
        gh auth login
    }

    if (gh auth status 2>&1 | Out-Null; $LASTEXITCODE -eq 0) {
        Install-GHExtensions
        Write-Success "GitHub CLI extensions installed"
    } else {
        Write-Warn "GitHub CLI login required for extensions. Please run 'gh auth login' manually."
    }
}

function Install-PWAs {
    Write-Info "Opening required websites for PWA installation..."

    foreach ($site in $config.pwa_sites) {
        Write-Info "Installing PWA for $($site.name)..."
        Start-Process "msedge" "--install-webapp=$($site.url)"
        Read-Host "Press Enter after you have added the PWA for $($site.name) in Edge"
    }
}

function New-DemoLoader {
    Write-Info "Creating demo loader script..."
    $demoScript = [System.IO.Path]::Combine([Environment]::GetFolderPath('Desktop'), 'load-demos.ps1')

    $lines = @()
    $lines += "#!/usr/bin/env pwsh"
    $lines += "Write-Host 'Loading demo environment...' -ForegroundColor Blue"
    $lines += ""

    # Add demo sites
    $lines += "# Open demo sites"
    foreach ($url in $config.demo_sites) {
        $lines += "Start-Process '$url'"
        $lines += "Start-Sleep -Seconds 1"
    }
    $lines += ""

    # Add editors from config
    $lines += "# Open editors"
    foreach ($editor in $config.vscode_editors) {
        $lines += "& $($editor.command)"
    }
    $lines += ""

    # Add VLC
    $lines += "# Open VLC"
    $lines += 'Start-Process "vlc" -ArgumentList "$env:USERPROFILE\Videos"'
    $lines += ""
    $lines += "Write-Host 'Demo environment loaded!' -ForegroundColor Green"

    $lines -join "`n" | Out-File -FilePath $demoScript -Force -Encoding UTF8

    Write-Success "Created demo loader script at $demoScript"
}

# ----------------------------------------
# Main Execution
# ----------------------------------------

$ErrorActionPreference = "Continue"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Starting setup script - $(Get-Date)"    -ForegroundColor Cyan
Write-Host "Running from: $PSScriptRoot"             -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

# Bootstrap
if (-not (Test-Prerequisites)) { return }
Import-Config

# Install packages
Install-Packages
Set-VLCConfiguration

# Setup environments
Authenticate-GH
Install-PWAs

# Install extensions and configure themes
Configure-Editors

# Create demo loader script
New-DemoLoader

# Print summary and finish
Write-Summary
Write-Success "Script completed successfully"
