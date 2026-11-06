# ============================================================================
#  Elevation.ps1  --  Admin check + reboot-resume registration
#  A scheduled task (logon trigger, highest privileges) relaunches the
#  orchestrator after a reboot so multi-phase setup survives restarts.
# ============================================================================

$script:AnniResumeTaskName = 'AnniWin11-Resume'

function Test-Admin {
    <# Returns $true if the current process is elevated. #>
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($id)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Register-ResumeTask {
    <#
        Registers a scheduled task that relaunches the orchestrator at next
        logon, elevated, so setup continues after a reboot. Idempotent:
        re-registering replaces the existing task.
        -OrchestratorPath  full path to Invoke-Setup.ps1
        -PwshPath          full path to pwsh.exe (7+)
    #>
    param(
        [Parameter(Mandatory)][string]$OrchestratorPath,
        [string]$PwshPath = 'pwsh.exe'
    )

    $argLine = '-NoProfile -ExecutionPolicy Bypass -File "{0}" -Resume' -f $OrchestratorPath
    $action  = New-ScheduledTaskAction -Execute $PwshPath -Argument $argLine
    $trigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
    $principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Highest
    $settings  = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable

    try {
        Register-ScheduledTask -TaskName $script:AnniResumeTaskName `
            -Action $action -Trigger $trigger -Principal $principal -Settings $settings `
            -Force -ErrorAction Stop | Out-Null
        Write-Log -Level OK -Message "Resume task registered ($script:AnniResumeTaskName)"
        return $true
    } catch {
        Write-Log -Level WARN -Message "Could not register resume task: $($_.Exception.Message)"
        return $false
    }
}

function Unregister-ResumeTask {
    <# Removes the resume task. Called on clean completion. #>
    try {
        $existing = Get-ScheduledTask -TaskName $script:AnniResumeTaskName -ErrorAction SilentlyContinue
        if ($existing) {
            Unregister-ScheduledTask -TaskName $script:AnniResumeTaskName -Confirm:$false -ErrorAction Stop
            Write-Log -Level OK -Message "Resume task removed"
        }
    } catch {
        Write-Log -Level WARN -Message "Could not remove resume task: $($_.Exception.Message)"
    }
}

function Request-Reboot {
    <#
        Registers resume, informs the user, and reboots after a short delay.
        Set the phase complete BEFORE calling this so resume skips it.
    #>
    param(
        [Parameter(Mandatory)][string]$OrchestratorPath,
        [string]$PwshPath = 'pwsh.exe',
        [int]$DelaySeconds = 10,
        [string]$Reason = 'A reboot is required to continue setup.'
    )
    Register-ResumeTask -OrchestratorPath $OrchestratorPath -PwshPath $PwshPath | Out-Null
    Write-Log -Level WARN -Message $Reason
    Write-Log -Level WARN -Message "Rebooting in $DelaySeconds seconds. Setup resumes automatically after logon."
    Start-Sleep -Seconds $DelaySeconds
    Restart-Computer -Force
}
