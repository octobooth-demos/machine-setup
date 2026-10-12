#!/usr/bin/env bats

setup() {
    export REPO_ROOT="$BATS_TEST_DIRNAME/../.."
    export HOME="$BATS_TEST_TMPDIR/home"
    mkdir -p "$HOME"
}

@test "reset.sh asks for confirmation and can be cancelled" {
    mkdir -p "$HOME/.copilot"

    run bash "$REPO_ROOT/reset.sh"

    [ "$status" -eq 0 ]
    [[ "$output" == *"Reset cancelled."* ]]
    [ -d "$HOME/.copilot" ]
}

@test "reset.sh removes configured resources and preserves unrelated repos" {
    export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
    export RESET_LOG="$BATS_TEST_TMPDIR/commands.log"
    mkdir -p "$BATS_TEST_TMPDIR/bin"
    cat > "$BATS_TEST_TMPDIR/bin/brew" <<'EOF'
#!/bin/bash
if [[ "$1" == "list" ]]; then exit 0; fi
echo "brew $*" >> "$RESET_LOG"
EOF
    cat > "$BATS_TEST_TMPDIR/bin/gh" <<'EOF'
#!/bin/bash
if [[ "$1" == "extension" && "$2" == "list" ]]; then
    jq -r '.shared.gh_cli_extensions[] | "installed " + .' "$REPO_ROOT/config.json"
elif [[ "$1" == "auth" && "$2" == "status" ]]; then
    exit 0
else
    echo "gh $*" >> "$RESET_LOG"
fi
EOF
    chmod +x "$BATS_TEST_TMPDIR/bin/brew" "$BATS_TEST_TMPDIR/bin/gh"
    export REPO_ROOT

    mkdir -p "$HOME/Library/Application Support/Code" \
        "$HOME/Library/Application Support/Code - Insiders" \
        "$HOME/Library/Caches/com.microsoft.VSCode" "$HOME/.copilot" \
        "$HOME/.nvm" "$HOME/.vscode/extensions" "$HOME/repos/unrelated" \
        "$HOME/Desktop" "$HOME/Library/Preferences/org.videolan.vlc"
    printf 'before\n# nvm (Node Version Manager)\nexport NVM_DIR="$HOME/.nvm"\n[ -s "/opt/homebrew/opt/nvm/nvm.sh" ] && \\. "/opt/homebrew/opt/nvm/nvm.sh"\n[ -s "/opt/homebrew/opt/nvm/etc/bash_completion.d/nvm" ] && \\. "/opt/homebrew/opt/nvm/etc/bash_completion.d/nvm"\nafter\n' > "$HOME/.zshrc"
    touch "$HOME/Desktop/load-demos.sh"
    while IFS= read -r repo; do
        mkdir -p "$HOME/repos/${repo##*/}"
    done < <(jq -r '.shared.repos_to_clone[]' "$REPO_ROOT/config.json")

    run bash "$REPO_ROOT/reset.sh" --yes

    [ "$status" -eq 0 ]
    [ ! -e "$HOME/Library/Application Support/Code" ]
    [ ! -e "$HOME/Library/Application Support/Code - Insiders" ]
    [ ! -e "$HOME/.copilot" ]
    [ ! -e "$HOME/.nvm" ]
    [ ! -e "$HOME/.vscode" ]
    [ ! -e "$HOME/Desktop/load-demos.sh" ]
    [ -d "$HOME/repos/unrelated" ]
    [ ! -d "$HOME/repos/tailspin-toys" ]
    run grep -F 'before' "$HOME/.zshrc"
    [ "$status" -eq 0 ]
    run grep -F 'after' "$HOME/.zshrc"
    [ "$status" -eq 0 ]
    run grep -F 'NVM_DIR' "$HOME/.zshrc"
    [ "$status" -ne 0 ]
    run grep -F 'brew uninstall --zap --cask github-copilot-app' "$RESET_LOG"
    [ "$status" -eq 0 ]
    run grep -F 'brew uninstall nvm' "$RESET_LOG"
    [ "$status" -eq 0 ]
    run grep -F 'gh extension remove github/gh-models' "$RESET_LOG"
    [ "$status" -eq 0 ]
    run grep -F 'gh auth logout' "$RESET_LOG"
    [ "$status" -eq 0 ]

    run bash "$REPO_ROOT/reset.sh" --yes
    [ "$status" -eq 0 ]
}
