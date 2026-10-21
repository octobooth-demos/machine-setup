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
- Clones the demo repos into `~/repos`, installs the standalone Demo Launcher service (http://127.0.0.1:4747/) and, on macOS, the Demo Launcher canvas for every Copilot session. `install-demo-launcher.sh` does just those steps on a Mac that is already set up (see [Demo Launcher](#demo-launcher)).

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

### Troubleshooting Windows package installs

WinGet error `-1978335138` (`0x8A15005E`, pinned certificate mismatch) can occur when querying the Microsoft Store source, even for a package available from the `winget` source. See [microsoft/winget-cli#3109](https://github.com/microsoft/winget-cli/issues/3109). [`setup.ps1`](setup.ps1) explicitly selects `--source winget` to avoid these unrelated Store failures while preserving certificate validation. All entries in `windows.packages` in [`config.json`](config.json) must be available from the `winget` source.

To retry Visual Studio Code installation:

```powershell
winget install --id Microsoft.VisualStudioCode -e --source winget --accept-source-agreements --accept-package-agreements
```

If the error persists, update App Installer through Microsoft Store and check whether a proxy or security product is intercepting HTTPS traffic. Do not disable certificate checks or certificate pinning.

## Demo Launcher

[`octobooth-demos/repo-setup-scripts`](https://github.com/octobooth-demos/repo-setup-scripts) (cloned to `~/repos/repo-setup-scripts`) ships a **Demo Launcher** canvas for the GitHub Copilot app. It creates booth demos in the background with `create-repo.sh`/`create-repo.ps1`, opens sessions for them in the Copilot app, and cleans up old demo repos.

1. Open the GitHub Copilot app and sign in with the booth/demo account.
2. Add `~/repos/repo-setup-scripts` (or `octobooth-demos/repo-setup-scripts`) as a project.
3. Start a session in that project and ask Copilot to "open the demo launcher".

On macOS, `setup.sh` also installs it for every Copilot session, not just the repo-setup-scripts project: it fast-forwards an existing `~/repos/repo-setup-scripts` checkout (`git pull --ff-only`) and runs the repo's `.github/extensions/demo-launcher/install.sh` when present. That writes a loader to `${COPILOT_HOME:-~/.copilot}/extensions/demo-launcher/extension.mjs` that imports the launcher from the checkout, so later pulls update it.

### Standalone Demo Launcher service

As a backup to the canvas, repo-setup-scripts also ships a standalone Demo Launcher (`launcher/server.mjs`, plain Node.js 18+) that runs in any browser at http://127.0.0.1:4747/, with or without the Copilot app. After the canvas step, the setup scripts install it as a login service from the `~/repos/repo-setup-scripts` checkout:

- **macOS:** `setup.sh` runs `launcher/install-service.sh --port <port>`, which installs the `com.octobooth.demo-launcher` LaunchAgent (logs: `~/Library/Logs/demo-launcher.log`). `config.json` installs the `node` Homebrew formula so the service has a Node.js to run.
- **Windows:** `setup.ps1` fast-forwards the checkout and runs `launcher\install-service.ps1 -Port <port>`, which registers a logon scheduled task named "Demo Launcher" (logs: `%LOCALAPPDATA%\demo-launcher\server.log`).

The installers are idempotent and restart the service, so they run on every setup to pick up the latest checkout. If the checkout doesn't have `launcher/install-service.*` yet, the step is skipped with a warning. Installer failures are listed in the summary like other steps.

Configure it in `config.json` under `shared.demo_launcher_service`: set `enabled` to `false` to skip it, or change `port` (default `4747`). The `DEMO_LAUNCHER_PORT` environment variable overrides the configured port.

### Install or update on a machine that's already set up

From this folder, run:

```bash
bash install-demo-launcher.sh
```

It's safe to re-run. It:

1. Checks for `gh`, `git`, and `jq` (`brew install gh jq`) and that the GitHub CLI is logged in. Logging in is interactive, so if it isn't, the script prints the `gh auth login` command to run and stops. It also warns if the login is missing the `codespace`/`delete_repo` scopes (`gh auth refresh -h github.com -s codespace,delete_repo`).
2. Clones `octobooth-demos/repo-setup-scripts` to `~/repos/repo-setup-scripts`, or pulls it if it's already there.
3. Runs `install.sh` to (re)write the loader.
4. Runs `launcher/install-service.sh` to (re)install and restart the standalone service, unless it's disabled in `config.json` or you pass `--no-service`. Use `--port N` to pick a different port.

Then restart the GitHub Copilot app (or reload extensions) and ask Copilot to "open the demo launcher" in any session to check it works, or open http://127.0.0.1:4747/ in a browser. To remove both the canvas and the service, run `bash install-demo-launcher.sh --uninstall`.

`install.sh` is macOS/Linux only, so on Windows use the Demo Launcher canvas from a session in the repo-setup-scripts project, or the standalone service at http://127.0.0.1:4747/. To reinstall or remove the Windows service, run `launcher\install-service.ps1 [-Port N] [-Uninstall]` from `~\repos\repo-setup-scripts`. For more on the Demo Launcher itself, see the [repo-setup-scripts quick start](https://github.com/octobooth-demos/repo-setup-scripts#quick-start-booth-machine).

## Development and Testing

The GitHub Actions workflow validates syntax, linting, configuration shape, and unit tests for both scripts without executing either installer end to end.

### Local checks

#### Bash

```bash
shellcheck -x setup.sh install-demo-launcher.sh
bash -n setup.sh && bash -n install-demo-launcher.sh
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