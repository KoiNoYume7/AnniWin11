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
    #
    #  Laptop set: populated from `winget list` on 2026-11-06 (laptop scan).
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
            'Kitware.CMake'
            'OpenJS.NodeJS.LTS'
            'Python.Python.3.13'
            'Microsoft.DotNet.SDK.8'
            'Microsoft.VisualStudio.2022.BuildTools'
            'CognitionAI.DevinDesktop'
            'Anthropic.Claude'
        )

        Utilities = @(
            'Tailscale.Tailscale'
            # '7zip.7zip'
            # 'Microsoft.PowerToys'
        )

        Media = @(
            'Spotify.Spotify'
            'ElementLabs.LMStudio'
            # 'VideoLAN.VLC'
        )

        Comms = @(
            'Discord.Discord'
        )

        Gaming = @(
            'Valve.Steam'
        )
    }
}
