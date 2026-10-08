#Requires -Version 7.0
<#
.SYNOPSIS
    Lists the genres in a Plex library with the number of titles in each.

.DESCRIPTION
    GET /library/sections/{key}/genre, then one count-only request per genre. Read-only.
    Returns Genre, Count and FastKey; FastKey lists the titles in that genre
    (Invoke-PlexApi -Path <FastKey>).

.PARAMETER Type
    Library name, e.g. Film or TV (see Get-PlexSections.ps1).

.PARAMETER Genre
    Wildcard filter on the genre name, e.g. 'Sci*'.

.PARAMETER List
    Return the genre names only, without counting (one request instead of one per genre).

.EXAMPLE
    .\Get-PlexGenres.ps1 -Type Film | Sort-Object Count -Descending
#>
[CmdletBinding()]
param(
    [string]$Type = 'Film',
    [string]$Genre = '*',
    [switch]$List
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. "$PSScriptRoot/.PlexApi.ps1"

$section = Get-PlexSection -Name $Type
$genres = @(Invoke-PlexApi -Path "/library/sections/$($section.key)/genre" | Get-PlexItem | Where-Object { $_.title -like $Genre })

if ($List) { return $genres.title }

foreach ($g in $genres) {
    # A zero-size page returns no items, just totalSize.
    $sep = if ($g.fastKey -match '\?') { '&' } else { '?' }
    $count = (Invoke-PlexApi -Path "$($g.fastKey)${sep}X-Plex-Container-Start=0&X-Plex-Container-Size=0").MediaContainer.totalSize
    [pscustomobject]@{ Genre = $g.title; Count = [int]$count; FastKey = $g.fastKey }
}
