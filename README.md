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
- Clones the demo repos into `~/repos` and, on macOS, installs the Demo Launcher canvas for every Copilot session. `install-demo-launcher.sh` does just that step on a machine that is already set up (see [Demo Launcher](#demo-launcher)).

## Configuration

`config.json` is the single source of truth for both setup scripts.

- `shared`: settings used by both platforms, including VS Code extensions, GitHub CLI extensions, GitHub CLI auth scopes, demo sites, VLC settings, MCP servers, and repos to clone.
- `mac`: Homebrew packages, editor binaries, iTerm2 theme settings, and post-install apps for `setup.sh`.
- `windows`: `winget` packages, editor commands, and post-install apps for `setup.ps1`.

`mac.iterm2` controls the iTerm2 theme. `setup.sh` takes the colors from `color_scheme_file` (stored in [`iterm2/`](iterm2/README.md)), adds them to iTerm2's Color Presets as `color_preset`, and applies them and `font` to iTerm2's default profile. If iTerm2 has never been opened, it creates that "Default" profile. The `font-sf-mono` cask installs SF Mono from Apple and asks for an admin password. Quit iTerm2 before running setup, because iTerm2 overwrites preference changes when it quits. Once the theme is applied, later runs leave the profile alone unless `FORCE_REINSTALL=true`.

`shared.gh_auth_scopes` lists the extra scopes the GitHub CLI login needs: `codespace` (the Tailspin Toys demo creates a Codespace) and `delete_repo` (the Demo Launcher's cleanup deletes demo repos). A new login requests them, and an existing login missing any of them is upgraded with `gh auth refresh`, which opens a browser to approve. Both scripts ignore `GH_TOKEN`/`GITHUB_TOKEN` for these steps so the stored login is the one updated. To do it by hand, see [GitHub CLI login](#github-cli-login).

`pwa_sites` currently remains in the schema for future use, but PWA setup is intentionally disabled in both scripts until the booth workflow needs it again.

## Setup Instructions

### Get the setup scripts

Clone this repo so you can update the scripts before each run. A ZIP download never updates, so an old copy keeps running old scripts.

1. Clone it.

   macOS (Terminal). On a new Mac, `git` may prompt you to install the Command Line Tools first:

   ```bash
   git clone https://github.com/octobooth-demos/machine-setup.git ~/repos/machine-setup
   ```

   Windows (PowerShell). `setup.ps1` installs Git, but you need it once to clone this repo before the first run. If `git --version` fails, install it, then open a new terminal:

   ```powershell
   winget install --id Git.Git -e --source winget
   git clone https://github.com/octobooth-demos/machine-setup.git "$HOME\repos\machine-setup"
   ```

2. Before each booth day, and before re-running `setup.sh`, `setup.ps1`, or `install-demo-launcher.sh`, pull the latest:

   ```bash
   git -C ~/repos/machine-setup pull                 # macOS
   git -C "$HOME\repos\machine-setup" pull           # Windows PowerShell
   ```

3. Follow the instructions for your operating system below, running commands from that folder.

**Fallback for a new Mac without Git:** [download the ZIP](https://github.com/octobooth-demos/machine-setup/archive/refs/heads/main.zip) and run commands from the extracted `machine-setup-main` folder. Keep all files together, because the scripts need `config.json` and `setup.sh` also needs the `iterm2/` folder. Setup installs Git, so switch to a clone afterward. If you stay on the ZIP, download it again before re-running any script.

### macOS

1. Open a terminal and go to `~/repos/machine-setup` (or the extracted `machine-setup-main` folder).
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
2. Go to `$HOME\repos\machine-setup` (`cd "$HOME\repos\machine-setup"`).
3. Run the setup script:

   ```powershell
   .\setup.ps1
   ```

4. The script pauses so you can sign in to GitHub.com in Microsoft Edge with the booth/demo account.
5. Approve the GitHub CLI login (or scope upgrade) in the browser when prompted.
6. A launcher script is created on the Desktop.
7. Store booth videos in `C:\Users\<YourUsername>\Videos` so the launcher opens them in VLC.

### GitHub CLI login

The setup scripts handle this for you, but check it on every booth machine (and do it by hand if a script warned about it):

1. Log in as the **booth account** (for example `octobooth-1`), not your personal account. Choose GitHub.com, HTTPS, and log in with a web browser:

   ```bash
   gh auth login -h github.com
   ```

2. Add the extra scopes the demos need:

   ```bash
   gh auth refresh -h github.com -s codespace,delete_repo
   ```

   - `codespace`: the Tailspin Toys demo creates a Codespace.
   - `delete_repo`: the Demo Launcher's cleanup deletes old demo repos.

   `gh`'s default scopes (`repo`, `read:org`, `gist`) cover everything else.
3. Check it with `gh auth status`. It should show the booth account as active, with `codespace` and `delete_repo` in its token scopes.

The booth account must be a member of the `octobooth-demos` org and allowed to create repositories there, because several demos create their repo in that org. It also needs a Copilot seat for the demos that use Copilot code review, assigning issues to Copilot, and Codespaces.

If `GH_TOKEN` or `GITHUB_TOKEN` is set, `gh` uses that token instead of this login, and `gh auth refresh` won't run. Unset them on booth machines.

### Troubleshooting Windows package installs

WinGet error `-1978335138` (`0x8A15005E`, pinned certificate mismatch) can occur when querying the Microsoft Store source, even for a package available from the `winget` source. See [microsoft/winget-cli#3109](https://github.com/microsoft/winget-cli/issues/3109). [`setup.ps1`](setup.ps1) explicitly selects `--source winget` to avoid these unrelated Store failures while preserving certificate validation. All entries in `windows.packages` in [`config.json`](config.json) must be available from the `winget` source.

To retry Visual Studio Code installation:

```powershell
winget install --id Microsoft.VisualStudioCode -e --source winget --accept-source-agreements --accept-package-agreements
```

If the error persists, update App Installer through Microsoft Store and check whether a proxy or security product is intercepting HTTPS traffic. Do not disable certificate checks or certificate pinning.

## Demo Launcher

[`octobooth-demos/repo-setup-scripts`](https://github.com/octobooth-demos/repo-setup-scripts) (cloned to `~/repos/repo-setup-scripts`) ships a **Demo Launcher** canvas for the GitHub Copilot app. It creates booth demos in the background with `create-repo.sh`/`create-repo.ps1`, opens sessions for them in the Copilot app, and cleans up old demo repos.

### macOS (and Linux): installed loader and project

On booth machines, do both. The loader makes the launcher available in any session if the app loads user extensions, and the project is a guaranteed fallback.

1. On macOS, run `setup.sh`. On Linux, or a Mac that's already set up, run `install-demo-launcher.sh` (see below). Either one clones the repo to `~/repos/repo-setup-scripts` and runs its `install.sh`.
2. Open the GitHub Copilot app and sign in with the booth/demo account.
3. Add the existing local folder `~/repos/repo-setup-scripts` as a project. Don't clone it again: then the loader and the project use the same checkout, and one `bash install-demo-launcher.sh` (or `git -C ~/repos/repo-setup-scripts pull`) plus an app restart updates both.
4. Ask Copilot to "open the demo launcher" in any session. If that doesn't work, ask from a session in the repo-setup-scripts project.

`setup.sh` fast-forwards an existing `~/repos/repo-setup-scripts` checkout (`git pull --ff-only`) and runs the repo's `.github/extensions/demo-launcher/install.sh` when present. That writes a loader to `${COPILOT_HOME:-~/.copilot}/extensions/demo-launcher/extension.mjs` that imports the launcher from the checkout, so later pulls update it.

### Windows: repo-setup-scripts project

`install.sh` is macOS/Linux only, so on Windows the project is the only way to get the launcher.

1. Open the GitHub Copilot app and sign in with the booth/demo account.
2. Add `~/repos/repo-setup-scripts` (or `octobooth-demos/repo-setup-scripts`) as a project.
3. Start a session in that project and ask Copilot to "open the demo launcher".

### Install or update on a machine that's already set up

Run it from an up-to-date clone, because an old copy installs with old logic:

```bash
git -C ~/repos/machine-setup pull
cd ~/repos/machine-setup
bash install-demo-launcher.sh
```

It's safe to re-run. It:

1. Checks for `gh`, `git`, and `jq` (`brew install gh jq`) and that the GitHub CLI is logged in. Logging in is interactive, so if it isn't, the script prints the `gh auth login` command to run and stops. It also warns if the login is missing the `codespace`/`delete_repo` scopes (`gh auth refresh -h github.com -s codespace,delete_repo`).
2. Clones `octobooth-demos/repo-setup-scripts` to `~/repos/repo-setup-scripts`, or pulls it if it's already there.
3. Runs `install.sh` to (re)write the loader.

Then restart the GitHub Copilot app (or reload extensions) and ask Copilot to "open the demo launcher" in any session to check it works. To remove it, run `bash install-demo-launcher.sh --uninstall`.

### Two Demo Launchers show up

On Copilot app builds with staff features, the app-wide canvas picker can list two "Demo Launcher" canvases: the installed loader (`user:demo-launcher`) and the project's copy (`project:demo-launcher`). Booth machines run without staff features, so this shouldn't happen there. Both are the same launcher and either one works. To hide one, remove `repo-setup-scripts` from the app's projects and restart the app, but keep the clone in `~/repos/repo-setup-scripts` because the loader imports from it.

For more on the Demo Launcher itself, see the [repo-setup-scripts quick start](https://github.com/octobooth-demos/repo-setup-scripts#quick-start-booth-machine).

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