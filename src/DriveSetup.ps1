# ------- DRIVE SETUP SCRIPT ------- #

# Interactive drive/partition selector for the AnniWin11 backup store.
# Writes the chosen backup path to config/backup_store.json.
# v0.3.0 rewrite: supports Fixed, Removable (USB/flash), and Network drives,
# warns when the selected path is on the system disk, and carries over the
# partition-creation flow with improved detection.
# Requires -Version 7.0

# ------- DEPENDENCIES ------- #
. "$PSScriptRoot\..\lib\Config.ps1"
Import-Module "$PSScriptRoot\..\lib\AnniLog.psd1" -Force

# ------- PATHS ------- #
$LogFile          = Get-LogPath -FileName "drive_setup.log"
$BackupStoreFile  = Get-ConfigPath -FileName "backup_store.json"

# ------- INITIALISE LOGGING ------- #
$ProjectConfig = Get-ProjectConfig
Initialize-AnniLog -LogFilePath $LogFile -LogLevel $ProjectConfig.log_level

Write-AnniLog -Level INFO -Message "AnniWin11 Drive Setup"
Write-AnniLog -Level INFO -Message "Select a drive or partition for the backup store."
Write-Host ""

# ------- HELPER: RESOLVE SYSTEM DISK NUMBER ------- #

function Get-SystemDiskNumber {
    <#
    .SYNOPSIS
        Returns the physical disk number that hosts the C: partition.
    .DESCRIPTION
        Used to detect whether a user-selected drive shares the same physical
        disk as the Windows installation. Returns $null if detection fails.
    #>
    try {
        $cPart = Get-Partition -DriveLetter C -ErrorAction Stop
        return $cPart.DiskNumber
    }
    catch {
        Write-AnniLog -Level DEBUG -Message "Could not resolve system disk number: $($_.Exception.Message)"
        return $null
    }
}

# ------- LIST AVAILABLE DRIVES ------- #

function Get-DriveList {
    <#
    .SYNOPSIS
        Returns a list of usable drives for the backup store.
    .DESCRIPTION
        Primary path: combines Get-Partition and Get-Volume to discover all
        drive types -- Fixed (internal), Removable (USB/flash), and Network.
        This replaces the v0.2.0 approach that only showed Fixed drives.

        Fallback path: Get-PSDrive, which works in environments where the
        Storage module is unavailable (notably Windows Sandbox).

        Each returned object includes a DriveType field for display and a
        DiskNumber field for system-disk detection.
    #>

    $results = @()

    # --- Primary: Get-Partition + Get-Volume ---
    try {
        $partitions = Get-Partition -ErrorAction Stop | Where-Object {
            $_.DriveLetter -and $_.Size -gt 0
        }

        foreach ($part in $partitions) {
            try {
                $vol = Get-Volume -DriveLetter $part.DriveLetter -ErrorAction Stop
            }
            catch {
                Write-AnniLog -Level DEBUG -Message "Get-Volume failed for $($part.DriveLetter): $($_.Exception.Message)"
                continue
            }

            if ($null -eq $vol.FileSystemType -or $vol.Size -le 0) { continue }

            # Determine drive type: check the physical disk for BusType
            $driveType = "Fixed"
            try {
                $disk = Get-Disk -Number $part.DiskNumber -ErrorAction Stop
                if ($disk.BusType -in @('USB', 'SD')) {
                    $driveType = "Removable"
                }
            }
            catch {
                # If Get-Disk fails, fall back to the volume's DriveType
                if ($vol.DriveType -eq 'Removable') { $driveType = "Removable" }
            }

            $results += [PSCustomObject]@{
                DriveLetter     = [string]$part.DriveLetter
                FileSystemLabel = if ($vol.FileSystemLabel) { $vol.FileSystemLabel } else { "" }
                FileSystemType  = [string]$vol.FileSystemType
                DriveType       = $driveType
                Size            = $vol.Size
                SizeRemaining   = $vol.SizeRemaining
                DiskNumber      = $part.DiskNumber
            }
        }
    }
    catch {
        Write-AnniLog -Level DEBUG -Message "Get-Partition failed: $($_.Exception.Message)"
    }

    # --- Also detect network (mapped) drives via Get-PSDrive ---
    try {
        $netDrives = Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue |
            Where-Object {
                $_.Name -match '^[A-Za-z]$' -and
                $null -ne $_.Used -and
                $_.DisplayRoot -and
                $_.DisplayRoot -match '^\\\\'
            }

        foreach ($nd in $netDrives) {
            # Skip if already captured via partition enumeration
            if ($results | Where-Object { $_.DriveLetter -eq $nd.Name }) { continue }

            $used  = [int64]($nd.Used | ForEach-Object { if ($_) { $_ } else { 0 } })
            $free  = [int64]($nd.Free | ForEach-Object { if ($_) { $_ } else { 0 } })
            $total = $used + $free
            if ($total -le 0) { continue }

            $results += [PSCustomObject]@{
                DriveLetter     = $nd.Name
                FileSystemLabel = $nd.DisplayRoot
                FileSystemType  = "(network)"
                DriveType       = "Network"
                Size            = $total
                SizeRemaining   = $free
                DiskNumber      = $null
            }
        }
    }
    catch {
        Write-AnniLog -Level DEBUG -Message "Network drive enumeration failed: $($_.Exception.Message)"
    }

    # --- If the primary path returned results, we're done ---
    if ($results.Count -gt 0) {
        return $results | Sort-Object DriveLetter
    }

    # --- Fallback: Get-PSDrive (works in Windows Sandbox) ---
    Write-AnniLog -Level DEBUG -Message "Partition/Volume enumeration returned no drives, falling back to Get-PSDrive."
    $psDrives = Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '^[A-Za-z]$' -and $null -ne $_.Used }

    $fallback = foreach ($d in $psDrives) {
        $used  = [int64]($d.Used | ForEach-Object { if ($_) { $_ } else { 0 } })
        $free  = [int64]($d.Free | ForEach-Object { if ($_) { $_ } else { 0 } })
        $total = $used + $free
        if ($total -le 0) { continue }

        [PSCustomObject]@{
            DriveLetter     = $d.Name
            FileSystemLabel = if ($d.Description) { $d.Description } else { "" }
            FileSystemType  = "(unknown)"
            DriveType       = "(unknown)"
            Size            = $total
            SizeRemaining   = $free
            DiskNumber      = $null
        }
    }

    return @($fallback | Sort-Object DriveLetter)
}

# ------- DISPLAY ------- #

function Show-DriveTable {
    param($Drives)

    Write-Host ""
    Write-Host "Available drives:" -ForegroundColor Cyan
    Write-Host ("-" * 88)
    Write-Host ("{0,-6} {1,-18} {2,-12} {3,-12} {4,-12} {5,-12}" -f "Drive", "Label", "Type", "FileSystem", "Size (GB)", "Free (GB)")
    Write-Host ("-" * 88)

    $index = 0
    foreach ($drive in $Drives) {
        $sizeGB = [math]::Round($drive.Size / 1GB, 1)
        $freeGB = [math]::Round($drive.SizeRemaining / 1GB, 1)
        $label  = if ($drive.FileSystemLabel) { $drive.FileSystemLabel } else { "(No label)" }
        # Truncate long labels (e.g. network UNC paths)
        if ($label.Length -gt 18) { $label = $label.Substring(0, 15) + "..." }

        Write-Host ("{0,-6} {1,-18} {2,-12} {3,-12} {4,-12} {5,-12}" -f "[$index] $($drive.DriveLetter):", $label, $drive.DriveType, $drive.FileSystemType, $sizeGB, $freeGB)
        $index++
    }
    Write-Host ("-" * 88)
}

# ------- WARNING HELPERS ------- #

function Test-IsSystemDisk {
    <#
    .SYNOPSIS
        Returns $true if the given drive letter is on the same physical disk as C:.
    #>
    param(
        [string]$DriveLetter,
        [object]$DriveEntry,
        [int]$SystemDiskNumber
    )

    # If we couldn't detect the system disk number, fall back to letter check
    if ($null -eq $SystemDiskNumber) {
        return ($DriveLetter -eq 'C')
    }

    # If the drive entry has a DiskNumber, compare directly
    if ($null -ne $DriveEntry.DiskNumber) {
        return ($DriveEntry.DiskNumber -eq $SystemDiskNumber)
    }

    # For network/fallback drives without DiskNumber, only flag if it's C:
    return ($DriveLetter -eq 'C')
}

function Show-SystemDiskWarning {
    Write-Host ""
    Write-Host "  ============================================================" -ForegroundColor Red
    Write-Host "  WARNING: You selected a location on your system drive (or a"  -ForegroundColor Red
    Write-Host "  partition on the same physical disk as C:). Your backup will"  -ForegroundColor Red
    Write-Host "  very likely be LOST if you wipe this drive during a Windows"   -ForegroundColor Red
    Write-Host "  reinstall."                                                    -ForegroundColor Red
    Write-Host "  ============================================================" -ForegroundColor Red
    Write-Host ""
}

function Show-ReinstallReminder {
    Write-Host ""
    Write-Host "  Make sure your backup destination is on a drive that will NOT" -ForegroundColor Yellow
    Write-Host "  be wiped during reinstall (external drive, USB, separate"      -ForegroundColor Yellow
    Write-Host "  internal drive, or network location)."                         -ForegroundColor Yellow
    Write-Host ""
}

# ------- DRIVE SELECTION ------- #

$drives = @(Get-DriveList)

if ($drives.Count -eq 0) {
    Write-AnniLog -Level ERROR -Message "No usable drives found. (Check Get-Volume, Get-Partition, and Get-PSDrive output.)"
    Close-AnniLog
    exit 1
}

$systemDiskNumber = Get-SystemDiskNumber

Show-DriveTable -Drives $drives

Write-Host ""
Write-Host "Options:" -ForegroundColor Cyan
Write-Host "  [0-$($drives.Count - 1)] Select a drive by index"
Write-Host "  [P]         Create a new partition on C: (requires admin)"
Write-Host "  [C]         Cancel"
Write-Host ""

$choice = Read-Host "Enter your choice"

$backupRoot    = $null
$selectedDrive = $null

if ($choice -match '^\d+$') {
    $idx = [int]$choice
    if ($idx -ge 0 -and $idx -lt $drives.Count) {
        $selectedDrive = $drives[$idx]
        $backupRoot = "$($selectedDrive.DriveLetter):\AnniWin11Backup"
        Write-AnniLog -Level INFO -Message "Selected drive: $($selectedDrive.DriveLetter): ($($selectedDrive.FileSystemLabel)) [$($selectedDrive.DriveType)]"

        # --- C: drive / system disk warning ---
        $isSystemDisk = Test-IsSystemDisk `
            -DriveLetter $selectedDrive.DriveLetter `
            -DriveEntry $selectedDrive `
            -SystemDiskNumber $systemDiskNumber

        if ($isSystemDisk -and -not $ProjectConfig.suppress_c_drive_warning) {
            Show-SystemDiskWarning
            Write-AnniLog -Level WARNING -Message "User selected a path on the system disk ($($selectedDrive.DriveLetter):)."
            $confirm = Read-Host "  Are you sure you want to continue? (yes/no)"
            if ($confirm -ne "yes") {
                Write-AnniLog -Level INFO -Message "Drive selection cancelled by user after system-disk warning."
                Close-AnniLog
                exit 0
            }
        }

        # --- General reinstall reminder (shown for every selection) ---
        Show-ReinstallReminder

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
        # Get the C: partition via Get-Partition (improved detection)
        $cPartition = Get-Partition -DriveLetter C -ErrorAction Stop

        # Validate shrink size against available space
        $minSupportedSize = (Get-PartitionSupportedSize -DriveLetter C -ErrorAction SilentlyContinue).SizeMin
        $proposedSize = $cPartition.Size - ([int64]$shrinkMB * 1MB)
        if ($minSupportedSize -and $proposedSize -lt $minSupportedSize) {
            $availableShrinkMB = [math]::Floor(($cPartition.Size - $minSupportedSize) / 1MB)
            Write-AnniLog -Level ERROR -Message "Cannot shrink C: by $shrinkMB MB. Maximum shrinkable: ~$availableShrinkMB MB."
            Close-AnniLog
            exit 1
        }

        # Shrink C:
        Write-AnniLog -Level INFO -Message "Shrinking C: by $shrinkMB MB..."
        Resize-Partition -DriveLetter C -Size $proposedSize

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

        # The new partition is on the same physical disk as C: -- always warn
        if (-not $ProjectConfig.suppress_c_drive_warning) {
            Show-SystemDiskWarning
            Write-AnniLog -Level WARNING -Message "The new partition is on the same physical disk as C:."
            Write-AnniLog -Level WARNING -Message "If you wipe the entire disk during reinstall, this partition will also be lost."
            Write-AnniLog -Level INFO -Message "Ensure you only format the C: partition (not the whole disk) during reinstall."
        }

        Show-ReinstallReminder
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
        backup_root   = $backupRoot
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
