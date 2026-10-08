#Requires -Version 7.0
<#
.SYNOPSIS
    Lists titles whose best copy has fewer audio channels than a threshold (stereo-only films by default).

.DESCRIPTION
    Read-only. Checks the audioChannels of every copy (Media) of each title in the
    library and returns those where even the best copy is below -MinChannels.
    Returns Title, Year, AudioChannels, AudioCodec and File of the best copy.

.PARAMETER Type
    Library name, e.g. Film (see Get-PlexSections.ps1).

.PARAMETER MinChannels
    Report titles with fewer channels than this. 5 finds anything below 5.1 surround.

.PARAMETER MinYear
    Only titles released in or after this year (older films are often mono or stereo by design).

.EXAMPLE
    .\Get-PlexLowChannelAudio.ps1 -Type Film -MinYear 2000
#>
[CmdletBinding()]
param(
    [string]$Type = 'Film',
    [ValidateRange(1, 16)][int]$MinChannels = 5,
    [int]$MinYear = 0
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. "$PSScriptRoot/.PlexApi.ps1"

$section = Get-PlexSection -Name $Type
foreach ($item in Invoke-PlexApi -Path "/library/sections/$($section.key)/all" -All | Get-PlexItem) {
    if (-not $item.PSObject.Properties['Media']) { continue }
    $year = [int]($item.PSObject.Properties['year']?.Value)
    if ($year -lt $MinYear) { continue }

    $best = $item.Media | Sort-Object { [int]($_.PSObject.Properties['audioChannels']?.Value) } -Descending | Select-Object -First 1
    $channels = [int]($best.PSObject.Properties['audioChannels']?.Value)
    if ($channels -ge $MinChannels) { continue }

    [pscustomobject]@{
        Title         = $item.title
        Year          = $year
        AudioChannels = $channels
        AudioCodec    = $best.PSObject.Properties['audioCodec']?.Value
        File          = @($best.Part.file)[0]
    }
}
