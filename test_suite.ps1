#Requires -Version 7.0
# AnniWin11 Test Suite
# Run before reinstall to validate configs, scripts, modules, and file system

$ProjectRoot = $PSScriptRoot
$pass = 0
$fail = 0
$warn = 0

function Pass($msg) { Write-Host "  [PASS] $msg" -ForegroundColor Green;  $script:pass++ }
function Fail($msg) { Write-Host "  [FAIL] $msg" -ForegroundColor Red;    $script:fail++ }
function Warn($msg) { Write-Host "  [WARN] $msg" -ForegroundColor Yellow; $script:warn++ }
function Section($title) { Write-Host "`n--- $title ---" -ForegroundColor Cyan }

# ------- 1. JSON CONFIG VALIDATION ------- #

Section "JSON Config Validation"

$jsonFiles = @(
    "config\apps.json",
    "config\settings.json",
    "config\app_configs.json",
    "config\backup_store.json",
    "config\ignored_apps.json"
)

foreach ($rel in $jsonFiles) {
    $path = Join-Path $ProjectRoot $rel
    if (-not (Test-Path $path)) {
        Warn "$rel -- file not found (may be optional)"
        continue
    }
    try {
        $raw = Get-Content $path -Raw -ErrorAction Stop
        $null = $raw | ConvertFrom-Json -ErrorAction Stop
        Pass "$rel -- valid JSON"
    } catch {
        Fail "$rel -- parse error: $($_.Exception.Message)"
    }
}

# ------- 2. CONFIG CONTENT CHECKS ------- #

Section "Config Content Checks"

$appsPath = Join-Path $ProjectRoot "config\apps.json"
if (Test-Path $appsPath) {
    $apps = Get-Content $appsPath -Raw | ConvertFrom-Json

    $mainCount = $apps.MainApps.Count
    $addCount  = $apps.AdditionalApps.Count
    $toolCount = $apps.Tools.Count
    Pass "apps.json -- MainApps: $mainCount, AdditionalApps: $addCount, Tools: $toolCount"

    # Check for MS Store IDs with wrong source
    $msIds = ($apps.MainApps + $apps.AdditionalApps + $apps.Tools) | Where-Object {
        $_.id -match '^9[A-Z0-9]{11}$' -and $_.source -ne 'msstore'
    }
    if ($msIds.Count -eq 0) {
        Pass "apps.json -- No MS Store IDs with wrong source"
    } else {
        Fail "apps.json -- $($msIds.Count) MS Store ID(s) still have wrong source: $($msIds.name -join ', ')"
    }

    # Check for obviously broken winget IDs (too short or just arch names)
    $brokenIds = ($apps.MainApps + $apps.AdditionalApps + $apps.Tools) | Where-Object {
        $_.source -eq 'winget' -and $_.id -and $_.id.Length -lt 4
    }
    if ($brokenIds.Count -eq 0) {
        Pass "apps.json -- No obviously broken winget IDs"
    } else {
        Fail "apps.json -- Short/broken IDs: $($brokenIds | ForEach-Object { "$($_.name)='$($_.id)'" } | Join-String ', ')"
    }

    # Check terminal commands have a command field
    $terminalMissing = ($apps.MainApps + $apps.AdditionalApps + $apps.Tools) | Where-Object {
        $_.source -eq 'terminal' -and -not $_.command
    }
    if ($terminalMissing.Count -eq 0) {
        Pass "apps.json -- All terminal entries have commands"
    } else {
        Fail "apps.json -- Terminal entries missing command: $($terminalMissing.name -join ', ')"
    }
}

$settingsPath = Join-Path $ProjectRoot "config\settings.json"
if (Test-Path $settingsPath) {
    $settings = Get-Content $settingsPath -Raw | ConvertFrom-Json
    $requiredKeys = @('device_name','theme','taskbar','explorer')
    $missingKeys = $requiredKeys | Where-Object { -not $settings.$_ }
    if ($missingKeys.Count -eq 0) {
        Pass "settings.json -- Required keys present: $($requiredKeys -join ', ')"
    } else {
        Fail "settings.json -- Missing keys: $($missingKeys -join ', ')"
    }
}

$backupStorePath = Join-Path $ProjectRoot "config\backup_store.json"
if (Test-Path $backupStorePath) {
    $store = Get-Content $backupStorePath -Raw | ConvertFrom-Json
    if ($store.backup_root) {
        if (Test-Path $store.backup_root) {
            Pass "backup_store.json -- Backup root exists: $($store.backup_root)"
        } else {
            Warn "backup_store.json -- Backup root NOT accessible: $($store.backup_root) (drive may be offline)"
        }
    } else {
        Fail "backup_store.json -- No backup_root set"
    }
}

# ------- 3. LOCAL INSTALLER FILES ------- #

Section "Local Installer Files"

$installersDir = Join-Path $ProjectRoot "config\installers"
if (Test-Path $installersDir) {
    Pass "config/installers/ -- directory exists"
    $appsData = Get-Content $appsPath -Raw | ConvertFrom-Json
    $localApps = ($appsData.MainApps + $appsData.AdditionalApps + $appsData.Tools) | Where-Object { $_.source -eq 'local' }
    foreach ($app in $localApps) {
        $localPath = Join-Path $installersDir $app.path
        if (Test-Path $localPath) {
            Pass "$($app.name) -- installer found at $($app.path)"
        } else {
            Warn "$($app.name) -- installer NOT found: $($app.path)"
        }
    }
} else {
    Warn "config/installers/ -- directory missing (local-source apps will be skipped)"
}

# ------- 4. POWERSHELL SYNTAX CHECKS ------- #

Section "PowerShell Syntax Checks"

$psFiles = Get-ChildItem -Path $ProjectRoot -Recurse -Include "*.ps1","*.psm1" |
    Where-Object { $_.FullName -notmatch '\\test_suite\.ps1$' }

foreach ($file in $psFiles) {
    $errors = $null
    $null = [System.Management.Automation.Language.Parser]::ParseFile(
        $file.FullName, [ref]$null, [ref]$errors
    )
    $rel = $file.FullName.Replace($ProjectRoot + "\", "")
    if ($errors.Count -eq 0) {
        Pass "$rel -- no syntax errors"
    } else {
        foreach ($err in $errors) {
            Fail "$rel -- line $($err.Extent.StartLineNumber): $($err.Message)"
        }
    }
}

# ------- 5. MODULE LOADING ------- #

Section "Module Loading"

try {
    Import-Module "$ProjectRoot\lib\AnniLog.psd1" -Force -ErrorAction Stop
    Pass "AnniLog.psd1 -- loaded"
    Remove-Module AnniLog -Force -ErrorAction SilentlyContinue
} catch {
    Fail "AnniLog.psd1 -- failed: $($_.Exception.Message)"
}

try {
    Import-Module "$ProjectRoot\lib\AnniLogo.psd1" -Force -ErrorAction Stop
    Pass "AnniLogo.psd1 -- loaded"
    Remove-Module AnniLogo -Force -ErrorAction SilentlyContinue
} catch {
    Fail "AnniLogo.psd1 -- failed: $($_.Exception.Message)"
}

try {
    . "$ProjectRoot\lib\Config.ps1"
    $root = Get-ProjectRoot
    if ($root -eq $ProjectRoot) {
        Pass "Config.ps1 -- loaded, Get-ProjectRoot: $root"
    } else {
        Warn "Config.ps1 -- Get-ProjectRoot returned '$root' (expected '$ProjectRoot')"
    }
} catch {
    Fail "Config.ps1 -- failed: $($_.Exception.Message)"
}

# ------- 6. LIB/CONFIG FUNCTION SMOKE TESTS ------- #

Section "Config.ps1 Function Smoke Tests"

try {
    $cfg = Get-ProjectConfig
    Pass "Get-ProjectConfig -- returned object (log_level: $($cfg.log_level))"
} catch {
    Fail "Get-ProjectConfig -- $($_.Exception.Message)"
}

try {
    $logPath = Get-LogPath -FileName "test.log"
    Pass "Get-LogPath -- $logPath"
} catch {
    Fail "Get-LogPath -- $($_.Exception.Message)"
}

try {
    $cfgPath = Get-ConfigPath -FileName "apps.json"
    if (Test-Path $cfgPath) {
        Pass "Get-ConfigPath -- $cfgPath"
    } else {
        Warn "Get-ConfigPath -- path resolved OK but apps.json not found (run GenerateConfigs first): $cfgPath"
    }
} catch {
    Fail "Get-ConfigPath -- $($_.Exception.Message)"
}

# Test Resolve-BackupPath for each type
foreach ($type in @('appdata','localappdata','programdata')) {
    try {
        $resolved = Resolve-BackupPath -PathType $type -RelativePath "TestApp\test.json"
        Pass "Resolve-BackupPath '$type' -- $resolved"
    } catch {
        Fail "Resolve-BackupPath '$type' -- $($_.Exception.Message)"
    }
}

try {
    $resolved = Resolve-BackupPath -PathType 'absolute' -RelativePath '%USERPROFILE%\.gitconfig'
    Pass "Resolve-BackupPath 'absolute' -- $resolved"
} catch {
    Fail "Resolve-BackupPath 'absolute' -- $($_.Exception.Message)"
}

# ------- 7. BACKUP STORE CONTENT ------- #

Section "Existing Backup Content"

if (Test-Path $backupStorePath) {
    $store = Get-Content $backupStorePath -Raw | ConvertFrom-Json
    $backupRoot = $store.backup_root
    if (Test-Path $backupRoot) {
        $manifestPath = Join-Path $backupRoot "backup_manifest.json"
        if (Test-Path $manifestPath) {
            $manifest = Get-Content $manifestPath -Raw | ConvertFrom-Json
            Pass "backup_manifest.json -- last backup: $($manifest.timestamp)"
            Pass "  Backed up: $($manifest.backed_up -join ', ')"
            if ($manifest.failed.Count -gt 0) {
                Warn "  Failed items from last backup: $($manifest.failed -join ', ')"
            }
        } else {
            Warn "No backup_manifest.json found in $backupRoot (backup never run?)"
        }

        $appConfigsDir = Join-Path $backupRoot "app_configs"
        if (Test-Path $appConfigsDir) {
            $backedDirs = Get-ChildItem $appConfigsDir -Directory
            Pass "app_configs dir -- $($backedDirs.Count) app folder(s): $($backedDirs.Name -join ', ')"
        } else {
            Warn "No app_configs/ dir in backup root (backup never run?)"
        }

        $wingetExport = Join-Path $backupRoot "winget_export.json"
        if (Test-Path $wingetExport) {
            Pass "winget_export.json -- exists"
        } else {
            Warn "winget_export.json -- not found (backup never run?)"
        }
    }
}

# ------- SUMMARY ------- #

Write-Host "`n$('=' * 50)" -ForegroundColor White
Write-Host "  PASS: $pass   FAIL: $fail   WARN: $warn" -ForegroundColor White
Write-Host "$('=' * 50)" -ForegroundColor White

if ($fail -gt 0) {
    Write-Host "`nSome tests FAILED. Review above before reinstalling." -ForegroundColor Red
    exit 1
} elseif ($warn -gt 0) {
    Write-Host "`nAll tests passed with warnings. Review WARNs above." -ForegroundColor Yellow
    exit 0
} else {
    Write-Host "`nAll tests passed!" -ForegroundColor Green
    exit 0
}
