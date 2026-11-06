#Requires -Version 5.1
# ============================================================================
#  bootstrap.ps1  --  AnniWin11 v2 bootstrap (runs under Windows PowerShell 5.1)
#
#  Responsibilities:
#    1. Confirm elevation.
#    2. Ensure winget is available (App Installer).
#    3. Ensure PowerShell 7 is installed (via winget) and locate pwsh.exe.
#    4. Relaunch Invoke-Setup.ps1 under pwsh 7, forwarding switches.
#
#  Keep this file 5.1-compatible: no ternary, no ??, no pwsh-only syntax.
# ============================================================================
[CmdletBinding()]
param(
    [switch]$DryRun,
    [switch]$Resume,
    [switch]$Yes
)

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot

. (Join-Path $root 'lib\Log.ps1')
. (Join-Path $root 'lib\Elevation.ps1')

Initialize-Log -LogDir (Join-Path $root 'logs') -MinLevel 'INFO' -Transcript
Write-Section 'AnniWin11 v2 :: bootstrap'

# --- 1. Elevation ----------------------------------------------------------
if (-not (Test-Admin)) {
    Write-Log -Level ERROR -Message 'Not running as Administrator. Re-launch via setup.bat.'
    Stop-Log
    exit 1
}
Write-Log -Level OK -Message 'Running elevated.'

# --- 2. winget -------------------------------------------------------------
$winget = Get-Command winget.exe -ErrorAction SilentlyContinue
if (-not $winget) {
    Write-Log -Level ERROR -Message 'winget (App Installer) not found on this system.'
    Write-Log -Level WARN  -Message 'Install "App Installer" from https://aka.ms/getwinget, then re-run setup.bat.'
    Stop-Log
    exit 1
}
Write-Log -Level OK -Message "winget present: $((& winget --version) 2>$null)"

# --- 3. PowerShell 7 -------------------------------------------------------
function Find-Pwsh {
    $cmd = Get-Command pwsh.exe -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $candidates = @(
        (Join-Path $env:ProgramFiles 'PowerShell\7\pwsh.exe'),
        (Join-Path ${env:ProgramFiles(x86)} 'PowerShell\7\pwsh.exe'),
        # winget may install the MSIX package instead of the MSI; its shim lives
        # here and is not resolvable via PATH in the same session as the install.
        (Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\pwsh.exe')
    )
    foreach ($c in $candidates) {
        if ($c -and (Test-Path -LiteralPath $c)) { return $c }
    }
    return $null
}

$pwshPath = Find-Pwsh
if (-not $pwshPath) {
    Write-Log -Level STEP -Message 'PowerShell 7 not found. Installing via winget...'
    if ($DryRun) {
        Write-Log -Level WARN -Message '[dry-run] Would run: winget install Microsoft.PowerShell'
    } else {
        & winget install --id Microsoft.PowerShell --source winget --silent `
            --accept-source-agreements --accept-package-agreements
        $pwshPath = Find-Pwsh
    }
}

if (-not $pwshPath -and -not $DryRun) {
    Write-Log -Level ERROR -Message 'PowerShell 7 install failed or pwsh.exe not found.'
    Write-Log -Level WARN  -Message 'Install manually from https://aka.ms/powershell then re-run setup.bat.'
    Stop-Log
    exit 1
}
if ($pwshPath) { Write-Log -Level OK -Message "PowerShell 7: $pwshPath" }

# --- 4. Relaunch orchestrator under pwsh 7 ---------------------------------
$orchestrator = Join-Path $root 'Invoke-Setup.ps1'
if (-not (Test-Path -LiteralPath $orchestrator)) {
    Write-Log -Level ERROR -Message "Orchestrator not found: $orchestrator"
    Stop-Log
    exit 1
}

$fwd = @('-NoProfile','-ExecutionPolicy','Bypass','-File', $orchestrator)
if ($DryRun) { $fwd += '-DryRun' }
if ($Resume) { $fwd += '-Resume' }
if ($Yes)    { $fwd += '-Yes' }

Write-Section 'Handing off to orchestrator (pwsh 7)'
Stop-Log   # child process starts its own transcript

if ($DryRun -and -not $pwshPath) {
    # dry-run before PS7 exists: run orchestrator under 5.1 just to preview parsing
    Write-Host '[dry-run] PowerShell 7 not installed; previewing under 5.1.' -ForegroundColor Yellow
    & powershell.exe @fwd
    exit $LASTEXITCODE
}

& $pwshPath @fwd
exit $LASTEXITCODE
