# ------- DRIVE SETUP SCRIPT ------- #

# Interactive drive/partition selector for the AnniWin11 backup store.
# Writes the chosen backup path to config/backup_store.json.
# Requires -Version 7.0

# ------- DEPENDENCIES ------- #
. "$PSScriptRoot\..\lib\Config.ps1"
Import-Module "$PSScriptRoot\..\lib\AnniLog.psd1" -Force

# ------- PATHS ------- #
$LogFile          = Get-LogPath -FileName "drive_setup.log"
$BackupStoreFile  = Get-ConfigPath -FileName "backup_store.json"

# ------- INITIALISE LOGGING ------- #
Initialize-AnniLog -LogFilePath $LogFile -LogLevel "INFO"

Write-AnniLog -Level INFO -Message "AnniWin11 Drive Setup"
Write-AnniLog -Level INFO -Message "Select a drive or partition for the backup store."
Write-Host ""

# ------- LIST AVAILABLE DRIVES ------- #

function Get-DriveList {
    $drives = Get-Volume | Where-Object {
        $_.DriveLetter -and
        $_.DriveType -eq 'Fixed' -and
        $_.FileSystemType -ne $null -and
        $_.Size -gt 0
    } | Sort-Object DriveLetter

    return $drives
}

function Show-DriveTable {
    param($Drives)

    Write-Host ""
    Write-Host "Available drives:" -ForegroundColor Cyan
    Write-Host ("-" * 75)
    Write-Host ("{0,-6} {1,-20} {2,-12} {3,-12} {4,-12}" -f "Drive", "Label", "FileSystem", "Size (GB)", "Free (GB)")
    Write-Host ("-" * 75)

    $index = 0
    foreach ($drive in $Drives) {
        $sizeGB = [math]::Round($drive.Size / 1GB, 1)
        $freeGB = [math]::Round($drive.SizeRemaining / 1GB, 1)
        $label  = if ($drive.FileSystemLabel) { $drive.FileSystemLabel } else { "(No label)" }

        Write-Host ("{0,-6} {1,-20} {2,-12} {3,-12} {4,-12}" -f "[$index] $($drive.DriveLetter):", $label, $drive.FileSystemType, $sizeGB, $freeGB)
        $index++
    }
    Write-Host ("-" * 75)
}

# ------- DRIVE SELECTION ------- #

$drives = Get-DriveList

if ($drives.Count -eq 0) {
    Write-AnniLog -Level ERROR -Message "No fixed drives found."
    Close-AnniLog
    exit 1
}

Show-DriveTable -Drives $drives

Write-Host ""
Write-Host "Options:" -ForegroundColor Cyan
Write-Host "  [0-$($drives.Count - 1)] Select a drive by index"
Write-Host "  [P]         Create a new partition on C: (requires admin)"
Write-Host "  [C]         Cancel"
Write-Host ""

$choice = Read-Host "Enter your choice"

$backupRoot = $null

if ($choice -match '^\d+$') {
    $idx = [int]$choice
    if ($idx -ge 0 -and $idx -lt $drives.Count) {
        $selectedDrive = $drives[$idx]
        $backupRoot = "$($selectedDrive.DriveLetter):\AnniWin11Backup"
        Write-AnniLog -Level INFO -Message "Selected drive: $($selectedDrive.DriveLetter): ($($selectedDrive.FileSystemLabel))"
    } else {
        Write-AnniLog -Level ERROR -Message "Invalid drive index: $idx"
        Close-AnniLog
        exit 1
    }
}
elseif ($choice -match '^[Pp]$') {
    Write-Host ""
    Write-AnniLog -Level WARNING -Message "Partition creation requires administrator privileges."
    Write-AnniLog -Level INFO -Message "This will shrink the C: drive and create a new partition."
    Write-Host ""

    $shrinkMB = Read-Host "How many MB to shrink C: by? (e.g. 51200 for ~50 GB)"
    if (-not ($shrinkMB -match '^\d+$') -or [int]$shrinkMB -lt 1024) {
        Write-AnniLog -Level ERROR -Message "Invalid size. Minimum 1024 MB."
        Close-AnniLog
        exit 1
    }

    $partLabel = Read-Host "Label for the new partition (default: ANNI-BACKUP)"
    if ([string]::IsNullOrWhiteSpace($partLabel)) { $partLabel = "ANNI-BACKUP" }

    Write-Host ""
    Write-AnniLog -Level WARNING -Message "About to shrink C: by $shrinkMB MB and create partition '$partLabel'."
    $confirm = Read-Host "Are you sure? (yes/no)"
    if ($confirm -ne "yes") {
        Write-AnniLog -Level INFO -Message "Partition creation cancelled."
        Close-AnniLog
        exit 0
    }

    try {
        # Get the C: partition
        $cPartition = Get-Partition -DriveLetter C

        # Shrink C:
        Write-AnniLog -Level INFO -Message "Shrinking C: by $shrinkMB MB..."
        $newSize = $cPartition.Size - ([int64]$shrinkMB * 1MB)
        Resize-Partition -DriveLetter C -Size $newSize

        # Get the disk number
        $diskNumber = $cPartition.DiskNumber

        # Create new partition in the unallocated space
        Write-AnniLog -Level INFO -Message "Creating new partition..."
        $newPartition = New-Partition -DiskNumber $diskNumber -UseMaximumSize -AssignDriveLetter

        # Format the new partition
        Write-AnniLog -Level INFO -Message "Formatting as NTFS with label '$partLabel'..."
        Format-Volume -Partition $newPartition -FileSystem NTFS -NewFileSystemLabel $partLabel -Confirm:$false | Out-Null

        $newDriveLetter = $newPartition.DriveLetter
        $backupRoot = "${newDriveLetter}:\AnniWin11Backup"
        Write-AnniLog -Level SUCCESS -Message "New partition created: ${newDriveLetter}: ($partLabel)"
    }
    catch {
        Write-AnniLog -Level ERROR -Message "Partition creation failed: $_"
        Write-AnniLog -Level ERROR -Message "You may need to run this as Administrator, or use Disk Management manually."
        Close-AnniLog
        exit 1
    }
}
elseif ($choice -match '^[Cc]$') {
    Write-AnniLog -Level INFO -Message "Drive setup cancelled."
    Close-AnniLog
    exit 0
}
else {
    Write-AnniLog -Level ERROR -Message "Invalid choice: $choice"
    Close-AnniLog
    exit 1
}

# ------- VALIDATE AND WRITE ------- #

if ($backupRoot) {
    # Create the backup root directory if it does not exist
    if (-not (Test-Path $backupRoot)) {
        try {
            New-Item -ItemType Directory -Path $backupRoot -Force | Out-Null
            Write-AnniLog -Level SUCCESS -Message "Created backup directory: $backupRoot"
        }
        catch {
            Write-AnniLog -Level ERROR -Message "Failed to create backup directory: $_"
            Close-AnniLog
            exit 1
        }
    }

    # Test write access
    $testFile = Join-Path $backupRoot ".anni_write_test"
    try {
        "test" | Out-File -FilePath $testFile -Force
        Remove-Item $testFile -Force
        Write-AnniLog -Level DEBUG -Message "Write access confirmed for $backupRoot"
    }
    catch {
        Write-AnniLog -Level ERROR -Message "Cannot write to $backupRoot -- check permissions."
        Close-AnniLog
        exit 1
    }

    # Create subdirectories
    $appConfigsDir = Join-Path $backupRoot "app_configs"
    if (-not (Test-Path $appConfigsDir)) {
        New-Item -ItemType Directory -Path $appConfigsDir -Force | Out-Null
    }

    # Write backup_store.json
    $storeConfig = @{
        backup_root  = $backupRoot
        configured_at = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
    }

    try {
        $storeConfig | ConvertTo-Json -Depth 3 | Out-File -FilePath $BackupStoreFile -Encoding utf8 -Force
        Write-AnniLog -Level SUCCESS -Message "Backup store path saved to: $BackupStoreFile"
        Write-AnniLog -Level SUCCESS -Message "Backup root: $backupRoot"
    }
    catch {
        Write-AnniLog -Level ERROR -Message "Failed to write backup_store.json: $_"
    }
}

Write-Host ""
Close-AnniLog
Pause

# ------- END DRIVE SETUP SCRIPT ------- #
