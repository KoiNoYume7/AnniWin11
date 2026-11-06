# ============================================================================
#  Phase.WinSettings.ps1  --  apply Windows settings from settings.psd1
#  Maps human-friendly values to registry keys; writes only when different.
# ============================================================================

$script:RegAdvanced    = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
$script:RegPersonalize = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'
$script:RegSearch      = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search'
$script:RegDevMode     = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock'

function Get-DesiredRegOps {
    # Translates settings.psd1 into concrete registry operations.
    param([Parameter(Mandatory)]$Manifest)
    $ops = @()

    function _op($Path, $Name, $Value, $Friendly) {
        @{ Path = $Path; Name = $Name; Value = $Value; Type = 'DWord'; Friendly = $Friendly }
    }

    if ($null -ne $Manifest.Theme) {
        $light = if ($Manifest.Theme -eq 'Light') { 1 } else { 0 }
        $ops += _op $script:RegPersonalize 'AppsUseLightTheme'   $light "Theme (apps) = $($Manifest.Theme)"
        $ops += _op $script:RegPersonalize 'SystemUsesLightTheme' $light "Theme (system) = $($Manifest.Theme)"
    }
    if ($null -ne $Manifest.TaskbarAlignment) {
        $v = if ($Manifest.TaskbarAlignment -eq 'Center') { 1 } else { 0 }
        $ops += _op $script:RegAdvanced 'TaskbarAl' $v "Taskbar alignment = $($Manifest.TaskbarAlignment)"
    }
    if ($null -ne $Manifest.TaskbarSearch) {
        $map = @{ Hide = 0; Icon = 1; Box = 2; Label = 3 }
        if ($map.ContainsKey($Manifest.TaskbarSearch)) {
            $ops += _op $script:RegSearch 'SearchboxTaskbarMode' $map[$Manifest.TaskbarSearch] "Taskbar search = $($Manifest.TaskbarSearch)"
        }
    }
    if ($null -ne $Manifest.TaskbarWidgets) {
        $ops += _op $script:RegAdvanced 'TaskbarDa' ([int][bool]$Manifest.TaskbarWidgets) "Taskbar widgets = $($Manifest.TaskbarWidgets)"
    }
    if ($null -ne $Manifest.TaskbarTaskView) {
        $ops += _op $script:RegAdvanced 'ShowTaskViewButton' ([int][bool]$Manifest.TaskbarTaskView) "Task View button = $($Manifest.TaskbarTaskView)"
    }
    if ($null -ne $Manifest.TaskbarChat) {
        $ops += _op $script:RegAdvanced 'TaskbarMn' ([int][bool]$Manifest.TaskbarChat) "Taskbar chat button = $($Manifest.TaskbarChat)"
    }
    if ($null -ne $Manifest.ShowFileExtensions) {
        $v = if ($Manifest.ShowFileExtensions) { 0 } else { 1 }
        $ops += _op $script:RegAdvanced 'HideFileExt' $v "Show file extensions = $($Manifest.ShowFileExtensions)"
    }
    if ($null -ne $Manifest.ShowHiddenFiles) {
        $v = if ($Manifest.ShowHiddenFiles) { 1 } else { 2 }
        $ops += _op $script:RegAdvanced 'Hidden' $v "Show hidden files = $($Manifest.ShowHiddenFiles)"
    }
    if ($null -ne $Manifest.LaunchTo) {
        $v = if ($Manifest.LaunchTo -eq 'QuickAccess') { 2 } else { 1 }
        $ops += _op $script:RegAdvanced 'LaunchTo' $v "Explorer opens = $($Manifest.LaunchTo)"
    }
    if ($null -ne $Manifest.DeveloperMode) {
        $ops += _op $script:RegDevMode 'AllowDevelopmentWithoutDevLicense' ([int][bool]$Manifest.DeveloperMode) "Developer Mode = $($Manifest.DeveloperMode)"
    }

    return $ops
}

function Get-WinSettingsPlan {
    param([Parameter(Mandatory)]$Manifest)
    $ops = Get-DesiredRegOps -Manifest $Manifest
    return @{
        Title = "WinSettings :: apply $($ops.Count) setting(s)"
        Items = @($ops | ForEach-Object { $_.Friendly })
        Risk  = $false
    }
}

function Set-RegValueChecked {
    param($Path, $Name, $Value, $Type, $Friendly, [switch]$DryRun)
    $current = $null
    try { $current = (Get-ItemProperty -Path $Path -Name $Name -ErrorAction Stop).$Name } catch { }

    if ($current -eq $Value) {
        Write-Log -Level OK -Message "$Friendly (already set)"
        return $false
    }
    if ($DryRun) {
        Write-Log -Level WARN -Message "[dry-run] would set $Friendly"
        return $false
    }
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -Path $Path -Force | Out-Null
    }
    New-ItemProperty -Path $Path -Name $Name -Value $Value -PropertyType $Type -Force | Out-Null
    Write-Log -Level OK -Message "$Friendly (set)"
    return $true
}

function Invoke-WinSettingsPhase {
    param(
        [Parameter(Mandatory)]$Manifest,
        [switch]$DryRun
    )
    $ops = Get-DesiredRegOps -Manifest $Manifest
    if ($ops.Count -eq 0) {
        Write-Log -Level INFO -Message 'No settings specified. Skipping.'
        return
    }

    $changed = 0
    foreach ($op in $ops) {
        if (Set-RegValueChecked -Path $op.Path -Name $op.Name -Value $op.Value -Type $op.Type -Friendly $op.Friendly -DryRun:$DryRun) {
            $changed++
        }
    }

    if ($changed -gt 0 -and -not $DryRun) {
        Write-Log -Level STEP -Message "Restarting Explorer to apply $changed change(s)..."
        Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
        # Explorer auto-restarts; give it a moment.
        Start-Sleep -Seconds 2
        if (-not (Get-Process -Name explorer -ErrorAction SilentlyContinue)) {
            Start-Process explorer.exe
        }
    }
}
