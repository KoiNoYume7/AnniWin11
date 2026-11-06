@{
    # =======================================================================
    #  settings.psd1  --  desired Windows settings (human-friendly values)
    #  The WinSettings phase maps each of these to the right registry keys and
    #  only writes when the current value differs (idempotent).
    #  Set a value to $null to leave that setting untouched.
    # =======================================================================

    Theme            = 'Dark'    # 'Dark' | 'Light'  (apps + system)
    AccentOnTaskbar  = $null     # $true | $false | $null

    TaskbarAlignment = 'Left'    # 'Left' | 'Center'
    TaskbarSearch    = 'Hide'    # 'Hide' | 'Icon' | 'Box' | 'Label'
    TaskbarWidgets   = $false    # weather/widgets button
    TaskbarTaskView  = $true     # task view button
    TaskbarChat      = $false    # Teams-chat button

    ShowFileExtensions = $true   # show known file extensions
    ShowHiddenFiles    = $true   # show hidden files/folders
    LaunchTo           = 'ThisPC' # 'ThisPC' | 'QuickAccess'  (Explorer start)

    DeveloperMode = $true        # enable Windows Developer Mode
}
