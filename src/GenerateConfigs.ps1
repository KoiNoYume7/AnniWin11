# ------- GENERATE CONFIGS SCRIPT ------- #

# Interactive config file generator for AnniWin11.
# v0.6.0 rewrite: orchestrates ScanApps + ScanConfigs to detect installed
# apps and discover their config paths, then writes apps.json and
# app_configs.json from the results. Settings config generation carried
# over from v0.1.0.
#
# Steps 2-4 (app detection + categorisation) and steps 5-7 (config
# discovery) can be run independently via the main menu.
# Requires -Version 7.0

# ------- DEPENDENCIES ------- #
. "$PSScriptRoot\..\lib\Config.ps1"
Import-Module "$PSScriptRoot\..\lib\AnniLog.psd1" -Force

# ------- PATHS ------- #
$LogFile         = Get-LogPath -FileName "generate_configs.log"
$ConfigDir       = Join-Path (Get-ProjectRoot) "config"
$AppsFile        = Join-Path $ConfigDir "apps.json"
$AppConfigsFile  = Join-Path $ConfigDir "app_configs.json"
$IgnoredAppsFile = Join-Path $ConfigDir "ignored_apps.json"
$BackupStoreFile = Join-Path $ConfigDir "backup_store.json"

# ------- INITIALISE LOGGING ------- #
$ProjectConfig = Get-ProjectConfig
Initialize-AnniLog -LogFilePath $LogFile -LogLevel $ProjectConfig.log_level

Write-AnniLog -Level INFO -Message "AnniWin11 Config Generator"
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

function Test-OverwriteOk {
    <#
    .SYNOPSIS
        Checks if an output file already exists and prompts before overwriting.
    .RETURNS
        $true if it's safe to write (file doesn't exist or user approved).
    #>
    param([string]$FilePath, [string]$DisplayName)

    if (Test-Path $FilePath) {
        Write-Host ""
        Write-AnniLog -Level WARNING -Message "$DisplayName already exists at: $FilePath"
        if (-not (Read-YesNo -Prompt "  Overwrite $DisplayName?" -Default $false)) {
            Write-AnniLog -Level INFO -Message "Skipping $DisplayName (user chose not to overwrite)."
            return $false
        }
    }
    return $true
}

# ======================================================================
# STEP 1: PREREQUISITES CHECK
# ======================================================================

function Test-Prerequisites {
    Write-Host "--- Step 1: Prerequisites ---" -ForegroundColor Cyan
    Write-Host ""

    $ok = $true

    if (-not (Test-Path $BackupStoreFile)) {
        Write-AnniLog -Level WARNING -Message "backup_store.json not found. DriveSetup has not been run yet."
        Write-Host "  You should run DriveSetup first to configure your backup destination."
        Write-Host "  Config generation can still proceed, but backup won't work until DriveSetup is done."
        Write-Host ""
    } else {
        $store = Read-JsonFile -Path $BackupStoreFile
        Write-AnniLog -Level INFO -Message "Backup root: $($store.backup_root)"
    }

    return $ok
}

# ======================================================================
# STEPS 2-4: APP DETECTION AND CATEGORISATION
# ======================================================================

function Invoke-AppDetectionFlow {
    <#
    .SYNOPSIS
        Runs ScanApps, lets user categorise detected apps, writes apps.json.
    .RETURNS
        The apps.json data structure (for use by config scan step).
    #>

    Write-Host ""
    Write-Host "--- Steps 2-4: App Detection & Categorisation ---" -ForegroundColor Cyan
    Write-Host ""

    # Check if apps.json already exists
    if (-not (Test-OverwriteOk -FilePath $AppsFile -DisplayName "apps.json")) {
        # Load existing and return it for use by config scan
        try {
            return Read-JsonFile -Path $AppsFile
        }
        catch {
            Write-AnniLog -Level ERROR -Message "Could not read existing apps.json: $_"
            return $null
        }
    }

    # --- Step 2: Run ScanApps ---
    Write-Host ""
    Write-AnniLog -Level INFO -Message "Step 2: Scanning installed apps (winget + Start Menu)..."
    Write-Host ""

    . "$PSScriptRoot\ScanApps.ps1"
    $detectedApps = @(Invoke-AppScan)

    if ($detectedApps.Count -eq 0) {
        Write-AnniLog -Level WARNING -Message "No apps detected. Cannot generate apps.json."
        return $null
    }

    Write-Host ""
    Write-AnniLog -Level INFO -Message "Detected $($detectedApps.Count) app(s). Now categorise each one."
    Write-Host ""

    # Load ignored apps
    $ignoredIds = @()
    if (Test-Path $IgnoredAppsFile) {
        try {
            $ignoredData = Read-JsonFile -Path $IgnoredAppsFile
            if ($ignoredData.ignored) {
                $ignoredIds = $ignoredData.ignored | ForEach-Object { $_.id.ToLower() }
            }
        }
        catch {}
    }

    # --- Step 3: Categorise ---
    $categories = @{
        MainApps       = [System.Collections.ArrayList]::new()
        AdditionalApps = [System.Collections.ArrayList]::new()
        Tools          = [System.Collections.ArrayList]::new()
        Deprecated     = [System.Collections.ArrayList]::new()
    }
    $newIgnores = @()

    Write-Host "For each app, choose a category:" -ForegroundColor Cyan
    Write-Host "  [1] MainApps   [2] AdditionalApps   [3] Tools   [I] Ignore   [Enter] Skip"
    Write-Host ""

    foreach ($app in $detectedApps) {
        # Skip already-ignored apps
        if ($app.Id -and ($app.Id.ToLower() -in $ignoredIds)) {
            Write-AnniLog -Level DEBUG -Message "Skipped (ignored): $($app.Name)"
            continue
        }

        $idDisplay = if ($app.Id) { $app.Id } else { "(no winget ID)" }
        $srcColour = switch ($app.Source) {
            "winget"  { "Green" }
            "msstore" { "Cyan" }
            default   { "Yellow" }
        }

        Write-Host "  $($app.Name)" -ForegroundColor White -NoNewline
        Write-Host "  $idDisplay" -ForegroundColor Gray -NoNewline
        Write-Host "  [$($app.Source)]" -ForegroundColor $srcColour

        $choice = Read-Host "  Category"

        $entry = @{ name = $app.Name; source = $app.Source }
        if ($app.Id) { $entry.id = $app.Id }
        if ($app.Executable) { $entry.executable = $app.Executable }
        if ($app.Notes -and $app.Source -eq "manual") { $entry.notes = $app.Notes }

        switch ($choice) {
            '1' {
                [void]$categories.MainApps.Add($entry)
                Write-AnniLog -Level DEBUG -Message "  -> MainApps: $($app.Name)"
            }
            '2' {
                [void]$categories.AdditionalApps.Add($entry)
                Write-AnniLog -Level DEBUG -Message "  -> AdditionalApps: $($app.Name)"
            }
            '3' {
                [void]$categories.Tools.Add($entry)
                Write-AnniLog -Level DEBUG -Message "  -> Tools: $($app.Name)"
            }
            { $_ -in @('I', 'i') } {
                if ($app.Id) {
                    $newIgnores += @{ id = $app.Id; name = $app.Name; ignored_at = (Get-Date -Format "yyyy-MM-dd") }
                }
                Write-AnniLog -Level DEBUG -Message "  -> Ignored: $($app.Name)"
            }
            default {
                Write-AnniLog -Level DEBUG -Message "  -> Skipped: $($app.Name)"
            }
        }
    }

    # --- Step 4: Write apps.json ---
    $totalCategorised = $categories.MainApps.Count + $categories.AdditionalApps.Count + $categories.Tools.Count

    if ($totalCategorised -eq 0) {
        Write-AnniLog -Level WARNING -Message "No apps were categorised. apps.json not written."
        return $null
    }

    $appsConfig = @{
        MainApps       = @($categories.MainApps)
        AdditionalApps = @($categories.AdditionalApps)
        Tools          = @($categories.Tools)
        Deprecated     = @($categories.Deprecated)
    }

    Write-Host ""
    Write-AnniLog -Level INFO -Message "Categorised: $($categories.MainApps.Count) Main, $($categories.AdditionalApps.Count) Additional, $($categories.Tools.Count) Tools"

    $confirm = Read-YesNo -Prompt "Write apps.json with $totalCategorised app(s)?"
    if ($confirm) {
        try {
            $appsConfig | ConvertTo-Json -Depth 5 | Out-File -FilePath $AppsFile -Encoding utf8 -Force
            Write-AnniLog -Level SUCCESS -Message "Written: $AppsFile"
        }
        catch {
            Write-AnniLog -Level ERROR -Message "Failed to write apps.json: $_"
        }
    }

    # Write new ignores
    if ($newIgnores.Count -gt 0) {
        $existingIgnored = @()
        if (Test-Path $IgnoredAppsFile) {
            try {
                $existing = Read-JsonFile -Path $IgnoredAppsFile
                if ($existing.ignored) { $existingIgnored = $existing.ignored }
            }
            catch {}
        }
        $merged = @($existingIgnored) + $newIgnores
        try {
            @{ ignored = $merged } | ConvertTo-Json -Depth 5 | Out-File -FilePath $IgnoredAppsFile -Encoding utf8 -Force
            Write-AnniLog -Level SUCCESS -Message "Saved $($newIgnores.Count) app(s) to ignored list."
        }
        catch {
            Write-AnniLog -Level ERROR -Message "Failed to write ignored_apps.json: $_"
        }
    }

    return $appsConfig
}

# ======================================================================
# STEPS 5-7: CONFIG DISCOVERY
# ======================================================================

function Invoke-ConfigDiscoveryFlow {
    <#
    .SYNOPSIS
        Runs ScanConfigs against the confirmed app list, writes app_configs.json.
    .PARAMETER AppsConfig
        The apps.json data structure (from Invoke-AppDetectionFlow or loaded from file).
    #>
    param([object]$AppsConfig)

    Write-Host ""
    Write-Host "--- Steps 5-7: Config Path Discovery ---" -ForegroundColor Cyan
    Write-Host ""

    if (-not (Test-OverwriteOk -FilePath $AppConfigsFile -DisplayName "app_configs.json")) {
        return
    }

    # Build a flat app list from all categories for ScanConfigs
    $allApps = @()
    foreach ($category in @("MainApps", "AdditionalApps", "Tools")) {
        if ($AppsConfig.$category) {
            foreach ($app in $AppsConfig.$category) {
                $allApps += [PSCustomObject]@{
                    Name       = $app.name
                    Id         = if ($app.PSObject.Properties['id']) { $app.id } else { $null }
                    Source     = if ($app.PSObject.Properties['source']) { $app.source } else { "manual" }
                    InstallDir = if ($app.PSObject.Properties['install_dir']) { $app.install_dir } else { $null }
                    Executable = if ($app.PSObject.Properties['executable']) { $app.executable } else { $null }
                    Publisher  = ""
                }
            }
        }
    }

    if ($allApps.Count -eq 0) {
        Write-AnniLog -Level WARNING -Message "No apps in config. Nothing to scan for configs."
        return
    }

    Write-AnniLog -Level INFO -Message "Step 5: Scanning config paths for $($allApps.Count) app(s)..."
    Write-Host ""

    # Dot-source ScanConfigs (and ScanApps if not already loaded)
    if (-not (Get-Command Invoke-ConfigScan -ErrorAction SilentlyContinue)) {
        . "$PSScriptRoot\ScanConfigs.ps1"
    }

    # --- Step 6: Run scan (user confirms fuzzy matches during this step) ---
    $configResults = Invoke-ConfigScan -Apps $allApps

    if ($configResults.Count -eq 0) {
        Write-AnniLog -Level WARNING -Message "No config paths discovered. app_configs.json not written."
        return
    }

    # --- Step 7: Write app_configs.json ---
    Write-Host ""
    Write-AnniLog -Level INFO -Message "Discovered config paths for $($configResults.Count) app(s)."

    # Build the app_configs.json structure
    $appConfigsData = @{
        apps = @($configResults | ForEach-Object {
            @{
                name         = $_.name
                backup_paths = @($_.backup_paths)
                notes        = $_.notes
            }
        })
    }

    $confirm = Read-YesNo -Prompt "Write app_configs.json with $($configResults.Count) app(s)?"
    if ($confirm) {
        try {
            $appConfigsData | ConvertTo-Json -Depth 10 | Out-File -FilePath $AppConfigsFile -Encoding utf8 -Force
            Write-AnniLog -Level SUCCESS -Message "Written: $AppConfigsFile"
        }
        catch {
            Write-AnniLog -Level ERROR -Message "Failed to write app_configs.json: $_"
        }
    }
}

# ======================================================================
# SETTINGS CONFIG (carried over from v0.1.0)
# ======================================================================

function New-SettingsConfig {
    $exampleFile = Join-Path $ConfigDir "settings_example.jsonc"
    $outputFile  = Join-Path $ConfigDir "settings.json"

    Write-Host ""
    Write-Host "--- Windows Settings Config (settings.json) ---" -ForegroundColor Cyan

    if (-not (Test-OverwriteOk -FilePath $outputFile -DisplayName "settings.json")) {
        return
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

# ======================================================================
# SUMMARY
# ======================================================================

function Show-GenerationSummary {
    Write-Host ""
    Write-Host ("-" * 60)
    Write-Host "Generation Summary:" -ForegroundColor Cyan
    Write-Host ("-" * 60)

    $files = @(
        @{ Name = "apps.json";        Path = $AppsFile },
        @{ Name = "app_configs.json"; Path = $AppConfigsFile },
        @{ Name = "settings.json";    Path = Join-Path $ConfigDir "settings.json" },
        @{ Name = "backup_store.json"; Path = $BackupStoreFile }
    )

    foreach ($f in $files) {
        if (Test-Path $f.Path) {
            Write-Host ("  {0,-22} OK" -f $f.Name) -ForegroundColor Green
        } else {
            Write-Host ("  {0,-22} MISSING" -f $f.Name) -ForegroundColor Yellow
        }
    }

    Write-Host ("-" * 60)
}

# ======================================================================
# MAIN FLOW
# ======================================================================

Write-Host "What would you like to generate?" -ForegroundColor Cyan
Write-Host ""
Write-Host "  [1] Full pipeline (detect apps -> categorise -> scan configs -> settings)"
Write-Host "  [2] Detect and categorise apps only (apps.json)"
Write-Host "  [3] Scan config paths only (app_configs.json -- requires apps.json)"
Write-Host "  [4] Windows settings only (settings.json)"
Write-Host "  [5] Exit"
Write-Host ""
$choice = Read-Host "Enter your choice (1-5)"

switch ($choice) {
    '1' {
        # Full pipeline
        Test-Prerequisites
        $appsConfig = Invoke-AppDetectionFlow
        if ($appsConfig) {
            Invoke-ConfigDiscoveryFlow -AppsConfig $appsConfig
        }
        New-SettingsConfig
        Show-GenerationSummary
    }
    '2' {
        # Apps only
        Invoke-AppDetectionFlow | Out-Null
    }
    '3' {
        # Config paths only (requires apps.json)
        if (-not (Test-Path $AppsFile)) {
            Write-AnniLog -Level ERROR -Message "apps.json not found. Run app detection first (option 2 or 1)."
        } else {
            $appsConfig = Read-JsonFile -Path $AppsFile
            Invoke-ConfigDiscoveryFlow -AppsConfig $appsConfig
        }
    }
    '4' {
        # Settings only
        New-SettingsConfig
    }
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
