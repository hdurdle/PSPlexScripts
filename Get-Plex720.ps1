#Requires -Version 7.0
<#
.SYNOPSIS
    Lists titles in a Plex library that have a copy at a given resolution (720p by default).

.DESCRIPTION
    Read-only. Unlike Get-Plex.ps1 -Resolution, which uses the server's filter, this
    checks every copy (Media) of each title, so a title with both a 720p and a 1080p
    file is included. Returns Title, Year, Resolutions and Files.

.PARAMETER Type
    Library name, e.g. Film or TV (see Get-PlexSections.ps1).

.PARAMETER Resolution
    videoResolution value to look for: 4k, 1080, 720, 576, 480 or sd.

.EXAMPLE
    .\Get-Plex720.ps1 -Type Film | Export-Csv out/720p.csv -NoTypeInformation
#>
[CmdletBinding()]
param(
    [string]$Type = 'Film',
    [string]$Resolution = '720'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. "$PSScriptRoot/.PlexApi.ps1"

$section = Get-PlexSection -Name $Type
Invoke-PlexApi -Path "/library/sections/$($section.key)/all" -All | Get-PlexItem |
    Where-Object { $_.PSObject.Properties['Media'] -and ($_.Media | Where-Object { $_.PSObject.Properties['videoResolution'] -and $_.videoResolution -eq $Resolution }) } |
    ForEach-Object {
        [pscustomobject]@{
            Title       = $_.title
            Year        = $_.PSObject.Properties['year']?.Value
            Resolutions = ($_.Media | ForEach-Object { $_.PSObject.Properties['videoResolution']?.Value }) -join ', '
            Files       = @($_.Media.Part.file)
        }
    }
