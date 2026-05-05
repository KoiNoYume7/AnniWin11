# ------- SETTINGS CONFIGURATION SCRIPT ------- #

# Script to configure various Windows settings from config/settings.json
# Requires -Version 7.0

# ------- DEPENDENCIES ------- #
. "$PSScriptRoot\..\lib\Config.ps1"
Import-Module "$PSScriptRoot\..\lib\AnniLog.psd1" -Force

# ------- PATHS ------- #
$SettingsConfig = Get-ConfigPath -FileName "settings.json"
$LogFile        = Get-LogPath -FileName "settings.log"

# ------- INITIALISE LOGGING ------- #
$ProjectConfig = Get-ProjectConfig
Initialize-AnniLog -LogFilePath $LogFile -LogLevel $ProjectConfig.log_level -EnableStopwatch

# ------- READ SETTINGS ------- #
if (-not (Test-Path $SettingsConfig)) {
    Write-AnniLog -Level ERROR -Message "settings.json not found at $SettingsConfig"
    Write-AnniLog -Level ERROR -Message "Run GenerateConfigs.ps1 or copy settings_example.jsonc to config/settings.json"
    Close-AnniLog
    throw "settings.json missing"
}

try {
    $Settings = Read-JsonFile -Path $SettingsConfig
}
catch {
    Write-AnniLog -Level ERROR -Message "Failed to parse settings.json: $($_.Exception.Message)"
    Close-AnniLog
    exit 1
}

Write-AnniLog -Level INFO -Message "Applying Windows settings from config..."

# ------- DEVICE NAME ------- #
if ($Settings.device_name) {
    try {
        Rename-Computer -NewName $Settings.device_name -ErrorAction Stop
        Write-AnniLog -Level SUCCESS -Message "Device renamed to '$($Settings.device_name)'"
    }
    catch {
        Write-AnniLog -Level WARNING -Message "Failed to rename device: $_"
    }
}

# ------- SOUND SCHEME ------- #
if ($Settings.sound_scheme -eq "none") {
    Write-AnniLog -Level INFO -Message "Setting sound scheme to none"
    try {
        Get-ChildItem -Path "HKCU:\AppEvents\Schemes\Apps" |
            Get-ChildItem |
            Get-ChildItem |
            Where-Object { $_.PSChildName -eq ".Current" } |
            Set-ItemProperty -Name "(Default)" -Value ""
        Write-AnniLog -Level SUCCESS -Message "Sound scheme set to none"
    }
    catch {
        Write-AnniLog -Level WARNING -Message "Failed to set sound scheme: $_"
    }
}

# ------- THEME ------- #
if ($Settings.theme -eq "dark") {
    Write-AnniLog -Level INFO -Message "Applying dark theme"
    Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize" -Name "AppsUseLightTheme" -Value 0
    Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize" -Name "SystemUsesLightTheme" -Value 0
}
elseif ($Settings.theme -eq "light") {
    Write-AnniLog -Level INFO -Message "Applying light theme"
    Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize" -Name "AppsUseLightTheme" -Value 1
    Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize" -Name "SystemUsesLightTheme" -Value 1
}

# ------- WALLPAPER ------- #
if ($Settings.wallpaper -eq "solid_black") {
    Write-AnniLog -Level INFO -Message "Setting wallpaper to solid black"
    Add-Type -TypeDefinition @"
using System.Runtime.InteropServices;
public class Wallpaper {
    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool SystemParametersInfo(int uAction, int uParam, string lpvParam, int fuWinIni);
}
"@
    [Wallpaper]::SystemParametersInfo(20, 0, "", 3) | Out-Null
    Set-ItemProperty -Path "HKCU:\Control Panel\Colors" -Name "Background" -Value "0 0 0"
}

# ------- REGION ------- #
if ($Settings.region) {
    Write-AnniLog -Level INFO -Message "Setting regional format to '$($Settings.region)'"
    try {
        Set-Culture -CultureInfo $Settings.region
        Write-AnniLog -Level SUCCESS -Message "Regional format set to '$($Settings.region)'"
    }
    catch {
        Write-AnniLog -Level WARNING -Message "Failed to set region: $_"
    }
}

# ------- TASKBAR ------- #
$explorerAdvanced = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced"

if ($null -ne $Settings.taskbar) {
    $tb = $Settings.taskbar

    # Alignment (0 = left, 1 = centre)
    if ($null -ne $tb.alignment) {
        $alignValue = if ($tb.alignment -eq "left") { 0 } else { 1 }
        Write-AnniLog -Level INFO -Message "Setting taskbar alignment to '$($tb.alignment)'"
        Set-ItemProperty -Path $explorerAdvanced -Name "TaskbarAl" -Value $alignValue
    }

    # Search (0 = hidden, 1 = icon, 2 = box)
    if ($null -ne $tb.search) {
        $searchValue = if ($tb.search -eq $false) { 0 } else { 1 }
        Write-AnniLog -Level INFO -Message "Setting taskbar search visibility to $($tb.search)"
        Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Search" -Name "SearchboxTaskbarMode" -Value $searchValue
    }

    # Task View
    if ($null -ne $tb.task_view) {
        $tvValue = if ($tb.task_view) { 1 } else { 0 }
        Write-AnniLog -Level INFO -Message "Setting Task View button to $($tb.task_view)"
        Set-ItemProperty -Path $explorerAdvanced -Name "ShowTaskViewButton" -Value $tvValue
    }

    # Widgets
    #
    # Background: the obvious key (HKCU:\...\Explorer\Advanced\TaskbarDa)
    # throws "unauthorized operation" on some Win11 builds when set via
    # PowerShell's registry provider, even from an elevated session. The
    # cause appears to be ACL hardening on recent cumulative updates --
    # Set-ItemProperty on a pre-existing DWord fails, but reg.exe succeeds.
    #
    # Strategy:
    #   1. Try reg.exe add (primary)  -- most reliable across builds.
    #   2. Try New-ItemProperty/Set-ItemProperty (native PS fallback).
    #   3. Try ShellFeedsTaskbarViewMode under Feeds (older key, last resort).
    if ($null -ne $tb.widgets) {
        $wValue = if ($tb.widgets) { 1 } else { 0 }
        Write-AnniLog -Level INFO -Message "Setting Widgets button to $($tb.widgets)"

        $widgetsOk = $false

        # --- Method 1: reg.exe add (primary) ---
        try {
            $regKey = "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
            $regOut = & reg.exe add $regKey /v "TaskbarDa" /t REG_DWORD /d $wValue /f 2>&1
            if ($LASTEXITCODE -eq 0) {
                Write-AnniLog -Level SUCCESS -Message "Widgets button set to $($tb.widgets) (reg.exe)"
                $widgetsOk = $true
            } else {
                Write-AnniLog -Level DEBUG -Message "reg.exe add failed (exit $LASTEXITCODE): $regOut"
            }
        }
        catch {
            Write-AnniLog -Level DEBUG -Message "reg.exe invocation threw: $_"
        }

        # --- Method 2: Native PowerShell registry provider ---
        if (-not $widgetsOk) {
            try {
                if (-not (Test-Path $explorerAdvanced)) {
                    New-Item -Path $explorerAdvanced -Force | Out-Null
                }
                $existing = Get-ItemProperty -Path $explorerAdvanced -Name "TaskbarDa" -ErrorAction SilentlyContinue
                if ($null -eq $existing) {
                    New-ItemProperty -Path $explorerAdvanced -Name "TaskbarDa" -Value $wValue -PropertyType DWord -Force | Out-Null
                } else {
                    Set-ItemProperty -Path $explorerAdvanced -Name "TaskbarDa" -Value $wValue -Type DWord -Force
                }
                Write-AnniLog -Level SUCCESS -Message "Widgets button set to $($tb.widgets) (PS registry)"
                $widgetsOk = $true
            }
            catch {
                Write-AnniLog -Level DEBUG -Message "Native PS method failed: $_"
            }
        }

        # --- Method 3: ShellFeedsTaskbarViewMode (older key) ---
        if (-not $widgetsOk) {
            try {
                $feedsPath  = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Feeds"
                $feedsValue = if ($tb.widgets) { 0 } else { 2 }  # 2 = hidden, 0 = shown
                if (-not (Test-Path $feedsPath)) {
                    New-Item -Path $feedsPath -Force | Out-Null
                }
                Set-ItemProperty -Path $feedsPath -Name "ShellFeedsTaskbarViewMode" -Value $feedsValue -Type DWord -Force
                Write-AnniLog -Level SUCCESS -Message "Widgets button set via Feeds fallback"
                $widgetsOk = $true
            }
            catch {
                Write-AnniLog -Level DEBUG -Message "Feeds fallback failed: $_"
            }
        }

        if (-not $widgetsOk) {
            Write-AnniLog -Level WARNING -Message "Could not set Widgets button -- all three methods failed. Toggle manually in Taskbar settings."
        }
    }

    # Show seconds in system clock
    if ($null -ne $tb.show_seconds) {
        $secValue = if ($tb.show_seconds) { 1 } else { 0 }
        Write-AnniLog -Level INFO -Message "Setting system clock seconds to $($tb.show_seconds)"
        Set-ItemProperty -Path $explorerAdvanced -Name "ShowSecondsInSystemClock" -Value $secValue
    }

    # Multi-monitor taskbar
    if ($null -ne $tb.multi_monitor) {
        $mmValue = if ($tb.multi_monitor) { 1 } else { 0 }
        Write-AnniLog -Level INFO -Message "Setting multi-monitor taskbar to $($tb.multi_monitor)"
        Set-ItemProperty -Path $explorerAdvanced -Name "MMTaskbarEnabled" -Value $mmValue
    }
}

# ------- EXPLORER ------- #
if ($null -ne $Settings.explorer) {
    $exp = $Settings.explorer

    # Start to This PC (1) or Quick Access (2)
    if ($null -ne $exp.start_to_this_pc) {
        $launchValue = if ($exp.start_to_this_pc) { 1 } else { 2 }
        Write-AnniLog -Level INFO -Message "Setting Explorer start folder to $(if ($exp.start_to_this_pc) { 'This PC' } else { 'Quick Access' })"
        Set-ItemProperty -Path $explorerAdvanced -Name "LaunchTo" -Value $launchValue
    }

    # Show file extensions
    if ($null -ne $exp.show_extensions) {
        $extValue = if ($exp.show_extensions) { 0 } else { 1 }
        Write-AnniLog -Level INFO -Message "Setting file extensions visibility to $($exp.show_extensions)"
        Set-ItemProperty -Path $explorerAdvanced -Name "HideFileExt" -Value $extValue
    }

    # Show hidden files
    if ($null -ne $exp.show_hidden) {
        $hidValue = if ($exp.show_hidden) { 1 } else { 0 }
        Write-AnniLog -Level INFO -Message "Setting hidden files visibility to $($exp.show_hidden)"
        Set-ItemProperty -Path $explorerAdvanced -Name "Hidden" -Value $hidValue
    }

    # Show super hidden files (system files)
    if ($null -ne $exp.show_super_hidden) {
        $shValue = if ($exp.show_super_hidden) { 1 } else { 0 }
        Write-AnniLog -Level INFO -Message "Setting super hidden files visibility to $($exp.show_super_hidden)"
        Set-ItemProperty -Path $explorerAdvanced -Name "ShowSuperHidden" -Value $shValue
    }

    # Desktop icons
    if ($null -ne $exp.desktop_icons) {
        $diValue = if ($exp.desktop_icons) { 0 } else { 1 }
        Write-AnniLog -Level INFO -Message "Setting desktop icons to $($exp.desktop_icons)"
        Set-ItemProperty -Path $explorerAdvanced -Name "HideIcons" -Value $diValue
    }
}

# ------- DEVELOPER ------- #
if ($null -ne $Settings.developer) {
    $dev = $Settings.developer

    # Dev mode
    if ($null -ne $dev.dev_mode -and $dev.dev_mode) {
        Write-AnniLog -Level INFO -Message "Enabling Developer Mode"
        reg add "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock" /t REG_DWORD /f /v "AllowDevelopmentWithoutDevLicense" /d "1" 2>&1 | Out-Null
    }

    # End task button
    if ($null -ne $dev.end_task_button -and $dev.end_task_button) {
        Write-AnniLog -Level INFO -Message "Enabling End Task button"
        reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced\TaskbarDeveloperSettings" /v TaskbarEndTask /t REG_DWORD /d 1 /f 2>&1 | Out-Null
    }
}

# ------- COMMENTED-OUT SECTIONS (manual management) ------- #

# Set execution policy to unrestricted, to run ps1 files for current user.
#Set-ExecutionPolicy -ExecutionPolicy Unrestricted -Scope CurrentUser

# 24h clock
#Set-ItemProperty -Path "HKCU:\Control Panel\International" -Name "sShortTime" -Value "HH:mm"
#Set-ItemProperty -Path "HKCU:\Control Panel\International" -Name "sTimeFormat" -Value "HH:mm:ss"

# Set Language to en-US
#$userLanguage = $lang[0]
#$userLanguage.InputMethodTips.Add("0409:00000409")
#$userLanguage.InputMethodTips.Add("0409:00000807")
#Set-WinUserLanguageList -LanguageList $lang -Force

# Windows Sandbox
#Enable-WindowsOptionalFeature -FeatureName "Containers-DisposableClientVM" -All -Online

# Install SSH
# Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0

# Start SSH
# Start-Service -Name "sshd"

# Auto Start SSH
# Set-Service -Name "sshd" -StartupType Automatic

# ------- RESTART EXPLORER ------- #
Write-AnniLog -Level INFO -Message "Restarting Explorer to apply changes..."
Stop-Process -ProcessName explorer -Force

Write-AnniLog -Level SUCCESS -Message "All Windows settings applied."
Close-AnniLog
Pause

# ------- END SETTINGS CONFIGURATION SCRIPT ------- #