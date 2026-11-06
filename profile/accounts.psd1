@{
    # =======================================================================
    #  accounts.psd1  --  optional local account provisioning
    #
    #  This creates a SEPARATE standard Windows account for school so that
    #  school-mandated apps (Teams, Office, etc.) and any school sign-in stay
    #  off your personal admin profile. The device is NOT enrolled/joined --
    #  the school only gets the app sandbox of this local account.
    #
    #  The Accounts phase runs only if Phases.Accounts = $true in setup.psd1
    #  AND School.Create = $true here.
    #
    #  SECURITY: no password is stored in this file. If a password is needed,
    #  the phase prompts for it interactively (Read-Host -AsSecureString).
    #  You then sign that account into M365/Teams yourself -- the script never
    #  handles school credentials.
    # =======================================================================

    School = @{
        Create   = $false
        UserName = 'School'
        FullName = 'School'
        Type     = 'Standard'   # 'Standard' (recommended) | 'Administrator'

        # If $true, prompt for a password at runtime. If $false, create a
        # passwordless local account (you set a PIN/password on first logon).
        SetPassword = $true
    }
}
