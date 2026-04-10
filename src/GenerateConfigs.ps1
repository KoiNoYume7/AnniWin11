# ------- GENERATE CONFIGS SCRIPT ------- #

# Interactive config file generator for AnniWin11.
# Walks the user through creating config/*.json files from the example templates.
# Requires -Version 7.0

# ------- DEPENDENCIES ------- #
. "$PSScriptRoot\..\lib\Config.ps1"
Import-Module "$PSScriptRoot\..\lib\AnniLog.psd1" -Force

# ------- PATHS ------- #
$LogFile    = Get-LogPath -FileName "generate_configs.log"
$ConfigDir  = Join-Path (Get-ProjectRoot) "config"

# ------- INITIALISE LOGGING ------- #
$ProjectConfig = Get-ProjectConfig
Initialize-AnniLog -LogFilePath $LogFile -LogLevel $ProjectConfig.log_level

Write-AnniLog -Level INFO -Message "AnniWin11 Config Generator"
Write-AnniLog -Level INFO -Message "This script will help you create your config files from the example templates."
Write-Host ""

# ------- HELPER FUNCTIONS ------- #

function Read-YesNo {
    param(
        [string]$Prompt,
        [bool]$Default = $true
    )
    $hint = if ($Default) { "(Y/n)" } else { "(y/N)" }
    $answer = Read-Host "$Prompt $hint"
    if ([string]::IsNullOrWhiteSpace($answer)) { return $Default }
    return $answer -match '^[Yy]'
}

function Read-StringInput {
    param(
        [string]$Prompt,
        [string]$Default
    )
    $answer = Read-Host "$Prompt (default: $Default)"
    if ([string]::IsNullOrWhiteSpace($answer)) { return $Default }
    return $answer
}

function Read-ChoiceInput {
    param(
        [string]$Prompt,
        [string[]]$Choices,
        [string]$Default
    )
    $choiceList = ($Choices | ForEach-Object { if ($_ -eq $Default) { "$_ *" } else { $_ } }) -join ", "
    $answer = Read-Host "$Prompt [$choiceList]"
    if ([string]::IsNullOrWhiteSpace($answer)) { return $Default }
    if ($answer -in $Choices) { return $answer }
    Write-AnniLog -Level WARNING -Message "Invalid choice '$answer', using default: $Default"
    return $Default
}

function Copy-ExampleToJson {
    <#
    .SYNOPSIS
        Copies a JSONC example file to a plain JSON output, stripping all comments.
    #>
    param(
        [string]$ExampleFile,
        [string]$OutputFile
    )

    if (-not (Test-Path $ExampleFile)) {
        Write-AnniLog -Level ERROR -Message "Example file not found: $ExampleFile"
        return $false
    }

    try {
        $data = Read-JsoncFile -Path $ExampleFile
        $json = $data | ConvertTo-Json -Depth 10
        $json | Out-File -FilePath $OutputFile -Encoding utf8 -Force
        Write-AnniLog -Level SUCCESS -Message "Created: $OutputFile"
        return $true
    }
    catch {
        Write-AnniLog -Level ERROR -Message "Failed to generate $OutputFile : $_"
        return $false
    }
}

# ------- APPS CONFIG ------- #

function New-AppsConfig {
    $exampleFile = Join-Path $ConfigDir "apps_example.jsonc"
    $outputFile  = Join-Path $ConfigDir "apps.json"

    Write-Host ""
    Write-Host "--- Apps Config (apps.json) ---" -ForegroundColor Cyan

    if (Test-Path $outputFile) {
        if (-not (Read-YesNo -Prompt "apps.json already exists. Overwrite?" -Default $false)) {
            Write-AnniLog -Level INFO -Message "Skipping apps.json (already exists)"
            return
        }
    }

    if (-not (Test-Path $exampleFile)) {
        Write-AnniLog -Level ERROR -Message "apps_example.jsonc not found at $exampleFile"
        return
    }

    Write-Host "The example app list will be used as your starting point."
    Write-Host "You can edit config/apps.json later to add, remove, or recategorise apps."
    Write-Host ""

    if (Read-YesNo -Prompt "Generate apps.json from the example template?") {
        Copy-ExampleToJson -ExampleFile $exampleFile -OutputFile $outputFile | Out-Null
    } else {
        Write-AnniLog -Level INFO -Message "Skipped apps.json generation"
    }
}

# ------- SETTINGS CONFIG ------- #

function New-SettingsConfig {
    $exampleFile = Join-Path $ConfigDir "settings_example.jsonc"
    $outputFile  = Join-Path $ConfigDir "settings.json"

    Write-Host ""
    Write-Host "--- Windows Settings Config (settings.json) ---" -ForegroundColor Cyan

    if (Test-Path $outputFile) {
        if (-not (Read-YesNo -Prompt "settings.json already exists. Overwrite?" -Default $false)) {
            Write-AnniLog -Level INFO -Message "Skipping settings.json (already exists)"
            return
        }
    }

    if (-not (Test-Path $exampleFile)) {
        Write-AnniLog -Level ERROR -Message "settings_example.jsonc not found at $exampleFile"
        return
    }

    # Load defaults from example
    $defaults = Read-JsoncFile -Path $exampleFile

    Write-Host "Answer the following to customise your Windows settings."
    Write-Host "Press Enter to accept the default value shown in parentheses."
    Write-Host ""

    # Device name
    $deviceName = Read-StringInput -Prompt "Device name" -Default $defaults.device_name

    # Region
    $region = Read-StringInput -Prompt "Regional format (e.g. en-CH, en-GB, en-US)" -Default $defaults.region

    # Sound scheme
    $soundScheme = Read-ChoiceInput -Prompt "Sound scheme" -Choices @("none", "default") -Default $defaults.sound_scheme

    # Theme
    $theme = Read-ChoiceInput -Prompt "Theme" -Choices @("dark", "light") -Default $defaults.theme

    # Wallpaper
    $wallpaper = Read-ChoiceInput -Prompt "Wallpaper" -Choices @("solid_black") -Default $defaults.wallpaper

    # Taskbar
    Write-Host ""
    Write-Host "Taskbar settings:" -ForegroundColor Cyan
    $tbAlignment   = Read-ChoiceInput -Prompt "  Alignment" -Choices @("left", "centre") -Default $defaults.taskbar.alignment
    $tbSearch      = Read-YesNo -Prompt "  Show search?" -Default $defaults.taskbar.search
    $tbTaskView    = Read-YesNo -Prompt "  Show Task View button?" -Default $defaults.taskbar.task_view
    $tbWidgets     = Read-YesNo -Prompt "  Show Widgets button?" -Default $defaults.taskbar.widgets
    $tbSeconds     = Read-YesNo -Prompt "  Show seconds in clock?" -Default $defaults.taskbar.show_seconds
    $tbMultiMon    = Read-YesNo -Prompt "  Show taskbar on all monitors?" -Default $defaults.taskbar.multi_monitor

    # Explorer
    Write-Host ""
    Write-Host "Explorer settings:" -ForegroundColor Cyan
    $expThisPC     = Read-YesNo -Prompt "  Open to This PC (instead of Quick Access)?" -Default $defaults.explorer.start_to_this_pc
    $expExt        = Read-YesNo -Prompt "  Show file extensions?" -Default $defaults.explorer.show_extensions
    $expHidden     = Read-YesNo -Prompt "  Show hidden files?" -Default $defaults.explorer.show_hidden
    $expSuperHid   = Read-YesNo -Prompt "  Show protected system files?" -Default $defaults.explorer.show_super_hidden
    $expDesktopIco = Read-YesNo -Prompt "  Show desktop icons?" -Default $defaults.explorer.desktop_icons

    # Developer
    Write-Host ""
    Write-Host "Developer settings:" -ForegroundColor Cyan
    $devMode       = Read-YesNo -Prompt "  Enable Developer Mode?" -Default $defaults.developer.dev_mode
    $devEndTask    = Read-YesNo -Prompt "  Enable End Task button?" -Default $defaults.developer.end_task_button

    # Build the settings object
    $settings = @{
        device_name  = $deviceName
        region       = $region
        sound_scheme = $soundScheme
        theme        = $theme
        wallpaper   = $wallpaper
        taskbar     = @{
            alignment     = $tbAlignment
            search        = $tbSearch
            task_view     = $tbTaskView
            widgets       = $tbWidgets
            show_seconds  = $tbSeconds
            multi_monitor = $tbMultiMon
        }
        explorer    = @{
            start_to_this_pc = $expThisPC
            show_extensions  = $expExt
            show_hidden      = $expHidden
            show_super_hidden = $expSuperHid
            desktop_icons    = $expDesktopIco
        }
        developer   = @{
            dev_mode        = $devMode
            end_task_button = $devEndTask
        }
        taskbar_apps = @()
    }

    Write-Host ""
    Write-Host "Taskbar pinned apps can be added later by editing config/settings.json." -ForegroundColor Yellow

    try {
        $json = $settings | ConvertTo-Json -Depth 5
        $json | Out-File -FilePath $outputFile -Encoding utf8 -Force
        Write-AnniLog -Level SUCCESS -Message "Created: $outputFile"
    }
    catch {
        Write-AnniLog -Level ERROR -Message "Failed to write settings.json: $_"
    }
}

# ------- APP CONFIGS CONFIG ------- #

function New-AppConfigsConfig {
    $exampleFile = Join-Path $ConfigDir "app_configs_example.jsonc"
    $outputFile  = Join-Path $ConfigDir "app_configs.json"

    Write-Host ""
    Write-Host "--- App Configs Mapping (app_configs.json) ---" -ForegroundColor Cyan

    if (Test-Path $outputFile) {
        if (-not (Read-YesNo -Prompt "app_configs.json already exists. Overwrite?" -Default $false)) {
            Write-AnniLog -Level INFO -Message "Skipping app_configs.json (already exists)"
            return
        }
    }

    if (-not (Test-Path $exampleFile)) {
        Write-AnniLog -Level ERROR -Message "app_configs_example.jsonc not found at $exampleFile"
        return
    }

    Write-Host "The example app config mapping defines which config files to back up for each app."
    Write-Host "You can edit config/app_configs.json later to add paths for your specific apps."
    Write-Host ""

    if (Read-YesNo -Prompt "Generate app_configs.json from the example template?") {
        Copy-ExampleToJson -ExampleFile $exampleFile -OutputFile $outputFile | Out-Null
    } else {
        Write-AnniLog -Level INFO -Message "Skipped app_configs.json generation"
    }
}

# ------- MAIN FLOW ------- #

Write-Host "Which config files would you like to generate?" -ForegroundColor Cyan
Write-Host ""
Write-Host "[1] All configs (apps, settings, app_configs)"
Write-Host "[2] Apps config only (apps.json)"
Write-Host "[3] Settings config only (settings.json)"
Write-Host "[4] App configs mapping only (app_configs.json)"
Write-Host "[5] Exit"
Write-Host ""
$choice = Read-Host "Enter your choice (1-5)"

switch ($choice) {
    '1' {
        New-AppsConfig
        New-SettingsConfig
        New-AppConfigsConfig
    }
    '2' { New-AppsConfig }
    '3' { New-SettingsConfig }
    '4' { New-AppConfigsConfig }
    '5' {
        Write-AnniLog -Level INFO -Message "Exiting config generator."
    }
    default {
        Write-AnniLog -Level WARNING -Message "Invalid choice: $choice"
    }
}

Write-Host ""
Write-AnniLog -Level SUCCESS -Message "Config generation complete."
Close-AnniLog
Pause

# ------- END GENERATE CONFIGS SCRIPT ------- #
