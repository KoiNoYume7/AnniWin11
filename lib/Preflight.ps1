# ============================================================================
#  Preflight.ps1  --  Risk disclosure + confirmation gate for AnniWin11 v2
#  Nothing destructive should run before Confirm-Preflight returns $true.
# ============================================================================

function Read-YesNo {
    <#
        Prompts for a yes/no answer. Returns [bool]. Empty input uses -Default.
        Recognises an explicit 'abort'/'quit' as a hard exit.
    #>
    param(
        [Parameter(Mandatory)][string]$Prompt,
        [bool]$Default = $false
    )
    $hint = if ($Default) { '[Y/n]' } else { '[y/N]' }
    while ($true) {
        $ans = (Read-Host "$Prompt $hint").Trim().ToLower()
        switch ($ans) {
            ''         { return $Default }
            'y'        { return $true }
            'yes'      { return $true }
            'n'        { return $false }
            'no'       { return $false }
            'q'        { throw 'AnniAbort' }
            'quit'     { throw 'AnniAbort' }
            'abort'    { throw 'AnniAbort' }
            default    { Write-Host "  Please answer y or n (or 'abort' to quit)." -ForegroundColor DarkGray }
        }
    }
}

function Show-PlanSection {
    <#
        Renders one titled block of the plan/risk table.
        -Items is an array of strings; -Risk marks the block as destructive.
    #>
    param(
        [Parameter(Mandatory)][string]$Title,
        [string[]]$Items = @(),
        [switch]$Risk
    )
    $color = if ($Risk) { 'Yellow' } else { 'White' }
    Write-Host ''
    Write-Host ("  {0}" -f $Title) -ForegroundColor $color
    if (-not $Items -or $Items.Count -eq 0) {
        Write-Host '    (nothing)' -ForegroundColor DarkGray
        return
    }
    foreach ($it in $Items) {
        $bullet = if ($Risk) { '  ! ' } else { '  - ' }
        Write-Host ($bullet + $it) -ForegroundColor ($(if ($Risk) { 'Yellow' } else { 'Gray' }))
    }
}

function Confirm-Preflight {
    <#
        Final gate before execution.
        -AutoConfirm  skip the prompt (used by -DryRun or an explicit -Yes flag).
        Returns [bool]; throws 'AnniAbort' if the user chooses to quit.
    #>
    param([switch]$AutoConfirm)

    if ($AutoConfirm) {
        Write-Host ''
        Write-Host '  Auto-confirmed (dry-run or -Yes).' -ForegroundColor DarkGray
        return $true
    }

    Write-Host ''
    Write-Host '  Review the plan above. Destructive items are marked in yellow.' -ForegroundColor Cyan
    Write-Host "  You can type 'abort' at any prompt to stop." -ForegroundColor DarkGray
    return (Read-YesNo -Prompt '  Proceed with setup?' -Default $false)
}
