# ============================================================================
#  Phase.Accounts.ps1  --  create the separate school standard account
#
#  Isolation model: a plain LOCAL Windows account. The device is never
#  enrolled/joined. School-mandated apps and any M365/Teams sign-in live here,
#  off the personal admin profile. The script NEVER handles school credentials
#  -- you sign that account into school services yourself.
# ============================================================================

function Get-AccountsPlan {
    param([Parameter(Mandatory)]$Manifest)
    $s = $Manifest.School
    if (-not $s -or -not $s.Create) {
        return @{ Title = 'Accounts :: disabled (School.Create = $false)'; Items = @(); Risk = $false }
    }
    $items = @(
        "create local $($s.Type) user '$($s.UserName)'"
        $(if ($s.SetPassword) { 'will PROMPT you for a password (not stored)' } else { 'passwordless (set on first logon)' })
    )
    return @{ Title = "Accounts :: provision school account"; Items = $items; Risk = $true }
}

function Invoke-AccountsPhase {
    param(
        [Parameter(Mandatory)]$Manifest,
        [switch]$DryRun
    )
    $s = $Manifest.School
    if (-not $s -or -not $s.Create) {
        Write-Log -Level INFO -Message 'School account creation disabled. Skipping.'
        return
    }

    if (Get-LocalUser -Name $s.UserName -ErrorAction SilentlyContinue) {
        Write-Log -Level OK -Message "Local user '$($s.UserName)' already exists."
        return
    }

    if ($DryRun) {
        Write-Log -Level WARN -Message "[dry-run] would create local $($s.Type) user '$($s.UserName)'"
        return
    }

    try {
        if ($s.SetPassword) {
            Write-Log -Level STEP -Message "Set a password for the new '$($s.UserName)' account (input hidden)."
            $pw = Read-Host -AsSecureString "  Password for $($s.UserName)"
            New-LocalUser -Name $s.UserName -FullName $s.FullName -Password $pw `
                -PasswordNeverExpires -AccountNeverExpires -ErrorAction Stop | Out-Null
        } else {
            New-LocalUser -Name $s.UserName -FullName $s.FullName -NoPassword `
                -AccountNeverExpires -ErrorAction Stop | Out-Null
        }
        Write-Log -Level OK -Message "Created local user '$($s.UserName)'."

        if ($s.Type -eq 'Administrator') {
            Add-LocalGroupMember -Group 'Administrators' -Member $s.UserName -ErrorAction Stop
            Write-Log -Level OK -Message "Added '$($s.UserName)' to Administrators."
        }
        # Standard users are members of 'Users' by default -- nothing to do.

        Write-Log -Level INFO -Message "Next: log into '$($s.UserName)' and sign into Teams/M365 yourself."
    } catch {
        Write-Log -Level WARN -Message "Account creation failed: $($_.Exception.Message)"
    }
}
