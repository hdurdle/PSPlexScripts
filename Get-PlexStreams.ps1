#Requires -Version 7.0
<#
.SYNOPSIS
    Finds files with image-based (PGS) subtitles or non-English audio, from a Get-PlexDetails.ps1 export.

.DESCRIPTION
    Read-only and offline: reads the JSON written by Get-PlexDetails.ps1 rather than
    calling Plex. Returns one object per file and problem:

        PgsSubtitles   PGS subtitle track. Image-based, so most clients have to transcode.
        ForeignAudio   more than one audio track and at least one tagged with a language
                       other than English. Untagged and 'und' tracks are ignored.

    Plex stream types: 1 video, 2 audio, 3 subtitle.

.PARAMETER Path
    JSON file from Get-PlexDetails.ps1. Default: the newest out/*-details-*.json.

.PARAMETER Check
    Which problems to report. Default: both.

.EXAMPLE
    .\Get-PlexStreams.ps1 -Check ForeignAudio | Format-Table Title, Language, Codec

.EXAMPLE
    .\Get-PlexStreams.ps1 -Path out/TV-details-20260101-120000.json -Check PgsSubtitles
#>
[CmdletBinding()]
param(
    [string]$Path,
    [ValidateSet('PgsSubtitles', 'ForeignAudio')][string[]]$Check = @('PgsSubtitles', 'ForeignAudio')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $Path) {
    $Path = Get-ChildItem -Path (Join-Path $PSScriptRoot 'out') -Filter '*-details-*.json' -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1 -ExpandProperty FullName
    if (-not $Path) { throw 'No details export found in out/. Run Get-PlexDetails.ps1 first, or pass -Path.' }
}

Write-Host "Reading $Path (large exports take a while)..."
$details = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -Depth 100

function Get-Prop([object]$Object, [string]$Name) { $Object.PSObject.Properties[$Name]?.Value }

foreach ($item in $details) {
    $title = if (Get-Prop $item 'grandparentTitle') {
        '{0} S{1:00}E{2:00} {3}' -f $item.grandparentTitle, (Get-Prop $item 'parentIndex'), (Get-Prop $item 'index'), $item.title
    } else { $item.title }

    foreach ($part in @(Get-Prop $item 'Media' | ForEach-Object { Get-Prop $_ 'Part' })) {
        $streams = @(Get-Prop $part 'Stream')

        if ('PgsSubtitles' -in $Check) {
            $pgs = @($streams | Where-Object { (Get-Prop $_ 'streamType') -eq 3 -and (Get-Prop $_ 'codec') -eq 'pgs' })
            if ($pgs) {
                [pscustomobject]@{ Problem = 'PgsSubtitles'; Title = $title; Codec = 'pgs'; Language = (@($pgs | ForEach-Object { Get-Prop $_ 'languageTag' }) -join ','); File = $part.file }
            }
        }

        if ('ForeignAudio' -in $Check) {
            $audio = @($streams | Where-Object { (Get-Prop $_ 'streamType') -eq 2 })
            $foreign = @($audio | Where-Object { (Get-Prop $_ 'languageTag') -notin 'en', 'und', '', $null })
            if ($audio.Count -gt 1 -and $foreign) {
                [pscustomobject]@{ Problem = 'ForeignAudio'; Title = $title; Codec = (Get-Prop $foreign[0] 'codec'); Language = (@($foreign | ForEach-Object { Get-Prop $_ 'languageTag' }) -join ','); File = $part.file }
            }
        }
    }
}
