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
    [ "$output" = "Default Dark+" ]

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
