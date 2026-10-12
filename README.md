# Booth Machine Setup

![CI](https://github.com/octobooth-demos/machine-setup/actions/workflows/ci.yml/badge.svg)

This repository contains setup scripts for configuring booth machines. The scripts install and configure Visual Studio Code, Visual Studio Code Insiders, the GitHub Copilot app, GitHub CLI, VLC media player, Node.js, and related tooling from a shared `config.json`.

## Features

- Installs and configures Visual Studio Code and Visual Studio Code Insiders.
- Installs GitHub CLI and a suite of GitHub CLI extensions.
- Installs Node.js LTS on macOS (via `nvm`) and Windows (via `winget`).
- Configures VLC media player settings.
- Creates a demo loader script to launch the required applications and sites.
- Installs the GitHub Copilot app (Homebrew cask `github-copilot-app` / winget `GitHub.CopilotApp`), opens it, and pauses so you can sign in.
- Registers shared MCP servers for Copilot CLI and the Copilot app (both read `~/.copilot/mcp-config.json`).
- Includes `reset.sh` (macOS) to undo the setup so you can start from a clean state.

## Configuration

`config.json` is the single source of truth for both setup scripts.

- `shared`: settings used by both platforms, including VS Code extensions, GitHub CLI extensions, demo sites, VLC settings, MCP servers, and repos to clone.
- `mac`: Homebrew packages, editor binaries, the Copilot app name (`copilot_app`), and post-install apps for `setup.sh`.
- `windows`: `winget` packages, editor commands, the Copilot app Start menu name (`copilot_app`), and post-install apps for `setup.ps1`.

`pwa_sites` currently remains in the schema for future use, but PWA setup is intentionally disabled in both scripts until the booth workflow needs it again.

## Setup Instructions

### Download the setup scripts

1. [Download the setup scripts as a ZIP](https://github.com/octobooth-demos/machine-setup/archive/refs/heads/main.zip). No Git installation is required.
2. Extract the ZIP file (on Windows, right-click it and choose **Extract All**).
3. Follow the instructions for your operating system below, running commands from the extracted `machine-setup-main` folder. Keep all files together; the scripts require `config.json`.

### macOS

1. Open a terminal and navigate to the extracted `machine-setup-main` folder.
2. Run the setup script:

   ```bash
   bash setup.sh
   ```

3. The script pauses so you can sign in to GitHub.com in Chrome with the booth/demo account.
4. Near the end, the GitHub Copilot app opens and the script pauses so you can sign in with the same account.
5. A launcher script is created on the Desktop.
6. Store booth videos in `$HOME/Videos` so the launcher opens them in VLC.

### Windows

1. Open Windows Terminal as an administrator.
2. Navigate to the extracted `machine-setup-main` folder.
3. Run the setup script:

   ```powershell
   .\setup.ps1
   ```

4. The script pauses so you can sign in to GitHub.com in Microsoft Edge with the booth/demo account.
5. Near the end, the GitHub Copilot app opens and the script pauses so you can sign in with the same account.
6. A launcher script is created on the Desktop.
7. Store booth videos in `C:\Users\<YourUsername>\Videos` so the launcher opens them in VLC.

### Resetting a macOS machine

`reset.sh` reverses `setup.sh`, driven by `config.json`, so you can re-run `setup.sh` from a clean state:

```bash
bash reset.sh        # asks you to type "yes" first
bash reset.sh --yes  # skip the confirmation prompt
```

It will:

- Remove the GitHub CLI extensions and run `gh auth logout`.
- Run `brew uninstall --zap --cask` for each cask and `brew uninstall` for each formula. Casks not installed through Homebrew (e.g. a Chrome installed by MDM) are skipped.
- Delete VS Code / VS Code Insiders user data (`~/Library/Application Support/Code*`, `~/.vscode*`), `~/.copilot` and `~/.nvm`, and the nvm block added to `~/.zshrc`.
- Delete the cloned repos in `~/repos`, the Desktop `load-demos.sh` launcher and the VLC config.

This is destructive. It is idempotent: anything already missing is skipped.

## Development and Testing

The GitHub Actions workflow validates syntax, linting, configuration shape, and unit tests for both scripts without executing either installer end to end.

### Local checks

#### Bash

```bash
shellcheck --severity=warning setup.sh reset.sh
bash -n setup.sh
bash -n reset.sh
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