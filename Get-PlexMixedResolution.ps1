#Requires -Version 7.0
<#
.SYNOPSIS
    Lists TV shows whose episodes are a mix of 720p and 1080p.

.DESCRIPTION
    Read-only. Lists every episode of every show in the library (one request per show)
    and counts episodes by video resolution, using the first copy of each. Returns
    shows that have both 720p and 1080p episodes, with counts and fractions, so you can
    see which are worth upgrading.

.PARAMETER Type
    Library name of a TV library (see Get-PlexSections.ps1).

.EXAMPLE
    .\Get-PlexMixedResolution.ps1 -Type TV | Sort-Object '720percent' -Descending
#>
[CmdletBinding()]
param(
    [string]$Type = 'TV'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. "$PSScriptRoot/.PlexApi.ps1"

$section = Get-PlexSection -Name $Type
if ($section.type -ne 'show') { throw "Library '$Type' is a $($section.type) library, not a TV library." }

$shows = @(Invoke-PlexApi -Path "/library/sections/$($section.key)/all" -All | Get-PlexItem)
$i = 0
foreach ($show in $shows) {
    $i++
    Write-Progress -Activity 'Checking episode resolutions' -Status "$i of $($shows.Count) [$($show.title)]" -PercentComplete ($i / $shows.Count * 100)

    $resolutions = @(Invoke-PlexApi -Path "/library/metadata/$($show.ratingKey)/allLeaves" -All | Get-PlexItem |
            Where-Object { $_.PSObject.Properties['Media'] } |
            ForEach-Object { @($_.Media)[0].PSObject.Properties['videoResolution']?.Value })
    $total = $resolutions.Count
    $r720 = @($resolutions | Where-Object { $_ -eq '720' }).Count
    $r1080 = @($resolutions | Where-Object { $_ -eq '1080' }).Count
    if ($r720 -eq 0 -or $r1080 -eq 0) { continue }

    [pscustomobject]@{
        Title         = $show.title
        '720p'        = $r720
        '1080p'       = $r1080
        Total         = $total
        '720percent'  = [math]::Round($r720 / $total, 2)
        '1080percent' = [math]::Round($r1080 / $total, 2)
    }
}
Write-Progress -Activity 'Checking episode resolutions' -Completed
