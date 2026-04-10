# ------- DETECT APPS SCRIPT ------- #

# Scans installed apps via winget, compares against config/apps.json,
# and prompts the user to categorise untracked apps.
# Requires -Version 7.0

# ------- DEPENDENCIES ------- #
. "$PSScriptRoot\..\lib\Config.ps1"
Import-Module "$PSScriptRoot\..\lib\AnniLog.psd1" -Force

# ------- PATHS ------- #
$LogFile          = Get-LogPath -FileName "detect_apps.log"
$AppsConfigFile   = Get-ConfigPath -FileName "apps.json"
$BackupStoreFile  = Get-ConfigPath -FileName "backup_store.json"
$IgnoredAppsFile  = Get-ConfigPath -FileName "ignored_apps.json"

# ------- INITIALISE LOGGING ------- #
$ProjectConfig = Get-ProjectConfig
Initialize-AnniLog -LogFilePath $LogFile -LogLevel $ProjectConfig.log_level

Write-AnniLog -Level INFO -Message "AnniWin11 App Detection"
Write-Host ""

# ------- VALIDATE PREREQUISITES ------- #

if (-not (Test-Path $AppsConfigFile)) {
    Write-AnniLog -Level ERROR -Message "apps.json not found. Run GenerateConfigs.ps1 first."
    Close-AnniLog
    throw "apps.json missing"
}

$appsConfig = Read-JsonFile -Path $AppsConfigFile

# ------- COLLECT KNOWN APP IDS ------- #

function Get-KnownIds {
    param($Config)

    $ids = @()
    foreach ($category in @("MainApps", "AdditionalApps", "Tools", "Deprecated")) {
        if ($Config.$category) {
            foreach ($app in $Config.$category) {
                if ($app.id) {
                    $ids += $app.id.Trim().ToLower()
                }
            }
        }
    }
    return $ids
}

$knownIds = Get-KnownIds -Config $appsConfig
Write-AnniLog -Level INFO -Message "Known app IDs in config: $($knownIds.Count)"

# Load permanently ignored app IDs
$ignoredIds = @()
if (Test-Path $IgnoredAppsFile) {
    try {
        $ignoredData = Read-JsonFile -Path $IgnoredAppsFile
        if ($ignoredData.ignored) {
            $ignoredIds = $ignoredData.ignored | ForEach-Object { $_.id.ToLower() }
        }
        Write-AnniLog -Level DEBUG -Message "Loaded $($ignoredIds.Count) ignored app ID(s)"
    }
    catch {
        Write-AnniLog -Level WARNING -Message "Could not read ignored_apps.json: $_"
    }
}

# ------- RUN WINGET LIST ------- #

Write-AnniLog -Level INFO -Message "Running 'winget list' to detect installed apps..."
Write-Host ""

try {
    $wingetOutput = & winget list --accept-source-agreements 2>&1
    $wingetLines = $wingetOutput | Where-Object { $_ -is [string] }
}
catch {
    Write-AnniLog -Level ERROR -Message "Failed to run 'winget list': $_"
    Close-AnniLog
    exit 1
}

# ------- PARSE WINGET OUTPUT ------- #

# NOTE: This parser uses regex to extract IDs rather than column positions.
# Winget IDs follow the pattern Publisher.AppName or a store/hex ID.
# We also attempt to extract the Source column (winget, msstore, or blank).
# Blank source = installed outside winget (Steam, browser download, local installer, etc.)
# If no apps are detected, verify winget list output manually and update the parser.
function ConvertFrom-WingetList {
    param([string[]]$Lines)

    $results = @()

    foreach ($line in $Lines) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        if ($line -match '^\s*[-]+\s*$') { continue }
        if ($line -match '^\s*Name\s+Id\s+') { continue }
        if ($line -match '^\d+ (upgrade|package)') { continue }
        if ($line -match '^-{3,}') { continue }

        # Match a winget ID in the line
        if ($line -match '\s{2,}([\w][\w\.\-]+[\w])\s+') {
            $appId = $Matches[1]

            if ($appId -match '^\d+[\.\d]+$') { continue }
            if ($appId.Length -lt 3) { continue }

            $appName = ($line -split '\s{2,}')[0].Trim()

            # Determine source: check if line ends with a known source token
            $detectedSource = "manual"
            if ($line -match '\bwinget\s*$') {
                $detectedSource = "winget"
            } elseif ($line -match '\bmsstore\s*$') {
                $detectedSource = "msstore"
            }

            if ($appName -and $appId -and $appName -ne $appId) {
                $results += [PSCustomObject]@{
                    Name   = $appName
                    Id     = $appId
                    Source = $detectedSource
                }
            }
        }
    }

    $results = $results | Sort-Object Id -Unique
    return $results
}

function Get-InstallNotes {
    param([string]$Name, [string]$Id)

    # Detect well-known launchers/stores from name patterns
    $knownPatterns = @(
        @{ Pattern = 'steam|steamapp';          Note = "Installed via Steam" },
        @{ Pattern = 'epic|epicgames';           Note = "Installed via Epic Games" },
        @{ Pattern = 'gog|gogalaxy';             Note = "Installed via GOG Galaxy" },
        @{ Pattern = 'rockstar|socialclub';      Note = "Installed via Rockstar Games Launcher" },
        @{ Pattern = 'ubisoft|uplay|ubiconnect'; Note = "Installed via Ubisoft Connect" },
        @{ Pattern = 'battlenet|battle\.net';    Note = "Installed via Battle.net" },
        @{ Pattern = 'origin|eaapp|ea app';      Note = "Installed via EA App" },
        @{ Pattern = 'nvidia|geforce';           Note = "NVIDIA component -- do not reinstall manually" },
        @{ Pattern = 'intel.*driver|killer.*driver'; Note = "Hardware driver -- reinstalls with system" },
        @{ Pattern = 'microsoft.*runtime|vcredist|dotnet.*native'; Note = "Runtime/dependency -- reinstalls automatically" }
    )

    $nameLower = $Name.ToLower()
    $idLower   = $Id.ToLower()

    foreach ($entry in $knownPatterns) {
        if ($nameLower -match $entry.Pattern -or $idLower -match $entry.Pattern) {
            return $entry.Note
        }
    }

    return "Manually installed -- update source if needed"
}

$installedApps = ConvertFrom-WingetList -Lines $wingetLines

if ($installedApps.Count -eq 0) {
    Write-AnniLog -Level WARNING -Message "No apps detected from winget list."
    Close-AnniLog
    exit 0
}

Write-AnniLog -Level INFO -Message "Detected $($installedApps.Count) installed app(s) from winget."

# ------- FIND UNTRACKED APPS ------- #

$untrackedApps = $installedApps | Where-Object {
    $_.Id -and
    ($_.Id.ToLower() -notin $knownIds) -and
    ($_.Id.ToLower() -notin $ignoredIds)
}

Write-AnniLog -Level INFO -Message "Untracked apps (not in apps.json): $($untrackedApps.Count)"

if ($untrackedApps.Count -eq 0) {
    Write-Host ""
    Write-AnniLog -Level SUCCESS -Message "All detected apps are already in your config."
    Close-AnniLog
    Pause
    exit 0
}

# ------- CHECK FOR NEW SINCE LAST BACKUP ------- #

$newSinceBackup = @()
if (Test-Path $BackupStoreFile) {
    $backupStore = Read-JsonFile -Path $BackupStoreFile
    $wingetExportPath = Join-Path $backupStore.backup_root "winget_export.json"

    if (Test-Path $wingetExportPath) {
        try {
            $exportData = Read-JsonFile -Path $wingetExportPath
            $exportIds = @()
            if ($exportData.Sources) {
                foreach ($source in $exportData.Sources) {
                    if ($source.Packages) {
                        foreach ($pkg in $source.Packages) {
                            if ($pkg.PackageIdentifier) {
                                $exportIds += $pkg.PackageIdentifier
                            }
                        }
                    }
                }
            }

            $exportIds = $exportIds | ForEach-Object { $_.ToLower() }

            if ($exportIds.Count -gt 0) {
                $newSinceBackup = $installedApps | Where-Object {
                    $_.Id -and ($_.Id.ToLower() -notin $exportIds) -and ($_.Id.ToLower() -notin $knownIds)
                }
                if ($newSinceBackup.Count -gt 0) {
                    Write-Host ""
                    Write-AnniLog -Level INFO -Message "New installs since last backup: $($newSinceBackup.Count)"
                    foreach ($app in $newSinceBackup) {
                        Write-AnniLog -Level INFO -Message "  [NEW] $($app.Name) ($($app.Id))"
                    }
                }
            }
        }
        catch {
            Write-AnniLog -Level DEBUG -Message "Could not parse winget export for comparison: $_"
        }
    }
}

# ------- PROMPT USER TO CATEGORISE ------- #

Write-Host ""
Write-Host "The following apps are installed but not in your apps.json:" -ForegroundColor Cyan
Write-Host ("-" * 60)

$additions = @{
    MainApps       = @()
    AdditionalApps = @()
    Tools          = @()
}

$ignoresToWrite = @()

foreach ($app in $untrackedApps) {
    # Generate install notes for manual-source apps
    if ($app.Source -eq "manual" -or $app.Source -eq "msstore") {
        $app | Add-Member -NotePropertyName Notes -NotePropertyValue (Get-InstallNotes -Name $app.Name -Id $app.Id) -Force
    } else {
        $app | Add-Member -NotePropertyName Notes -NotePropertyValue $null -Force
    }

    Write-Host ""
    Write-Host "  $($app.Name)" -ForegroundColor White -NoNewline
    Write-Host "  ($($app.Id))" -ForegroundColor Gray -NoNewline

    # Show detected source as a hint
    switch ($app.Source) {
        "winget"  { Write-Host "  [winget]" -ForegroundColor Green }
        "msstore" { Write-Host "  [Microsoft Store]" -ForegroundColor Cyan }
        "manual"  { Write-Host "  [manual install]" -ForegroundColor Yellow }
        default   { Write-Host "" }
    }

    if ($app.Notes) {
        Write-Host "  Note: $($app.Notes)" -ForegroundColor DarkGray
    }

    Write-Host "  Add to: [1] MainApps  [2] AdditionalApps  [3] Tools  [I] Ignore forever  [Enter] Skip"
    $choice = Read-Host "  Choice"

    switch ($choice) {
        '1' {
            $entry = @{ name = $app.Name; source = $app.Source; id = $app.Id }
            if ($app.Notes) { $entry.notes = $app.Notes }
            $additions.MainApps += $entry
            Write-AnniLog -Level INFO -Message "Added '$($app.Name)' to MainApps"
        }
        '2' {
            $entry = @{ name = $app.Name; source = $app.Source; id = $app.Id }
            if ($app.Notes) { $entry.notes = $app.Notes }
            $additions.AdditionalApps += $entry
            Write-AnniLog -Level INFO -Message "Added '$($app.Name)' to AdditionalApps"
        }
        '3' {
            $entry = @{ name = $app.Name; source = $app.Source; id = $app.Id }
            if ($app.Notes) { $entry.notes = $app.Notes }
            $additions.Tools += $entry
            Write-AnniLog -Level INFO -Message "Added '$($app.Name)' to Tools"
        }
        { $_ -in @('I', 'i') } {
            $newIgnore = @{ id = $app.Id; name = $app.Name; ignored_at = (Get-Date -Format "yyyy-MM-dd") }
            $ignoresToWrite += $newIgnore
            Write-AnniLog -Level INFO -Message "Ignored '$($app.Name)' permanently"
        }
        default {
            Write-AnniLog -Level DEBUG -Message "Skipped '$($app.Name)'"
        }
    }
}

# ------- WRITE ADDITIONS ------- #

$totalAdded = $additions.MainApps.Count + $additions.AdditionalApps.Count + $additions.Tools.Count

if ($totalAdded -eq 0 -and $ignoresToWrite.Count -eq 0) {
    Write-Host ""
    Write-AnniLog -Level INFO -Message "No apps selected for addition."
    Close-AnniLog
    Pause
    exit 0
}

if ($totalAdded -gt 0) {
    Write-Host ""
    Write-AnniLog -Level INFO -Message "Adding $totalAdded app(s) to apps.json..."

    # Confirm before writing
    Write-Host ""
    $confirm = Read-Host "Write $totalAdded addition(s) to apps.json? (Y/n)"
    if ($confirm -match '^[Nn]') {
        Write-AnniLog -Level INFO -Message "Cancelled. No changes written to apps.json."
    } else {
        # Merge additions into existing config
        if ($additions.MainApps.Count -gt 0) {
            $existing = @($appsConfig.MainApps)
            $existing += $additions.MainApps
            $appsConfig.MainApps = $existing
        }

        if ($additions.AdditionalApps.Count -gt 0) {
            $existing = @($appsConfig.AdditionalApps)
            $existing += $additions.AdditionalApps
            $appsConfig.AdditionalApps = $existing
        }

        if ($additions.Tools.Count -gt 0) {
            $existing = @($appsConfig.Tools)
            $existing += $additions.Tools
            $appsConfig.Tools = $existing
        }

        try {
            $appsConfig | ConvertTo-Json -Depth 5 | Out-File -FilePath $AppsConfigFile -Encoding utf8 -Force
            Write-AnniLog -Level SUCCESS -Message "apps.json updated with $totalAdded new app(s)."
        }
        catch {
            Write-AnniLog -Level ERROR -Message "Failed to write apps.json: $_"
        }
    }
}

# ------- WRITE IGNORED APPS ------- #

if ($ignoresToWrite.Count -gt 0) {
    # Load existing ignored list or start fresh
    $existingIgnored = @()
    if (Test-Path $IgnoredAppsFile) {
        try {
            $existing = Read-JsonFile -Path $IgnoredAppsFile
            if ($existing.ignored) { $existingIgnored = $existing.ignored }
        }
        catch { }
    }

    $mergedIgnored = @($existingIgnored) + $ignoresToWrite
    $ignoreConfig = @{ ignored = $mergedIgnored }

    try {
        $ignoreConfig | ConvertTo-Json -Depth 5 | Out-File -FilePath $IgnoredAppsFile -Encoding utf8 -Force
        Write-AnniLog -Level SUCCESS -Message "Saved $($ignoresToWrite.Count) app(s) to ignored list."
    }
    catch {
        Write-AnniLog -Level ERROR -Message "Failed to write ignored_apps.json: $_"
    }
}

Write-Host ""
Close-AnniLog
Pause

# ------- END DETECT APPS SCRIPT ------- #
