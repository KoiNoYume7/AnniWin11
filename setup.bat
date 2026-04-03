@echo off
title AnniWin11 Setup
echo.
echo  AnniWin11 -- Windows 11 Post-Install Automation
echo  ================================================
echo.

:: ------- UAC ELEVATION ------- ::
:: Check if running as admin. If not, relaunch elevated.
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo Requesting administrator privileges...
    powershell -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

echo Running as Administrator.
echo.

:: ------- CHECK FOR POWERSHELL 7 ------- ::
where pwsh >nul 2>&1
if %errorlevel% neq 0 (
    echo PowerShell 7+ not found. Attempting to install via winget...
    winget install --id Microsoft.Powershell --source winget --accept-source-agreements --accept-package-agreements
    if %errorlevel% neq 0 (
        echo.
        echo ERROR: Failed to install PowerShell 7.
        echo Please install it manually from https://aka.ms/powershell
        pause
        exit /b 1
    )
    echo.
    echo PowerShell 7 installed successfully.
    echo Please close this window and re-run setup.bat to continue.
    echo.
    pause
    exit /b 0
)

:: ------- LAUNCH MAIN MENU ------- ::
echo Launching AnniWin11 main menu...
pwsh -NoProfile -ExecutionPolicy Bypass -File "%~dp0src\Main.ps1"

pause
