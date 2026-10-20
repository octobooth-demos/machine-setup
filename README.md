# Booth Machine Setup

![CI](https://github.com/octobooth-demos/machine-setup/actions/workflows/ci.yml/badge.svg)

This repository contains setup scripts for configuring booth machines. The scripts install and configure the GitHub Copilot app, Visual Studio Code, Visual Studio Code Insiders, GitHub CLI, VLC media player, Node.js, iTerm2 (macOS), and related tooling from a shared `config.json`.

## Features

- Installs the GitHub Copilot app (`github-copilot-app` cask / `GitHub.CopilotApp` winget package) and Copilot CLI.
- Installs and configures Visual Studio Code and Visual Studio Code Insiders.
- Installs GitHub CLI, logs it in with the scopes the booth demos need, and installs a suite of GitHub CLI extensions.
- Installs Node.js LTS on macOS (via `nvm`) and Windows (via `winget`).
- Installs iTerm2 on macOS and sets its default profile to the GitHub Dark Default color scheme with SF Mono.
- Configures VLC media player settings.
- Creates a demo loader script to launch the required applications and sites.
- Registers shared MCP servers for Copilot CLI.
- Clones the demo repos into `~/repos` and, on macOS, installs the Demo Launcher canvas for every Copilot session (see [Demo Launcher](#demo-launcher)).

## Configuration

`config.json` is the single source of truth for both setup scripts.

- `shared`: settings used by both platforms, including VS Code extensions, GitHub CLI extensions, GitHub CLI auth scopes, demo sites, VLC settings, MCP servers, and repos to clone.
- `mac`: Homebrew packages, editor binaries, iTerm2 theme settings, and post-install apps for `setup.sh`.
- `windows`: `winget` packages, editor commands, and post-install apps for `setup.ps1`.

`mac.iterm2` controls the iTerm2 theme. `setup.sh` takes the colors from `color_scheme_file` (stored in [`iterm2/`](iterm2/README.md)), adds them to iTerm2's Color Presets as `color_preset`, and applies them and `font` to iTerm2's default profile. If iTerm2 has never been opened, it creates that "Default" profile. The `font-sf-mono` cask installs SF Mono from Apple and asks for an admin password. Quit iTerm2 before running setup, because iTerm2 overwrites preference changes when it quits. Once the theme is applied, later runs leave the profile alone unless `FORCE_REINSTALL=true`.

`shared.gh_auth_scopes` lists the extra scopes the GitHub CLI login needs: `codespace` (the Tailspin Toys demo creates a Codespace) and `delete_repo` (the Demo Launcher's cleanup deletes demo repos). A new login requests them, and an existing login missing any of them is upgraded with `gh auth refresh`, which opens a browser to approve. Both scripts ignore `GH_TOKEN`/`GITHUB_TOKEN` for these steps so the stored login is the one updated. To add them by hand, run `gh auth refresh -h github.com -s codespace,delete_repo`.

`pwa_sites` currently remains in the schema for future use, but PWA setup is intentionally disabled in both scripts until the booth workflow needs it again.

## Setup Instructions

### Download the setup scripts

1. [Download the setup scripts as a ZIP](https://github.com/octobooth-demos/machine-setup/archive/refs/heads/main.zip). No Git installation is required.
2. Extract the ZIP file (on Windows, right-click it and choose **Extract All**).
3. Follow the instructions for your operating system below, running commands from the extracted `machine-setup-main` folder. Keep all files together; the scripts require `config.json`, and `setup.sh` also needs the `iterm2/` folder.

### macOS

1. Open a terminal and navigate to the extracted `machine-setup-main` folder.
2. Run the setup script:

   ```bash
   bash setup.sh
   ```

3. The script pauses so you can sign in to GitHub.com in Chrome with the booth/demo account.
4. Approve the GitHub CLI login (or scope upgrade) in the browser when prompted.
5. A launcher script that also opens the GitHub Copilot app is created on the Desktop.
6. Store booth videos in `$HOME/Videos` so the launcher opens them in VLC.

### Windows

1. Open Windows Terminal as an administrator.
2. Navigate to the extracted `machine-setup-main` folder.
3. Run the setup script:

   ```powershell
   .\setup.ps1
   ```

4. The script pauses so you can sign in to GitHub.com in Microsoft Edge with the booth/demo account.
5. Approve the GitHub CLI login (or scope upgrade) in the browser when prompted.
6. A launcher script is created on the Desktop.
7. Store booth videos in `C:\Users\<YourUsername>\Videos` so the launcher opens them in VLC.

## Demo Launcher

[`octobooth-demos/repo-setup-scripts`](https://github.com/octobooth-demos/repo-setup-scripts) (cloned to `~/repos/repo-setup-scripts`) ships a **Demo Launcher** canvas for the GitHub Copilot app. It creates booth demos in the background with `create-repo.sh`/`create-repo.ps1`, opens sessions for them in the Copilot app, and cleans up old demo repos.

1. Open the GitHub Copilot app and sign in with the booth/demo account.
2. Add `~/repos/repo-setup-scripts` (or `octobooth-demos/repo-setup-scripts`) as a project.
3. Start a session in that project and ask Copilot to "open the demo launcher".

On macOS, `setup.sh` also runs the repo's `.github/extensions/demo-launcher/install.sh` (when present) so the canvas is available in every Copilot session, not just the repo-setup-scripts project. Restart open sessions to pick it up. To do this manually, or after pulling an update that adds the launcher, run:

```bash
bash ~/repos/repo-setup-scripts/.github/extensions/demo-launcher/install.sh
```

`install.sh` is macOS/Linux only, so on Windows use the Demo Launcher from a session in the repo-setup-scripts project.

## Development and Testing

The GitHub Actions workflow validates syntax, linting, configuration shape, and unit tests for both scripts without executing either installer end to end.

### Local checks

#### Bash

```bash
shellcheck setup.sh
bash -n setup.sh
bats tests/bash
```

#### PowerShell

```powershell
Invoke-ScriptAnalyzer -Path .\setup.ps1 -Settings .\PSScriptAnalyzerSettings.psd1
Invoke-Pester -Path .\tests\powershell
```

Both scripts now guard their main entry point so they can be sourced or dot-sourced safely from tests without triggering installs.

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.