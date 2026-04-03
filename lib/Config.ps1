# Config.ps1 -- Centralised Configuration Helper
# Provides path resolution, JSONC/JSON reading, and path token expansion.
# Dot-source this file in any script: . "$PSScriptRoot\..\lib\Config.ps1"

# ------- Path Resolution ------- #

function Get-ProjectRoot {
    <#
    .SYNOPSIS
        Resolves the AnniWin11 repository root directory.
    .DESCRIPTION
        Walks up from the lib/ directory to find the project root.
        Assumes this file lives in <ProjectRoot>/lib/.
    #>
    [CmdletBinding()]
    param()

    return (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
}

function Get-ConfigPath {
    <#
    .SYNOPSIS
        Resolves a config file path relative to the project root.
    .PARAMETER FileName
        Name of the config file (e.g. "apps.json", "settings.json").
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$FileName
    )

    $root = Get-ProjectRoot
    return Join-Path $root "config" $FileName
}

function Get-LogPath {
    <#
    .SYNOPSIS
        Resolves a log file path relative to the project root.
    .PARAMETER FileName
        Name of the log file (e.g. "installation.log").
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$FileName
    )

    $root = Get-ProjectRoot
    return Join-Path $root "logs" $FileName
}

# ------- JSON / JSONC Reading ------- #

function Read-JsoncFile {
    <#
    .SYNOPSIS
        Reads a JSONC file, strips comments, and parses to a PowerShell object.
    .DESCRIPTION
        Strips both block comments (/* ... */) and line comments (// ...)
        before parsing. Handles UTF-8 encoding.
    .PARAMETER Path
        Full path to the .jsonc file.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path $Path)) {
        throw "JSONC file not found: $Path"
    }

    $raw = Get-Content -Path $Path -Raw -Encoding UTF8

    # Strip block comments (/* ... */)
    $raw = [regex]::Replace(
        $raw,
        '/\*.*?\*/',
        '',
        [System.Text.RegularExpressions.RegexOptions]::Singleline
    )

    # Strip line comments (// ...)
    $raw = [regex]::Replace(
        $raw,
        '^\s*//.*$',
        '',
        [System.Text.RegularExpressions.RegexOptions]::Multiline
    )

    # Also strip inline comments after values (e.g. "value", // comment)
    $raw = [regex]::Replace(
        $raw,
        '(?<=,|{|\[)\s*//.*$',
        '',
        [System.Text.RegularExpressions.RegexOptions]::Multiline
    )

    try {
        return $raw | ConvertFrom-Json
    }
    catch {
        throw "Failed to parse JSONC file '$Path': $($_.Exception.Message)"
    }
}

function Read-JsonFile {
    <#
    .SYNOPSIS
        Reads a plain JSON file and parses to a PowerShell object.
    .PARAMETER Path
        Full path to the .json file.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path $Path)) {
        throw "JSON file not found: $Path"
    }

    try {
        $raw = Get-Content -Path $Path -Raw -Encoding UTF8
        return $raw | ConvertFrom-Json
    }
    catch {
        throw "Failed to parse JSON file '$Path': $($_.Exception.Message)"
    }
}

# ------- Path Token Resolver ------- #

function Resolve-BackupPath {
    <#
    .SYNOPSIS
        Expands a path token from app_configs.json into a full filesystem path.
    .DESCRIPTION
        Supports the following path types:
          appdata         -> %APPDATA%           (e.g. C:\Users\X\AppData\Roaming)
          appdata_roaming -> %APPDATA%           (alias for appdata)
          localappdata    -> %LOCALAPPDATA%      (e.g. C:\Users\X\AppData\Local)
          programdata     -> %PROGRAMDATA%       (e.g. C:\ProgramData)
          absolute        -> literal path as-is
    .PARAMETER PathType
        One of: appdata, appdata_roaming, localappdata, programdata, absolute.
    .PARAMETER RelativePath
        The relative path fragment to append to the resolved root.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet("appdata", "appdata_roaming", "localappdata", "programdata", "absolute")]
        [string]$PathType,

        [Parameter(Mandatory = $true)]
        [string]$RelativePath
    )

    switch ($PathType) {
        "appdata"         { return Join-Path $env:APPDATA $RelativePath }
        "appdata_roaming" { return Join-Path $env:APPDATA $RelativePath }
        "localappdata"    { return Join-Path $env:LOCALAPPDATA $RelativePath }
        "programdata"     { return Join-Path $env:PROGRAMDATA $RelativePath }
        "absolute"        { return $RelativePath }
        default           { throw "Unknown path type: $PathType" }
    }
}
