# ------- RESTORE CONFIGS SCRIPT ------- #

# Restores app config files from the backup store after reinstall.
# Run this AFTER InstallApps.ps1 has completed.
# Requires -Version 7.0

# ------- PARAMETERS ------- #
[CmdletBinding()]
param(
    # Force overwrite even when the destination file is newer than the
    # backup source. Without this switch, RestoreConfigs is non-destructive
    # and will skip files whose destination has been modified since the
    # snapshot was taken. Use with care.
    [switch]$Force,

    # Skip all interactive prompts: proceed with the restore, re-hydrate
    # missing project config files automatically, and do not offer to run
    # InstallApps/WinSettings afterwards. Intended for automation/testing.
    [switch]$NoConfirm
)

# ------- DEPENDENCIES ------- #
. "$PSScriptRoot\..\lib\Config.ps1"
Import-Module "$PSScriptRoot\..\lib\AnniLog.psd1" -Force

# ------- PATHS ------- #
$LogFile          = Get-LogPath -FileName "restore.log"
$AppConfigsFile   = Get-ConfigPath -FileName "app_configs.json"
$BackupStoreFile  = Get-ConfigPath -FileName "backup_store.json"

# ------- INITIALISE LOGGING ------- #
$ProjectConfig = Get-ProjectConfig
Initialize-AnniLog -LogFilePath $LogFile -LogLevel $ProjectConfig.log_level -EnableStopwatch

Write-AnniLog -Level INFO -Message "AnniWin11 Config Restore"
if ($Force) {
    Write-AnniLog -Level WARNING -Message "-Force enabled: destination files will be overwritten even if newer than backup."
}
Write-Host ""

# ------- DPAPI WARNING ------- #

Write-Host ("-" * 70) -ForegroundColor Yellow
Write-AnniLog -Level WARNING -Message "DPAPI NOTICE:"
Write-AnniLog -Level WARNING -Message "Browser saved passwords and login sessions CANNOT be restored"
Write-AnniLog -Level WARNING -Message "across Windows reinstalls. This is a Windows security feature."
Write-AnniLog -Level WARNING -Message "Use a password manager (e.g. Bitwarden) for your passwords."
Write-Host ("-" * 70) -ForegroundColor Yellow
Write-Host ""

# ------- VALIDATE PREREQUISITES ------- #

if (-not (Test-Path $BackupStoreFile)) {
    Write-AnniLog -Level ERROR -Message "backup_store.json not found. Run DriveSetup.ps1 first."
    Close-AnniLog
    throw "backup_store.json missing"
}

$backupStore = Read-JsonFile -Path $BackupStoreFile
$backupRoot  = $backupStore.backup_root

if (-not $backupRoot -or -not (Test-Path $backupRoot)) {
    Write-AnniLog -Level ERROR -Message "Backup root directory not found: $backupRoot"
    Close-AnniLog
    exit 1
}

$appConfigsBackupDir = Join-Path $backupRoot "app_configs"
if (-not (Test-Path $appConfigsBackupDir)) {
    Write-AnniLog -Level ERROR -Message "No app_configs directory found in backup store."
    Close-AnniLog
    exit 1
}

# ------- READ AND VALIDATE MANIFEST ------- #

$manifestPath = Join-Path $backupRoot "backup_manifest.json"
$manifest = $null
if (Test-Path $manifestPath) {
    try {
        $manifest = Read-JsonFile -Path $manifestPath
        Write-AnniLog -Level INFO -Message "Backup manifest found. Last backup: $($manifest.timestamp)"
        if (-not $manifest.manifest_version -or $manifest.manifest_version -lt 2) {
            Write-AnniLog -Level WARNING -Message "Manifest is from a pre-v0.8.0 backup -- no checksums available. Consider re-running a backup."
        }
    }
    catch {
        Write-AnniLog -Level WARNING -Message "Backup manifest is unreadable: $($_.Exception.Message)"
        $manifest = $null
    }
} else {
    Write-AnniLog -Level WARNING -Message "No backup manifest found. The backup may be incomplete or was never run."
}

if (-not $manifest -and -not $NoConfirm) {
    $answer = Read-Host "Continue restoring WITHOUT a valid manifest? (y/N)"
    if ($answer -notmatch '^[Yy]') {
        Write-AnniLog -Level INFO -Message "Restore cancelled by user."
        Close-AnniLog
        exit 0
    }
}

# ------- RE-HYDRATE PROJECT CONFIG FILES ------- #

# On a fresh install the repo clone has no config/*.json (they are
# gitignored). Backups from v0.8.0 onwards carry them in <root>\config, so
# restore any that are missing locally before they are needed below.
# Existing local files are never overwritten.
$configBackupDir = Join-Path $backupRoot "config"
if (Test-Path $configBackupDir) {
    $restorableConfigs = Get-ChildItem -Path $configBackupDir -Filter "*.json" -File |
        Where-Object { -not (Test-Path (Get-ConfigPath -FileName $_.Name)) }

    if ($restorableConfigs.Count -gt 0) {
        Write-Host ""
        Write-AnniLog -Level INFO -Message "The backup contains project config files missing locally: $($restorableConfigs.Name -join ', ')"
        $doRestore = $NoConfirm
        if (-not $NoConfirm) {
            $answer = Read-Host "Restore them into the local config directory? (Y/n)"
            $doRestore = $answer -notmatch '^[Nn]'
        }
        if ($doRestore) {
            foreach ($cfg in $restorableConfigs) {
                try {
                    Copy-Item -Path $cfg.FullName -Destination (Get-ConfigPath -FileName $cfg.Name) -Force
                    Write-AnniLog -Level SUCCESS -Message "Restored project config: $($cfg.Name)"
                }
                catch {
                    Write-AnniLog -Level ERROR -Message "Failed to restore project config '$($cfg.Name)': $_"
                }
            }
        }
    }
}

if (-not (Test-Path $AppConfigsFile)) {
    Write-AnniLog -Level ERROR -Message "app_configs.json not found locally or in the backup. Run GenerateConfigs.ps1 first."
    Close-AnniLog
    throw "app_configs.json missing"
}

$appConfigs = Read-JsonFile -Path $AppConfigsFile

# ------- VERIFY BACKUP INTEGRITY (SHA256) ------- #

$checksumMismatches = @()
if ($manifest -and $manifest.files) {
    Write-Host ""
    Write-AnniLog -Level INFO -Message "Verifying backup integrity ($($manifest.files.Count) checksummed file(s))..."

    $missingCount = 0
    foreach ($entry in $manifest.files) {
        $filePath = Join-Path $backupRoot $entry.path
        if (-not (Test-Path $filePath -PathType Leaf)) {
            $missingCount++
            Write-AnniLog -Level DEBUG -Message "Checksummed file missing from backup: $($entry.path)"
            continue
        }
        try {
            $actual = (Get-FileHash -Path $filePath -Algorithm SHA256 -ErrorAction Stop).Hash
            if ($actual -ne $entry.sha256) {
                $checksumMismatches += $entry.path
                Write-AnniLog -Level WARNING -Message "Checksum MISMATCH: $($entry.path)"
            }
        }
        catch {
            $checksumMismatches += $entry.path
            Write-AnniLog -Level WARNING -Message "Could not hash '$($entry.path)': $($_.Exception.Message)"
        }
    }

    if ($missingCount -gt 0) {
        Write-AnniLog -Level WARNING -Message "$missingCount file(s) from the manifest are missing in the backup store."
    }

    if ($checksumMismatches.Count -eq 0 -and $missingCount -eq 0) {
        Write-AnniLog -Level SUCCESS -Message "Backup integrity verified -- all checksums match."
    }
    elseif ($checksumMismatches.Count -gt 0) {
        Write-AnniLog -Level WARNING -Message "$($checksumMismatches.Count) file(s) failed checksum verification. The backup may be corrupted."
        if (-not $NoConfirm) {
            $answer = Read-Host "Continue restoring despite checksum mismatches? (y/N)"
            if ($answer -notmatch '^[Yy]') {
                Write-AnniLog -Level INFO -Message "Restore cancelled by user."
                Close-AnniLog
                exit 0
            }
        }
    }
}

# ------- RESTORE SUMMARY AND CONFIRMATION ------- #

$appsWithPaths = @($appConfigs.apps | Where-Object { $_.backup_paths -and $_.backup_paths.Count -gt 0 })

Write-Host ""
Write-Host ("-" * 50)
Write-AnniLog -Level INFO -Message "Restore Plan:"
Write-AnniLog -Level INFO -Message "  Backup root:    $backupRoot"
if ($manifest) {
    Write-AnniLog -Level INFO -Message "  Backup taken:   $($manifest.timestamp)"
    if ($manifest.total_bytes) {
        Write-AnniLog -Level INFO -Message "  Backup size:    $([math]::Round([int64]$manifest.total_bytes / 1MB, 1)) MB"
    }
}
Write-AnniLog -Level INFO -Message "  Apps to check:  $($appsWithPaths.Count) of $($appConfigs.apps.Count) configured app(s)"
Write-AnniLog -Level INFO -Message "  Overwrite mode: $(if ($Force) { 'FORCE (newer local files WILL be overwritten)' } else { 'safe (newer local files are kept)' })"
Write-Host ("-" * 50)
Write-Host ""
Write-AnniLog -Level WARNING -Message "This writes files into your user profile and app data directories."

if (-not $NoConfirm) {
    $answer = Read-Host "Proceed with restore? (Y/n)"
    if ($answer -match '^[Nn]') {
        Write-AnniLog -Level INFO -Message "Restore cancelled by user."
        Close-AnniLog
        exit 0
    }
}

Write-Host ""
Write-AnniLog -Level INFO -Message "Processing $($appConfigs.apps.Count) app(s)..."
Write-Host ""

# ------- RESTORE EACH APP ------- #

$restored = @()
$skipped  = @()
$failed   = @()

foreach ($app in $appConfigs.apps) {
    $appName = $app.name

    if (-not $app.backup_paths -or $app.backup_paths.Count -eq 0) {
        Write-AnniLog -Level DEBUG -Message "[$appName] No backup paths defined, skipping."
        $skipped += $appName
        continue
    }

    $appBackupDir = Join-Path $appConfigsBackupDir ($appName -replace '[\\/:*?"<>|]', '_')

    if (-not (Test-Path $appBackupDir)) {
        Write-AnniLog -Level DEBUG -Message "[$appName] No backup data found, skipping."
        $skipped += $appName
        continue
    }

    $appHasContent = $false

    foreach ($entry in $app.backup_paths) {
        $pathType = $entry.type
        $relPath  = $entry.path

        # For absolute paths, strip drive letter and colon so the path
        # can be safely used as a subfolder name inside the backup directory.
        # e.g. "C:\Users\X\.gitconfig" -> "Users\X\.gitconfig"
        $safeRelPath = if ($pathType -eq "absolute") {
            $expanded = [System.Environment]::ExpandEnvironmentVariables($relPath)
            $expanded -replace '^[A-Za-z]:\\', '' `
                      -replace '^\\', ''
        } else {
            $relPath
        }

        try {
            $destPath = Resolve-BackupPath -PathType $pathType -RelativePath $relPath
        }
        catch {
            Write-AnniLog -Level WARNING -Message "[$appName] Invalid path type '$pathType' for '$relPath'"
            continue
        }

        # Expand environment variables in absolute paths
        if ($pathType -eq "absolute") {
            $destPath = [System.Environment]::ExpandEnvironmentVariables($destPath)
        }

        $sourcePath = Join-Path $appBackupDir $safeRelPath

        if (-not (Test-Path $sourcePath)) {
            Write-AnniLog -Level DEBUG -Message "[$appName] Backup source not found: $sourcePath"
            continue
        }

        # Non-destructive check: skip if destination is newer than backup.
        # -Force bypasses this safety check and overwrites unconditionally.
        if (-not $Force -and (Test-Path $destPath) -and (Test-Path $sourcePath -PathType Leaf)) {
            $destItem   = Get-Item $destPath -ErrorAction SilentlyContinue
            $sourceItem = Get-Item $sourcePath -ErrorAction SilentlyContinue
            if ($destItem -and $sourceItem -and $destItem.LastWriteTime -gt $sourceItem.LastWriteTime) {
                Write-AnniLog -Level INFO -Message "[$appName] Destination newer than backup, skipping: $relPath (use -Force to override)"
                continue
            }
        }

        # Create destination directory
        $destDir = if (Test-Path $sourcePath -PathType Container) {
            $destPath
        } else {
            Split-Path -Parent $destPath
        }

        if ($destDir -and -not (Test-Path $destDir)) {
            New-Item -ItemType Directory -Path $destDir -Force | Out-Null
        }

        # Restore files
        try {
            if (Test-Path $sourcePath -PathType Container) {
                $robocopyArgs = @("`"$sourcePath`"", "`"$destPath`"", "/MIR", "/R:1", "/W:1", "/NJH", "/NJS", "/NP", "/NFL", "/NDL")
                $proc = Start-Process -FilePath "robocopy" -ArgumentList $robocopyArgs -NoNewWindow -Wait -PassThru
                if ($proc.ExitCode -le 7) {
                    Write-AnniLog -Level SUCCESS -Message "[$appName] Restored directory: $relPath"
                    $appHasContent = $true
                } else {
                    Write-AnniLog -Level WARNING -Message "[$appName] Robocopy returned exit code $($proc.ExitCode) for $relPath"
                }
            } else {
                Copy-Item -Path $sourcePath -Destination $destPath -Force
                Write-AnniLog -Level SUCCESS -Message "[$appName] Restored file: $relPath"
                $appHasContent = $true
            }
        }
        catch {
            Write-AnniLog -Level ERROR -Message "[$appName] Failed to restore '$relPath': $_"
            $failed += "$appName/$relPath"
        }
    }

    if ($appHasContent) {
        $restored += $appName
    } else {
        $skipped += $appName
    }
}

# ------- SUMMARY ------- #

Write-Host ""
Write-Host ("-" * 50)
Write-AnniLog -Level INFO -Message "Restore Summary:"
Write-AnniLog -Level INFO -Message "  Restored: $($restored.Count) app(s)"
Write-AnniLog -Level INFO -Message "  Skipped:  $($skipped.Count) app(s)"
Write-AnniLog -Level INFO -Message "  Failed:   $($failed.Count) item(s)"
Write-Host ("-" * 50)

if ($failed.Count -gt 0) {
    Write-AnniLog -Level WARNING -Message "Failed items:"
    foreach ($f in $failed) {
        Write-AnniLog -Level WARNING -Message "  - $f"
    }
}

if ($restored.Count -gt 0) {
    Write-Host ""
    Write-AnniLog -Level INFO -Message "Restored apps: $($restored -join ', ')"
    Write-AnniLog -Level WARNING -Message "Some apps may need to be restarted for config changes to take effect."
}

# ------- POST-RESTORE: OFFER INSTALLAPPS / WINSETTINGS ------- #

# If the backup carried apps.json / settings.json, the rest of the
# post-install flow can run right away. Both scripts are launched
# out-of-process so their exit calls cannot kill this session.
if (-not $NoConfirm) {
    $installAppsScript = Join-Path $PSScriptRoot "InstallApps.ps1"
    $winSettingsScript = Join-Path $PSScriptRoot "WinSettings.ps1"

    if ((Test-Path (Get-ConfigPath -FileName "apps.json")) -and (Test-Path $installAppsScript)) {
        Write-Host ""
        $answer = Read-Host "apps.json is present -- run InstallApps now to install your apps? (y/N)"
        if ($answer -match '^[Yy]') {
            Start-Process -FilePath "pwsh" `
                -ArgumentList "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $installAppsScript `
                -NoNewWindow -Wait
        }
    }

    if ((Test-Path (Get-ConfigPath -FileName "settings.json")) -and (Test-Path $winSettingsScript)) {
        Write-Host ""
        $answer = Read-Host "settings.json is present -- run WinSettings now to apply Windows settings? (y/N)"
        if ($answer -match '^[Yy]') {
            Start-Process -FilePath "pwsh" `
                -ArgumentList "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $winSettingsScript `
                -NoNewWindow -Wait
        }
    }
}

Write-Host ""
Write-AnniLog -Level SUCCESS -Message "Restore complete."
Close-AnniLog
Pause

# ------- END RESTORE CONFIGS SCRIPT ------- #
