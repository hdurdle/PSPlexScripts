#Requires -Version 7.0
<#
.SYNOPSIS
    Finds films and episodes that have two or more files on disk.

.DESCRIPTION
    Read-only. Lists the library named by -Type and returns one object per file for
    every item with more than one version (Plex "Media"), so you can see which copies
    to delete. For a TV library it lists each show's episodes, which is one request
    per show.

    By default a 4K copy alongside a lower-resolution one is not reported, since
    keeping both is usually deliberate. Use -Include4K to report those too.

.PARAMETER Type
    Library name, e.g. Film or TV (see Get-PlexSections.ps1).

.PARAMETER Include4K
    Also report items where one of the copies is 4K.

.EXAMPLE
    .\Get-PlexMulti.ps1 Film | Format-Table Title, Resolution, Codec, File
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)][string]$Type = 'TV',
    [Alias('4kDupes')][switch]$Include4K
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. "$PSScriptRoot/.PlexApi.ps1"

function Get-Duplicate {
    param([object]$Item, [string]$Title)

    if (-not $Item.PSObject.Properties['Media'] -or @($Item.Media).Count -lt 2) { return }
    if (-not $Include4K -and @($Item.Media | Where-Object { $_.PSObject.Properties['videoResolution'] -and $_.videoResolution -eq '4k' }).Count) { return }

    foreach ($media in $Item.Media) {
        foreach ($part in $media.Part) {
            [pscustomobject]@{
                Title      = $Title
                RatingKey  = $Item.ratingKey
                Resolution = if ($media.PSObject.Properties['videoResolution']) { $media.videoResolution } else { $null }
                Codec      = if ($media.PSObject.Properties['videoCodec']) { $media.videoCodec } else { $null }
                SizeGB     = if ($part.PSObject.Properties['size']) { [math]::Round($part.size / 1GB, 2) } else { $null }
                File       = $part.file
            }
        }
    }
}

$section = Get-PlexSection -Name $Type
$items = @(Invoke-PlexApi -Path "/library/sections/$($section.key)/all" -All | Get-PlexItem)

if ($section.type -eq 'movie') {
    foreach ($item in $items) { Get-Duplicate -Item $item -Title $item.title }
}
elseif ($section.type -eq 'show') {
    $i = 0
    foreach ($show in $items) {
        $i++
        Write-Progress -Activity "Finding $Type episodes with duplicate files" -Status "$i of $($items.Count) [$($show.title)]" -PercentComplete ($i / $items.Count * 100)
        foreach ($episode in @(Invoke-PlexApi -Path "/library/metadata/$($show.ratingKey)/allLeaves" -All | Get-PlexItem)) {
            $label = '{0} S{1:00}E{2:00} {3}' -f $show.title, $episode.PSObject.Properties['parentIndex']?.Value, $episode.PSObject.Properties['index']?.Value, $episode.title
            Get-Duplicate -Item $episode -Title $label
        }
    }
    Write-Progress -Activity "Finding $Type episodes with duplicate files" -Completed
}
else {
    throw "Library '$Type' is a $($section.type) library; only movie and show libraries are supported."
}
