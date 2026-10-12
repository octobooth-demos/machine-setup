#!/bin/bash
#
# Reset script for GitHub development environment (macOS)
# Reverses what setup.sh does, driven by config.json, so setup.sh can be
# re-run from a clean state.
#
# Usage: bash reset.sh [--yes]
#   --yes, -y   Skip the confirmation prompt
#

# ----------------------------------------
# Constants
# ----------------------------------------

readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly RED='\033[0;31m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

readonly CHECK="✅"
readonly WARN="⚠️"
readonly INFO="ℹ️"
readonly ERROR="❌"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
readonly CONFIG_FILE="$SCRIPT_DIR/config.json"

failed_items=()

log_info()    { echo -e "${BLUE}${INFO} $1${NC}"; }
log_success() { echo -e "${GREEN}${CHECK} $1${NC}"; }
log_warn()    { echo -e "${YELLOW}${WARN} $1${NC}"; }
log_error()   { echo -e "${RED}${ERROR} $1${NC}"; }

# Runs a command and tracks failures without stopping the script
# $1 = description for error reporting, remaining args = command to run
try_run() {
    local description="$1"
    shift

    if ! "$@" 2>&1; then
        failed_items+=("$description")
        log_error "Failed: $description"
    fi
}

# Removes a path if it exists (idempotent)
# $1 = path
remove_path() {
    local target="$1"

    if [[ -e "$target" || -L "$target" ]]; then
        if rm -rf "$target"; then
            log_success "Removed: $target"
        else
            failed_items+=("remove: $target")
            log_error "Failed to remove: $target"
        fi
    else
        log_info "Not found, skipping: $target"
    fi
}

# ----------------------------------------
# Config
# ----------------------------------------

load_config() {
    if ! command -v jq &> /dev/null; then
        log_error "jq is required to read config.json"
        exit 1
    fi

    if [[ ! -f "$CONFIG_FILE" ]]; then
        log_error "Config file not found: $CONFIG_FILE"
        exit 1
    fi

    # Use read loop instead of mapfile for macOS bash 3.2 compatibility
    brew_casks=()
    while IFS= read -r line; do brew_casks+=("$line"); done < <(jq -r '.mac.packages.casks[]' "$CONFIG_FILE")

    brew_formulas=()
    while IFS= read -r line; do brew_formulas+=("$line"); done < <(jq -r '.mac.packages.formulas[]' "$CONFIG_FILE")

    gh_cli_extensions=()
    while IFS= read -r line; do gh_cli_extensions+=("$line"); done < <(jq -r '.shared.gh_cli_extensions[]' "$CONFIG_FILE")

    repos=()
    while IFS= read -r line; do repos+=("$line"); done < <(jq -r '.shared.repos_to_clone[]' "$CONFIG_FILE")

    editor_settings_dirs=()
    while IFS= read -r line; do editor_settings_dirs+=("$line"); done < <(jq -r '.mac.editors[].settings_dir' "$CONFIG_FILE")
}

# ----------------------------------------
# Confirmation
# ----------------------------------------

# Prompts the user unless --yes was given; exits if not confirmed
# $1 = "true" to skip the prompt
confirm_reset() {
    local assume_yes="$1"

    if [[ "$assume_yes" == "true" ]]; then
        return
    fi

    log_warn "This will uninstall everything listed in config.json and delete:"
    log_warn "  - VS Code / VS Code Insiders user data and ~/.vscode*"
    log_warn "  - ~/.copilot and ~/.nvm"
    log_warn "  - cloned repos, the Desktop launcher and VLC settings"
    log_warn "  - GitHub CLI extensions and your gh login"
    echo -n "Type 'yes' to continue: "

    local answer=""
    read -r answer
    if [[ "$answer" != "yes" ]]; then
        log_info "Aborted. Nothing was changed."
        exit 0
    fi
}

# ----------------------------------------
# Reset steps
# ----------------------------------------

# Removes gh extensions and logs out (must run before gh is uninstalled)
reset_gh() {
    if ! command -v gh &> /dev/null; then
        log_info "gh not found, skipping GitHub CLI cleanup"
        return
    fi

    log_info "Removing GitHub CLI extensions..."
    local installed_exts
    installed_exts=$(gh extension list 2>/dev/null | awk -F'\t' '{print $2}' || true)

    for ext in "${gh_cli_extensions[@]}"; do
        if echo "$installed_exts" | grep -qx "$ext"; then
            try_run "gh extension remove: $ext" gh extension remove "$ext"
        else
            log_info "Extension not installed, skipping: $ext"
        fi
    done

    if gh auth status &> /dev/null; then
        log_info "Logging out of GitHub CLI..."
        try_run "gh auth logout" gh auth logout
    else
        log_info "Not logged in to gh, skipping logout"
    fi
}

# Uninstalls all casks and formulas from config.json
reset_packages() {
    if ! command -v brew &> /dev/null; then
        log_warn "brew not found, skipping package removal"
        return
    fi

    log_info "Uninstalling Brew casks..."
    for cask in "${brew_casks[@]}"; do
        # Chrome is often installed outside brew (MDM, manual), so it is kept
        if [[ "$cask" == "google-chrome" ]]; then
            log_info "Keeping: $cask"
            continue
        fi

        if brew list --cask "$cask" &> /dev/null; then
            try_run "brew cask: $cask" brew uninstall --zap --cask "$cask"
        else
            log_info "Cask not installed, skipping: $cask"
        fi
    done

    log_info "Uninstalling Brew formulas..."
    for formula in "${brew_formulas[@]}"; do
        if brew list --formula "$formula" &> /dev/null; then
            try_run "brew formula: $formula" brew uninstall "$formula"
        else
            log_info "Formula not installed, skipping: $formula"
        fi
    done
}

# Removes editor user data, Copilot config and nvm
reset_user_data() {
    log_info "Removing editor and tool user data..."

    for settings_dir in "${editor_settings_dirs[@]}"; do
        remove_path "$HOME/Library/Application Support/$settings_dir"
    done

    # Matches both ~/.vscode and ~/.vscode-insiders
    local vscode_dir
    for vscode_dir in "$HOME"/.vscode*; do
        remove_path "$vscode_dir"
    done

    remove_path "$HOME/.copilot"
    remove_path "$HOME/.nvm"
}

# Removes the nvm block setup.sh appends to ~/.zshrc
reset_shell_config() {
    local shell_rc="$HOME/.zshrc"

    if [[ ! -f "$shell_rc" ]] || ! grep -q 'NVM_DIR' "$shell_rc"; then
        log_info "No nvm config in $shell_rc, skipping"
        return
    fi

    local tmp_file
    tmp_file=$(mktemp)
    # shellcheck disable=SC2016
    grep -v -e '^# nvm (Node Version Manager)$' \
            -e '^export NVM_DIR="\$HOME/\.nvm"$' \
            -e 'opt/homebrew/opt/nvm/nvm\.sh' \
            -e 'opt/homebrew/opt/nvm/etc/bash_completion\.d/nvm' \
            "$shell_rc" > "$tmp_file"
    cat "$tmp_file" > "$shell_rc"
    rm -f "$tmp_file"
    log_success "Removed nvm config from $shell_rc"
}

# Removes repos that setup.sh cloned
reset_repos() {
    local repos_dir="$HOME/repos"

    for repo in "${repos[@]}"; do
        remove_path "$repos_dir/${repo##*/}"
    done
}

# Removes the demo launcher and VLC settings
reset_generated_files() {
    remove_path "$HOME/Desktop/load-demos.sh"
    remove_path "$HOME/Library/Preferences/org.videolan.vlc/vlcrc"
}

# ----------------------------------------
# Main Execution
# ----------------------------------------

main() {
    local assume_yes="false"

    for arg in "$@"; do
        case "$arg" in
            --yes|-y) assume_yes="true" ;;
            *)
                log_error "Unknown option: $arg"
                echo "Usage: bash reset.sh [--yes]"
                exit 2
                ;;
        esac
    done

    load_config
    confirm_reset "$assume_yes"

    # gh must be cleaned up before it is uninstalled
    reset_gh
    reset_packages
    reset_user_data
    reset_shell_config
    reset_repos
    reset_generated_files

    if [[ ${#failed_items[@]} -gt 0 ]]; then
        echo ""
        log_warn "The following items failed:"
        for item in "${failed_items[@]}"; do
            log_warn "  - $item"
        done
        exit 1
    fi
    log_success "Reset complete. Re-run setup.sh to set up from scratch."
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
