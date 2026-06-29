$script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
. (Join-Path $script:repoRoot 'setup.ps1')

Describe 'setup.ps1' {
    BeforeAll {
        $script:config = Get-Content -Raw -Path (Join-Path $script:repoRoot 'config.json') | ConvertFrom-Json
    }

    BeforeEach {
        $script:failedItems = @()
        Remove-Item Function:\gh -ErrorAction SilentlyContinue
        Remove-Item Env:\SETUP_SCRIPT_DESKTOP_PATH -ErrorAction SilentlyContinue
    }

    AfterEach {
        Remove-Item Function:\gh -ErrorAction SilentlyContinue
        Remove-Item Env:\SETUP_SCRIPT_DESKTOP_PATH -ErrorAction SilentlyContinue
    }

    It 'Set-EditorTheme merges the configured theme into settings.json' {
        $env:APPDATA = Join-Path $TestDrive 'AppData\Roaming'
        $settingsDir = Join-Path $env:APPDATA 'Code\User'
        $settingsPath = Join-Path $settingsDir 'settings.json'
        New-Item -Path $settingsDir -ItemType Directory -Force | Out-Null
        '{"editor.fontSize":14}' | Out-File -FilePath $settingsPath -Encoding utf8

        Set-EditorTheme -Name 'VS Code' -SettingsDir 'Code'

        $settings = Get-Content -Raw -Path $settingsPath | ConvertFrom-Json
        $settings.'workbench.colorTheme' | Should -Be 'Default Dark+'
        $settings.'editor.fontSize' | Should -Be 14
    }

    It 'Register-MCPServers writes local and http server entries' {
        $env:COPILOT_HOME = Join-Path $TestDrive 'copilot'

        Register-MCPServers

        $configPath = Join-Path $env:COPILOT_HOME 'mcp-config.json'
        Test-Path $configPath | Should -BeTrue

        $mcpConfig = Get-Content -Raw -Path $configPath | ConvertFrom-Json
        $mcpConfig.mcpServers.playwright.command | Should -Be 'npx'
        $mcpConfig.mcpServers.'microsoft-learn'.url | Should -Be 'https://learn.microsoft.com/api/mcp'
    }

    It 'Register-MCPServers initializes mcpServers on an existing config that lacks it' {
        $env:COPILOT_HOME = Join-Path $TestDrive 'copilot'
        New-Item -Path $env:COPILOT_HOME -ItemType Directory -Force | Out-Null
        '{"someOtherSetting":true}' | Out-File -FilePath (Join-Path $env:COPILOT_HOME 'mcp-config.json') -Encoding utf8

        Register-MCPServers

        $mcpConfig = Get-Content -Raw -Path (Join-Path $env:COPILOT_HOME 'mcp-config.json') | ConvertFrom-Json
        $mcpConfig.someOtherSetting | Should -BeTrue
        $mcpConfig.mcpServers.playwright.command | Should -Be 'npx'
    }

    It 'New-DemoLoader writes the launcher script to the Desktop path' {
        $desktopPath = Join-Path $TestDrive 'Desktop'
        $env:SETUP_SCRIPT_DESKTOP_PATH = $desktopPath

        New-DemoLoader

        $demoScript = Join-Path $desktopPath 'load-demos.ps1'
        Test-Path $demoScript | Should -BeTrue
        $content = Get-Content -Raw -Path $demoScript
        $content | Should -Match "Start-Process 'https://github.com'"
        $content | Should -Match 'Start-Process "vlc" -ArgumentList "\$env:USERPROFILE\\Videos"'
    }

    It 'Invoke-SafeInstall records native command failures' {
        Invoke-SafeInstall -Description 'example failure' -Action { & cmd /c exit 1 }

        $script:failedItems | Should -Contain 'example failure'
    }

    It 'Get-ChromePath falls back to command lookup when Chrome is not in Program Files' {
        Mock Test-Path { $false } -ParameterFilter { $Path -like '*chrome.exe' }
        Mock Get-Command { [PSCustomObject]@{ Source = 'C:\Tools\chrome.exe' } } -ParameterFilter { $Name -eq 'chrome' }

        Get-ChromePath | Should -Be 'C:\Tools\chrome.exe'
    }

    It 'Copy-Repos skips repositories that already exist' {
        $env:USERPROFILE = $TestDrive
        $reposDir = Join-Path $env:USERPROFILE 'repos'
        $ghLog = Join-Path $TestDrive 'gh.log'
        New-Item -Path $reposDir -ItemType Directory -Force | Out-Null

        foreach ($repo in $script:config.shared.repos_to_clone) {
            $repoName = ($repo -split '/')[-1]
            New-Item -Path (Join-Path $reposDir $repoName) -ItemType Directory -Force | Out-Null
        }

        function global:gh {
            param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Args)
            Add-Content -Path $ghLog -Value ($Args -join ' ')
        }

        Copy-Repos

        Test-Path $ghLog | Should -BeFalse
    }
}
