# ============================================================================
#  Phase.Apps.ps1  --  install winget packages from apps.psd1
# ============================================================================

function Get-AppsFlatList {
    # Flattens the Categories hashtable into an ordered list of entries.
    param([Parameter(Mandatory)]$Manifest)
    $list = @()
    if ($Manifest.Categories) {
        foreach ($cat in $Manifest.Categories.Keys) {
            foreach ($entry in @($Manifest.Categories[$cat])) {
                if ($entry) { $list += $entry }
            }
        }
    }
    return $list
}

function Get-AppsPlan {
    param([Parameter(Mandatory)]$Manifest)
    $ids = foreach ($e in (Get-AppsFlatList -Manifest $Manifest)) {
        if ($e -is [hashtable]) { $e.Id } else { [string]$e }
    }
    return @{
        Title = "Apps :: install $($ids.Count) winget package(s)"
        Items = @($ids)
        Risk  = $false
    }
}

function Invoke-AppsPhase {
    param(
        [Parameter(Mandatory)]$Manifest,
        [switch]$DryRun
    )
    $entries = Get-AppsFlatList -Manifest $Manifest
    if ($entries.Count -eq 0) {
        Write-Log -Level INFO -Message 'No apps listed. Skipping.'
        return
    }

    $summary = @{ installed = 0; present = 0; failed = 0; dryrun = 0 }
    $failed  = @()
    foreach ($e in $entries) {
        $result = Install-WingetApp -Entry $e -DryRun:$DryRun
        $summary[$result]++
        if ($result -eq 'failed') {
            $failed += $(if ($e -is [hashtable]) { $e.Id } else { [string]$e })
        }
    }

    Write-Log -Level INFO -Message ("Apps summary -> installed:{0} present:{1} failed:{2} dryrun:{3}" -f `
        $summary.installed, $summary.present, $summary.failed, $summary.dryrun)
    if ($failed.Count -gt 0) {
        Write-Log -Level WARN -Message "Failed installs: $($failed -join ', ')"
    }
}
