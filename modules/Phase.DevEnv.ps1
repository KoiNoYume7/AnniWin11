# ============================================================================
#  Phase.DevEnv.ps1  --  developer environment (git, ssh, VS Code, runtimes)
# ============================================================================

function Get-DevEnvPlan {
    param([Parameter(Mandatory)]$Manifest)
    $items = @()
    if ($Manifest.Git.UserName)  { $items += "git user.name  = $($Manifest.Git.UserName)" }
    if ($Manifest.Git.UserEmail) { $items += "git user.email = $($Manifest.Git.UserEmail)" }
    if ($Manifest.Git.Defaults)  { $items += "git defaults: $($Manifest.Git.Defaults.Keys -join ', ')" }
    if ($Manifest.Ssh.Generate)  { $items += "generate SSH key ($($Manifest.Ssh.Type)) if missing" }
    foreach ($e in @($Manifest.VSCode.Extensions)) { if ($e) { $items += "VS Code ext: $e" } }
    foreach ($r in @($Manifest.Runtimes))          { if ($r) { $items += "runtime: $r" } }
    if ($Manifest.Profile.InstallPwshProfile) { $items += 'install starter pwsh profile if missing' }
    if ($Manifest.Terminal.Apply)             { $items += 'apply Windows Terminal settings' }
    return @{ Title = 'DevEnv :: git / ssh / VS Code / runtimes'; Items = $items; Risk = $false }
}

function Set-GitConfigChecked {
    param([string]$Key, [string]$Value, [switch]$DryRun)
    if ([string]::IsNullOrWhiteSpace($Value)) { return }
    $current = (& git config --global --get $Key) 2>$null
    if ($current -eq $Value) { Write-Log -Level OK -Message "git $Key (already set)"; return }
    if ($DryRun) { Write-Log -Level WARN -Message "[dry-run] would set git $Key = $Value"; return }
    & git config --global $Key $Value
    Write-Log -Level OK -Message "git $Key = $Value"
}

function Invoke-DevEnvPhase {
    param(
        [Parameter(Mandatory)]$Manifest,
        [switch]$DryRun
    )

    # --- git -----------------------------------------------------------------
    if (Get-Command git -ErrorAction SilentlyContinue) {
        Set-GitConfigChecked -Key 'user.name'  -Value $Manifest.Git.UserName  -DryRun:$DryRun
        Set-GitConfigChecked -Key 'user.email' -Value $Manifest.Git.UserEmail -DryRun:$DryRun
        if ($Manifest.Git.Defaults) {
            foreach ($k in $Manifest.Git.Defaults.Keys) {
                Set-GitConfigChecked -Key $k -Value ([string]$Manifest.Git.Defaults[$k]) -DryRun:$DryRun
            }
        }
    } else {
        Write-Log -Level WARN -Message 'git not found on PATH yet (installed this run?). Re-run to finish git config.'
    }

    # --- SSH key -------------------------------------------------------------
    if ($Manifest.Ssh.Generate) {
        $sshDir = Join-Path $env:USERPROFILE '.ssh'
        $type   = if ($Manifest.Ssh.Type) { $Manifest.Ssh.Type } else { 'ed25519' }
        $keyPath = Join-Path $sshDir "id_$type"
        if (Test-Path -LiteralPath $keyPath) {
            Write-Log -Level OK -Message "SSH key already exists ($keyPath)"
        } elseif ($DryRun) {
            Write-Log -Level WARN -Message "[dry-run] would generate SSH key at $keyPath"
        } elseif (Get-Command ssh-keygen -ErrorAction SilentlyContinue) {
            if (-not (Test-Path -LiteralPath $sshDir)) { New-Item -ItemType Directory -Path $sshDir -Force | Out-Null }
            $comment = if ($Manifest.Ssh.Comment) { $Manifest.Ssh.Comment } else { $Manifest.Git.UserEmail }
            & ssh-keygen -t $type -C $comment -f $keyPath -N '""' | Out-Null
            Write-Log -Level OK -Message "SSH key generated ($keyPath)"
        } else {
            Write-Log -Level WARN -Message 'ssh-keygen not found; skipping SSH key generation.'
        }
    }

    # --- VS Code extensions --------------------------------------------------
    $exts = @($Manifest.VSCode.Extensions) | Where-Object { $_ }
    if ($exts.Count -gt 0) {
        $code = Get-Command code -ErrorAction SilentlyContinue
        if (-not $code) {
            Write-Log -Level WARN -Message "VS Code 'code' CLI not on PATH yet; re-run to install extensions."
        } else {
            $installed = & code --list-extensions 2>$null
            foreach ($ext in $exts) {
                if ($installed -contains $ext) {
                    Write-Log -Level OK -Message "VS Code ext $ext (present)"
                } elseif ($DryRun) {
                    Write-Log -Level WARN -Message "[dry-run] would install VS Code ext $ext"
                } else {
                    & code --install-extension $ext --force | Out-Null
                    Write-Log -Level OK -Message "VS Code ext $ext installed"
                }
            }
        }
    }

    # --- Language / runtime packages via winget ------------------------------
    foreach ($rt in (@($Manifest.Runtimes) | Where-Object { $_ })) {
        Install-WingetApp -Entry $rt -DryRun:$DryRun | Out-Null
    }

    # --- Starter pwsh profile ------------------------------------------------
    if ($Manifest.Profile.InstallPwshProfile) {
        if (Test-Path -LiteralPath $PROFILE) {
            Write-Log -Level OK -Message 'pwsh profile already exists (left untouched).'
        } elseif ($DryRun) {
            Write-Log -Level WARN -Message "[dry-run] would create pwsh profile at $PROFILE"
        } else {
            $pdir = Split-Path -Parent $PROFILE
            if (-not (Test-Path -LiteralPath $pdir)) { New-Item -ItemType Directory -Path $pdir -Force | Out-Null }
            @(
                '# pwsh profile (AnniWin11 starter)'
                'Set-PSReadLineOption -PredictionSource History -ErrorAction SilentlyContinue'
                '$PSStyle.FileInfo.Directory = "`e[36m"'
            ) | Set-Content -LiteralPath $PROFILE -Encoding UTF8
            Write-Log -Level OK -Message "pwsh profile created ($PROFILE)"
        }
    }

    # --- Windows Terminal settings ------------------------------------------
    if ($Manifest.Terminal.Apply) {
        $src = Join-Path $PSScriptRoot ('..\' + $Manifest.Terminal.SourcePath)
        if (-not (Test-Path -LiteralPath $src)) {
            Write-Log -Level WARN -Message "Terminal settings source not found: $($Manifest.Terminal.SourcePath)"
        } else {
            $dst = Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json'
            if ($DryRun) {
                Write-Log -Level WARN -Message "[dry-run] would copy Terminal settings -> $dst"
            } else {
                $dstDir = Split-Path -Parent $dst
                if (Test-Path -LiteralPath $dstDir) {
                    Copy-Item -LiteralPath $src -Destination $dst -Force
                    Write-Log -Level OK -Message 'Windows Terminal settings applied.'
                } else {
                    Write-Log -Level WARN -Message 'Windows Terminal not installed yet; skipping settings copy.'
                }
            }
        }
    }

    # --- Show SSH public key for GitHub -------------------------------------
    if (-not $DryRun -and $Manifest.Ssh.Generate) {
        $pub = Join-Path $env:USERPROFILE (".ssh\id_" + $(if ($Manifest.Ssh.Type) { $Manifest.Ssh.Type } else { 'ed25519' }) + '.pub')
        if (Test-Path -LiteralPath $pub) {
            Write-Log -Level INFO -Message 'SSH public key (add to GitHub -> Settings -> SSH keys):'
            Write-Host (Get-Content -LiteralPath $pub -Raw).Trim() -ForegroundColor Cyan
        }
    }
}
