# ------- INSTALL APPS SCRIPT ------- #

# Install script for Apps and Tools
# Requires -Version 7.0

# ------- DEPENDENCIES ------- #
. "$PSScriptRoot\..\lib\Config.ps1"
Import-Module "$PSScriptRoot\..\lib\AnniLog.psd1" -Force

# ------- PATHS ------- #
$ProjectRoot = Get-ProjectRoot
$AppsConfig  = Get-ConfigPath -FileName "apps.json"
$Installers  = Join-Path $ProjectRoot "config" "installers"
$LogFile     = Get-LogPath -FileName "installation.log"

# ------- INITIALISE LOGGING ------- #
$ProjectConfig = Get-ProjectConfig
Initialize-AnniLog -LogFilePath $LogFile -LogLevel $ProjectConfig.log_level -EnableStopwatch

# ------- READ APP LIST ------- #
if (-not (Test-Path $AppsConfig)) {
    Write-AnniLog -Level ERROR -Message "apps.json not found at $AppsConfig"
    Write-AnniLog -Level ERROR -Message "Run GenerateConfigs.ps1 or copy apps_example.jsonc to config/apps.json"
    Close-AnniLog
    throw "apps.json missing"
}

try {
    $AppsData = Read-JsonFile -Path $AppsConfig
}
catch {
    Write-AnniLog -Level ERROR -Message "Failed to parse apps.json: $($_.Exception.Message)"
    Close-AnniLog
    exit 1
}

# ------- INSTALL FUNCTIONS ------- #

function WingetInstall {
    param([string] $Id, [string] $Name)

    if (-not $Id) {
        Write-AnniLog -Level WARNING -Message "Missing winget id for $Name"
        return $false
    }

    Write-AnniLog -Level INFO -Message "Invoking winget for id: $Id"

    try {
        $process = Start-Process -FilePath "winget" `
            -ArgumentList "install", "--id", $Id, "--source", "winget", "-e", "--accept-package-agreements", "--accept-source-agreements", "-h" `
            -NoNewWindow -Wait -PassThru

        $exitCode = $process.ExitCode

        if ($exitCode -eq 0) {
            Write-AnniLog -Level SUCCESS -Message "Installed $Name successfully (exit $exitCode)"
            return $true
        } elseif ($exitCode -eq 1602) {
            Write-AnniLog -Level WARNING -Message "Installation of $Name skipped by user."
            return $false
        } else {
            Write-AnniLog -Level ERROR -Message "winget failed for $Id (exit $exitCode)"
            return $false
        }
    } catch {
        Write-AnniLog -Level ERROR -Message "Exception running winget for ${Id}: $_"
        return $false
    }
}

function Install-App {
    param($App, [int]$Index, [int]$Total)

    $name   = $App.name
    $source = $App.source

    if (-not $name) {
        Write-AnniLog -Level WARNING -Message "Unnamed app entry skipped"
        return
    }

    Write-AnniLog -Level INFO -Message "[$Index/$Total] Installing '$name' (source: $source)"

    switch ($source) {
        'winget' {
            $id = $App.id
            if (-not $id) {
                Write-AnniLog -Level WARNING -Message "'$name' skipped: missing winget id"
                return
            }
            WingetInstall -Id $id -Name $name | Out-Null
        }

        'internet' {
            $url = $App.url
            if (-not $url) {
                Write-AnniLog -Level WARNING -Message "'$name' skipped: missing download URL"
                return
            }
            $fileName = Split-Path -Leaf $url
            if (-not (Test-Path $Installers)) { New-Item -ItemType Directory -Path $Installers | Out-Null }
            $downloadPath = Join-Path $Installers $fileName
            try {
                Write-AnniLog -Level INFO -Message "Downloading '$name' from $url"
                Invoke-WebRequest -Uri $url -OutFile $downloadPath -UseBasicParsing -ErrorAction Stop
                Write-AnniLog -Level INFO -Message "Running installer for '$name': $downloadPath"
                $proc = Start-Process -FilePath $downloadPath -Wait -PassThru -ErrorAction Stop
                if ($proc.ExitCode -eq 0) {
                    Write-AnniLog -Level SUCCESS -Message "Installer finished for '$name' (exit 0)"
                } else {
                    Write-AnniLog -Level WARNING -Message "Installer for '$name' returned exit code $($proc.ExitCode)"
                }
            } catch {
                Write-AnniLog -Level ERROR -Message "Failed to download/run '$name': $_"
            }
        }

        'local' {
            $rel = $App.path
            if (-not $rel) {
                Write-AnniLog -Level WARNING -Message "'$name' skipped: missing local path"
                return
            }
            $localPath = Join-Path $Installers $rel
            if (-not (Test-Path $localPath)) {
                Write-AnniLog -Level WARNING -Message "'$name' skipped: local installer not found at $localPath"
                return
            }
            try {
                Write-AnniLog -Level INFO -Message "Running local installer for '$name': $localPath"
                $proc = Start-Process -FilePath $localPath -Wait -PassThru -ErrorAction Stop
                if ($proc.ExitCode -eq 0) {
                    Write-AnniLog -Level SUCCESS -Message "Local installer finished for '$name' (exit 0)"
                } else {
                    Write-AnniLog -Level WARNING -Message "Local installer for '$name' returned exit code $($proc.ExitCode)"
                }
            } catch {
                Write-AnniLog -Level ERROR -Message "Failed to run local installer for '$name': $_"
            }
        }

        'terminal' {
            $cmd = $App.command
            if (-not $cmd) {
                Write-AnniLog -Level WARNING -Message "'$name' skipped: missing terminal command"
                return
            }
            Write-AnniLog -Level INFO -Message "Running terminal command for '$name': $cmd"

            try {
                $process = Start-Process -FilePath "pwsh" `
                                         -ArgumentList "-NoProfile", "-Command", $cmd `
                                         -NoNewWindow -Wait -PassThru -ErrorAction Stop

                if ($process.ExitCode -eq 0) {
                    Write-AnniLog -Level SUCCESS -Message "Terminal command finished for '$name' (exit 0)"
                } else {
                    Write-AnniLog -Level WARNING -Message "Terminal command for '$name' returned exit code $($process.ExitCode)"
                }
            } catch {
                Write-AnniLog -Level ERROR -Message "Failed to run terminal command for '$name': $_"
            }
        }

        default {
            Write-AnniLog -Level ERROR -Message "'$name' has unknown source: $source"
        }
    }
}

# ------- INSTALL SECTIONS ------- #

Write-AnniLog -Level INFO -Message "------- Installing MainApps -------"
$totalMain = $AppsData.MainApps.Count
for ($i = 0; $i -lt $totalMain; $i++) {
    Install-App $AppsData.MainApps[$i] ($i + 1) $totalMain
}

Write-AnniLog -Level INFO -Message "------- Installing Tools -------"
$totalTools = $AppsData.Tools.Count
for ($i = 0; $i -lt $totalTools; $i++) {
    Install-App $AppsData.Tools[$i] ($i + 1) $totalTools
}

Write-AnniLog -Level INFO -Message "------- Prompting for AdditionalApps -------"
for ($i = 0; $i -lt $AppsData.AdditionalApps.Count; $i++) {
    $a = $AppsData.AdditionalApps[$i]
    Write-Host "[$i] $($a.name)"
}
$selection = Read-Host "Enter comma-separated indexes to install (or press Enter to skip)"
if ($selection) {
    $indexes = $selection -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ -match '^\d+$' } | ForEach-Object { [int]$_ }
    foreach ($idx in $indexes) {
        if ($idx -ge 0 -and $idx -lt $AppsData.AdditionalApps.Count) {
            Install-App $AppsData.AdditionalApps[$idx] ($idx + 1) $AppsData.AdditionalApps.Count
        } else {
            Write-AnniLog -Level WARNING -Message "Invalid AdditionalApps index: $idx"
        }
    }
} else {
    Write-AnniLog -Level INFO -Message "No AdditionalApps selected"
}

# ------- FINISH ------- #

Write-AnniLog -Level SUCCESS -Message "All requested tasks completed. See log: $LogFile"
Close-AnniLog
Pause

# ------- END INSTALL APPS SCRIPT ------- #