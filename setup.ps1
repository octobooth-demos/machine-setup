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

$script:configPath = Join-Path $PSScriptRoot "config.json"
$script:failedItems = @()
$script:ForceReinstall = $env:FORCE_REINSTALL -eq "true"

# winget (and the installers it invokes) return non-zero exit codes for
# conditions that are not actual failures. Treat these as success so the
# script doesn't report false failures.
$script:WingetSuccessExitCodes = @(
    0,           # Success
    -1978335189, # 0x8A15002B APPINSTALLER_CLI_ERROR_UPDATE_NOT_APPLICABLE (already up to date)
    -1978335135, # 0x8A150061 APPINSTALLER_CLI_ERROR_PACKAGE_ALREADY_INSTALLED
    3010,        # ERROR_SUCCESS_REBOOT_REQUIRED (installer succeeded, reboot needed)
    1641         # ERROR_SUCCESS_REBOOT_INITIATED
)

function Test-ShouldSkipInstalled { return -not $script:ForceReinstall }

# ----------------------------------------
# Logging Helpers
# ----------------------------------------

function Write-Info    { param([string]$Message) Write-Host "ℹ️  $Message" -ForegroundColor Blue }
function Write-Success { param([string]$Message) Write-Host "✅ $Message" -ForegroundColor Green }
function Write-Warn    { param([string]$Message) Write-Host "⚠️  $Message" -ForegroundColor Yellow }
function Write-Err     { param([string]$Message) Write-Host "❌ $Message" -ForegroundColor Red }

function Invoke-SafeInstall {
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
    if (-not (Test-Path $script:configPath)) {
        Write-Err "Config file not found: $script:configPath"
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
    $script:config = Get-Content -Raw -Path $script:configPath | ConvertFrom-Json
}

# ----------------------------------------
# Function Definitions
# ----------------------------------------

# Note: winget install is idempotent — no need to pre-check installed packages.
function Install-WingetPackage {
    param([string]$PackageId)

    $description = "winget: $PackageId"
    try {
        $output = winget install --id $PackageId -e --accept-source-agreements --accept-package-agreements --silent 2>&1
        $exitCode = $LASTEXITCODE

        if ($script:WingetSuccessExitCodes -contains $exitCode) {
            Write-Success "Installed: $PackageId"
        }
        else {
            $script:failedItems += $description
            Write-Err "Failed: $description (exit code: $exitCode)"
            if ($output) { Write-Host ($output | Out-String).TrimEnd() }
        }
    }
    catch {
        $script:failedItems += $description
        Write-Err "Failed: $description - $_"
    }
}

function Install-Packages {
    Write-Info "Installing packages via winget..."

    foreach ($package in $config.windows.packages) {
        Install-WingetPackage -PackageId $package
    }

    # Refresh PATH so newly installed tools are available
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")

    Write-Success "Package installation complete"
}

function Start-PostInstallApps {
    $apps = $config.windows.post_install_launch

    if ($null -eq $apps -or $apps.Count -eq 0) {
        return
    }

    Write-Info "Launching post-install apps..."

    foreach ($app in $apps) {
        Write-Info "Opening $app..."

        try {
            Start-Process $app
        }
        catch {
            Write-Warn "Could not open $app"
        }
    }
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

    $installedExts = @()
    if (Test-ShouldSkipInstalled) {
        $rawExts = & $Command --list-extensions 2>&1
        if ($rawExts) {
            $installedExts = $rawExts | ForEach-Object { $_.ToLower() }
        }
    }

    foreach ($ext in $config.shared.vs_code_extensions) {
        if ((Test-ShouldSkipInstalled) -and ($installedExts -contains $ext.ToLower())) {
            Write-Success "Already installed: $ext ($Name extension)"
            continue
        }

        # Attempt install; handle built-in conflicts gracefully
        # (e.g., Copilot is now bundled in VS Code/Insiders)
        try {
            $output = & $Command --install-extension $ext 2>&1
            if ($LASTEXITCODE -ne 0) {
                if ($output -match "built-in extension") {
                    Write-Success "Built-in: $ext ($Name), skipping..."
                } else {
                    $script:failedItems += "$Name extension: $ext"
                    Write-Err "Failed: $Name extension: $ext"
                }
            }
        }
        catch {
            $script:failedItems += "$Name extension: $ext"
            Write-Err "Failed: $Name extension: $ext - $_"
        }
    }
}

function Install-GHExtension {
    param([string]$Extension)

    $description = "gh extension: $Extension"
    try {
        $output = gh extension install $Extension 2>&1
        $exitCode = $LASTEXITCODE
        $text = ($output | Out-String)

        if ($exitCode -eq 0) {
            Write-Success "Installed: $Extension (gh extension)"
        }
        elseif ($text -match 'already installed' -or $text -match 'already exists' -or $text -match 'there is already an installed extension') {
            Write-Success "Already installed: $Extension (gh extension)"
        }
        elseif ($text -match 'unsupported for') {
            # Precompiled extensions may not ship a binary for every architecture
            # (e.g. windows-arm64). This isn't fixable here, so skip rather than fail.
            Write-Warn "Skipped: $Extension (gh extension) - not supported on this architecture"
        }
        else {
            $script:failedItems += $description
            Write-Err "Failed: $description (exit code: $exitCode)"
            if ($text.Trim()) { Write-Host $text.TrimEnd() }
        }
    }
    catch {
        $script:failedItems += $description
        Write-Err "Failed: $description - $_"
    }
}

function Install-GHExtensions {
    $ghExists = Get-Command gh -ErrorAction SilentlyContinue
    if ($null -eq $ghExists) {
        Write-Warn "GitHub CLI is not available in PATH. Can't install extensions."
        return
    }

    Write-Info "Installing GitHub CLI extensions..."

    $installedExts = @()
    if (Test-ShouldSkipInstalled) {
        $rawList = gh extension list 2>&1
        if ($LASTEXITCODE -eq 0 -and $rawList) {
            $installedExts = $rawList | ForEach-Object { ($_ -split '\t')[1] } | Where-Object { $_ }
        }
    }

    foreach ($ext in $config.shared.gh_cli_extensions) {
        if ((Test-ShouldSkipInstalled) -and ($installedExts -contains $ext)) {
            Write-Success "Already installed: $ext (gh extension)"
            continue
        }

        Install-GHExtension -Extension $ext
    }
}

function Set-VLCConfiguration {
    Write-Info "Configuring VLC settings..."
    $vlcConfigPath = "$env:APPDATA\vlc\vlcrc"
    Stop-Process -Name "vlc" -ErrorAction SilentlyContinue

    if ((Test-ShouldSkipInstalled) -and (Test-Path $vlcConfigPath)) {
        if (Select-String -Path $vlcConfigPath -Pattern "Setup-script-configured=true" -Quiet) {
            Write-Info "VLC settings already configured, skipping..."
            return
        }
    } else {
        New-Item -Path (Split-Path $vlcConfigPath) -ItemType Directory -Force | Out-Null
        New-Item -Path $vlcConfigPath -ItemType File -Force | Out-Null
    }

    Add-Content -Path $vlcConfigPath -Value "# Setup-script-configured=true"
    Add-Content -Path $vlcConfigPath -Value $config.shared.vlc_settings

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

    $settings = Get-Content -Raw -Path $settingsPath | ConvertFrom-Json
    $settings | Add-Member -NotePropertyName "workbench.colorTheme" -NotePropertyValue $config.shared.vscode_theme -Force
    $settings | ConvertTo-Json -Depth 10 | Out-File -FilePath $settingsPath -Force -Encoding UTF8
}

function Initialize-Editors {
    foreach ($editor in $config.windows.editors) {
        Install-EditorExtensions -Name $editor.name -Command $editor.command
        Set-EditorTheme -Name $editor.name -SettingsDir $editor.settings_dir
    }

    Write-Success "Editor configuration complete"
}

function Connect-GH {
    $ghExists = Get-Command gh -ErrorAction SilentlyContinue
    if ($null -eq $ghExists) {
        Write-Warn "GitHub CLI not found, skipping authentication."
        return
    }

    gh auth status 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Info "Please authenticate with GitHub..."
        gh auth login --web
    }

    gh auth status 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Install-GHExtensions
        Write-Success "GitHub CLI extensions installed"
    } else {
        Write-Warn "GitHub CLI login required for extensions. Please run 'gh auth login' manually."
    }
}

function Get-EdgePath {
    $candidatePaths = @(
        @(
            (Join-Path ${env:ProgramFiles(x86)} "Microsoft\Edge\Application\msedge.exe"),
            (Join-Path $env:ProgramFiles "Microsoft\Edge\Application\msedge.exe")
        ) | Where-Object { $_ -and (Test-Path $_) }
    )

    if ($candidatePaths.Count -gt 0) {
        return $candidatePaths[0]
    }

    $edgeCommand = Get-Command msedge -ErrorAction SilentlyContinue
    if ($null -ne $edgeCommand) {
        return $edgeCommand.Source
    }

    return $null
}

function Connect-GitHubWeb {
    Write-Info "Opening GitHub.com in Microsoft Edge..."
    $edgePath = Get-EdgePath

    $opened = $false
    if ($null -ne $edgePath) {
        try {
            Start-Process -FilePath $edgePath -ArgumentList "https://github.com"
            $opened = $true
        }
        catch {
            Write-Warn "Could not launch Microsoft Edge ($edgePath): $_"
        }
    }

    if (-not $opened) {
        Write-Warn "Falling back to the default browser."
        try {
            Start-Process "https://github.com"
        }
        catch {
            Write-Warn "Could not open a browser automatically. Please open https://github.com manually."
        }
    }

    Write-Info "Please log in to GitHub.com in your browser with the demo account"
    [void](Read-Host "Press Enter once you have logged in")
    Write-Success "GitHub web authentication confirmed"
}

function Copy-Repos {
    $reposDir = Join-Path $env:USERPROFILE "repos"

    $repos = $config.shared.repos_to_clone
    if ($null -eq $repos -or $repos.Count -eq 0) {
        return
    }

    Write-Info "Cloning repos into $reposDir..."

    if (-not (Test-Path $reposDir)) {
        New-Item -Path $reposDir -ItemType Directory -Force | Out-Null
    }

    foreach ($repo in $repos) {
        $repoName = ($repo -split '/')[-1]
        $target = Join-Path $reposDir $repoName

        if ((Test-ShouldSkipInstalled) -and (Test-Path $target)) {
            Write-Info "$repoName already exists, skipping..."
        } else {
            Invoke-SafeInstall -Description "clone: $repo" -Action {
                gh repo clone $repo $target 2>&1
            }
        }
    }
}

function Register-MCPServers {
    Write-Info "Registering MCP servers for Copilot CLI..."

    $copilotHome = if ($env:COPILOT_HOME) { $env:COPILOT_HOME } else { Join-Path $env:USERPROFILE ".copilot" }
    $mcpConfigPath = Join-Path $copilotHome "mcp-config.json"

    # Create config directory if needed
    if (-not (Test-Path $copilotHome)) {
        New-Item -Path $copilotHome -ItemType Directory -Force | Out-Null
    }

    # Start with existing config or empty object
    if (Test-Path $mcpConfigPath) {
        $mcpConfig = Get-Content -Raw -Path $mcpConfigPath | ConvertFrom-Json
    } else {
        $mcpConfig = [PSCustomObject]@{ mcpServers = [PSCustomObject]@{} }
    }

    if ($null -eq $mcpConfig.mcpServers) {
        $mcpConfig | Add-Member -NotePropertyName "mcpServers" -NotePropertyValue ([PSCustomObject]@{}) -Force
    }

    foreach ($server in $config.shared.mcp_servers) {
        $serverConfig = if ($server.type -eq "local") {
            [PSCustomObject]@{
                tools   = @("*")
                type    = $server.type
                command = $server.command
                args    = @($server.args)
            }
        } else {
            [PSCustomObject]@{
                tools   = @("*")
                type    = $server.type
                url     = $server.url
                headers = [PSCustomObject]@{}
            }
        }

        $mcpConfig.mcpServers | Add-Member -NotePropertyName $server.name -NotePropertyValue $serverConfig -Force
        Write-Success "Registered MCP server: $($server.name)"
    }

    $mcpConfig | ConvertTo-Json -Depth 10 | Out-File -FilePath $mcpConfigPath -Force -Encoding UTF8
    Write-Success "MCP servers written to $mcpConfigPath"
}

function Get-DesktopPath {
    if ($env:SETUP_SCRIPT_DESKTOP_PATH) {
        return $env:SETUP_SCRIPT_DESKTOP_PATH
    }

    $desktopPath = [Environment]::GetFolderPath([Environment+SpecialFolder]::Desktop)
    if ($desktopPath) {
        return $desktopPath
    }

    if ($env:USERPROFILE) {
        return (Join-Path $env:USERPROFILE "Desktop")
    }

    return [Environment]::GetFolderPath("Desktop")
}

function New-DemoLoader {
    Write-Info "Creating demo loader script..."
    $desktopPath = Get-DesktopPath
    $demoScript = Join-Path $desktopPath "load-demos.ps1"
    New-Item -Path $desktopPath -ItemType Directory -Force | Out-Null

    $lines = @()
    $lines += "Write-Host 'Loading demo environment...' -ForegroundColor Blue"
    $lines += ""

    # Add demo sites
    $lines += "# Open demo sites"
    foreach ($url in $config.shared.demo_sites) {
        $lines += "Start-Process '$url'"
        $lines += "Start-Sleep -Seconds 1"
    }
    $lines += ""

    # Add editors from config
    $lines += "# Open editors"
    foreach ($editor in $config.windows.editors) {
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

function Invoke-Main {
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

    # Launch post-install apps
    Start-PostInstallApps

    # Web authentication (Edge is preinstalled on Windows)
    Connect-GitHubWeb

    # Setup environments
    Connect-GH
    Copy-Repos

    # PWA setup is intentionally disabled until the booth workflow needs it again.
    # See README for the rationale and re-enable notes.
    # Install-PWAs

    # Install extensions and configure themes
    Initialize-Editors

    # Register MCP servers for Copilot CLI
    Register-MCPServers

    # Create demo loader script
    New-DemoLoader

    # Print summary and finish
    Write-Summary
    if ($script:failedItems.Count -gt 0) {
        Write-Warn "Script completed with $($script:failedItems.Count) failure(s)"
        exit 1
    }
    Write-Success "Script completed successfully"
}

if ($MyInvocation.InvocationName -ne ".") {
    Invoke-Main
}
