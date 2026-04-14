# ------- SCAN CONFIGS SCRIPT ------- #

# Config path discovery engine with three-tier approach:
#   Tier 1: Community lookup table (app_configs_example.jsonc)
#   Tier 2: Fuzzy AppData scan (name matching with size/exclusion filters)
#   Tier 3: Install directory scan (config file patterns)
#
# When dot-sourced, exports Invoke-ConfigScan which returns config mappings.
# When run directly, runs a scan against the current app list and displays results.
# Requires -Version 7.0

# ------- DEPENDENCIES ------- #
. "$PSScriptRoot\..\lib\Config.ps1"
Import-Module "$PSScriptRoot\..\lib\AnniLog.psd1" -Force

# ------- PATHS ------- #
$LogFile = Get-LogPath -FileName "scan_configs.log"

# ------- INITIALISE LOGGING ------- #
$ProjectConfig = Get-ProjectConfig
Initialize-AnniLog -LogFilePath $LogFile -LogLevel $ProjectConfig.log_level

# ------- CONSTANTS ------- #

# Folders that should never be suggested as config backup candidates
$script:ExcludedFolderNames = @(
    'Temp', 'Cache', 'CrashDumps', 'CrashReports', 'logs', 'Logs',
    'node_modules', 'npm-cache', 'pip', 'pnpm', 'yarn',
    'ShaderCache', 'GPUCache', 'GrShaderCache', 'DawnCache',
    'Code Cache', 'Service Worker', 'ScriptCache',
    'Crashpad', 'BrowserMetrics', 'blob_storage'
)

# File extensions indicating private keys -- NEVER include in backup
$script:PrivateKeyExtensions = @(
    '.key', '.pem', '.pfx', '.p12', '.ppk'
)

# File name patterns indicating private keys
$script:PrivateKeyPatterns = @(
    'id_rsa', 'id_ed25519', 'id_ecdsa', 'id_dsa'
)

# Config file extensions to look for in install directory (Tier 3)
$script:ConfigFileExtensions = @(
    '*.json', '*.ini', '*.cfg', '*.xml', '*.toml', '*.yaml', '*.yml',
    '*.conf', '*.config', '*.properties', '*.db', '*.sqlite'
)

# Subdirectories to skip when scanning install directories (Tier 3)
$script:SkipInstallSubdirs = @(
    'bin', 'lib', 'lib64', 'node_modules', 'vendor', 'dist',
    'build', 'obj', 'packages', 'runtime', 'runtimes'
)

# Browser profile root patterns -- suggest specific subfolders only
$script:BrowserProfileRoots = @(
    'Google\\Chrome\\User Data',
    'BraveSoftware\\Brave-Browser\\User Data',
    'Microsoft\\Edge\\User Data',
    'Mozilla\\Firefox\\Profiles'
)

# ======================================================================
# SECURITY HELPERS
# ======================================================================

function Test-ContainsPrivateKeys {
    <#
    .SYNOPSIS
        Checks if a folder contains private key files.
    .DESCRIPTION
        Returns $true and logs a warning if private key files are found.
        These must NEVER be included in automated backup.
    #>
    [CmdletBinding()]
    param([string]$Path)

    foreach ($ext in $script:PrivateKeyExtensions) {
        $found = Get-ChildItem -Path $Path -Filter "*$ext" -Recurse -ErrorAction SilentlyContinue -Force | Select-Object -First 1
        if ($found) {
            Write-AnniLog -Level WARNING -Message "[Security] Private key file detected in '$Path': $($found.Name) -- folder excluded from backup candidates."
            return $true
        }
    }

    foreach ($pattern in $script:PrivateKeyPatterns) {
        $found = Get-ChildItem -Path $Path -Filter "$pattern*" -Recurse -ErrorAction SilentlyContinue -Force | Select-Object -First 1
        if ($found) {
            Write-AnniLog -Level WARNING -Message "[Security] Private key file detected in '$Path': $($found.Name) -- folder excluded from backup candidates."
            return $true
        }
    }

    return $false
}

function Test-IsSymlink {
    <#
    .SYNOPSIS
        Returns $true if the path is a symlink, junction, or reparse point.
    #>
    [CmdletBinding()]
    param([string]$Path)

    try {
        $item = Get-Item -Path $Path -Force -ErrorAction Stop
        if ($item.LinkType) { return $true }
        if ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) { return $true }
    }
    catch {}
    return $false
}

function Test-IsBrowserProfileRoot {
    <#
    .SYNOPSIS
        Returns $true if the path matches a known browser profile root.
    #>
    [CmdletBinding()]
    param([string]$Path)

    $pathLower = $Path.ToLower()
    foreach ($pattern in $script:BrowserProfileRoots) {
        if ($pathLower -match [regex]::Escape($pattern.ToLower())) {
            return $true
        }
    }
    return $false
}

function Test-IsSystemPath {
    <#
    .SYNOPSIS
        Returns $true if the path is under System32, SysWOW64, or Windows dir.
    #>
    [CmdletBinding()]
    param([string]$Path)

    $pathLower = $Path.ToLower()
    return ($pathLower -match '\\windows\\system32\\' -or
            $pathLower -match '\\windows\\syswow64\\' -or
            $pathLower -match '^[a-z]:\\windows\\$')
}

# ======================================================================
# TIER 1: COMMUNITY LOOKUP TABLE
# ======================================================================

function Find-ConfigInLookupTable {
    <#
    .SYNOPSIS
        Searches the community lookup table for a known config mapping.
    .PARAMETER AppName
        The app name to search for.
    .PARAMETER LookupTable
        The parsed app_configs_example.jsonc data.
    .RETURNS
        The matching entry from the lookup table, or $null.
    #>
    [CmdletBinding()]
    param(
        [string]$AppName,
        [object]$LookupTable
    )

    if (-not $LookupTable -or -not $LookupTable.apps) { return $null }

    # Exact name match (case-insensitive)
    foreach ($entry in $LookupTable.apps) {
        if ($entry.name -and $entry.name.ToLower() -eq $AppName.ToLower()) {
            Write-AnniLog -Level DEBUG -Message "[Tier1] Exact match for '$AppName' in lookup table."
            return $entry
        }
    }

    # Normalised match (strip non-alphanumeric)
    $normalised = ($AppName -replace '[^a-zA-Z0-9]', '').ToLower()
    foreach ($entry in $LookupTable.apps) {
        $entryNorm = ($entry.name -replace '[^a-zA-Z0-9]', '').ToLower()
        if ($entryNorm -eq $normalised) {
            Write-AnniLog -Level DEBUG -Message "[Tier1] Normalised match for '$AppName' -> '$($entry.name)' in lookup table."
            return $entry
        }
    }

    return $null
}

# ======================================================================
# TIER 2: FUZZY APPDATA SCAN
# ======================================================================

function Find-ConfigInAppData {
    <#
    .SYNOPSIS
        Scans AppData locations for folders matching an app name.
    .DESCRIPTION
        Checks %APPDATA%, %LOCALAPPDATA%, and %PROGRAMDATA% for folders
        that match the app name or publisher name. Applies size limits,
        exclusion filters, age filters, and security rules.
    .PARAMETER AppName
        The app name to search for.
    .PARAMETER Publisher
        Optional publisher name for secondary matching.
    .PARAMETER MaxSizeMB
        Maximum folder size in MB before it's skipped.
    .RETURNS
        Array of candidate PSCustomObjects with Path, Size, LastModified, MatchType.
    #>
    [CmdletBinding()]
    param(
        [string]$AppName,
        [string]$Publisher = "",
        [int]$MaxSizeMB = 500
    )

    $searchRoots = @(
        @{ Root = $env:APPDATA;      Type = "appdata" },
        @{ Root = $env:LOCALAPPDATA; Type = "localappdata" },
        @{ Root = $env:PROGRAMDATA;  Type = "programdata" }
    )

    $candidates = @()
    $appLower = $AppName.ToLower()
    $appNorm  = ($AppName -replace '[^a-zA-Z0-9]', '').ToLower()
    $pubLower = $Publisher.ToLower()

    foreach ($sr in $searchRoots) {
        $root = $sr.Root
        if (-not $root -or -not (Test-Path $root)) { continue }

        # Only enumerate top-level subdirectories
        $folders = Get-ChildItem -Path $root -Directory -ErrorAction SilentlyContinue

        foreach ($folder in $folders) {
            $folderName = $folder.Name
            $folderLower = $folderName.ToLower()
            $folderNorm  = ($folderName -replace '[^a-zA-Z0-9]', '').ToLower()

            # --- Exclusion checks ---

            # Skip excluded folder names
            if ($folderLower -in ($script:ExcludedFolderNames | ForEach-Object { $_.ToLower() })) {
                Write-AnniLog -Level DEBUG -Message "[Tier2] Skipped excluded folder: $($folder.FullName)"
                continue
            }

            # Skip symlinks
            if (Test-IsSymlink -Path $folder.FullName) {
                Write-AnniLog -Level DEBUG -Message "[Tier2] Skipped symlink: $($folder.FullName)"
                continue
            }

            # Skip system paths
            if (Test-IsSystemPath -Path $folder.FullName) {
                Write-AnniLog -Level DEBUG -Message "[Tier2] Skipped system path: $($folder.FullName)"
                continue
            }

            # --- Matching ---

            $matchType = $null

            # Match 1: Exact folder name match (case-insensitive)
            if ($folderLower -eq $appLower -or $folderNorm -eq $appNorm) {
                $matchType = "exact"
            }
            # Match 2: Folder name contains app name or publisher
            elseif ($folderLower.Contains($appLower) -or
                    ($appLower.Length -ge 3 -and $folderNorm.Contains($appNorm))) {
                $matchType = "contains"
            }
            elseif ($pubLower -and $pubLower.Length -ge 3 -and $folderLower.Contains($pubLower)) {
                $matchType = "publisher"
            }
            # Match 3: App name contains folder name (folder is substring of app)
            elseif ($folderLower.Length -ge 3 -and $appLower.Contains($folderLower)) {
                $matchType = "substring"
            }
            else {
                continue
            }

            # --- Post-match validation ---

            # Check folder age
            $lastModified = $folder.LastWriteTime
            if ($lastModified -lt (Get-Date).AddYears(-2)) {
                Write-AnniLog -Level DEBUG -Message "[Tier2] Skipped (too old): $($folder.FullName) last modified $($lastModified.ToString('yyyy-MM-dd'))"
                continue
            }

            # Check for private keys
            if (Test-ContainsPrivateKeys -Path $folder.FullName) {
                continue
            }

            # Check if this is a browser profile root
            if (Test-IsBrowserProfileRoot -Path $folder.FullName) {
                Write-AnniLog -Level DEBUG -Message "[Tier2] Browser profile root detected: $($folder.FullName) -- skipping (use specific subfolders from lookup table)"
                continue
            }

            # Measure folder size
            $folderSize = 0
            try {
                $folderSize = (Get-ChildItem -Path $folder.FullName -Recurse -Force -ErrorAction SilentlyContinue |
                    Measure-Object -Property Length -Sum).Sum
                if ($null -eq $folderSize) { $folderSize = 0 }
            }
            catch {
                Write-AnniLog -Level DEBUG -Message "[Tier2] Could not measure size: $($folder.FullName)"
            }

            $sizeMB = [math]::Round($folderSize / 1MB, 1)
            if ($sizeMB -gt $MaxSizeMB) {
                Write-AnniLog -Level DEBUG -Message "[Tier2] Skipped (oversize ${sizeMB}MB > ${MaxSizeMB}MB): $($folder.FullName)"
                continue
            }

            # Check if folder contains only .log files
            $nonLogFiles = Get-ChildItem -Path $folder.FullName -File -Recurse -ErrorAction SilentlyContinue |
                Where-Object { $_.Extension -ne '.log' } | Select-Object -First 1
            if (-not $nonLogFiles) {
                Write-AnniLog -Level DEBUG -Message "[Tier2] Skipped (log-only folder): $($folder.FullName)"
                continue
            }

            $candidates += [PSCustomObject]@{
                Path         = $folder.FullName
                RelPath      = $folderName
                PathType     = $sr.Type
                SizeMB       = $sizeMB
                LastModified = $lastModified
                MatchType    = $matchType
            }
        }
    }

    # Sort by match confidence: exact > contains > publisher > substring
    $priority = @{ "exact" = 0; "contains" = 1; "publisher" = 2; "substring" = 3 }
    $candidates = $candidates | Sort-Object { $priority[$_.MatchType] }

    return $candidates
}

# ======================================================================
# TIER 3: INSTALL DIRECTORY SCAN
# ======================================================================

function Find-ConfigInInstallDir {
    <#
    .SYNOPSIS
        Scans an app's install directory for config files.
    .PARAMETER InstallDir
        The app's install directory path.
    .PARAMETER MaxSizeMB
        Maximum total config file size in MB.
    .RETURNS
        Array of candidate file paths, or empty array.
    #>
    [CmdletBinding()]
    param(
        [string]$InstallDir,
        [int]$MaxSizeMB = 500
    )

    if (-not $InstallDir -or -not (Test-Path $InstallDir)) { return @() }

    # Security: skip system paths and symlinks
    if (Test-IsSystemPath -Path $InstallDir) { return @() }
    if (Test-IsSymlink -Path $InstallDir) { return @() }
    if (Test-ContainsPrivateKeys -Path $InstallDir) { return @() }

    $candidates = @()

    foreach ($pattern in $script:ConfigFileExtensions) {
        $files = Get-ChildItem -Path $InstallDir -Filter $pattern -Recurse -ErrorAction SilentlyContinue -Force |
            Where-Object {
                # Skip files in bin/lib subdirectories
                $relDir = $_.DirectoryName.Substring($InstallDir.Length).TrimStart('\').ToLower()
                $skipThis = $false
                foreach ($skip in $script:SkipInstallSubdirs) {
                    if ($relDir -eq $skip -or $relDir.StartsWith("$skip\")) {
                        $skipThis = $true
                        break
                    }
                }
                -not $skipThis
            }

        foreach ($file in $files) {
            $sizeMB = [math]::Round($file.Length / 1MB, 1)
            if ($sizeMB -gt $MaxSizeMB) { continue }

            $candidates += [PSCustomObject]@{
                Path         = $file.FullName
                RelPath      = $file.FullName.Substring($InstallDir.Length).TrimStart('\')
                SizeMB       = $sizeMB
                LastModified = $file.LastWriteTime
            }
        }
    }

    return $candidates
}

# ======================================================================
# CONFIRMATION FLOW
# ======================================================================

function Confirm-ConfigCandidate {
    <#
    .SYNOPSIS
        Prompts the user to confirm a fuzzy config match.
    .RETURNS
        'Y' (add), 'N' (skip), 'A' (auto-confirm remaining), '?' (open folder)
    #>
    [CmdletBinding()]
    param(
        [string]$AppName,
        [PSCustomObject]$Candidate,
        [bool]$AutoConfirm = $false
    )

    if ($AutoConfirm) {
        Write-AnniLog -Level DEBUG -Message "[Confirm] Auto-confirmed: $($Candidate.Path)"
        return 'Y'
    }

    Write-Host ""
    Write-Host "[ScanConfigs] Found possible config folder for '$AppName':" -ForegroundColor Cyan
    Write-Host ("  Path:          {0}" -f $Candidate.Path)
    Write-Host ("  Size:          {0} MB" -f $Candidate.SizeMB)
    Write-Host ("  Last modified: {0}" -f $Candidate.LastModified.ToString('yyyy-MM-dd'))
    Write-Host ("  Match type:    {0}" -f $Candidate.MatchType)
    Write-Host ""
    Write-Host "  [Y] Add to backup"
    Write-Host "  [N] Skip"
    Write-Host "  [A] Auto-confirm remaining matches"
    Write-Host "  [?] Open folder to inspect"
    Write-Host ""

    while ($true) {
        $choice = Read-Host "  Choice"
        switch ($choice.ToUpper()) {
            'Y' { return 'Y' }
            'N' { return 'N' }
            'A' { return 'A' }
            '?' {
                try {
                    Start-Process "explorer.exe" -ArgumentList $Candidate.Path
                    Write-Host "  (Opened in Explorer)" -ForegroundColor Gray
                }
                catch {
                    Write-Host "  Could not open folder." -ForegroundColor Red
                }
            }
            default {
                Write-Host "  Invalid choice. Enter Y, N, A, or ?" -ForegroundColor Yellow
            }
        }
    }
}

# ======================================================================
# MAIN SCAN FUNCTION
# ======================================================================

function Invoke-ConfigScan {
    <#
    .SYNOPSIS
        Runs the three-tier config discovery for a list of apps.
    .PARAMETER Apps
        Array of app objects from Invoke-AppScan (or equivalent), each with
        at minimum a Name property. Optional: InstallDir, Publisher.
    .RETURNS
        Array of PSCustomObjects in the app_configs.json format, each with
        name, backup_paths (array of type/path), and notes.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$Apps
    )

    $maxSizeMB = $ProjectConfig.max_config_folder_mb
    if (-not $maxSizeMB -or $maxSizeMB -le 0) { $maxSizeMB = 500 }

    $autoConfirmFuzzy = [bool]$ProjectConfig.auto_confirm_fuzzy
    $sessionAutoConfirm = $false

    # Load community lookup table
    $lookupTablePath = Get-ConfigPath -FileName "app_configs_example.jsonc"
    $lookupTable = $null
    if (Test-Path $lookupTablePath) {
        try {
            $lookupTable = Read-JsoncFile -Path $lookupTablePath
            Write-AnniLog -Level INFO -Message "Loaded community lookup table: $($lookupTable.apps.Count) entries."
        }
        catch {
            Write-AnniLog -Level WARNING -Message "Could not parse lookup table: $_"
        }
    } else {
        Write-AnniLog -Level WARNING -Message "Community lookup table not found at $lookupTablePath"
    }

    $results    = @()
    $tier1Count = 0
    $tier2Count = 0
    $tier3Count = 0
    $skippedCount = 0

    foreach ($app in $Apps) {
        $appName = $app.Name
        if (-not $appName) { continue }

        Write-AnniLog -Level DEBUG -Message "Processing: $appName"

        # --- TIER 1: Community lookup table ---
        $lookupMatch = Find-ConfigInLookupTable -AppName $appName -LookupTable $lookupTable
        if ($lookupMatch) {
            $results += [PSCustomObject]@{
                name         = $lookupMatch.name
                backup_paths = $lookupMatch.backup_paths
                notes        = $lookupMatch.notes
                tier         = "lookup"
            }
            $tier1Count++
            Write-AnniLog -Level DEBUG -Message "[Tier1] '$appName' matched in lookup table."
            continue
        }

        # --- TIER 2: Fuzzy AppData scan ---
        $publisher = if ($app.PSObject.Properties['Publisher']) { $app.Publisher } else { "" }
        $appDataCandidates = Find-ConfigInAppData -AppName $appName -Publisher $publisher -MaxSizeMB $maxSizeMB

        if ($appDataCandidates.Count -gt 0) {
            $confirmed = @()
            foreach ($candidate in $appDataCandidates) {
                $useAutoConfirm = $autoConfirmFuzzy -or $sessionAutoConfirm

                $choice = Confirm-ConfigCandidate -AppName $appName -Candidate $candidate -AutoConfirm $useAutoConfirm

                if ($choice -eq 'A') {
                    $sessionAutoConfirm = $true
                    Write-AnniLog -Level WARNING -Message "Auto-confirm enabled for remaining fuzzy matches this session."
                    $confirmed += $candidate
                }
                elseif ($choice -eq 'Y') {
                    $confirmed += $candidate
                }
                else {
                    Write-AnniLog -Level DEBUG -Message "[Tier2] User skipped: $($candidate.Path)"
                }
            }

            if ($confirmed.Count -gt 0) {
                $backupPaths = $confirmed | ForEach-Object {
                    @{ type = $_.PathType; path = $_.RelPath }
                }
                $results += [PSCustomObject]@{
                    name         = $appName
                    backup_paths = @($backupPaths)
                    notes        = "Discovered via AppData scan (fuzzy match). Verify paths are correct."
                    tier         = "appdata"
                }
                $tier2Count++
                continue
            }
        }

        # --- TIER 3: Install directory scan ---
        $installDir = if ($app.PSObject.Properties['InstallDir']) { $app.InstallDir } else { $null }
        if ($installDir) {
            $installCandidates = Find-ConfigInInstallDir -InstallDir $installDir -MaxSizeMB $maxSizeMB

            if ($installCandidates.Count -gt 0) {
                # For Tier 3, just note what was found -- user can review
                $fileList = ($installCandidates | Select-Object -First 5 | ForEach-Object { $_.RelPath }) -join ', '
                $truncated = if ($installCandidates.Count -gt 5) { " (and $($installCandidates.Count - 5) more)" } else { "" }

                Write-AnniLog -Level DEBUG -Message "[Tier3] Found $($installCandidates.Count) config file(s) in install dir for '$appName': $fileList$truncated"

                $backupPaths = @(@{ type = "absolute"; path = $installDir })
                $results += [PSCustomObject]@{
                    name         = $appName
                    backup_paths = $backupPaths
                    notes        = "Config files found in install directory. Review before backup: $fileList$truncated"
                    tier         = "installdir"
                }
                $tier3Count++
                continue
            }
        }

        # No config found at any tier
        Write-AnniLog -Level DEBUG -Message "No config found for '$appName' at any tier."
        $skippedCount++
    }

    Write-AnniLog -Level INFO -Message "Config scan complete: Tier1=$tier1Count, Tier2=$tier2Count, Tier3=$tier3Count, Skipped=$skippedCount"
    return $results
}

# ======================================================================
# STANDALONE EXECUTION
# ======================================================================

if ($MyInvocation.InvocationName -notin @('.', '&')) {
    Write-AnniLog -Level INFO -Message "AnniWin11 Config Scanner (standalone mode)"
    Write-Host ""

    # Load ScanApps to get the app list
    . "$PSScriptRoot\ScanApps.ps1"
    $apps = Invoke-AppScan

    if ($apps.Count -eq 0) {
        Write-AnniLog -Level WARNING -Message "No apps detected. Nothing to scan for configs."
        Close-AnniLog
        Pause
        exit 0
    }

    Write-Host ""
    Write-AnniLog -Level INFO -Message "Scanning config paths for $($apps.Count) detected app(s)..."
    Write-Host ""

    $configResults = Invoke-ConfigScan -Apps $apps

    # Display summary
    Write-Host ""
    Write-Host ("-" * 70)
    Write-Host "Config Scan Summary:" -ForegroundColor Cyan
    Write-Host ("-" * 70)

    $lookupCount  = ($configResults | Where-Object { $_.tier -eq 'lookup' }).Count
    $appdataCount = ($configResults | Where-Object { $_.tier -eq 'appdata' }).Count
    $installdirCount = ($configResults | Where-Object { $_.tier -eq 'installdir' }).Count

    Write-Host ("  Lookup table matches:    {0}" -f $lookupCount) -ForegroundColor Green
    Write-Host ("  AppData fuzzy matches:   {0}" -f $appdataCount) -ForegroundColor Yellow
    Write-Host ("  Install dir matches:     {0}" -f $installdirCount) -ForegroundColor Cyan
    Write-Host ("  Total configs found:     {0}" -f $configResults.Count)
    Write-Host ("  Apps with no config:     {0}" -f ($apps.Count - $configResults.Count))
    Write-Host ("-" * 70)

    # List all found configs
    Write-Host ""
    foreach ($cfg in $configResults) {
        $tierLabel = switch ($cfg.tier) {
            "lookup"     { "[Lookup]" }
            "appdata"    { "[AppData]" }
            "installdir" { "[InstDir]" }
            default      { "[?]" }
        }
        $colour = switch ($cfg.tier) {
            "lookup"     { "Green" }
            "appdata"    { "Yellow" }
            "installdir" { "Cyan" }
            default      { "White" }
        }
        $pathCount = if ($cfg.backup_paths) { $cfg.backup_paths.Count } else { 0 }
        Write-Host ("  {0,-12} {1,-30} ({2} path(s))" -f $tierLabel, $cfg.name, $pathCount) -ForegroundColor $colour
    }

    Write-Host ""
    Close-AnniLog
    Pause
}

# ------- END SCAN CONFIGS SCRIPT ------- #
