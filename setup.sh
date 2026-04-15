#!/bin/bash
#
# Setup script for GitHub development environment
# Installs and configures VS Code, VS Code Insiders, and GitHub tooling
#

# ----------------------------------------
# Constants
# ----------------------------------------

# Colors
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly RED='\033[0;31m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Emojis
readonly CHECK="✅"
readonly WARN="⚠️"
readonly INFO="ℹ️"
readonly ERROR="❌"

readonly CONFIG_FILE="$(cd "$(dirname "$0")" && pwd)/config.json"

# Mutable state
failed_items=()

# ----------------------------------------
# Logging Helpers
# ----------------------------------------

log_info()    { echo -e "${BLUE}${INFO} $1${NC}"; }
log_success() { echo -e "${GREEN}${CHECK} $1${NC}"; }
log_warn()    { echo -e "${YELLOW}${WARN} $1${NC}"; }
log_error()   { echo -e "${RED}${ERROR} $1${NC}"; }

# Runs a command and tracks failures without stopping the script
# $1 = description for error reporting, remaining args = command to run
try_install() {
    local description="$1"
    shift

    if ! "$@" 2>&1; then
        failed_items+=("$description")
        log_error "Failed: $description"
    fi
}

# Prints a summary of any failed installations
print_summary() {
    if [[ ${#failed_items[@]} -gt 0 ]]; then
        echo ""
        log_warn "The following items failed to install:"
        for item in "${failed_items[@]}"; do
            log_warn "  - $item"
        done
        echo ""
    fi
}

# ----------------------------------------
# Bootstrap
# ----------------------------------------

# Installs Homebrew if not present and updates it
install_homebrew() {
    if ! command -v brew &> /dev/null; then
        log_info "Installing Homebrew..."
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    else
        log_success "Homebrew is already installed"
    fi

    log_info "Updating Homebrew..."
    brew update
}

# Ensures jq is installed (required to read config.json)
install_jq() {
    if ! command -v jq &> /dev/null; then
        log_info "Installing jq..."
        brew install jq
    fi
}

# Load configuration from JSON file (called after jq is available)
load_config() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        log_error "Config file not found: $CONFIG_FILE"
        exit 1
    fi

    readonly VSCODE_THEME=$(jq -r '.shared.vscode_theme' "$CONFIG_FILE")
    readonly VLC_SETTINGS=$(jq -r '.shared.vlc_settings' "$CONFIG_FILE")

    mapfile -t vs_code_extensions < <(jq -r '.shared.vs_code_extensions[]' "$CONFIG_FILE")
    mapfile -t gh_cli_extensions < <(jq -r '.shared.gh_cli_extensions[]' "$CONFIG_FILE")
    mapfile -t brew_casks < <(jq -r '.mac.packages.casks[]' "$CONFIG_FILE")
    mapfile -t brew_formulas < <(jq -r '.mac.packages.formulas[]' "$CONFIG_FILE")
    mapfile -t pwa_names < <(jq -r '.shared.pwa_sites[].name' "$CONFIG_FILE")
    mapfile -t pwa_urls < <(jq -r '.shared.pwa_sites[].url' "$CONFIG_FILE")
    mapfile -t demo_sites < <(jq -r '.shared.demo_sites[]' "$CONFIG_FILE")
}

# ----------------------------------------
# Function Definitions
# ----------------------------------------

# Configures VLC settings to hide filename display and enable loop by default
configure_vlc() {
    log_info "Configuring VLC settings..."

    local pref_file="$HOME/Library/Preferences/org.videolan.vlc/vlcrc"
    mkdir -p "$(dirname "$pref_file")"

    # Check if we've already configured settings
    if grep -q "# Setup-script-configured=true" "$pref_file" 2>/dev/null; then
        log_info "VLC settings already configured, skipping..."
        return
    fi

    # Kill VLC if running
    killall VLC 2>/dev/null || true

    # Add our sentinel and settings
    {
        echo "# Setup-script-configured=true"
        echo "$VLC_SETTINGS"
    } >> "$pref_file"

    log_success "VLC settings configured - please restart VLC"
}

# Installs all Brew casks and formulas from config.json
install_packages() {
    log_info "Installing Brew casks..."
    for cask in "${brew_casks[@]}"; do
        try_install "brew cask: $cask" brew install --cask "$cask"
    done

    log_info "Installing Brew formulas..."
    for formula in "${brew_formulas[@]}"; do
        try_install "brew formula: $formula" brew install "$formula"
    done
}

# Installs a suite of GitHub CLI extensions for enhanced functionality
install_gh_extensions() {
    log_info "Installing GitHub CLI extensions..."
    for ext in "${gh_cli_extensions[@]}"; do
        try_install "gh extension: $ext" gh extension install "$ext"
    done
}

# Launches apps that need to run after package installation
launch_post_install_apps() {
    mapfile -t post_install_apps < <(jq -r '.mac.post_install_launch[]' "$CONFIG_FILE")

    if [[ ${#post_install_apps[@]} -eq 0 ]]; then
        return
    fi

    log_info "Launching post-install apps..."

    for app in "${post_install_apps[@]}"; do
        log_info "Opening $app..."
        open -a "$app" || log_warn "Could not open $app"
    done
}

# Installs VS Code extensions for a given editor
# $1 = display name, $2 = binary path
install_vscode_extensions() {
    local name="$1"
    local binary="$2"

    log_info "Installing $name extensions..."

    if ! "$binary" --version &> /dev/null; then
        log_error "Error: $name binary not found"
        return 1
    fi

    for ext in "${vs_code_extensions[@]}"; do
        try_install "$name extension: $ext" "$binary" --install-extension "$ext"
    done
}

# Ensures user is authenticated with GitHub CLI and installs extensions if authenticated
authenticate_gh() {
    if command -v gh &> /dev/null; then
        if ! gh auth status &> /dev/null; then
            log_info "Please login to GitHub CLI first..."
            gh auth login
        fi

        if gh auth status &> /dev/null; then
            install_gh_extensions
            log_success "GitHub CLI extensions installed"
        else
            log_warn "GitHub CLI login required for installing extensions. Please run 'gh auth login' manually."
        fi
    fi
}

# Guides user through GitHub web authentication process using Chrome
authenticate_github_web() {
    log_info "Opening GitHub.com in Chrome..."
    open -a "Google Chrome" https://github.com

    log_info "Please log in to GitHub.com in Chrome with the demo account"
    log_info "Press Enter once you have logged in..."
    read -r

    log_success "GitHub web authentication confirmed"
}

# Assists user in setting up Progressive Web Apps (PWAs)
install_pwas() {
    log_info "Opening required websites in Chrome..."

    for i in "${!pwa_urls[@]}"; do
        open -a "Google Chrome" "${pwa_urls[$i]}"
        log_info "Please manually add ${pwa_names[$i]} (${pwa_urls[$i]}) as a PWA by:"
        log_info "1. Click the three-dot menu in Chrome"
        log_info "2. Select 'Install page as app...'"
        log_info "Press Enter when done..."
        read -r
    done
}

# Sets the VS Code theme for a given editor
# $1 = display name, $2 = settings dir name (e.g. "Code" or "Code - Insiders")
configure_vscode_theme() {
    local name="$1"
    local settings_dir="$2"
    local settings_file="$HOME/Library/Application Support/$settings_dir/User/settings.json"

    log_info "Setting $name theme..."
    mkdir -p "$(dirname "$settings_file")"

    if [[ ! -f "$settings_file" ]]; then
        echo "{\"workbench.colorTheme\": \"$VSCODE_THEME\"}" > "$settings_file"
    else
        local tmp_file
        tmp_file=$(mktemp)
        jq ". + {\"workbench.colorTheme\": \"$VSCODE_THEME\"}" "$settings_file" > "$tmp_file"
        mv "$tmp_file" "$settings_file"
    fi
}

# Installs extensions and configures themes for all editors in config.json
configure_editors() {
    local editor_count
    editor_count=$(jq '.mac.editors | length' "$CONFIG_FILE")

    for i in $(seq 0 $((editor_count - 1))); do
        local editor_name editor_binary editor_settings_dir
        editor_name=$(jq -r ".mac.editors[$i].name" "$CONFIG_FILE")
        editor_binary=$(jq -r ".mac.editors[$i].binary" "$CONFIG_FILE")
        editor_settings_dir=$(jq -r ".mac.editors[$i].settings_dir" "$CONFIG_FILE")

        install_vscode_extensions "$editor_name" "$editor_binary"
        configure_vscode_theme "$editor_name" "$editor_settings_dir"
    done
}

# Creates a demo loader script to launch all required applications and sites
create_demo_loader() {
    log_info "Creating demo loader script..."
    local demo_script="$HOME/Desktop/load-demos.sh"

    # Create the script header
    cat > "$demo_script" << 'EOF'
#!/bin/bash

EOF

    # Add the sites dynamically
    echo "# Open all required sites in Chrome" >> "$demo_script"
    printf 'open -a "Google Chrome" %s\n\n' "$(printf '"%s" ' "${demo_sites[@]}")" >> "$demo_script"

    # Add the remaining standard content
    cat >> "$demo_script" << 'EOF'
# Open VS Code and VS Code Insiders
open -a "Visual Studio Code"
open -a "Visual Studio Code - Insiders"

# Open VLC pointing to Videos folder
open -a VLC "$HOME/Videos"
EOF

    chmod +x "$demo_script"
    log_success "Created demo loader script at $demo_script"
}

# ----------------------------------------
# Main Execution
# ----------------------------------------

# Bootstrap: install homebrew and jq before loading config
install_homebrew
install_jq
load_config

# Initial web authentication
authenticate_github_web

# Install packages
install_packages
configure_vlc

# Launch post-install apps (e.g., Docker)
launch_post_install_apps

# Setup environments
authenticate_gh
install_pwas

# Install extensions and configure themes
configure_editors

# Create demo loader script
create_demo_loader

# Print summary and finish
print_summary
log_success "Script completed successfully"
