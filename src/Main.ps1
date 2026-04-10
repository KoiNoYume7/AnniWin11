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
    Write-Host "  [1] First-time setup       (full setup flow)"
    Write-Host "  [2] Restore configs only"
    Write-Host "  [3] Backup configs now"
    Write-Host "  [4] Detect and add new apps"
    Write-Host "  [5] Apply Windows settings"
    Write-Host "  [6] Pin taskbar apps"
    Write-Host "  [7] Install apps"
    Write-Host "  [8] Generate / regenerate configs"
    Write-Host "  [9] Drive setup (backup store)"
    Write-Host "  [0] Exit"
    Write-Host ""
}

function Invoke-Script {
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

function Invoke-FirstTimeSetup {
    Write-AnniLog -Level INFO -Message "Starting first-time setup flow..."
    Write-Host ""

    # Step 1: Drive setup
    Write-Host "Step 1/6: Drive Setup" -ForegroundColor Cyan
    Invoke-Script -ScriptName "DriveSetup.ps1" -Description "Backup drive selection"

    # Step 2: Generate configs
    Write-Host "Step 2/6: Generate Configs" -ForegroundColor Cyan
    Invoke-Script -ScriptName "GenerateConfigs.ps1" -Description "Config file generation"

    # Step 3: Install apps
    Write-Host "Step 3/6: Install Apps" -ForegroundColor Cyan
    Invoke-Script -ScriptName "InstallApps.ps1" -Description "App installation"

    # Step 4: Apply Windows settings
    Write-Host "Step 4/6: Windows Settings" -ForegroundColor Cyan
    Invoke-Script -ScriptName "WinSettings.ps1" -Description "Windows settings"

    # Step 5: Pin taskbar apps
    Write-Host "Step 5/6: Pin Taskbar Apps" -ForegroundColor Cyan
    Invoke-Script -ScriptName "Pin-TaskbarApp.ps1" -Description "Taskbar pinning"

    # Step 6: Restore configs
    Write-Host "Step 6/6: Restore Configs" -ForegroundColor Cyan
    Invoke-Script -ScriptName "RestoreConfigs.ps1" -Description "Config restoration"

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
        '2' { Invoke-Script -ScriptName "RestoreConfigs.ps1" -Description "Restore configs" }
        '3' { Invoke-Script -ScriptName "BackupConfigs.ps1" -Description "Backup configs" }
        '4' { Invoke-Script -ScriptName "DetectApps.ps1" -Description "Detect and add apps" }
        '5' { Invoke-Script -ScriptName "WinSettings.ps1" -Description "Apply Windows settings" }
        '6' { Invoke-Script -ScriptName "Pin-TaskbarApp.ps1" -Description "Pin taskbar apps" }
        '7' { Invoke-Script -ScriptName "InstallApps.ps1" -Description "Install apps" }
        '8' { Invoke-Script -ScriptName "GenerateConfigs.ps1" -Description "Generate configs" }
        '9' { Invoke-Script -ScriptName "DriveSetup.ps1" -Description "Drive setup" }
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
