# ============================================================================
#  Phase.Backup.ps1  --  export the configured state (forward-only)
#
#  Captures the machine's current good state so it can be reviewed or restored
#  later. Writes to Backup.LocalPath. Pushing to the RPi4 over Tailscale is a
#  future config toggle (Backup.Remote) -- not implemented against the server
#  yet, so it only warns when enabled.
# ============================================================================

function Get-BackupPlan {
    param([Parameter(Mandatory)]$Manifest)
    $items = @(
        "export winget app list"
        "copy profile/*.psd1 (declarative source of truth)"
        "export Explorer/theme registry keys"
        "target: $($Manifest.Backup.LocalPath)"
    )
    if ($Manifest.Backup.Remote.Enabled) {
        $items += "remote push to $($Manifest.Backup.Remote.Host) (NOT yet implemented)"
    }
    return @{ Title = 'Backup :: snapshot configured state'; Items = $items; Risk = $false }
}

function Invoke-BackupPhase {
    param(
        [Parameter(Mandatory)]$Manifest,
        [switch]$DryRun
    )
    $repoRoot = Split-Path -Parent $PSScriptRoot
    $base     = $Manifest.Backup.LocalPath
    $stamp    = Get-Date -Format 'yyyyMMdd-HHmmss'
    $dest     = Join-Path $base "backup-$stamp"

    if ($DryRun) {
        Write-Log -Level WARN -Message "[dry-run] would export state to $dest"
        if ($Manifest.Backup.Remote.Enabled) {
            Write-Log -Level WARN -Message '[dry-run] remote push is not implemented yet.'
        }
        return
    }

    New-Item -ItemType Directory -Path $dest -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $dest 'profile') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $dest 'reg') -Force | Out-Null

    # 1. winget app export
    try {
        & winget export --output (Join-Path $dest 'apps.json') --accept-source-agreements | Out-Null
        Write-Log -Level OK -Message 'winget app list exported.'
    } catch {
        Write-Log -Level WARN -Message "winget export failed: $($_.Exception.Message)"
    }

    # 2. declarative manifests (the real source of truth)
    Copy-Item -Path (Join-Path $repoRoot 'profile\*.psd1') -Destination (Join-Path $dest 'profile') -Force
    Write-Log -Level OK -Message 'profile manifests copied.'

    # 3. registry snapshots
    $regKeys = @{
        'explorer-advanced.reg' = 'HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
        'personalize.reg'       = 'HKCU\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'
        'search.reg'            = 'HKCU\Software\Microsoft\Windows\CurrentVersion\Search'
    }
    foreach ($file in $regKeys.Keys) {
        & reg.exe export $regKeys[$file] (Join-Path $dest "reg\$file") /y *> $null
    }
    Write-Log -Level OK -Message 'registry keys exported.'

    # 4. manifest of this backup
    [PSCustomObject]@{
        createdAt = (Get-Date).ToString('o')
        machine   = $env:COMPUTERNAME
        user      = $env:USERNAME
        contents  = @('apps.json', 'profile/*.psd1', 'reg/*.reg')
    } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $dest 'manifest.json') -Encoding UTF8

    Write-Log -Level OK -Message "Backup written to $dest"

    # 5. remote (future)
    if ($Manifest.Backup.Remote.Enabled) {
        Write-Log -Level WARN -Message "Remote push to RPi4 over Tailscale is not implemented yet; backup kept locally at $dest."
    }
}
