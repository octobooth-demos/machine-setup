# Booth Machine Setup

![CI](https://github.com/octobooth-demos/machine-setup/actions/workflows/ci.yml/badge.svg)

This repository contains setup scripts for configuring booth machines. The scripts install and configure Visual Studio Code, Visual Studio Code Insiders, GitHub CLI, VLC media player, Node.js, and related tooling from a shared `config.json`.

## Features

- Installs and configures Visual Studio Code and Visual Studio Code Insiders.
- Installs GitHub CLI and a suite of GitHub CLI extensions.
- Installs Node.js LTS on macOS (via `nvm`) and Windows (via `winget`).
- Configures VLC media player settings.
- Creates a demo loader script to launch the required applications and sites.
- Registers shared MCP servers for Copilot CLI.

## Configuration

`config.json` is the single source of truth for both setup scripts.

- `shared`: settings used by both platforms, including VS Code extensions, GitHub CLI extensions, demo sites, VLC settings, MCP servers, and repos to clone.
- `mac`: Homebrew packages, editor binaries, and post-install apps for `setup.sh`.
- `windows`: `winget` packages, editor commands, and post-install apps for `setup.ps1`.

`pwa_sites` currently remains in the schema for future use, but PWA setup is intentionally disabled in both scripts until the booth workflow needs it again.

## Setup Instructions

### macOS

1. Open a terminal and navigate to the repository directory.
2. Run the setup script:

   ```bash
   ./setup.sh
   ```

3. The script pauses so you can sign in to GitHub.com in Chrome with the booth/demo account.
4. A launcher script is created on the Desktop.
5. Store booth videos in `$HOME/Videos` so the launcher opens them in VLC.

### Windows

1. Open PowerShell as an administrator.
2. Navigate to the repository directory.
3. Run the setup script:

   ```powershell
   .\setup.ps1
   ```

4. The script pauses so you can sign in to GitHub.com in Microsoft Edge with the booth/demo account.
5. A launcher script is created on the Desktop.
6. Store booth videos in `C:\Users\<YourUsername>\Videos` so the launcher opens them in VLC.

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