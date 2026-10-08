#Requires -Version 7.0
<#
.SYNOPSIS
    Saves the full metadata, including every audio and subtitle stream, for each film or episode in a library.

.DESCRIPTION
    Read-only against Plex. Library listings leave out the per-file stream details, so
    this fetches each item's own metadata: one request per film, or per episode for a
    TV library, which takes a while on a big library. Writes the results as JSON to
    -OutFile for Get-PlexStreams.ps1 to read, and lists items that failed in a matching
    -errors.txt file.

    In the saved JSON, keys that clash with a capitalised key are prefixed: the item's
    plex:// GUID is plexGuid and its critic rating plexRating (see ConvertFrom-PlexJson
    in .PlexApi.ps1).

.PARAMETER Type
    Library name, e.g. Film or TV (see Get-PlexSections.ps1).

.PARAMETER Title
    Only items whose title (for TV, the show's title) contains this text.

.PARAMETER OutFile
    Where to write the JSON. Default: out/<Type>-details-<timestamp>.json.

.PARAMETER PassThru
    Also return the items.

.EXAMPLE
    .\Get-PlexDetails.ps1 -Type TV

.EXAMPLE
    .\Get-PlexDetails.ps1 -Type Film -Title Matrix -PassThru
#>
[CmdletBinding()]
param(
    [string]$Type = 'TV',
    [string]$Title,
    [string]$OutFile,
    [switch]$PassThru
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. "$PSScriptRoot/.PlexApi.ps1"

$section = Get-PlexSection -Name $Type
# Plex item types: 1 = movie, 4 = episode.
$itemType = switch ($section.type) { 'movie' { 1 } 'show' { 4 } default { throw "Library '$Type' is a $($section.type) library; only movie and show libraries are supported." } }

if (-not $OutFile) {
    $outDir = Join-Path $PSScriptRoot 'out'
    New-Item -ItemType Directory -Path $outDir -Force | Out-Null
    $safeName = $section.title -replace '[^\w-]', ''
    $OutFile = Join-Path $outDir "$safeName-details-$(Get-Date -Format yyyyMMdd-HHmmss).json"
}
$errorFile = [IO.Path]::ChangeExtension($OutFile, $null).TrimEnd('.') + '-errors.txt'

Write-Host "Listing $($section.title)..."
$items = @(Invoke-PlexApi -Path "/library/sections/$($section.key)/all?type=$itemType" -All | Get-PlexItem)
if ($Title) {
    $items = @($items | Where-Object {
            $name = if ($itemType -eq 4) { $_.PSObject.Properties['grandparentTitle']?.Value } else { $_.title }
            $name -like "*$Title*"
        })
}

$details = [Collections.Generic.List[object]]::new()
$failed = 0
$i = 0
foreach ($item in $items) {
    $i++
    $label = if ($itemType -eq 4) { '{0} - {1}' -f $item.PSObject.Properties['grandparentTitle']?.Value, $item.title } else { $item.title }
    Write-Progress -Activity "Getting $($section.title) details" -Status "$i of $($items.Count) [$label]" -PercentComplete ($i / $items.Count * 100)
    try {
        foreach ($d in Invoke-PlexApi -Path $item.key | Get-PlexItem) { $details.Add($d) }
    }
    catch {
        $failed++
        "$label`t$($item.key)`t$($_.Exception.Message)" | Out-File -FilePath $errorFile -Append
    }
}
Write-Progress -Activity "Getting $($section.title) details" -Completed

ConvertTo-Json -InputObject @($details) -Depth 20 -Compress | Set-Content -Path $OutFile
Write-Host "Saved $($details.Count) items to $OutFile"
if ($failed) { Write-Warning "$failed items failed; see $errorFile" }

if ($PassThru) { $details }
