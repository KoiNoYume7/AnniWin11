$pass = 0; $fail = 0
function Pass($m) { Write-Host "  [PASS] $m" -ForegroundColor Green;  $script:pass++ }
function Fail($m) { Write-Host "  [FAIL] $m" -ForegroundColor Red;    $script:fail++ }

foreach ($f in @(
    'd:\.src\AnniWin11\src\ScanApps.ps1',
    'd:\.src\AnniWin11\src\Main.ps1'
)) {
    $errs = $null
    [System.Management.Automation.Language.Parser]::ParseFile($f, [ref]$null, [ref]$errs) | Out-Null
    if ($errs.Count -eq 0) { Pass "syntax OK: $(Split-Path $f -Leaf)" }
    else { $errs | ForEach-Object { Fail "syntax: $_" } }
}

# No ThreadJob refs in ScanApps.ps1
$hits = Select-String -Path 'd:\.src\AnniWin11\src\ScanApps.ps1' -Pattern 'ThreadJob|Start-ThreadJob|Receive-Job'
if ($hits) { Fail "ThreadJob refs still present in ScanApps.ps1: $($hits.Count) hit(s)" }
else        { Pass "No ThreadJob references in ScanApps.ps1" }

# Invoke-AppScan is sequential (no if/else branching on ThreadJob)
$body = (Select-String -Path 'd:\.src\AnniWin11\src\ScanApps.ps1' -Pattern 'function Invoke-AppScan' -SimpleMatch)
if ($body) { Pass "Invoke-AppScan function found" } else { Fail "Invoke-AppScan not found" }

# FirstTimeSetup has exactly 2 steps (Step 1/2, 2/2)
$steps = Select-String -Path 'd:\.src\AnniWin11\src\Main.ps1' -Pattern 'Step \d/2:'
if ($steps.Count -eq 2) { Pass "FirstTimeSetup has exactly 2 steps" }
else { Fail "FirstTimeSetup step count wrong: $($steps.Count)" }

# No InstallApps, Pin-TaskbarApp, RestoreConfigs in FirstTimeSetup block
$badRefs = Select-String -Path 'd:\.src\AnniWin11\src\Main.ps1' -Pattern 'InstallApps|Pin-TaskbarApp|RestoreConfigs' |
    Where-Object { $_.LineNumber -ge 116 -and $_.LineNumber -le 147 }
if ($badRefs) { Fail "Post-reinstall scripts referenced in FirstTimeSetup: $($badRefs.Line -join ', ')" }
else          { Pass "No post-reinstall scripts in FirstTimeSetup" }

# Menu label updated
$menuLine = Select-String -Path 'd:\.src\AnniWin11\src\Main.ps1' -Pattern 'select backup drive, detect apps, build config files'
if ($menuLine) { Pass "Menu label updated for option 1" }
else            { Fail "Menu label for option 1 not updated" }

Write-Host ""
Write-Host "  PASS: $pass   FAIL: $fail"
if ($fail -gt 0) { exit 1 }
