# ============================================================================
#  Phase.Debloat.ps1  --  remove ONLY the appx packages listed in debloat.psd1
#  Removes for the current user and deprovisions so it stays gone for new users.
# ============================================================================

function Get-DebloatPlan {
    param([Parameter(Mandatory)]$Manifest)
    $names = @($Manifest.Remove)
    return @{
        Title = "Debloat :: remove $($names.Count) package pattern(s)"
        Items = $names
        Risk  = $true    # destructive -> shown in yellow
    }
}

function Invoke-DebloatPhase {
    param(
        [Parameter(Mandatory)]$Manifest,
        [switch]$DryRun
    )
    $patterns = @($Manifest.Remove)
    if ($patterns.Count -eq 0) {
        Write-Log -Level INFO -Message 'Debloat list empty. Nothing to remove.'
        return
    }

    foreach ($pattern in $patterns) {
        if ([string]::IsNullOrWhiteSpace($pattern)) { continue }

        $installed   = @(Get-AppxPackage -Name $pattern -ErrorAction SilentlyContinue)
        $provisioned = @(Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue |
                         Where-Object { $_.DisplayName -like $pattern })

        if ($installed.Count -eq 0 -and $provisioned.Count -eq 0) {
            Write-Log -Level OK -Message "$pattern (not present)"
            continue
        }

        if ($DryRun) {
            Write-Log -Level WARN -Message "[dry-run] would remove $pattern (installed:$($installed.Count) provisioned:$($provisioned.Count))"
            continue
        }

        foreach ($pkg in $installed) {
            try {
                Remove-AppxPackage -Package $pkg.PackageFullName -ErrorAction Stop
                Write-Log -Level OK -Message "removed (user): $($pkg.Name)"
            } catch {
                Write-Log -Level WARN -Message "failed to remove $($pkg.Name): $($_.Exception.Message)"
            }
        }
        foreach ($pp in $provisioned) {
            try {
                Remove-AppxProvisionedPackage -Online -PackageName $pp.PackageName -ErrorAction Stop | Out-Null
                Write-Log -Level OK -Message "deprovisioned: $($pp.DisplayName)"
            } catch {
                Write-Log -Level WARN -Message "failed to deprovision $($pp.DisplayName): $($_.Exception.Message)"
            }
        }
    }
}
