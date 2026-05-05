$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$a = Get-Content (Join-Path $ProjectRoot "config\apps.json") -Raw | ConvertFrom-Json
$all = @($a.MainApps) + @($a.AdditionalApps) + @($a.Tools)
$targets = @('HyperX NGENUITY','Windows Clock','Windows Media Player','Scoop Extension for Command Palette')
$all | Where-Object { $_.name -in $targets } | Select-Object name, id, source | Format-Table -AutoSize
