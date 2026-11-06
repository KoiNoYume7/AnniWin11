# ============================================================================
#  State.ps1  --  Resume/idempotency state for AnniWin11 v2
#  Tracks which phases have completed so a run can survive reboots and be
#  safely re-invoked. Compatible with PS 5.1 and pwsh 7+.
# ============================================================================

function Get-SetupState {
    <#
        Loads state.json, or returns a fresh state object if none exists.
        The state is a PSCustomObject; pass it to Save-SetupState to persist.
    #>
    param([Parameter(Mandatory)][string]$Path)

    if (Test-Path -LiteralPath $Path) {
        try {
            $raw = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
            $obj = $raw | ConvertFrom-Json
            # Normalise: ensure completedPhases is always an array we can .Contains().
            if ($null -eq $obj.completedPhases) {
                $obj | Add-Member -NotePropertyName completedPhases -NotePropertyValue @() -Force
            }
            return $obj
        } catch {
            Write-Log -Level WARN -Message "state file unreadable, starting fresh: $($_.Exception.Message)"
        }
    }

    return [PSCustomObject]@{
        runId           = [guid]::NewGuid().ToString()
        startedAt       = (Get-Date).ToString('o')
        completedPhases = @()
        data            = [PSCustomObject]@{}
    }
}

function Save-SetupState {
    param(
        [Parameter(Mandatory)]$State,
        [Parameter(Mandatory)][string]$Path
    )
    $dir = Split-Path -Parent $Path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    $State | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Test-PhaseComplete {
    param(
        [Parameter(Mandatory)]$State,
        [Parameter(Mandatory)][string]$Name
    )
    return ($State.completedPhases -contains $Name)
}

function Set-PhaseComplete {
    <#
        Marks a phase complete and immediately persists, so a crash/reboot right
        after a phase does not lose the fact that it finished.
    #>
    param(
        [Parameter(Mandatory)]$State,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Path
    )
    if ($State.completedPhases -notcontains $Name) {
        $State.completedPhases = @($State.completedPhases) + $Name
    }
    Save-SetupState -State $State -Path $Path
}

function Clear-SetupState {
    param([Parameter(Mandatory)][string]$Path)
    if (Test-Path -LiteralPath $Path) {
        Remove-Item -LiteralPath $Path -Force
    }
}
