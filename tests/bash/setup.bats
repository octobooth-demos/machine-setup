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
    mkdir -p "$BATS_TEST_TMPDIR/bin"

    # defaults stub: back the preferences domain with a plain plist file
    cat > "$BATS_TEST_TMPDIR/bin/defaults" <<'EOF'
#!/bin/bash
echo "$*" >> "$DEFAULTS_LOG"
case "$1" in
    export)
        if [[ -f "$PREFS_STORE" ]]; then cp "$PREFS_STORE" "$3"; else plutil -create xml1 "$3"; fi ;;
    import)
        cp "$3" "$PREFS_STORE" ;;
    read)
        [[ -f "$PREFS_STORE" ]] && /usr/libexec/PlistBuddy -c "Print ':$3'" "$PREFS_STORE" ;;
esac
EOF
    # pgrep stub: iTerm2 is not running unless ITERM2_RUNNING=true
    cat > "$BATS_TEST_TMPDIR/bin/pgrep" <<'EOF'
#!/bin/bash
[[ "$ITERM2_RUNNING" == "true" ]]
EOF
    chmod +x "$BATS_TEST_TMPDIR/bin/defaults" "$BATS_TEST_TMPDIR/bin/pgrep"
}

prefs_value() {
    /usr/libexec/PlistBuddy -c "Print '$1'" "$PREFS_STORE"
}

# Prints the Red Component of a profile/preset color, rounded to 4 places
red_component() {
    printf '%.4f' "$(prefs_value "$1:Red Component")"
}

@test "config installs iTerm2 and SF Mono casks" {
    run jq -e '.mac.packages.casks | index("iterm2") and index("font-sf-mono")' "$REPO_ROOT/config.json"
    [ "$status" -eq 0 ]

    run plutil -lint -s "$REPO_ROOT/$(jq -r '.mac.iterm2.color_scheme_file' "$REPO_ROOT/config.json")"
    [ "$status" -eq 0 ]
}

@test "configure_iterm2 creates a themed Default profile on a fresh install" {
    stub_iterm2_tools
    load_script
    load_config

    configure_iterm2

    run prefs_value ":New Bookmarks:0:Name"
    [ "$output" = "Default" ]

    local guid
    guid=$(prefs_value ":New Bookmarks:0:Guid")
    run prefs_value ":Default Bookmark Guid"
    [ "$output" = "$guid" ]

    run red_component ":New Bookmarks:0:Background Color"
    [ "$output" = "0.0510" ]

    run prefs_value ":New Bookmarks:0:Use Separate Colors for Light and Dark Mode"
    [ "$output" = "false" ]

    run prefs_value ":New Bookmarks:0:Normal Font"
    [ "$output" = "SFMono-Regular 12" ]

    run red_component ":Custom Color Presets:GitHub Dark Default:Background Color"
    [ "$output" = "0.0510" ]
}

@test "configure_iterm2 applies theme to the existing default profile only" {
    stub_iterm2_tools
    plutil -create xml1 "$PREFS_STORE"
    /usr/libexec/PlistBuddy \
        -c "Add ':Default Bookmark Guid' string GUID-B" \
        -c "Add ':New Bookmarks' array" \
        -c "Add ':New Bookmarks:0' dict" \
        -c "Add ':New Bookmarks:0:Name' string Other" \
        -c "Add ':New Bookmarks:0:Guid' string GUID-A" \
        -c "Add ':New Bookmarks:1' dict" \
        -c "Add ':New Bookmarks:1:Name' string Default" \
        -c "Add ':New Bookmarks:1:Guid' string GUID-B" \
        "$PREFS_STORE"
    # Split across calls: PlistBuddy aborts when given 15+ -c commands at once
    /usr/libexec/PlistBuddy \
        -c "Add ':New Bookmarks:1:Columns' integer 120" \
        -c "Add ':New Bookmarks:1:Normal Font' string 'Monaco 12'" \
        -c "Add ':New Bookmarks:1:Use Separate Colors for Light and Dark Mode' bool true" \
        -c "Add ':New Bookmarks:1:Background Color' dict" \
        -c "Add ':New Bookmarks:1:Background Color:Red Component' real 0.98" \
        -c "Add ':Custom Color Presets' dict" \
        -c "Add ':Custom Color Presets:Mine' dict" \
        "$PREFS_STORE"

    load_script
    load_config
    configure_iterm2

    run red_component ":New Bookmarks:1:Background Color"
    [ "$output" = "0.0510" ]

    run prefs_value ":New Bookmarks:1:Normal Font"
    [ "$output" = "SFMono-Regular 12" ]

    run prefs_value ":New Bookmarks:1:Use Separate Colors for Light and Dark Mode"
    [ "$output" = "false" ]

    run prefs_value ":New Bookmarks:1:Columns"
    [ "$output" = "120" ]

    run prefs_value ":Default Bookmark Guid"
    [ "$output" = "GUID-B" ]

    run prefs_value ":New Bookmarks:0:Background Color"
    [ "$status" -ne 0 ]

    run prefs_value ":Custom Color Presets:Mine"
    [ "$status" -eq 0 ]
}

@test "configure_iterm2 skips when already configured unless forced" {
    stub_iterm2_tools
    load_script
    load_config

    configure_iterm2
    /usr/libexec/PlistBuddy -c "Set ':New Bookmarks:0:Normal Font' 'Menlo 14'" "$PREFS_STORE"

    configure_iterm2
    run prefs_value ":New Bookmarks:0:Normal Font"
    [ "$output" = "Menlo 14" ]

    FORCE_REINSTALL=true
    configure_iterm2
    run prefs_value ":New Bookmarks:0:Normal Font"
    [ "$output" = "SFMono-Regular 12" ]

    run prefs_value ":New Bookmarks:1"
    [ "$status" -ne 0 ]
}

@test "configure_iterm2 refuses to change preferences while iTerm2 is running" {
    stub_iterm2_tools
    export ITERM2_RUNNING=true
    load_script
    load_config

    run configure_iterm2
    [ "$status" -eq 1 ]
    [[ ! -f "$PREFS_STORE" ]]
}

@test "config installs the GitHub Copilot app on both platforms" {
    run jq -e '.mac.packages.casks | index("github-copilot-app")' "$REPO_ROOT/config.json"
    [ "$status" -eq 0 ]

    run jq -e '.windows.packages | index("GitHub.CopilotApp")' "$REPO_ROOT/config.json"
    [ "$status" -eq 0 ]
}

@test "config installs Git on Windows before cloning repos" {
    run jq -e '.windows.packages | index("Git.Git")' "$REPO_ROOT/config.json"
    [ "$status" -eq 0 ]
}

@test "create_demo_loader opens the GitHub Copilot app" {
    load_script
    load_config

    create_demo_loader

    run grep -F 'open -a "GitHub Copilot"' "$HOME/Desktop/load-demos.sh"
    [ "$status" -eq 0 ]
}

# gh stub: reports the scopes in GH_SCOPES and logs every call with the
# GH_TOKEN/GITHUB_TOKEN values it saw
stub_gh_auth() {
    export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
    export GH_LOG="$BATS_TEST_TMPDIR/gh.log"
    mkdir -p "$BATS_TEST_TMPDIR/bin"
    cat > "$BATS_TEST_TMPDIR/bin/gh" <<'STUB'
#!/bin/bash
echo "$* [GH_TOKEN=${GH_TOKEN-unset} GITHUB_TOKEN=${GITHUB_TOKEN-unset}]" >> "$GH_LOG"
if [[ "$1 $2" == "auth status" ]]; then
    echo "  - Token scopes: $GH_SCOPES"
fi
STUB
    chmod +x "$BATS_TEST_TMPDIR/bin/gh"
}

@test "ensure_gh_scopes refreshes only missing scopes using the stored login" {
    stub_gh_auth
    export GH_SCOPES="'codespace', 'gist', 'repo'"
    export GH_TOKEN="env-token" GITHUB_TOKEN="env-token"
    load_script
    load_config

    ensure_gh_scopes

    run grep -F 'auth refresh -h github.com -s delete_repo [GH_TOKEN=unset GITHUB_TOKEN=unset]' "$GH_LOG"
    [ "$status" -eq 0 ]

    run grep -F 'env-token' "$GH_LOG"
    [ "$status" -ne 0 ]
}

@test "ensure_gh_scopes does nothing when all scopes are granted" {
    stub_gh_auth
    export GH_SCOPES="'codespace', 'delete_repo', 'repo'"
    load_script
    load_config

    ensure_gh_scopes

    run grep -F 'auth refresh' "$GH_LOG"
    [ "$status" -ne 0 ]
}

@test "install_demo_launcher skips when repo-setup-scripts has no Demo Launcher" {
    load_script

    failed_items=()
    install_demo_launcher

    [ "${#failed_items[@]}" -eq 0 ]
    [[ ! -e "$COPILOT_HOME/extensions/demo-launcher" ]]
}

@test "install_demo_launcher runs install.sh once unless forced" {
    local ext_dir="$HOME/repos/repo-setup-scripts/.github/extensions/demo-launcher"
    mkdir -p "$ext_dir"
    cat > "$ext_dir/install.sh" <<'STUB'
#!/bin/bash
echo run >> "$INSTALL_LOG"
mkdir -p "$COPILOT_HOME/extensions/demo-launcher"
touch "$COPILOT_HOME/extensions/demo-launcher/extension.mjs"
STUB
    export INSTALL_LOG="$BATS_TEST_TMPDIR/install.log"
    load_script

    install_demo_launcher
    install_demo_launcher
    [ "$(wc -l < "$INSTALL_LOG")" -eq 1 ]

    FORCE_REINSTALL=true
    install_demo_launcher
    [ "$(wc -l < "$INSTALL_LOG")" -eq 2 ]
}

@test "install_demo_launcher fast-forwards an existing repo-setup-scripts clone" {
    local origin="$BATS_TEST_TMPDIR/origin.git"
    local repo="$HOME/repos/repo-setup-scripts"
    git init -q --bare "$origin"
    git clone -q "$origin" "$repo"
    git -C "$repo" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
    git -C "$repo" push -q origin HEAD

    local other="$BATS_TEST_TMPDIR/other"
    git clone -q "$origin" "$other"
    mkdir -p "$other/.github/extensions/demo-launcher"
    printf '#!/bin/bash\necho run >> "$INSTALL_LOG"\n' > "$other/.github/extensions/demo-launcher/install.sh"
    git -C "$other" add -A
    git -C "$other" -c user.name=t -c user.email=t@t commit -q -m launcher
    git -C "$other" push -q origin HEAD

    export INSTALL_LOG="$BATS_TEST_TMPDIR/install.log"
    load_script

    install_demo_launcher

    [[ -f "$repo/.github/extensions/demo-launcher/install.sh" ]]
    [ "$(wc -l < "$INSTALL_LOG")" -eq 1 ]
}

@test "check_demo_launcher_prereqs fails with login instructions when gh is logged out" {
    mkdir -p "$BATS_TEST_TMPDIR/bin"
    printf '#!/bin/bash\nexit 1\n' > "$BATS_TEST_TMPDIR/bin/gh"
    chmod +x "$BATS_TEST_TMPDIR/bin/gh"
    export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
    load_script
    load_config

    run check_demo_launcher_prereqs
    [ "$status" -eq 1 ]
    [[ "$output" == *"gh auth login -h github.com -s codespace,delete_repo"* ]]
}

@test "check_demo_launcher_prereqs warns about missing scopes but continues" {
    stub_gh_auth
    export GH_SCOPES="'codespace', 'repo'"
    load_script
    load_config

    run check_demo_launcher_prereqs
    [ "$status" -eq 0 ]
    [[ "$output" == *"gh auth refresh -h github.com -s delete_repo"* ]]
}

@test "sourcing install-demo-launcher.sh does not execute it" {
    source "$REPO_ROOT/install-demo-launcher.sh"

    [[ ! -e "$HOME/repos" ]]
    declare -f demo_launcher_main > /dev/null
}

@test "install-demo-launcher.sh rejects unknown arguments" {
    run bash "$REPO_ROOT/install-demo-launcher.sh" --bogus
    [ "$status" -eq 2 ]
    [[ "$output" == *"Usage:"* ]]
}
