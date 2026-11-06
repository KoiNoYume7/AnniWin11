#Requires -Version 7.0
# ============================================================================
#  Invoke-Setup.ps1  --  AnniWin11 v2 orchestrator (runs under pwsh 7)
#
#  Loads the declarative manifests, shows a preflight risk table, gets one
#  confirmation, then runs the enabled phases in order. Tracks completion in
#  state.json so it resumes after a reboot and is safe to re-run.
#
#  Phase-module contract (modules/Phase.<Name>.ps1):
#    Get-<Name>Plan  -Manifest <obj>            -> @{ Title; Items[]; Risk }
#    Invoke-<Name>Phase -Manifest <obj> [-DryRun] -> throws on hard failure
#
#  Normally launched by bootstrap.ps1; can be run directly for testing:
#    pwsh -File Invoke-Setup.ps1 -DryRun
# ============================================================================
[CmdletBinding()]
param(
    [switch]$DryRun,
    [switch]$Resume,
    [switch]$Yes
)

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot

# --- Load libraries + phase modules ----------------------------------------
. (Join-Path $root 'lib\Log.ps1')
. (Join-Path $root 'lib\State.ps1')
. (Join-Path $root 'lib\Preflight.ps1')
. (Join-Path $root 'lib\Elevation.ps1')
. (Join-Path $root 'lib\Winget.ps1')
Get-ChildItem (Join-Path $root 'modules') -Filter 'Phase.*.ps1' -ErrorAction SilentlyContinue |
    ForEach-Object { . $_.FullName }

# --- Setup manifest + logging ----------------------------------------------
$setupManifestPath = Join-Path $root 'profile\setup.psd1'
$setup = Import-PowerShellDataFile -Path $setupManifestPath

Initialize-Log -LogDir (Join-Path $root 'logs') -MinLevel $setup.MinLogLevel -Transcript
Write-Section ('AnniWin11 v2 :: orchestrator' + $(if ($DryRun) { '  [DRY RUN]' } else { '' }))

$statePath = Join-Path $root 'state.json'
$state = Get-SetupState -Path $statePath
if ($Resume) { Write-Log -Level INFO -Message "Resuming run $($state.runId)" }

# --- Phase registry: name -> manifest file + plan/run functions ------------
$registry = [ordered]@{
    Apps        = @{ Manifest = 'profile\apps.psd1';     Plan = 'Get-AppsPlan';        Run = 'Invoke-AppsPhase' }
    WinSettings = @{ Manifest = 'profile\settings.psd1'; Plan = 'Get-WinSettingsPlan'; Run = 'Invoke-WinSettingsPhase' }
    Debloat     = @{ Manifest = 'profile\debloat.psd1';  Plan = 'Get-DebloatPlan';     Run = 'Invoke-DebloatPhase' }
    DevEnv      = @{ Manifest = 'profile\devenv.psd1';   Plan = 'Get-DevEnvPlan';      Run = 'Invoke-DevEnvPhase' }
    Accounts    = @{ Manifest = 'profile\accounts.psd1'; Plan = 'Get-AccountsPlan';    Run = 'Invoke-AccountsPhase' }
    Backup      = @{ Manifest = 'profile\setup.psd1';    Plan = 'Get-BackupPlan';      Run = 'Invoke-BackupPhase' }
}

# --- Which phases are enabled + not yet complete ---------------------------
$enabled = @($setup.PhaseOrder | Where-Object { $setup.Phases[$_] -eq $true -and $registry.Contains($_) })
if ($enabled.Count -eq 0) {
    Write-Log -Level WARN -Message 'No phases enabled in setup.psd1. Nothing to do.'
    Stop-Log; exit 0
}

# Cache loaded manifests so we don't parse twice (plan + run).
$manifests = @{}
foreach ($p in $enabled) {
    $mpath = Join-Path $root $registry[$p].Manifest
    $manifests[$p] = Import-PowerShellDataFile -Path $mpath
}

try {
    # --- Preflight: build the plan from each enabled+pending phase ----------
    Write-Section 'Preflight :: what this run will do'
    Write-Host ''
    Write-Host '  Machine : ' -NoNewline; Write-Host $env:COMPUTERNAME -ForegroundColor White
    Write-Host '  User    : ' -NoNewline; Write-Host $env:USERNAME -ForegroundColor White
    Write-Host '  Phases  : ' -NoNewline; Write-Host ($enabled -join ', ') -ForegroundColor White

    foreach ($p in $enabled) {
        if (Test-PhaseComplete -State $state -Name $p) {
            Show-PlanSection -Title "$p  (already done -- will skip)" -Items @()
            continue
        }
        $planFn = $registry[$p].Plan
        if (Get-Command $planFn -ErrorAction SilentlyContinue) {
            $plan = & $planFn -Manifest $manifests[$p]
            Show-PlanSection -Title $plan.Title -Items $plan.Items -Risk:([bool]$plan.Risk)
        } else {
            Show-PlanSection -Title "$p" -Items @('(no plan preview available)')
        }
    }

    # --- Confirmation gate -------------------------------------------------
    $auto = $DryRun -or $Yes -or $Resume
    if (-not (Confirm-Preflight -AutoConfirm:$auto)) {
        Write-Log -Level WARN -Message 'User declined. No changes made.'
        Stop-Log; exit 0
    }

    if ($DryRun) {
        Write-Section 'DRY RUN :: executing phases in preview mode (no changes)'
    } else {
        Write-Section 'Executing phases'
    }

    # --- Execute -----------------------------------------------------------
    foreach ($p in $enabled) {
        if (Test-PhaseComplete -State $state -Name $p) {
            Write-Log -Level INFO -Message "Skipping $p (already complete)."
            continue
        }

        Write-Section "Phase :: $p"
        $runFn = $registry[$p].Run
        if (-not (Get-Command $runFn -ErrorAction SilentlyContinue)) {
            Write-Log -Level WARN -Message "$runFn not found; skipping $p."
            continue
        }

        & $runFn -Manifest $manifests[$p] -DryRun:$DryRun

        # Only record progress on a real run so dry-runs never pollute state.
        if (-not $DryRun) {
            Set-PhaseComplete -State $state -Name $p -Path $statePath
            Write-Log -Level OK -Message "$p complete."
        }
    }

    # --- Clean finish ------------------------------------------------------
    if (-not $DryRun) {
        Unregister-ResumeTask
        Clear-SetupState -Path $statePath
    }
    Write-Section 'Done'
    Write-Log -Level OK -Message 'AnniWin11 setup finished.'
    Write-Host ''
    Write-Host '  Manual follow-ups the script cannot do for you:' -ForegroundColor Cyan
    Write-Host '    - Sign into your Microsoft/personal account where you want it.' -ForegroundColor Gray
    Write-Host '    - On the school account: sign into Teams/M365 (your credentials).' -ForegroundColor Gray
    Write-Host '    - Add the printed SSH public key to GitHub if you generated one.' -ForegroundColor Gray
    Stop-Log
    exit 0
}
catch {
    if ($_.Exception.Message -eq 'AnniAbort') {
        Write-Log -Level WARN -Message 'Aborted by user. Progress saved; re-run setup.bat to continue.'
        Stop-Log; exit 2
    }
    Write-Log -Level ERROR -Message "Unhandled error: $($_.Exception.Message)"
    Write-Log -Level ERROR -Message ($_.ScriptStackTrace)
    Write-Log -Level WARN  -Message 'Progress saved; fix the issue and re-run setup.bat to continue.'
    Stop-Log
    exit 1
}
