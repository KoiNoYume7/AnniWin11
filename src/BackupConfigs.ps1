# ------- BACKUP CONFIGS SCRIPT ------- #

# Snapshots app config files to the backup store.
# Run this BEFORE reinstalling Windows.
# Requires -Version 7.0

# ------- DEPENDENCIES ------- #
. "$PSScriptRoot\..\lib\Config.ps1"
Import-Module "$PSScriptRoot\..\lib\AnniLog.psd1" -Force

# ------- PATHS ------- #
$LogFile          = Get-LogPath -FileName "backup.log"
$AppConfigsFile   = Get-ConfigPath -FileName "app_configs.json"
$BackupStoreFile  = Get-ConfigPath -FileName "backup_store.json"

# ------- INITIALISE LOGGING ------- #
Initialize-AnniLog -LogFilePath $LogFile -LogLevel "INFO" -EnableStopwatch

Write-AnniLog -Level INFO -Message "AnniWin11 Config Backup"
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
    Write-AnniLog -Level ERROR -Message "Run DriveSetup.ps1 to configure the backup store."
    Close-AnniLog
    exit 1
}

$appConfigsBackupDir = Join-Path $backupRoot "app_configs"
if (-not (Test-Path $appConfigsBackupDir)) {
    New-Item -ItemType Directory -Path $appConfigsBackupDir -Force | Out-Null
}

Write-AnniLog -Level INFO -Message "Backup root: $backupRoot"
Write-AnniLog -Level INFO -Message "Processing $($appConfigs.apps.Count) app(s)..."
Write-Host ""

# ------- BACKUP EACH APP ------- #

$backedUp = @()
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
    $appHasContent = $false

    foreach ($entry in $app.backup_paths) {
        $pathType = $entry.type
        $relPath  = $entry.path

        # For absolute paths, strip drive letter and colon so the path
        # can be safely used as a subfolder name inside the backup directory.
        # e.g. "C:\Users\X\.gitconfig" -> "Users\X\.gitconfig"
        $safeRelPath = if ($pathType -eq "absolute") {
            # Expand env vars first, then strip drive letter and leading slash
            $expanded = [System.Environment]::ExpandEnvironmentVariables($relPath)
            $expanded -replace '^[A-Za-z]:\\', '' `
                    -replace '^\\', ''
        } else {
            $relPath
        }

        try {
            $sourcePath = Resolve-BackupPath -PathType $pathType -RelativePath $relPath
        }
        catch {
            Write-AnniLog -Level WARNING -Message "[$appName] Invalid path type '$pathType' for '$relPath'"
            continue
        }

        # Expand environment variables in absolute paths
        if ($pathType -eq "absolute") {
            $sourcePath = [System.Environment]::ExpandEnvironmentVariables($sourcePath)
        }

        if (-not (Test-Path $sourcePath)) {
            Write-AnniLog -Level WARNING -Message "[$appName] Source not found: $sourcePath"
            continue
        }

        # Determine destination path (mirror the relative path structure)
        $destPath = Join-Path $appBackupDir $safeRelPath

        # Create destination directory
        $destDir = if (Test-Path $sourcePath -PathType Container) {
            $destPath
        } else {
            Split-Path -Parent $destPath
        }

        if ($destDir -and -not (Test-Path $destDir)) {
            New-Item -ItemType Directory -Path $destDir -Force | Out-Null
        }

        # Copy files
        try {
            if (Test-Path $sourcePath -PathType Container) {
                # Directory: use robocopy for reliability
                $robocopyArgs = @("`"$sourcePath`"", "`"$destPath`"", "/MIR", "/R:1", "/W:1", "/NJH", "/NJS", "/NP", "/NFL", "/NDL")
                $proc = Start-Process -FilePath "robocopy" -ArgumentList $robocopyArgs -NoNewWindow -Wait -PassThru
                # Robocopy exit codes 0-7 are success/partial
                if ($proc.ExitCode -le 7) {
                    Write-AnniLog -Level SUCCESS -Message "[$appName] Backed up directory: $relPath"
                    $appHasContent = $true
                } else {
                    Write-AnniLog -Level WARNING -Message "[$appName] Robocopy returned exit code $($proc.ExitCode) for $relPath"
                }
            } else {
                # Single file
                Copy-Item -Path $sourcePath -Destination $destPath -Force
                Write-AnniLog -Level SUCCESS -Message "[$appName] Backed up file: $relPath"
                $appHasContent = $true
            }
        }
        catch {
            Write-AnniLog -Level ERROR -Message "[$appName] Failed to copy '$relPath': $_"
            $failed += "$appName/$relPath"
        }
    }

    if ($appHasContent) {
        $backedUp += $appName
    } else {
        $skipped += $appName
    }
}

# ------- WINGET EXPORT ------- #

Write-Host ""
Write-AnniLog -Level INFO -Message "Running winget export..."

$wingetExportPath = Join-Path $backupRoot "winget_export.json"
try {
    # Run winget export and capture all output (noise goes to stdout, not stderr)
    $wingetOutput = & winget export -o $wingetExportPath --accept-source-agreements 2>&1

    # Count noise lines for a summary without spamming the console
    $noiseLines = $wingetOutput | Where-Object {
        $_ -match 'not available from any source' -or
        $_ -match 'requires license agreement'
    }

    if ($noiseLines.Count -gt 0) {
        Write-AnniLog -Level DEBUG -Message "Winget export: $($noiseLines.Count) package(s) skipped (no source or license required)"
    }

    if (Test-Path $wingetExportPath) {
        Write-AnniLog -Level SUCCESS -Message "Winget export saved to: $wingetExportPath"
    } else {
        Write-AnniLog -Level WARNING -Message "Winget export completed but output file not found."
    }
}
catch {
    Write-AnniLog -Level WARNING -Message "Failed to run winget export: $_"
}

# ------- WRITE MANIFEST ------- #

$manifest = @{
    timestamp    = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
    backup_root  = $backupRoot
    backed_up    = $backedUp
    skipped      = $skipped
    failed       = $failed
    app_count    = $appConfigs.apps.Count
    winget_export = if (Test-Path $wingetExportPath) { $wingetExportPath } else { $null }
}

$manifestPath = Join-Path $backupRoot "backup_manifest.json"
try {
    $manifest | ConvertTo-Json -Depth 5 | Out-File -FilePath $manifestPath -Encoding utf8 -Force
    Write-AnniLog -Level SUCCESS -Message "Backup manifest written to: $manifestPath"
}
catch {
    Write-AnniLog -Level ERROR -Message "Failed to write backup manifest: $_"
}

# ------- SUMMARY ------- #

Write-Host ""
Write-Host ("-" * 50)
Write-AnniLog -Level INFO -Message "Backup Summary:"
Write-AnniLog -Level INFO -Message "  Backed up: $($backedUp.Count) app(s)"
Write-AnniLog -Level INFO -Message "  Skipped:   $($skipped.Count) app(s)"
Write-AnniLog -Level INFO -Message "  Failed:    $($failed.Count) item(s)"
Write-Host ("-" * 50)

if ($failed.Count -gt 0) {
    Write-AnniLog -Level WARNING -Message "Failed items:"
    foreach ($f in $failed) {
        Write-AnniLog -Level WARNING -Message "  - $f"
    }
}

Write-Host ""
Write-AnniLog -Level SUCCESS -Message "Backup complete."
Close-AnniLog
Pause

# ------- END BACKUP CONFIGS SCRIPT ------- #
