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

stub_iterm2_tools() {
    export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
    export PREFS_STORE="$BATS_TEST_TMPDIR/iterm2-prefs.plist"
    export DEFAULTS_LOG="$BATS_TEST_TMPDIR/defaults.log"
    export SCHEME_FIXTURE="$BATS_TEST_TMPDIR/fixture.itermcolors"
    mkdir -p "$BATS_TEST_TMPDIR/bin"

    cat > "$SCHEME_FIXTURE" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Background Color</key>
    <dict>
        <key>Blue Component</key><real>0.0705</real>
        <key>Green Component</key><real>0.0549</real>
        <key>Red Component</key><real>0.0509</real>
    </dict>
</dict>
</plist>
EOF

    # curl stub: "download" the fixture to the -o path
    cat > "$BATS_TEST_TMPDIR/bin/curl" <<'EOF'
#!/bin/bash
while [[ $# -gt 0 ]]; do
    if [[ "$1" == "-o" ]]; then cp "$SCHEME_FIXTURE" "$2"; exit 0; fi
    shift
done
exit 1
EOF

    # defaults stub: back the preferences domain with a plain plist file
    cat > "$BATS_TEST_TMPDIR/bin/defaults" <<'EOF'
#!/bin/bash
echo "$*" >> "$DEFAULTS_LOG"
case "$1" in
    export)
        if [[ -f "$PREFS_STORE" ]]; then cp "$PREFS_STORE" "$3"; else plutil -create xml1 "$3"; fi ;;
    import)
        cp "$3" "$PREFS_STORE" ;;
esac
EOF
    chmod +x "$BATS_TEST_TMPDIR/bin/curl" "$BATS_TEST_TMPDIR/bin/defaults"
}

@test "config installs iTerm2 cask" {
    run jq -e '.mac.packages.casks | index("iterm2")' "$REPO_ROOT/config.json"
    [ "$status" -eq 0 ]
}

@test "configure_iterm2 installs theme as preset and default dynamic profile" {
    stub_iterm2_tools
    load_script
    load_config

    configure_iterm2

    local profile_file="$HOME/Library/Application Support/iTerm2/DynamicProfiles/machine-setup.json"
    [[ -f "$profile_file" ]]

    run jq -r '.Profiles[0].Name' "$profile_file"
    [ "$output" = "GitHub Dark Default" ]

    run jq -r '.Profiles[0].Guid' "$profile_file"
    [ "$output" = "$ITERM2_PROFILE_GUID" ]

    run jq -r '.Profiles[0]["Use Separate Colors for Light and Dark Mode"]' "$profile_file"
    [ "$output" = "false" ]

    run jq -e '.Profiles[0]["Background Color"]["Red Component"] - 0.0509 | fabs < 0.000001' "$profile_file"
    [ "$status" -eq 0 ]

    run /usr/libexec/PlistBuddy -c "Print ':Custom Color Presets:GitHub Dark Default:Background Color:Red Component'" "$PREFS_STORE"
    [ "$status" -eq 0 ]
    [[ "$output" == 0.0509* ]]

    run grep -Fx "write com.googlecode.iterm2 Default Bookmark Guid -string $ITERM2_PROFILE_GUID" "$DEFAULTS_LOG"
    [ "$status" -eq 0 ]
}

@test "configure_iterm2 preserves existing presets and skips when already configured" {
    stub_iterm2_tools
    plutil -create xml1 "$PREFS_STORE"
    /usr/libexec/PlistBuddy -c "Add ':Custom Color Presets' dict" -c "Add ':Custom Color Presets:Mine' dict" "$PREFS_STORE"

    load_script
    load_config

    configure_iterm2
    run /usr/libexec/PlistBuddy -c "Print ':Custom Color Presets:Mine'" "$PREFS_STORE"
    [ "$status" -eq 0 ]

    rm "$DEFAULTS_LOG"
    configure_iterm2
    [[ ! -f "$DEFAULTS_LOG" ]]
}

@test "configure_iterm2 fails without writing a profile when download fails" {
    stub_iterm2_tools
    printf '#!/bin/bash\nexit 22\n' > "$BATS_TEST_TMPDIR/bin/curl"

    load_script
    load_config

    run configure_iterm2
    [ "$status" -eq 1 ]
    [[ ! -f "$HOME/Library/Application Support/iTerm2/DynamicProfiles/machine-setup.json" ]]
    [[ ! -f "$DEFAULTS_LOG" ]]
}
