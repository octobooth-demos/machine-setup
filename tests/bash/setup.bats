#!/usr/bin/env bats

setup() {
    export REPO_ROOT="$BATS_TEST_DIRNAME/../.."
    export HOME="$BATS_TEST_TMPDIR/home"
    export COPILOT_HOME="$HOME/.copilot"

    mkdir -p "$HOME/Desktop" "$HOME/.copilot" "$HOME/Library/Application Support/Code/User"
}

load_script() {
    source "$REPO_ROOT/setup.sh"
}

@test "sourcing setup.sh does not execute main" {
    load_script

    [[ ! -f "$HOME/Desktop/load-demos.sh" ]]
    [[ ! -f "$COPILOT_HOME/mcp-config.json" ]]
}

@test "configure_vscode_theme merges theme into existing settings" {
    load_script
    load_config

    local settings_file="$HOME/Library/Application Support/Code/User/settings.json"
    printf '{"editor.fontSize":14}\n' > "$settings_file"

    configure_vscode_theme "VS Code" "Code"

    run jq -r '.["workbench.colorTheme"]' "$settings_file"
    [ "$status" -eq 0 ]
    [ "$output" = "Light 2026" ]

    run jq -r '.["editor.fontSize"]' "$settings_file"
    [ "$status" -eq 0 ]
    [ "$output" = "14" ]
}

@test "register_mcp_servers writes config for local and http servers" {
    load_script
    load_config

    register_mcp_servers

    local mcp_config="$COPILOT_HOME/mcp-config.json"
    [[ -f "$mcp_config" ]]

    run jq -r '.mcpServers.playwright.command' "$mcp_config"
    [ "$status" -eq 0 ]
    [ "$output" = "npx" ]

    run jq -r '.mcpServers["microsoft-learn"].url' "$mcp_config"
    [ "$status" -eq 0 ]
    [ "$output" = "https://learn.microsoft.com/api/mcp" ]
}

@test "create_demo_loader writes the launcher script to Desktop" {
    load_script
    load_config

    create_demo_loader

    local demo_script="$HOME/Desktop/load-demos.sh"
    [[ -f "$demo_script" ]]

    run grep -F 'open -a "Google Chrome" "https://github.com"' "$demo_script"
    [ "$status" -eq 0 ]

    run grep -F 'open -a VLC "$HOME/Videos"' "$demo_script"
    [ "$status" -eq 0 ]
}

@test "try_install records failures without exiting" {
    load_script

    failed_items=()
    try_install "example failure" false

    [ "${#failed_items[@]}" -eq 1 ]
    [ "${failed_items[0]}" = "example failure" ]
}

@test "clone_repos skips repos that already exist" {
    export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
    mkdir -p "$BATS_TEST_TMPDIR/bin"
    cat > "$BATS_TEST_TMPDIR/bin/gh" <<'EOF'
#!/bin/bash
echo "$*" >> "$GH_LOG"
EOF
    chmod +x "$BATS_TEST_TMPDIR/bin/gh"
    export GH_LOG="$BATS_TEST_TMPDIR/gh.log"

    mkdir -p "$HOME/repos/repo-setup-scripts" "$HOME/repos/tailspin-toys" "$HOME/repos/security-octo-supply"

    load_script
    load_config
    clone_repos

    [[ ! -f "$GH_LOG" ]]
}

@test "config.json includes the Copilot app cask and app name" {
    run jq -r '.mac.packages.casks | index("github-copilot-app") != null' "$REPO_ROOT/config.json"
    [ "$output" = "true" ]

    run jq -r '.mac.copilot_app.app' "$REPO_ROOT/config.json"
    [ "$output" = "GitHub Copilot" ]
}

@test "authenticate_copilot_app opens the app and waits for sign-in" {
    mkdir -p "$BATS_TEST_TMPDIR/bin"
    cat > "$BATS_TEST_TMPDIR/bin/open" <<'STUB'
#!/bin/bash
echo "$*" >> "$OPEN_LOG"
STUB
    chmod +x "$BATS_TEST_TMPDIR/bin/open"
    export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
    export OPEN_LOG="$BATS_TEST_TMPDIR/open.log"

    load_script
    load_config

    authenticate_copilot_app <<< ""

    run cat "$OPEN_LOG"
    [ "$output" = "-a GitHub Copilot" ]
}

@test "create_demo_loader opens the Copilot app" {
    load_script
    load_config

    create_demo_loader

    run grep -F 'open -a "GitHub Copilot"' "$HOME/Desktop/load-demos.sh"
    [ "$status" -eq 0 ]
}

# ---- reset.sh ----

reset_stubs() {
    mkdir -p "$BATS_TEST_TMPDIR/bin"
    cat > "$BATS_TEST_TMPDIR/bin/brew" <<'STUB'
#!/bin/bash
echo "brew $*" >> "$CMD_LOG"
if [[ "$1" == "list" ]]; then exit 0; fi
STUB
    cat > "$BATS_TEST_TMPDIR/bin/gh" <<'STUB'
#!/bin/bash
echo "gh $*" >> "$CMD_LOG"
if [[ "$1 $2" == "extension list" ]]; then printf 'gh sbom\tadvanced-security/gh-sbom\tv1\n'; fi
STUB
    chmod +x "$BATS_TEST_TMPDIR/bin/brew" "$BATS_TEST_TMPDIR/bin/gh"
    export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
    export CMD_LOG="$BATS_TEST_TMPDIR/cmd.log"
}

@test "reset.sh aborts without confirmation and changes nothing" {
    reset_stubs
    mkdir -p "$HOME/.nvm"

    run bash "$REPO_ROOT/reset.sh" <<< "no"
    [ "$status" -eq 0 ]
    [[ -d "$HOME/.nvm" ]]
    [[ ! -f "$CMD_LOG" ]]
}

@test "reset.sh --yes removes user data, repos, launcher and VLC config" {
    reset_stubs
    mkdir -p "$HOME/.nvm" "$HOME/.vscode" "$HOME/.vscode-insiders" \
        "$HOME/Library/Application Support/Code - Insiders" \
        "$HOME/repos/tailspin-toys" "$HOME/repos/unrelated" \
        "$HOME/Library/Preferences/org.videolan.vlc"
    touch "$HOME/Desktop/load-demos.sh" "$HOME/Library/Preferences/org.videolan.vlc/vlcrc"
    printf 'export PATH=x\n# nvm (Node Version Manager)\nexport NVM_DIR="$HOME/.nvm"\n[ -s "/opt/homebrew/opt/nvm/nvm.sh" ] && \\. "/opt/homebrew/opt/nvm/nvm.sh"\n' > "$HOME/.zshrc"

    run bash "$REPO_ROOT/reset.sh" --yes
    [ "$status" -eq 0 ]

    [[ ! -e "$HOME/.nvm" ]]
    [[ ! -e "$HOME/.copilot" ]]
    [[ ! -e "$HOME/.vscode" ]]
    [[ ! -e "$HOME/.vscode-insiders" ]]
    [[ ! -e "$HOME/Library/Application Support/Code" ]]
    [[ ! -e "$HOME/Library/Application Support/Code - Insiders" ]]
    [[ ! -e "$HOME/repos/tailspin-toys" ]]
    [[ -d "$HOME/repos/unrelated" ]]
    [[ ! -e "$HOME/Desktop/load-demos.sh" ]]
    [[ ! -e "$HOME/Library/Preferences/org.videolan.vlc/vlcrc" ]]

    run cat "$HOME/.zshrc"
    [ "$output" = "export PATH=x" ]
}

@test "reset.sh --yes uninstalls casks with zap, formulas, gh extensions and logs out" {
    reset_stubs

    run bash "$REPO_ROOT/reset.sh" --yes
    [ "$status" -eq 0 ]

    run grep -F 'brew uninstall --zap --cask github-copilot-app' "$CMD_LOG"
    [ "$status" -eq 0 ]
    run grep -F 'brew uninstall --zap --cask github' "$CMD_LOG"
    [ "$status" -eq 0 ]
    run grep -F 'google-chrome' "$CMD_LOG"
    [ "$status" -ne 0 ]
    run grep -Fx 'brew uninstall nvm' "$CMD_LOG"
    [ "$status" -eq 0 ]
    run grep -F 'gh extension remove advanced-security/gh-sbom' "$CMD_LOG"
    [ "$status" -eq 0 ]
    run grep -F 'gh auth logout' "$CMD_LOG"
    [ "$status" -eq 0 ]
}

@test "reset.sh is idempotent when nothing is installed" {
    mkdir -p "$BATS_TEST_TMPDIR/bin"
    printf '#!/bin/bash\necho "brew $*" >> "$CMD_LOG"\nexit 1\n' > "$BATS_TEST_TMPDIR/bin/brew"
    printf '#!/bin/bash\nexit 1\n' > "$BATS_TEST_TMPDIR/bin/gh"
    chmod +x "$BATS_TEST_TMPDIR/bin/brew" "$BATS_TEST_TMPDIR/bin/gh"
    export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
    export CMD_LOG="$BATS_TEST_TMPDIR/cmd.log"

    run bash "$REPO_ROOT/reset.sh" --yes
    [ "$status" -eq 0 ]

    run grep -F 'uninstall' "$CMD_LOG"
    [ "$status" -ne 0 ]
}

@test "reset.sh rejects unknown options" {
    run bash "$REPO_ROOT/reset.sh" --bogus
    [ "$status" -eq 2 ]
}
