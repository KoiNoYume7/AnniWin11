@{
    # =======================================================================
    #  apps.psd1  --  winget packages to install (personal account)
    #
    #  Each category maps to a list of entries. An entry is either:
    #    - a string  : the winget package Id  (e.g. 'Brave.Brave')
    #    - a hashtable: @{ Id = 'Foo.Bar'; Args = @('--override','...') }
    #
    #  Find IDs with:  winget search <name>
    #  The Apps phase skips anything already installed (idempotent).
    #
    #  NOTE: Teams / Office / anything school-mandated is intentionally NOT
    #  here -- those belong on the separate school account, not this profile.
    # =======================================================================

    Categories = @{

        Browsers = @(
            'Brave.Brave'
        )

        Dev = @(
            'Git.Git'
            'Microsoft.PowerShell'
            'Microsoft.WindowsTerminal'
            'Microsoft.VisualStudioCode'
        )

        # --- Fill these in. Examples left commented as a starting point. -----
        Utilities = @(
            # '7zip.7zip'
            # 'Microsoft.PowerToys'
        )

        Media = @(
            # 'VideoLAN.VLC'
        )

        Comms = @(
            # 'Discord.Discord'
        )
    }
}
