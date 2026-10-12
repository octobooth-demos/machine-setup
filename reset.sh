#!/bin/bash
#
# Resets the macOS booth machine using the packages and resources in config.json.
#

set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly CONFIG_FILE="$SCRIPT_DIR/config.json"

usage() {
    echo "Usage: $0 [--yes]" >&2
}

yes=false
while [[ $# -gt 0 ]]; do
    case "$1" in
        --yes) yes=true ;;
        *) usage; exit 2 ;;
    esac
    shift
done

if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "Config file not found: $CONFIG_FILE" >&2
    exit 1
fi
if ! command -v jq >/dev/null 2>&1; then
    echo "jq is required to read config.json" >&2
    exit 1
fi

if [[ "$yes" != true ]]; then
    echo "This will remove configured booth apps, settings, extensions, and cloned repositories."
    read -r -p "Continue? [y/N] " answer
    case "$answer" in
        [yY]|[yY][eE][sS]) ;;
        *) echo "Reset cancelled."; exit 0 ;;
    esac
fi

brew_casks=()
while IFS= read -r line; do brew_casks+=("$line"); done < <(jq -r '.mac.packages.casks[]' "$CONFIG_FILE")
brew_formulas=()
while IFS= read -r line; do brew_formulas+=("$line"); done < <(jq -r '.mac.packages.formulas[]' "$CONFIG_FILE")
gh_cli_extensions=()
while IFS= read -r line; do gh_cli_extensions+=("$line"); done < <(jq -r '.shared.gh_cli_extensions[]' "$CONFIG_FILE")
repos=()
while IFS= read -r line; do repos+=("$line"); done < <(jq -r '.shared.repos_to_clone[]' "$CONFIG_FILE")

if command -v gh >/dev/null 2>&1; then
    installed_extensions=$(gh extension list 2>/dev/null | awk '{print $2}' || true)
    for extension in "${gh_cli_extensions[@]}"; do
        if echo "$installed_extensions" | grep -Fqx "$extension"; then
            gh extension remove "$extension" || echo "Could not remove gh extension: $extension" >&2
        fi
    done
    if gh auth status >/dev/null 2>&1; then
        gh auth logout || echo "Could not log out of GitHub CLI" >&2
    fi
fi

if command -v brew >/dev/null 2>&1; then
    for cask in "${brew_casks[@]}"; do
        if brew list --cask "$cask" >/dev/null 2>&1; then
            brew uninstall --zap --cask "$cask" || echo "Could not uninstall cask: $cask" >&2
        fi
    done
    for formula in "${brew_formulas[@]}"; do
        if brew list --formula "$formula" >/dev/null 2>&1; then
            brew uninstall "$formula" || echo "Could not uninstall formula: $formula" >&2
        fi
    done
fi

for path in \
    "$HOME/Library/Application Support/Code" \
    "$HOME/Library/Application Support/Code - Insiders" \
    "$HOME/Library/Caches/com.microsoft.VSCode" \
    "$HOME/Library/Caches/com.microsoft.VSCodeInsiders" \
    "$HOME/Library/Saved Application State/com.microsoft.VSCode.savedState" \
    "$HOME/Library/Saved Application State/com.microsoft.VSCodeInsiders.savedState" \
    "$HOME/Library/Preferences/com.microsoft.VSCode.plist" \
    "$HOME/Library/Preferences/com.microsoft.VSCodeInsiders.plist" \
    "$HOME/.copilot" \
    "$HOME/.nvm" \
    "$HOME/Desktop/load-demos.sh" \
    "$HOME/Library/Preferences/org.videolan.vlc"; do
    rm -rf "$path"
done

for path in "$HOME"/.vscode*; do
    [[ -e "$path" || -L "$path" ]] || continue
    rm -rf "$path"
done

if [[ -f "$HOME/.zshrc" ]] && grep -q '^# nvm (Node Version Manager)$' "$HOME/.zshrc"; then
    tmp_file=$(mktemp)
    awk '
        /^# nvm \(Node Version Manager\)$/ { in_nvm=1; next }
        in_nvm && /nvm\/etc\/bash_completion\.d\/nvm/ { in_nvm=0; next }
        in_nvm && /NVM_DIR|nvm\.sh/ { next }
        in_nvm { in_nvm=0 }
        !in_nvm { print }
    ' "$HOME/.zshrc" > "$tmp_file"
    mv "$tmp_file" "$HOME/.zshrc"
fi

for repo in "${repos[@]}"; do
    repo_name="${repo##*/}"
    case "$repo_name" in
        ""|.|..) continue ;;
    esac
    rm -rf "$HOME/repos/$repo_name"
done

echo "Reset complete."
