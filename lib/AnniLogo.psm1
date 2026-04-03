# AnniLogo -- Reusable ASCII Art Logo Renderer
# Renders ASCII art with horizontal colour gradient using ANSI escape sequences.
# No project-specific assumptions -- usable in any PowerShell 7+ project.
# source: https://patorjk.com/software/taag/
#
# Usage:
#   Import-Module "$PSScriptRoot\..\lib\AnniLogo.psm1"
#   Show-AnniLogo -AsciiLines @("LINE1", "LINE2") -StartColor @{R=0;G=255;B=255} -EndColor @{R=255;G=0;B=0}

# ------- Internal Helpers ------- #

function Get-InterpolatedColor {
    param(
        [int]$Position,
        [int]$MaxPosition,
        [hashtable]$Start,
        [hashtable]$End
    )

    if ($MaxPosition -le 0) {
        return @{ R = $Start.R; G = $Start.G; B = $Start.B }
    }

    $ratio = $Position / $MaxPosition
    $r = [math]::Round($Start.R + ($End.R - $Start.R) * $ratio)
    $g = [math]::Round($Start.G + ($End.G - $Start.G) * $ratio)
    $b = [math]::Round($Start.B + ($End.B - $Start.B) * $ratio)
    return @{ R = $r; G = $g; B = $b }
}

function Write-ColorChar {
    param(
        [char]$Char,
        [int]$R,
        [int]$G,
        [int]$B
    )

    $esc = "`e[38;2;${R};${G};${B}m"
    $reset = "`e[0m"
    Write-Host -NoNewline "${esc}${Char}${reset}"
}

# ------- Public Function ------- #

function Show-AnniLogo {
    <#
    .SYNOPSIS
        Renders ASCII art with a horizontal colour gradient.
    .DESCRIPTION
        Takes an array of strings (ASCII art lines) and renders each character
        with an interpolated colour between StartColor and EndColor.
        Clears the host before rendering.
    .PARAMETER AsciiLines
        Array of strings representing the ASCII art to render.
    .PARAMETER StartColor
        Hashtable with R, G, B keys (0-255) for the left-side colour.
        Default: cyan (R=0, G=255, B=255).
    .PARAMETER EndColor
        Hashtable with R, G, B keys (0-255) for the right-side colour.
        Default: red (R=255, G=0, B=0).
    .PARAMETER ClearScreen
        If set, clears the console before rendering. Default: true.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$AsciiLines,

        [hashtable]$StartColor = @{ R = 0; G = 255; B = 255 },

        [hashtable]$EndColor = @{ R = 255; G = 0; B = 0 },

        [bool]$ClearScreen = $true
    )

    if ($ClearScreen) {
        Clear-Host
    }

    foreach ($line in $AsciiLines) {
        $chars = $line.ToCharArray()
        $maxIndex = $chars.Length - 1

        for ($i = 0; $i -le $maxIndex; $i++) {
            $color = Get-InterpolatedColor -Position $i -MaxPosition $maxIndex -Start $StartColor -End $EndColor
            Write-ColorChar -Char $chars[$i] -R $color.R -G $color.G -B $color.B
        }
        Write-Host ""
    }
}

# ------- Module Exports ------- #

Export-ModuleMember -Function Show-AnniLogo
