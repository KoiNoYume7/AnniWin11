# ============================================================================
#  Log.ps1  --  Slim logging + transcript for AnniWin11 v2
#  Dot-source this file. Compatible with Windows PowerShell 5.1 and pwsh 7+.
# ============================================================================

# Script-scoped state so callers don't have to thread a logger object around.
$script:AnniLogFile        = $null
$script:AnniTranscriptOn   = $false
$script:AnniMinLevel       = 'INFO'

# Level ordering for min-level filtering.
$script:AnniLevelRank = @{
    DEBUG = 0
    INFO  = 1
    STEP  = 2
    OK    = 2
    WARN  = 3
    ERROR = 4
}

$script:AnniLevelColor = @{
    DEBUG = 'DarkGray'
    INFO  = 'Gray'
    STEP  = 'Cyan'
    OK    = 'Green'
    WARN  = 'Yellow'
    ERROR = 'Red'
}

function Initialize-Log {
    <#
        Sets up the log file + optional transcript. Safe to call once at startup.
        -LogDir    directory for logs (created if missing)
        -MinLevel  lowest level to emit (DEBUG|INFO|STEP|OK|WARN|ERROR)
        -Transcript  start a full console transcript alongside the structured log
    #>
    param(
        [Parameter(Mandatory)][string]$LogDir,
        [string]$MinLevel = 'INFO',
        [switch]$Transcript
    )

    if (-not (Test-Path -LiteralPath $LogDir)) {
        New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
    }

    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $script:AnniLogFile  = Join-Path $LogDir "anni-$stamp.log"
    $script:AnniMinLevel = $MinLevel

    if ($Transcript) {
        $tpath = Join-Path $LogDir "transcript-$stamp.log"
        try {
            Start-Transcript -Path $tpath -Append -ErrorAction Stop | Out-Null
            $script:AnniTranscriptOn = $true
        } catch {
            # Transcript already running or unsupported host; not fatal.
            $script:AnniTranscriptOn = $false
        }
    }

    Write-Log -Level INFO -Message "Log initialised -> $script:AnniLogFile"
}

function Write-Log {
    <#
        Writes a coloured console line and appends a structured line to the log
        file. Levels: DEBUG, INFO, STEP, OK, WARN, ERROR.
    #>
    param(
        [ValidateSet('DEBUG','INFO','STEP','OK','WARN','ERROR')]
        [string]$Level = 'INFO',
        [Parameter(Mandatory, Position = 0)][string]$Message
    )

    $rank    = $script:AnniLevelRank[$Level]
    $minRank = $script:AnniLevelRank[$script:AnniMinLevel]
    if ($null -eq $minRank) { $minRank = 1 }

    $ts   = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $line = "[{0}] [{1,-5}] {2}" -f $ts, $Level, $Message

    # Always persist to file (even below console threshold) if a file is set.
    if ($script:AnniLogFile) {
        try { Add-Content -LiteralPath $script:AnniLogFile -Value $line -Encoding UTF8 } catch { }
    }

    if ($rank -lt $minRank) { return }

    $prefix = switch ($Level) {
        'STEP'  { '==> ' }
        'OK'    { '  + ' }
        'WARN'  { '  ! ' }
        'ERROR' { '  x ' }
        default { '    ' }
    }
    $color = $script:AnniLevelColor[$Level]
    Write-Host ($prefix + $Message) -ForegroundColor $color
}

function Write-Section {
    param([Parameter(Mandatory)][string]$Title)
    Write-Host ''
    Write-Host ("-" * 70) -ForegroundColor DarkGray
    Write-Log -Level STEP -Message $Title
}

function Stop-Log {
    if ($script:AnniTranscriptOn) {
        try { Stop-Transcript | Out-Null } catch { }
        $script:AnniTranscriptOn = $false
    }
}
