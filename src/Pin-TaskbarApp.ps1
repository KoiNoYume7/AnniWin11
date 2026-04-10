# ------- PIN TASKBAR APPS SCRIPT ------- #

# Pins apps to the taskbar via LayoutModification.xml.
# Reads taskbar_apps from config/settings.json when run standalone.
# Requires -Version 7.0

# ------- DEPENDENCIES ------- #
. "$PSScriptRoot\..\lib\Config.ps1"
Import-Module "$PSScriptRoot\..\lib\AnniLog.psd1" -Force

# ------- FUNCTION ------- #

function Pin-TaskbarApp {
    <#
    .SYNOPSIS
    Pins apps to the taskbar by generating and applying a LayoutModification.xml.

    .DESCRIPTION
    Creates a custom LayoutModification.xml with the given apps and updates the registry for current user.
    Requires Explorer restart to take effect.

    .PARAMETER AppPaths
    Paths to executables or shortcuts to pin.

    .PARAMETER Reset
    If set, REPLACES existing taskbar pins, else APPENDS (default behaviour may vary).

    .EXAMPLE
    Pin-TaskbarApp -AppPaths "C:\Windows\System32\notepad.exe", "C:\Windows\System32\calc.exe"
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$AppPaths,

        [switch]$Reset
    )

    # --- Paths and setup --- #
    $layoutXmlDir = Join-Path $env:LOCALAPPDATA "Microsoft\Windows\Shell"
    $layoutXmlPath = Join-Path $layoutXmlDir "LayoutModification.xml"

    if (-not (Test-Path $layoutXmlDir)) {
        New-Item -Path $layoutXmlDir -ItemType Directory -Force | Out-Null
    }

    # --- Prepare XML header with dynamic PinListPlacement --- #
    $pinPlacement = if ($Reset) { "Replace" } else { "Append" }

    $xmlContent = @"
<?xml version="1.0" encoding="utf-8"?>
<LayoutModificationTemplate
    xmlns="http://schemas.microsoft.com/Start/2014/LayoutModification"
    xmlns:defaultlayout="http://schemas.microsoft.com/Start/2014/FullDefaultLayout"
    xmlns:start="http://schemas.microsoft.com/Start/2014/StartLayout"
    xmlns:taskbar="http://schemas.microsoft.com/Start/2014/TaskbarLayout"
    Version="1">
    <CustomTaskbarLayoutCollection PinListPlacement="$pinPlacement">
        <defaultlayout:TaskbarLayout>
            <taskbar:TaskbarPinList>
"@

    # --- Add valid apps --- #
    foreach ($path in $AppPaths) {
        if (Test-Path $path) {
            $fullPath = (Resolve-Path $path).Path
            $xmlContent += "                <taskbar:DesktopApp DesktopApplicationLinkPath=`"$fullPath`" />`n"
            Write-AnniLog -Level INFO -Message "Adding to layout: $fullPath"
        } else {
            Write-AnniLog -Level WARNING -Message "File not found, skipping: $path"
        }
    }

    # --- Close XML --- #
    $xmlContent += @"
            </taskbar:TaskbarPinList>
        </defaultlayout:TaskbarLayout>
    </CustomTaskbarLayoutCollection>
</LayoutModificationTemplate>
"@

    # --- Write XML file --- #
    try {
        $xmlContent | Out-File -FilePath $layoutXmlPath -Encoding UTF8 -Force
        Write-AnniLog -Level SUCCESS -Message "Layout XML saved at: $layoutXmlPath"
    } catch {
        Write-AnniLog -Level ERROR -Message "Failed to write XML file: $_"
        return
    }

    # --- Update registry --- #
    $regPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer"

    try {
        Set-ItemProperty -Path $regPath -Name "StartLayoutFile" -Value $layoutXmlPath -Type String -Force
        Set-ItemProperty -Path $regPath -Name "LockedStartLayout" -Value 0 -Type DWord -Force
        Write-AnniLog -Level SUCCESS -Message "Registry updated to use the new layout."
    } catch {
        Write-AnniLog -Level ERROR -Message "Failed to update registry: $_"
        return
    }

    Write-AnniLog -Level WARNING -Message "Restart Explorer for changes to take effect."
}

# ------- STANDALONE EXECUTION ------- #
# When run directly (not dot-sourced), reads taskbar_apps from config/settings.json

if ($MyInvocation.InvocationName -ne '.') {
    $LogFile = Get-LogPath -FileName "taskbar.log"
    $ProjectConfig = Get-ProjectConfig
    Initialize-AnniLog -LogFilePath $LogFile -LogLevel $ProjectConfig.log_level

    $SettingsConfig = Get-ConfigPath -FileName "settings.json"
    if (-not (Test-Path $SettingsConfig)) {
        Write-AnniLog -Level ERROR -Message "settings.json not found at $SettingsConfig"
        Close-AnniLog
        throw "settings.json missing"
    }

    $Settings = Read-JsonFile -Path $SettingsConfig

    if (-not $Settings.taskbar_apps -or $Settings.taskbar_apps.Count -eq 0) {
        Write-AnniLog -Level WARNING -Message "No taskbar_apps defined in settings.json. Nothing to pin."
        Close-AnniLog
        exit 0
    }

    Write-AnniLog -Level INFO -Message "Pinning $($Settings.taskbar_apps.Count) app(s) to taskbar..."
    Pin-TaskbarApp -AppPaths $Settings.taskbar_apps -Reset

    Close-AnniLog
    Pause
}

# ------- END PIN TASKBAR APPS SCRIPT ------- #
