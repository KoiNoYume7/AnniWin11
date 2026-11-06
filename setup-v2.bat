@echo off
title AnniWin11 Setup (v2 orchestrator)
echo.
echo  AnniWin11 v2 -- Declarative Windows 11 Setup
echo  ==============================================
echo.

:: ------- UAC ELEVATION ------- ::
:: Check if running as admin. If not, relaunch elevated (forwarding args).
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo Requesting administrator privileges...
    powershell -Command "Start-Process -FilePath '%~f0' -ArgumentList '%*' -Verb RunAs"
    exit /b
)

echo Running as Administrator.
echo.

:: ------- LAUNCH V2 BOOTSTRAP (Windows PowerShell 5.1) ------- ::
:: bootstrap.ps1 verifies winget + installs/locates PowerShell 7, then hands
:: off to Invoke-Setup.ps1. Forward any args, e.g.:  setup-v2.bat -DryRun
echo Launching v2 bootstrap...
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0bootstrap.ps1" %*

pause
