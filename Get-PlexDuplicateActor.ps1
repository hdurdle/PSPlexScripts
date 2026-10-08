#Requires -Version 7.0
<#
.SYNOPSIS
    Finds actors that appear more than once in a Plex library under the same name.

.DESCRIPTION
    Read-only. Plex sometimes keeps two actor entries for one person, typically one
    matched to an old agent (TMDb or TheTVDB thumbnail) and one to Plex's own people
    database. Returns one object per name with every Key and Thumb, so you can see which
    entries are stale. Repair-PlexDuplicateActor.ps1 refreshes the affected titles.

.PARAMETER Type
    Library name, e.g. Film or TV (see Get-PlexSections.ps1).

.EXAMPLE
    .\Get-PlexDuplicateActor.ps1 -Type TV
#>
[CmdletBinding()]
param(
    [string]$Type = 'TV'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. "$PSScriptRoot/.PlexApi.ps1"

$section = Get-PlexSection -Name $Type
Invoke-PlexApi -Path "/library/sections/$($section.key)/actor" -All | Get-PlexItem |
    Group-Object -Property title | Where-Object Count -gt 1 | Sort-Object Name |
    ForEach-Object {
        [pscustomobject]@{
            Name   = $_.Name
            Count  = $_.Count
            Keys   = @($_.Group.key)
            Thumbs = @($_.Group | ForEach-Object { $_.PSObject.Properties['thumb']?.Value })
        }
    }
