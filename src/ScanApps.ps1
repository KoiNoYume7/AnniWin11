# ------- SCAN APPS SCRIPT ------- #

# System app scanner with two scan sources:
#   Source 1: winget list (regex parser carried over from DetectApps.ps1)
#   Source 2: Start Menu shortcut scan (.lnk resolution via WScript.Shell COM)
#
# Outputs a unified, deduplicated app list. Designed to be called by
# GenerateConfigs.ps1 or run standalone for diagnostics.
#
# When dot-sourced, exports Invoke-AppScan which returns the app list.
# When run directly, prints results to console and writes scan_results.json.
# Requires -Version 7.0

# ------- DEPENDENCIES ------- #
. "$PSScriptRoot\..\lib\Config.ps1"
Import-Module "$PSScriptRoot\..\lib\AnniLog.psd1" -Force

# ------- PATHS ------- #
$LogFile = Get-LogPath -FileName "scan_apps.log"

# ------- INITIALISE LOGGING ------- #
$ProjectConfig = Get-ProjectConfig
Initialize-AnniLog -LogFilePath $LogFile -LogLevel $ProjectConfig.log_level

# ======================================================================
# SOURCE 1: WINGET LIST
# ======================================================================

function Get-WingetApps {
    <#
    .SYNOPSIS
        Runs 'winget list' and parses the output into structured objects.
    .DESCRIPTION
        Regex-based parser carried over from DetectApps.ps1 (v0.1.1).
        Returns objects with: Name, Id, Source (winget/msstore/manual),
        Version. Does not return system components or version-only lines.
    #>
    [CmdletBinding()]
    param()

    Write-AnniLog -Level INFO -Message "[WingetScan] Running 'winget list'..."

    try {
        $rawOutput = & winget list --accept-source-agreements 2>&1
        $lines = $rawOutput | Where-Object { $_ -is [string] }
    }
    catch {
        Write-AnniLog -Level ERROR -Message "[WingetScan] Failed to run 'winget list': $_"
        return @()
    }

    if (-not $lines -or $lines.Count -eq 0) {
        Write-AnniLog -Level WARNING -Message "[WingetScan] winget list returned no output."
        return @()
    }

    $results = @()

    foreach ($line in $lines) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        if ($line -match '^\s*[-]+\s*$') { continue }
        if ($line -match '^\s*Name\s+Id\s+') { continue }
        if ($line -match '^\d+ (upgrade|package)') { continue }
        if ($line -match '^-{3,}') { continue }

        # Match a winget ID in the line (Publisher.AppName pattern or hex store ID)
        if ($line -match '\s{2,}([\w][\w\.\-]+[\w])\s+') {
            $appId = $Matches[1]

            # Skip pure version strings and very short matches
            if ($appId -match '^\d+[\.\d]+$') { continue }
            if ($appId.Length -lt 3) { continue }

            $appName = ($line -split '\s{2,}')[0].Trim()

            # Determine source from line ending
            $detectedSource = "manual"
            if ($line -match '\bwinget\s*$') {
                $detectedSource = "winget"
            } elseif ($line -match '\bmsstore\s*$') {
                $detectedSource = "msstore"
            }

            # Extract version (field between ID and Source)
            $version = ""
            $fields = $line -split '\s{2,}'
            if ($fields.Count -ge 3) {
                $version = $fields[2].Trim()
                # If version looks like a source token, clear it
                if ($version -in @('winget', 'msstore')) { $version = "" }
            }

            if ($appName -and $appId -and $appName -ne $appId) {
                $results += [PSCustomObject]@{
                    Name       = $appName
                    Id         = $appId
                    Source     = $detectedSource
                    Version    = $version
                    Executable = $null
                    InstallDir = $null
                    Notes      = "Detected via winget list"
                }
            }
        }
    }

    $results = $results | Sort-Object Id -Unique
    Write-AnniLog -Level INFO -Message "[WingetScan] Parsed $($results.Count) app(s) from winget."
    return $results
}

# ======================================================================
# SOURCE 2: START MENU SHORTCUT SCAN
# ======================================================================

# Folders to exclude when encountered as shortcut group names in Start Menu
$script:SystemShortcutGroups = @(
    'Accessibility',
    'Accessories',
    'Administrative Tools',
    'Maintenance',
    'Startup',
    'System Tools',
    'Windows Accessories',
    'Windows Administrative Tools',
    'Windows Ease of Access',
    'Windows PowerShell',
    'Windows System',
    'Windows Tools'
)

# Filename patterns that indicate an uninstaller, not an app
$script:UninstallerPatterns = @(
    'uninstall',
    'uninst',
    'remove',
    'deinstall'
)

function Get-StartMenuApps {
    <#
    .SYNOPSIS
        Scans Start Menu shortcut locations and resolves .lnk targets.
    .DESCRIPTION
        Scans both per-user and system-wide Start Menu Programs folders.
        Resolves each .lnk file using the WScript.Shell COM object to
        extract the target executable path. Filters out system components,
        uninstallers, and web shortcuts.
    #>
    [CmdletBinding()]
    param()

    Write-AnniLog -Level INFO -Message "[StartMenuScan] Scanning Start Menu shortcuts..."

    $searchPaths = @(
        [System.IO.Path]::Combine($env:APPDATA, 'Microsoft\Windows\Start Menu\Programs'),
        [System.IO.Path]::Combine($env:ProgramData, 'Microsoft\Windows\Start Menu\Programs')
    )

    # Create WScript.Shell COM object for resolving .lnk files
    try {
        $shell = New-Object -ComObject WScript.Shell
    }
    catch {
        Write-AnniLog -Level ERROR -Message "[StartMenuScan] Failed to create WScript.Shell COM object: $_"
        return @()
    }

    $results = @()
    $seenExecutables = @{}

    foreach ($searchPath in $searchPaths) {
        if (-not (Test-Path $searchPath)) {
            Write-AnniLog -Level DEBUG -Message "[StartMenuScan] Path not found: $searchPath"
            continue
        }

        $lnkFiles = Get-ChildItem -Path $searchPath -Filter '*.lnk' -Recurse -ErrorAction SilentlyContinue

        foreach ($lnk in $lnkFiles) {
            # Skip shortcuts inside system group folders
            $parentFolder = Split-Path -Leaf (Split-Path -Parent $lnk.FullName)
            if ($parentFolder -in $script:SystemShortcutGroups) {
                Write-AnniLog -Level DEBUG -Message "[StartMenuScan] Skipped (system group): $($lnk.Name)"
                continue
            }

            # Skip uninstaller shortcuts by filename
            $lnkBaseName = $lnk.BaseName.ToLower()
            $isUninstaller = $false
            foreach ($pattern in $script:UninstallerPatterns) {
                if ($lnkBaseName -match $pattern) {
                    $isUninstaller = $true
                    break
                }
            }
            if ($isUninstaller) {
                Write-AnniLog -Level DEBUG -Message "[StartMenuScan] Skipped (uninstaller): $($lnk.Name)"
                continue
            }

            # Resolve the shortcut target
            try {
                $shortcut = $shell.CreateShortcut($lnk.FullName)
                $targetPath = $shortcut.TargetPath
            }
            catch {
                Write-AnniLog -Level DEBUG -Message "[StartMenuScan] Failed to resolve: $($lnk.Name) -- $_"
                continue
            }

            # Skip shortcuts with no target or empty target
            if ([string]::IsNullOrWhiteSpace($targetPath)) {
                Write-AnniLog -Level DEBUG -Message "[StartMenuScan] Skipped (no target): $($lnk.Name)"
                continue
            }

            # Skip web URLs (some apps create web shortcuts as .lnk)
            if ($targetPath -match '^https?://') {
                Write-AnniLog -Level DEBUG -Message "[StartMenuScan] Skipped (web URL): $($lnk.Name)"
                continue
            }

            # Skip targets pointing to system directories and SDK/Kit tools
            $targetLower = $targetPath.ToLower()
            if ($targetLower -match '\\windows\\system32\\' -or
                $targetLower -match '\\windows\\syswow64\\' -or
                $targetLower -match '\\windows\\explorer\.exe$' -or
                $targetLower -match '\\windows kits\\' -or
                $targetLower -match '\\windows sdks\\') {
                Write-AnniLog -Level DEBUG -Message "[StartMenuScan] Skipped (system dir): $($lnk.Name) -> $targetPath"
                continue
            }

            # Skip if target doesn't exist (broken shortcut)
            if (-not (Test-Path $targetPath -ErrorAction SilentlyContinue)) {
                Write-AnniLog -Level DEBUG -Message "[StartMenuScan] Skipped (target missing): $($lnk.Name) -> $targetPath"
                continue
            }

            # Skip if target is not an executable
            $ext = [System.IO.Path]::GetExtension($targetPath).ToLower()
            if ($ext -notin @('.exe', '.cmd', '.bat', '.com', '.msc')) {
                Write-AnniLog -Level DEBUG -Message "[StartMenuScan] Skipped (not executable): $($lnk.Name) -> $targetPath"
                continue
            }

            # Deduplicate by executable path
            $normalizedTarget = $targetPath.ToLower()
            if ($seenExecutables.ContainsKey($normalizedTarget)) {
                continue
            }
            $seenExecutables[$normalizedTarget] = $true

            # Deduplicate by app name -- keep only the first shortcut for
            # multi-arch installs (e.g. WinDbg arm/arm64/x86/x64)
            $nameKey = $lnk.BaseName.ToLower().Trim()
            if ($seenExecutables.ContainsKey("name:$nameKey")) {
                Write-AnniLog -Level DEBUG -Message "[StartMenuScan] Skipped (duplicate name): $($lnk.BaseName) -> $targetPath"
                continue
            }
            $seenExecutables["name:$nameKey"] = $true

            # Extract app name from shortcut name (strip common suffixes)
            $appName = $lnk.BaseName
            $appName = $appName -replace '\s*\(.*?\)\s*$', ''   # Remove trailing (x64) etc.
            $appName = $appName -replace '\s*-\s*Shortcut$', '' # Remove "- Shortcut"

            # Determine install directory from executable path
            $installDir = Split-Path -Parent $targetPath

            # Try to get publisher from file version info
            $publisher = ""
            try {
                $fileInfo = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($targetPath)
                if ($fileInfo.CompanyName) {
                    $publisher = $fileInfo.CompanyName
                }
            }
            catch {
                Write-AnniLog -Level DEBUG -Message "[StartMenuScan] Could not read version info: $targetPath"
            }

            $results += [PSCustomObject]@{
                Name       = $appName
                Id         = $null
                Source     = "manual"
                Version    = ""
                Executable = $targetPath
                InstallDir = $installDir
                Publisher  = $publisher
                Notes      = "Detected via Start Menu shortcut"
            }
        }
    }

    # Release COM object
    try { [System.Runtime.InteropServices.Marshal]::ReleaseComObject($shell) | Out-Null } catch {}

    Write-AnniLog -Level INFO -Message "[StartMenuScan] Found $($results.Count) app(s) from Start Menu."
    return $results
}

# ======================================================================
# DEDUPLICATION AND MERGE
# ======================================================================

function Merge-AppLists {
    <#
    .SYNOPSIS
        Merges winget and Start Menu scan results into a single deduplicated list.
    .DESCRIPTION
        When an app appears in both lists, the winget entry is preferred (has ID
        for automated reinstall) but the executable path from Start Menu is added.
        Matching is done by fuzzy name comparison.
    #>
    [CmdletBinding()]
    param(
        [object[]]$WingetApps,
        [object[]]$StartMenuApps
    )

    Write-AnniLog -Level INFO -Message "[Merge] Merging $($WingetApps.Count) winget + $($StartMenuApps.Count) Start Menu entries..."

    # Build a lookup of winget apps by normalised name for fuzzy matching
    $wingetByName = @{}
    foreach ($wa in $WingetApps) {
        $key = ($wa.Name -replace '[^a-zA-Z0-9]', '').ToLower()
        if ($key -and -not $wingetByName.ContainsKey($key)) {
            $wingetByName[$key] = $wa
        }
    }

    # Also build a lookup by executable name (without extension) for matching
    # This catches cases where the winget name differs from the shortcut name
    $wingetById = @{}
    foreach ($wa in $WingetApps) {
        if ($wa.Id) {
            $wingetById[$wa.Id.ToLower()] = $wa
        }
    }

    $merged = [System.Collections.ArrayList]::new()
    $matchedWingetKeys = @{}

    foreach ($sma in $StartMenuApps) {
        $smaKey = ($sma.Name -replace '[^a-zA-Z0-9]', '').ToLower()

        $matchedWinget = $null

        # Strategy 1: Exact normalised name match
        if ($wingetByName.ContainsKey($smaKey)) {
            $matchedWinget = $wingetByName[$smaKey]
        }

        # Strategy 2: Winget name contains Start Menu name or vice versa
        if (-not $matchedWinget) {
            foreach ($wa in $WingetApps) {
                $waKey = ($wa.Name -replace '[^a-zA-Z0-9]', '').ToLower()
                if ($waKey -and $smaKey -and ($waKey.Contains($smaKey) -or $smaKey.Contains($waKey))) {
                    $matchedWinget = $wa
                    break
                }
            }
        }

        # Strategy 3: Executable filename matches winget app name
        if (-not $matchedWinget -and $sma.Executable) {
            $exeName = [System.IO.Path]::GetFileNameWithoutExtension($sma.Executable).ToLower()
            foreach ($wa in $WingetApps) {
                $waKey = ($wa.Name -replace '[^a-zA-Z0-9]', '').ToLower()
                $waIdPart = if ($wa.Id -and $wa.Id.Contains('.')) {
                    ($wa.Id.Split('.')[-1]).ToLower()
                } else { "" }

                if (($waKey -and $exeName -eq $waKey) -or
                    ($waIdPart -and $exeName -eq $waIdPart)) {
                    $matchedWinget = $wa
                    break
                }
            }
        }

        if ($matchedWinget) {
            # Enrich the winget entry with executable info from Start Menu
            $waKey = ($matchedWinget.Name -replace '[^a-zA-Z0-9]', '').ToLower()
            if (-not $matchedWingetKeys.ContainsKey($waKey)) {
                $matchedWingetKeys[$waKey] = $true

                $enriched = [PSCustomObject]@{
                    Name       = $matchedWinget.Name
                    Id         = $matchedWinget.Id
                    Source     = $matchedWinget.Source
                    Version    = $matchedWinget.Version
                    Executable = $sma.Executable
                    InstallDir = $sma.InstallDir
                    Notes      = "Detected via winget list + Start Menu shortcut"
                }
                [void]$merged.Add($enriched)
            }
            Write-AnniLog -Level DEBUG -Message "[Merge] Matched: '$($sma.Name)' <-> '$($matchedWinget.Name)' ($($matchedWinget.Id))"
        } else {
            # Start Menu only -- manual install not in winget
            $entry = [PSCustomObject]@{
                Name       = $sma.Name
                Id         = $null
                Source     = "manual"
                Version    = ""
                Executable = $sma.Executable
                InstallDir = $sma.InstallDir
                Notes      = "Detected via Start Menu shortcut"
            }
            [void]$merged.Add($entry)
            Write-AnniLog -Level DEBUG -Message "[Merge] Start Menu only: '$($sma.Name)'"
        }
    }

    # Add winget-only apps that were not matched to any Start Menu shortcut
    foreach ($wa in $WingetApps) {
        $waKey = ($wa.Name -replace '[^a-zA-Z0-9]', '').ToLower()
        if (-not $matchedWingetKeys.ContainsKey($waKey)) {
            $entry = [PSCustomObject]@{
                Name       = $wa.Name
                Id         = $wa.Id
                Source     = $wa.Source
                Version    = $wa.Version
                Executable = $null
                InstallDir = $null
                Notes      = "Detected via winget list"
            }
            [void]$merged.Add($entry)
        }
    }

    Write-AnniLog -Level INFO -Message "[Merge] Final unified list: $($merged.Count) app(s)."
    return @($merged | Sort-Object Name)
}

# ======================================================================
# MAIN SCAN FUNCTION
# ======================================================================

function Invoke-AppScan {
    <#
    .SYNOPSIS
        Runs the full dual-source app scan and returns a unified app list.
    .DESCRIPTION
        Calls Get-WingetApps and Get-StartMenuApps, then merges and
        deduplicates the results. Returns an array of PSCustomObjects.
        This is the primary entry point when ScanApps.ps1 is dot-sourced.
    #>
    [CmdletBinding()]
    param()

    Write-AnniLog -Level INFO -Message "Starting dual-source app scan..."
    Write-Host ""

    # Source 1: winget
    $wingetApps = @(Get-WingetApps)

    # Source 2: Start Menu
    $startMenuApps = @(Get-StartMenuApps)

    # Merge and deduplicate
    $unified = Merge-AppLists -WingetApps $wingetApps -StartMenuApps $startMenuApps

    Write-AnniLog -Level SUCCESS -Message "App scan complete: $($unified.Count) app(s) detected."
    return $unified
}

# ======================================================================
# STANDALONE EXECUTION
# ======================================================================

# If run directly (not dot-sourced), execute the scan and display results.
# Detection: when dot-sourced, $MyInvocation.InvocationName is '.' or '&'.
if ($MyInvocation.InvocationName -notin @('.', '&')) {
    Write-AnniLog -Level INFO -Message "AnniWin11 App Scanner (standalone mode)"
    Write-Host ""

    $apps = Invoke-AppScan

    # Display summary table
    Write-Host ""
    Write-Host "Scan Results:" -ForegroundColor Cyan
    Write-Host ("-" * 90)
    Write-Host ("{0,-35} {1,-30} {2,-10} {3,-12}" -f "Name", "ID", "Source", "Has Exe?")
    Write-Host ("-" * 90)

    $wingetCount  = 0
    $manualCount  = 0
    $msstoreCount = 0

    foreach ($app in $apps) {
        $hasExe = if ($app.Executable) { "Yes" } else { "No" }
        $id     = if ($app.Id) { $app.Id } else { "(none)" }
        $name   = if ($app.Name.Length -gt 33) { $app.Name.Substring(0, 30) + "..." } else { $app.Name }
        $idDisp = if ($id.Length -gt 28) { $id.Substring(0, 25) + "..." } else { $id }

        $colour = switch ($app.Source) {
            "winget"  { "Green" }
            "msstore" { "Cyan" }
            default   { "Yellow" }
        }

        Write-Host ("{0,-35} {1,-30} {2,-10} {3,-12}" -f $name, $idDisp, $app.Source, $hasExe) -ForegroundColor $colour

        switch ($app.Source) {
            "winget"  { $wingetCount++ }
            "msstore" { $msstoreCount++ }
            default   { $manualCount++ }
        }
    }

    Write-Host ("-" * 90)
    Write-Host ""
    Write-AnniLog -Level INFO -Message "Summary: $wingetCount winget, $msstoreCount msstore, $manualCount manual -- $($apps.Count) total"

    # Write results to scan_results.json for inspection
    $outputPath = Get-ConfigPath -FileName "scan_results.json"
    $output = @{
        scanned_at = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
        total      = $apps.Count
        winget     = $wingetCount
        msstore    = $msstoreCount
        manual     = $manualCount
        apps       = $apps | ForEach-Object {
            @{
                name       = $_.Name
                id         = $_.Id
                source     = $_.Source
                version    = $_.Version
                executable = $_.Executable
                install_dir = $_.InstallDir
                notes      = $_.Notes
            }
        }
    }

    try {
        $output | ConvertTo-Json -Depth 5 | Out-File -FilePath $outputPath -Encoding utf8 -Force
        Write-AnniLog -Level SUCCESS -Message "Scan results written to: $outputPath"
    }
    catch {
        Write-AnniLog -Level ERROR -Message "Failed to write scan results: $_"
    }

    Write-Host ""
    Close-AnniLog
    Pause
}

# ------- END SCAN APPS SCRIPT ------- #
