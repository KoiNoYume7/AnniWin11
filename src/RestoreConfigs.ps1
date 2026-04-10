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
    [switch]$Force
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

if (-not (Test-Path $AppConfigsFile)) {
    Write-AnniLog -Level ERROR -Message "app_configs.json not found. Run GenerateConfigs.ps1 first."
    Close-AnniLog
    throw "app_configs.json missing"
}

$backupStore = Read-JsonFile -Path $BackupStoreFile
$appConfigs  = Read-JsonFile -Path $AppConfigsFile

$backupRoot = $backupStore.backup_root

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

# ------- READ MANIFEST ------- #

$manifestPath = Join-Path $backupRoot "backup_manifest.json"
$manifest = $null
if (Test-Path $manifestPath) {
    $manifest = Read-JsonFile -Path $manifestPath
    Write-AnniLog -Level INFO -Message "Backup manifest found. Last backup: $($manifest.timestamp)"
} else {
    Write-AnniLog -Level WARNING -Message "No backup manifest found. Proceeding without timestamp checks."
}

Write-AnniLog -Level INFO -Message "Backup root: $backupRoot"
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
            $relPath -replace '^[A-Za-z]:\\', '' `
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

Write-Host ""
Write-AnniLog -Level SUCCESS -Message "Restore complete."
Close-AnniLog
Pause

# ------- END RESTORE CONFIGS SCRIPT ------- #
