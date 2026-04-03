# ------- BOOTSTRAP SCRIPT ------- #

# Ensures the calling script is running under PowerShell 7+.
# If not, attempts to install PS7 via winget and relaunches.
# NOTE: This script must remain compatible with PowerShell 5.1 (Windows default)
# so it CANNOT use AnniLog or other PS7-only modules.

param(
    [string]$ScriptToRun = $MyInvocation.InvocationName
)

function Install-Pwsh {
    Write-Host "PowerShell 7+ not found. Installing from Winget..." -ForegroundColor Yellow
    try {
        winget install --id Microsoft.Powershell --source winget --accept-source-agreements --accept-package-agreements
    } catch {
        Write-Warning "Automatic install failed. Please install PowerShell 7+ manually from https://aka.ms/powershell"
        exit 1
    }
}

function Restart-WithPwsh {
    $pwshCommand = Get-Command pwsh.exe -ErrorAction SilentlyContinue
    if ($pwshCommand) {
        $pwshPath = $pwshCommand.Source
    } else {
        $pwshPath = $null
    }

    if (-not $pwshPath) {
        Write-Host "PowerShell 7+ not found. Do you want to install it now? (Y/N)" -ForegroundColor Yellow
        $answer = Read-Host
        if ($answer -match '^[Yy]') {
            Install-Pwsh
            Write-Host "Waiting for PowerShell 7 to become available..." -ForegroundColor Cyan

            $retries = 6
            $found = $false
            for ($i = 0; $i -lt $retries; $i++) {
                Start-Sleep -Seconds 5
                $pwshCommand = Get-Command pwsh.exe -ErrorAction SilentlyContinue
                if ($pwshCommand) {
                    $pwshPath = $pwshCommand.Source
                    $found = $true
                    break
                }
                Write-Host "  Still waiting... ($($i + 1)/$retries)" -ForegroundColor Yellow
            }

            if (-not $found) {
                Write-Warning "PowerShell 7+ still not found after install. Aborting."
                exit 1
            }
        } else {
            Write-Warning "PowerShell 7+ required. Exiting."
            exit 1
        }
    }

    if (-not $env:RUNNING_IN_PWSH7) {
        $env:RUNNING_IN_PWSH7 = '1'
        Write-Host "Restarting script with PowerShell 7+..." -ForegroundColor Cyan
        & $pwshPath -NoProfile -File $ScriptToRun @args
        exit
    }
}

if ($PSVersionTable.PSVersion.Major -lt 7) {
    Restart-WithPwsh
}

# ------- END BOOTSTRAP SCRIPT ------- #