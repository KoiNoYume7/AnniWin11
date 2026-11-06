@{
    # =======================================================================
    #  setup.psd1  --  top-level control for an AnniWin11 v2 run
    #  Edit this to turn phases on/off and set global options.
    # =======================================================================

    # Which phases run, and in what order. A phase only runs if it is $true
    # here AND appears in PhaseOrder.
    Phases = @{
        Apps        = $true
        WinSettings = $true
        Debloat     = $true
        DevEnv      = $true
        Accounts    = $false   # optional: create the school standard account
        Backup      = $true
    }

    PhaseOrder = @('Apps', 'WinSettings', 'Debloat', 'DevEnv', 'Accounts', 'Backup')

    # Lowest log level shown on the console (file always gets everything).
    MinLogLevel = 'INFO'

    # Where the Backup phase writes an export of the configured state.
    Backup = @{
        LocalPath = 'D:\AnniWin11-Backup'

        # Forward-looking: push the export to the RPi4 over Tailscale later.
        # Not implemented against the server yet -- leave Enabled = $false.
        Remote = @{
            Enabled = $false
            Host    = ''   # e.g. 'rpi4' (tailscale MagicDNS name)
            Path    = ''   # e.g. '/srv/backups/laptop'
        }
    }
}
