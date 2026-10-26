Describe 'install-demo-launcher.ps1' {
    BeforeAll {
        . (Join-Path (Get-Location) 'install-demo-launcher.ps1')

        Mock Write-Info { }
        Mock Write-Success { }
        Mock Write-Warn { }
        Mock Write-Err { }
        Mock Write-Host { }
        Mock Out-Host { }
    }

    BeforeEach {
        $script:originalUserProfile = $env:USERPROFILE
        $env:USERPROFILE = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        New-Item -Path $env:USERPROFILE -ItemType Directory -Force | Out-Null
        $script:calls = [System.Collections.Generic.List[string]]::new()
        $script:ghLoggedIn = $true
        $script:gitExitCode = 0
        $script:originUrl = 'https://github.com/octobooth-demos/repo-setup-scripts.git'

        Mock git {
            if ($args -contains 'remote') {
                $global:LASTEXITCODE = 0
                return $script:originUrl
            }
            $script:calls.Add("git $($args -join ' ')")
            $global:LASTEXITCODE = $script:gitExitCode
        }
        Mock gh {
            $script:calls.Add("gh $($args -join ' ')")
            if ($args[0] -eq 'auth') {
                $global:LASTEXITCODE = if ($script:ghLoggedIn) { 0 } else { 1 }
            } else {
                $global:LASTEXITCODE = 0
            }
        }
    }

    AfterEach {
        $env:USERPROFILE = $script:originalUserProfile
    }

    It 'reads the repo-setup-scripts repo from config.json' {
        Import-Config
        Get-DemoLauncherRepo | Should -Be 'octobooth-demos/repo-setup-scripts'
    }

    It 'ignores an untrusted repo-setup-scripts entry in config.json' {
        $script:config = [pscustomobject]@{ shared = [pscustomobject]@{ repos_to_clone = @('attacker/repo-setup-scripts') } }

        Get-DemoLauncherRepo | Should -Be 'octobooth-demos/repo-setup-scripts'
        Should -Invoke Write-Warn -Times 1 -Exactly
    }

    It 'accepts SSH remotes for the trusted repo' {
        $script:originUrl = 'git@github.com:octobooth-demos/repo-setup-scripts.git'
        Test-DemoLauncherRemote -Target (Get-DemoLauncherRepoDir) | Should -BeTrue
    }

    It 'refuses to pull a checkout whose origin is not the trusted repo' {
        New-Item -Path (Join-Path (Get-DemoLauncherRepoDir) '.git') -ItemType Directory -Force | Out-Null
        $script:originUrl = 'https://github.com/attacker/repo-setup-scripts.git'

        Invoke-DemoLauncherMain | Should -Be 1

        $script:calls | Where-Object { $_ -like 'git *pull*' } | Should -BeNullOrEmpty
    }

    It 'clones repo-setup-scripts when the checkout is missing' {
        $target = Get-DemoLauncherRepoDir

        Invoke-DemoLauncherMain | Should -Be 0

        $script:calls | Should -Contain "gh repo clone octobooth-demos/repo-setup-scripts $target"
        $script:calls | Where-Object { $_ -like 'git *pull*' } | Should -BeNullOrEmpty
    }

    It 'fast-forwards an existing checkout instead of cloning' {
        $target = Get-DemoLauncherRepoDir
        New-Item -Path (Join-Path $target '.git') -ItemType Directory -Force | Out-Null

        Invoke-DemoLauncherMain | Should -Be 0

        $script:calls | Should -Contain "git -C $target pull --ff-only"
        $script:calls | Where-Object { $_ -like 'gh repo clone*' } | Should -BeNullOrEmpty
    }

    It 'fails without cloning when the GitHub CLI is not logged in' {
        $script:ghLoggedIn = $false

        Invoke-DemoLauncherMain | Should -Be 1

        $script:calls | Where-Object { $_ -like 'gh repo clone*' } | Should -BeNullOrEmpty
        $script:failedItems | Should -HaveCount 1
    }

    It 'reports a failed pull' {
        New-Item -Path (Join-Path (Get-DemoLauncherRepoDir) '.git') -ItemType Directory -Force | Out-Null
        $script:gitExitCode = 1

        Invoke-DemoLauncherMain | Should -Be 1

        $script:failedItems | Should -Contain 'update: octobooth-demos/repo-setup-scripts'
    }

    It 'refuses to overwrite a folder that is not a git checkout' {
        New-Item -Path (Get-DemoLauncherRepoDir) -ItemType Directory -Force | Out-Null

        Invoke-DemoLauncherMain | Should -Be 1

        $script:calls | Where-Object { $_ -like 'gh repo clone*' } | Should -BeNullOrEmpty
    }
}
