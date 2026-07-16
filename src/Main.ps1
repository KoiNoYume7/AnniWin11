# ------- ANNIWIN11 MAIN MENU ------- #

# Interactive orchestrator for AnniWin11.
# Requires -Version 7.0

# ------- DEPENDENCIES ------- #
. "$PSScriptRoot\..\lib\Config.ps1"
Import-Module "$PSScriptRoot\..\lib\AnniLog.psd1" -Force
Import-Module "$PSScriptRoot\..\lib\AnniLogo.psd1" -Force

# ------- PATHS ------- #
$LogFile = Get-LogPath -FileName "main.log"

# ------- INITIALISE LOGGING ------- #
$ProjectConfig = Get-ProjectConfig
Initialize-AnniLog -LogFilePath $LogFile -LogLevel $ProjectConfig.log_level

# ------- ASCII ART (AnniWin11-specific) ------- #
# source: https://patorjk.com/software/taag/#p=display&f=Alligator2&t=Type+Something+&x=none&v=4&h=4&w=80&we=false

$AnniAsciiLines = @(
    "                                                                                                       ",
    "                                                                                                       ",
    "     :::     ::::    ::: ::::    ::: ::::::::::: :::       ::: ::::::::::: ::::    :::   :::     :::   ",
    "   :+: :+:   :+:+:   :+: :+:+:   :+:     :+:     :+:       :+:     :+:     :+:+:   :+: :+:+:   :+:+:   ",
    "  +:+   +:+  :+:+:+  +:+ :+:+:+  +:+     +:+     +:+       +:+     +:+     :+:+:+  +:+   +:+     +:+   ",
    " +#++:++#++: +#+ +:+ +#+ +#+ +:+ +#+     +#+     +#+  +:+  +#+     +#+     +#+ +:+ +#+   +#+     +#+   ",
    " +#+     +#+ +#+  +#+#+# +#+  +#+#+#     +#+     +#+ +#+#+ +#+     +#+     +#+  +#+#+#   +#+     +#+   ",
    " #+#     #+# #+#   #+#+# #+#   #+#+#     #+#      #+#+# #+#+#      #+#     #+#   #+#+#   #+#     #+#   ",
    " ###     ### ###    #### ###    #### ###########   ###   ###   ########### ###    #### ####### ####### ",
    "                                                                                                       ",
    "                                                                                                       ",
    "                                                                                                       "
)

$AnniStartColor = @{ R = 0; G = 255; B = 255 }    # Cyan
$AnniEndColor   = @{ R = 255; G = 0; B = 0 }      # Red

# ------- MENU FUNCTIONS ------- #

function Show-Menu {
    Show-AnniLogo -AsciiLines $AnniAsciiLines -StartColor $AnniStartColor -EndColor $AnniEndColor
    Write-Host ""
    Write-Host "  AnniWin11 -- Windows 11 Post-Install Automation" -ForegroundColor White
    Write-Host "  ================================================" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  [1] First-time setup       (select backup drive, detect apps, build config files)"
    Write-Host "  [2] Restore configs only"
    Write-Host "  [3] Backup configs now"
    Write-Host "  [4] Detect and add new apps"
    Write-Host "  [5] Apply Windows settings"
    Write-Host "  [6] Pin taskbar apps"
    Write-Host "  [7] Install apps"
    Write-Host "  [8] Generate / regenerate configs"
    Write-Host "  [9] Drive setup (backup store)"
    Write-Host "  [R] Reset / wipe state"
    Write-Host "  [0] Exit"
    Write-Host ""
}

function Invoke-Script {
    # Out-of-process: use for scripts that need isolation (winget, elevation, exit codes).
    param(
        [string]$ScriptName,
        [string]$Description
    )

    $scriptPath = Join-Path $PSScriptRoot $ScriptName
    if (-not (Test-Path $scriptPath)) {
        Write-AnniLog -Level ERROR -Message "$ScriptName not found at $scriptPath"
        return
    }

    Write-AnniLog -Level INFO -Message "Running: $Description"
    Write-Host ""

    $proc = Start-Process -FilePath "pwsh" `
        -ArgumentList "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $scriptPath `
        -NoNewWindow -Wait -PassThru

    if ($proc.ExitCode -ne 0) {
        Write-AnniLog -Level WARNING -Message "$ScriptName exited with code $($proc.ExitCode)"
    }
}

function Invoke-ScriptInProcess {
    # In-process via Start-ThreadJob: no cold-start overhead, output streams live.
    # exit calls in the child script terminate only the thread, not Main.ps1.
    # Falls back to Invoke-Script if Start-ThreadJob is unavailable.
    #
    # DO NOT use this for scripts that call Read-Host: Read-Host does not
    # work reliably inside a thread job when the parent host is an interactive
    # console (the prompt shows but the thread cannot acquire console input).
    # Use Invoke-Script (out-of-process) for any interactive script.
    param(
        [string]$ScriptName,
        [string]$Description
    )

    $scriptPath = Join-Path $PSScriptRoot $ScriptName
    if (-not (Test-Path $scriptPath)) {
        Write-AnniLog -Level ERROR -Message "$ScriptName not found at $scriptPath"
        return
    }

    Write-AnniLog -Level INFO -Message "Running: $Description"
    Write-Host ""

    if (Get-Command Start-ThreadJob -ErrorAction SilentlyContinue) {
        $job = Start-ThreadJob -ScriptBlock { & $using:scriptPath } -StreamingHost $Host
        Wait-Job $job | Out-Null
        if ($job.State -eq 'Failed') {
            Write-AnniLog -Level WARNING -Message "$ScriptName failed: $($job.ChildJobs[0].JobStateInfo.Reason.Message)"
        }
        Remove-Job $job -Force
    } else {
        Invoke-Script -ScriptName $ScriptName -Description $Description
    }
}

function Invoke-FirstTimeSetup {
    Write-AnniLog -Level INFO -Message "Starting first-time setup flow..."
    Write-Host ""
    Write-Host "This flow sets up AnniWin11 on your current system so it is ready to" -ForegroundColor Yellow
    Write-Host "back up and restore your apps and configs after a Windows reinstall." -ForegroundColor Yellow
    Write-Host ""

    # Step 1: Drive setup
    Write-Host "Step 1/2: Drive Setup" -ForegroundColor Cyan
    Write-Host "  Select where your backups will be stored." -ForegroundColor Gray
    Invoke-Script -ScriptName "DriveSetup.ps1" -Description "Backup drive selection"

    # Step 2: Generate configs
    Write-Host "Step 2/2: Generate Configs" -ForegroundColor Cyan
    Write-Host "  Detect your installed apps, discover their config paths, build config files." -ForegroundColor Gray
    Invoke-Script -ScriptName "GenerateConfigs.ps1" -Description "Config file generation"

    Write-Host ""
    Write-Host "  First-time setup complete." -ForegroundColor Green
    Write-Host ""
    Write-Host "  Next steps:" -ForegroundColor Cyan
    Write-Host "    - Run [3] Backup configs now to snapshot your current app configs."
    Write-Host "    - After reinstalling Windows, use [7] Install apps and [2] Restore configs."
    Write-Host ""
    Write-AnniLog -Level SUCCESS -Message "First-time setup complete."
    Pause
}

# ------- MAIN LOOP ------- #

$running = $true

while ($running) {
    Show-Menu
    $choice = Read-Host "  Enter your choice (0-9)"

    switch ($choice) {
        '1' { Invoke-FirstTimeSetup }
        # RestoreConfigs is interactive (Read-Host confirmations) -> must run out-of-process.
        '2' { Invoke-Script -ScriptName "RestoreConfigs.ps1" -Description "Restore configs" }
        '3' { Invoke-Script -ScriptName "BackupConfigs.ps1" -Description "Backup configs" }
        '4' { Invoke-Script -ScriptName "DetectApps.ps1" -Description "Detect and add apps" }
        '5' { Invoke-ScriptInProcess -ScriptName "WinSettings.ps1" -Description "Apply Windows settings" }
        '6' { Invoke-ScriptInProcess -ScriptName "Pin-TaskbarApp.ps1" -Description "Pin taskbar apps" }
        '7' { Invoke-Script -ScriptName "InstallApps.ps1" -Description "Install apps" }
        '8' { Invoke-Script -ScriptName "GenerateConfigs.ps1" -Description "Generate configs" }
        '9' { Invoke-Script -ScriptName "DriveSetup.ps1" -Description "Drive setup" }
        'R' { Invoke-Script -ScriptName "ResetState.ps1" -Description "Reset / wipe state" }
        'r' { Invoke-Script -ScriptName "ResetState.ps1" -Description "Reset / wipe state" }
        '0' {
            Write-AnniLog -Level INFO -Message "Exiting AnniWin11."
            $running = $false
        }
        default {
            Write-AnniLog -Level WARNING -Message "Invalid choice: $choice"
            Start-Sleep -Seconds 1
        }
    }
}

Close-AnniLog

# ------- END MAIN MENU ------- #
