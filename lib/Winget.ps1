# ============================================================================
#  Winget.ps1  --  shared winget helpers (install-if-missing, idempotent)
# ============================================================================

function Test-WingetInstalled {
    <# Returns $true if a package Id is already installed. #>
    param([Parameter(Mandatory)][string]$Id)
    try {
        $out = & winget list --id $Id --exact --accept-source-agreements 2>$null
        if ($LASTEXITCODE -ne 0) { return $false }
        # winget prints a "no installed package found" message with exit 0 in
        # some versions, so also confirm the id actually appears.
        return (($out | Out-String) -match [regex]::Escape($Id))
    } catch {
        return $false
    }
}

function Install-WingetApp {
    <#
        Installs a winget package if not already present. Idempotent.
        -Entry may be a string Id or a hashtable @{ Id; Args }.
        Returns 'installed' | 'present' | 'failed' | 'dryrun'.
    #>
    param(
        [Parameter(Mandatory)]$Entry,
        [switch]$DryRun
    )

    if ($Entry -is [hashtable]) {
        $id   = $Entry.Id
        $extra = @($Entry.Args)
    } else {
        $id   = [string]$Entry
        $extra = @()
    }
    if ([string]::IsNullOrWhiteSpace($id)) { return 'failed' }

    if (Test-WingetInstalled -Id $id) {
        Write-Log -Level OK -Message "$id already installed"
        return 'present'
    }

    if ($DryRun) {
        Write-Log -Level WARN -Message "[dry-run] would install $id"
        return 'dryrun'
    }

    Write-Log -Level STEP -Message "Installing $id ..."
    $args = @('install','--id', $id, '--exact', '--silent',
              '--accept-source-agreements','--accept-package-agreements') + $extra
    & winget @args
    if ($LASTEXITCODE -eq 0) {
        Write-Log -Level OK -Message "$id installed"
        return 'installed'
    } else {
        Write-Log -Level WARN -Message "$id failed (winget exit $LASTEXITCODE)"
        return 'failed'
    }
}
