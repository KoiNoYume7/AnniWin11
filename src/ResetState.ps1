# ------- RESET STATE SCRIPT ------- #

# Selectively wipes AnniWin11 state: generated configs, project settings,
# backup store pointer, or actual backup data. Every destructive action requires
# explicit confirmation. The nuclear option requires typing RESET.
# Requires -Version 7.0

# ------- DEPENDENCIES ------- #
. "$PSScriptRoot\..\lib\Config.ps1"
Import-Module "$PSScriptRoot\..\lib\AnniLog.psd1" -Force

# ------- PATHS ------- #
$LogFile = Get-LogPath -FileName "reset.log"

# ------- INITIALISE LOGGING ------- #
$ProjectConfig = Get-ProjectConfig
Initialize-AnniLog -LogFilePath $LogFile -LogLevel $ProjectConfig.log_level

Write-AnniLog -Level INFO -Message "AnniWin11 Reset / Wipe State"

# ------- CONSTANTS ------- #

$GeneratedConfigFiles = @(
    "apps.json",
    "app_configs.json",
    "settings.json",
    "ignored_apps.json",
    "scan_results.json"
)

# ------- HELPERS ------- #

function Remove-IfExists {
    param(
        [string]$Path,
        [string]$Label,
        [switch]$IsDirectory
    )
    if (-not (Test-Path $Path)) {
        Write-AnniLog -Level DEBUG -Message "Not found (skip): $Label"
        return
    }
    try {
        if ($IsDirectory) {
            Remove-Item -Path $Path -Recurse -Force
        } else {
            Remove-Item -Path $Path -Force
        }
        Write-AnniLog -Level SUCCESS -Message "Deleted: $Label"
    }
    catch {
        Write-AnniLog -Level ERROR -Message "Failed to delete ${Label}: $_"
    }
}

function Get-BackupRoot {
    $storeFile = Get-ConfigPath -FileName "backup_store.json"
    if (-not (Test-Path $storeFile)) { return $null }
    try {
        $store = Read-JsonFile -Path $storeFile
        return $store.backup_root
    }
    catch {
        Write-AnniLog -Level DEBUG -Message "Could not read backup_store.json: $_"
        return $null
    }
}

function Confirm-Action {
    param([string[]]$Items)
    Write-Host ""
    Write-Host "  The following will be permanently deleted:" -ForegroundColor Yellow
    foreach ($item in $Items) {
        Write-Host "    - $item"
    }
    Write-Host ""
    Write-Host "  This cannot be undone. Proceed? (y/N): " -ForegroundColor Yellow -NoNewline
    $answer = Read-Host
    return ($answer -eq 'y' -or $answer -eq 'Y')
}

# ------- WIPE ACTIONS ------- #

function Invoke-WipeGeneratedConfigs {
    $toDelete = @()
    foreach ($f in $GeneratedConfigFiles) {
        $path = Get-ConfigPath -FileName $f
        if (Test-Path $path) { $toDelete += $path }
    }

    if ($toDelete.Count -eq 0) {
        Write-Host ""
        Write-AnniLog -Level INFO -Message "No generated config files found -- nothing to delete."
        return
    }

    if (-not (Confirm-Action -Items $toDelete)) {
        Write-AnniLog -Level INFO -Message "Wipe generated configs cancelled."
        return
    }

    foreach ($path in $toDelete) {
        Remove-IfExists -Path $path -Label $path
    }
}

function Invoke-WipeProjectSettings {
    $path = Get-ConfigPath -FileName "project_config.json"

    if (-not (Confirm-Action -Items @($path))) {
        Write-AnniLog -Level INFO -Message "Wipe project settings cancelled."
        return
    }

    Remove-IfExists -Path $path -Label "config\project_config.json"
}

function Invoke-WipeBackupStorePointer {
    $path = Get-ConfigPath -FileName "backup_store.json"

    if (-not (Confirm-Action -Items @($path))) {
        Write-AnniLog -Level INFO -Message "Wipe backup store pointer cancelled."
        return
    }

    Remove-IfExists -Path $path -Label "config\backup_store.json"
}

function Invoke-WipeBackupData {
    param([string]$BackupRoot)

    $items = @(
        (Join-Path $BackupRoot "app_configs"),
        (Join-Path $BackupRoot "winget_export.json"),
        (Join-Path $BackupRoot "backup_manifest.json")
    )

    $existing = $items | Where-Object { Test-Path $_ }
    if ($existing.Count -eq 0) {
        Write-Host ""
        Write-AnniLog -Level INFO -Message "No backup data found at '$BackupRoot' -- nothing to delete."
        return
    }

    if (-not (Confirm-Action -Items $existing)) {
        Write-AnniLog -Level INFO -Message "Wipe backup data cancelled."
        return
    }

    Remove-IfExists -Path (Join-Path $BackupRoot "app_configs")          -Label "app_configs/"          -IsDirectory
    Remove-IfExists -Path (Join-Path $BackupRoot "winget_export.json")   -Label "winget_export.json"
    Remove-IfExists -Path (Join-Path $BackupRoot "backup_manifest.json") -Label "backup_manifest.json"
}

function Invoke-WipeEverything {
    param([string]$BackupRoot)

    Write-Host ""
    Write-Host "  !! WARNING: THIS WILL WIPE ALL ANNIWIN11 STATE !!" -ForegroundColor Red
    Write-Host ""

    if ($BackupRoot) {
        Write-Host "  Backup data ($BackupRoot\):" -ForegroundColor Yellow
        Write-Host "    - app_configs\"
        Write-Host "    - winget_export.json"
        Write-Host "    - backup_manifest.json"
        Write-Host ""
    }

    Write-Host "  Config files:" -ForegroundColor Yellow
    foreach ($f in $GeneratedConfigFiles) {
        Write-Host "    - config\$f"
    }
    Write-Host ""
    Write-Host "  Project settings:" -ForegroundColor Yellow
    Write-Host "    - config\project_config.json"
    Write-Host ""
    Write-Host "  Backup store pointer:" -ForegroundColor Yellow
    Write-Host "    - config\backup_store.json"
    Write-Host ""
    Write-Host "  Type RESET to confirm, or press Enter to cancel: " -ForegroundColor Red -NoNewline
    $answer = Read-Host

    if ($answer -cne 'RESET') {
        Write-AnniLog -Level INFO -Message "Nuclear wipe cancelled (input was '$answer')."
        Write-Host ""
        Write-Host "  Cancelled." -ForegroundColor Gray
        return
    }

    Write-AnniLog -Level WARNING -Message "Nuclear wipe confirmed. Proceeding..."

    # 1. Backup data first
    if ($BackupRoot) {
        Remove-IfExists -Path (Join-Path $BackupRoot "app_configs")          -Label "app_configs/"          -IsDirectory
        Remove-IfExists -Path (Join-Path $BackupRoot "winget_export.json")   -Label "winget_export.json"
        Remove-IfExists -Path (Join-Path $BackupRoot "backup_manifest.json") -Label "backup_manifest.json"
    }

    # 2. Backup store pointer
    Remove-IfExists -Path (Get-ConfigPath -FileName "backup_store.json") -Label "config\backup_store.json"

    # 3. Generated config files
    foreach ($f in $GeneratedConfigFiles) {
        Remove-IfExists -Path (Get-ConfigPath -FileName $f) -Label "config\$f"
    }

    # 4. Project settings
    Remove-IfExists -Path (Get-ConfigPath -FileName "project_config.json") -Label "config\project_config.json"

    Write-Host ""
    Write-AnniLog -Level SUCCESS -Message "Nuclear wipe complete."
}

# ------- MENU ------- #

$backupRoot = Get-BackupRoot
$option4Label = if ($backupRoot) { $backupRoot } else { "(no backup configured)" }
$option4Enabled = $null -ne $backupRoot

Write-Host ""
Write-Host "  AnniWin11 -- Reset / Wipe State" -ForegroundColor Cyan
Write-Host "  ================================" -ForegroundColor Gray
Write-Host ""
Write-Host "  Select what to wipe:"
Write-Host ""
Write-Host "  [1] Generated configs       apps.json, app_configs.json, settings.json, ignored_apps.json"
Write-Host "  [2] Project settings        project_config.json (resets to defaults)"
Write-Host "  [3] Backup store pointer    backup_store.json (forgets drive path, does NOT touch backup data)"

if ($option4Enabled) {
    Write-Host "  [4] Actual backup data      $option4Label"
} else {
    Write-Host "  [4] Actual backup data      $option4Label" -ForegroundColor DarkGray
}

Write-Host "  [5] WIPE EVERYTHING         All of the above" -ForegroundColor Red
Write-Host "  [0] Cancel"
Write-Host ""

$choice = Read-Host "  Enter your choice (0-5)"

switch ($choice) {
    '0' {
        Write-AnniLog -Level INFO -Message "Reset cancelled by user."
        Write-Host ""
        Write-Host "  Cancelled." -ForegroundColor Gray
    }
    '1' { Invoke-WipeGeneratedConfigs }
    '2' { Invoke-WipeProjectSettings }
    '3' { Invoke-WipeBackupStorePointer }
    '4' {
        if (-not $option4Enabled) {
            Write-Host ""
            Write-AnniLog -Level WARNING -Message "Option 4 unavailable: no backup store configured (backup_store.json not found)."
        } else {
            Invoke-WipeBackupData -BackupRoot $backupRoot
        }
    }
    '5' { Invoke-WipeEverything -BackupRoot $backupRoot }
    default {
        Write-AnniLog -Level WARNING -Message "Invalid choice: '$choice'"
        Write-Host ""
        Write-Host "  Invalid choice. Enter 0-5." -ForegroundColor Yellow
    }
}

Write-Host ""
Write-AnniLog -Level INFO -Message "Reset complete. Run setup again to start fresh."
Close-AnniLog
Pause

# ------- END RESET STATE SCRIPT ------- #
