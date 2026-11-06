@{
    # =======================================================================
    #  devenv.psd1  --  developer environment setup
    #  Consumed by the DevEnv phase. Everything here is idempotent.
    # =======================================================================

    Git = @{
        UserName  = 'KoiNoYume7'
        UserEmail = 'koinoyume7@gmail.com'
        Defaults  = @{
            'init.defaultBranch' = 'main'
            'pull.rebase'        = 'false'
            'core.autocrlf'      = 'true'
            'core.editor'        = 'code --wait'
        }
    }

    Ssh = @{
        Generate = $true
        Type     = 'ed25519'
        Comment  = 'koinoyume7@gmail.com'    # blank -> uses Git.UserEmail
        # The public key path is printed at the end so you can add it to GitHub.
    }

    VSCode = @{
        # Prefer VS Code's built-in Settings Sync over copying settings.json.
        SettingsSync = $true
        Extensions   = @(
            # 'ms-vscode.powershell'
            # 'esbenp.prettier-vscode'
        )
    }

    Runtimes = @(
        # winget IDs for languages/runtimes you always want:
        # 'OpenJS.NodeJS.LTS'
        # 'Python.Python.3.12'
        # 'GoLang.Go'
    )

    Terminal = @{
        # If you later add a Windows Terminal settings.json to profile/assets/,
        # set Apply = $true to install it.
        Apply      = $false
        SourcePath = 'profile\assets\terminal-settings.json'
    }

    Profile = @{
        # Install a starter pwsh 7 $PROFILE if one does not exist.
        InstallPwshProfile = $true
    }
}
