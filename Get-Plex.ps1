#Requires -Version 7.0
<#
.SYNOPSIS
    Queries a Plex library and returns the server's MediaContainer response.

.DESCRIPTION
    Read-only. With no switches, lists everything in the library named by -Type,
    optionally filtered by -Title, -Year, -Resolution and -AddedAfter. The switches
    pick a different query instead: -NowPlaying, -History, -Actors, -Search or
    -AllEpisodes. Large results are fetched in pages and returned as one container.

    Results are in .MediaContainer.Metadata (or .Directory for -Actors). Server and
    token come from PlexServer and PlexToken (see .PlexApi.ps1).

.PARAMETER Type
    Library name, e.g. Film or TV (see Get-PlexSections.ps1). Default: the library with key 1.

.PARAMETER Resolution
    Video resolution filter: 4k, 1080, 720, 576, 480 or sd.

.PARAMETER Title
    Title filter (substring match).

.PARAMETER Year
    Release year filter.

.PARAMETER AddedAfter
    Only items added on or after this date.

.PARAMETER Search
    Search the whole server for this text instead of listing a library.

.PARAMETER AllEpisodes
    ratingKey of a show: return every episode of it.

.PARAMETER OriginalTitle
    Only items whose original title differs from their title (foreign-language releases).

.PARAMETER NowPlaying
    What is playing on the server now.

.PARAMETER History
    Full play history for the server.

.PARAMETER Actors
    Every actor in the library.

.EXAMPLE
    .\Get-Plex.ps1 -Type Film -Resolution 720

.EXAMPLE
    .\Get-Plex.ps1 -Type TV -AddedAfter 2026-01-01
#>
[CmdletBinding(DefaultParameterSetName = 'Library')]
param(
    [Parameter(ParameterSetName = 'Library')]
    [Parameter(ParameterSetName = 'Actors')]
    [string]$Type,
    [Parameter(ParameterSetName = 'Library')][string]$Resolution,
    [Parameter(ParameterSetName = 'Library')][string]$Title,
    [Parameter(ParameterSetName = 'Library')][string]$Year,
    [Parameter(ParameterSetName = 'Library')][Alias('addedAt')][datetime]$AddedAfter,
    [Parameter(ParameterSetName = 'Library')][switch]$OriginalTitle,
    [Parameter(ParameterSetName = 'Search', Mandatory)][string]$Search,
    [Parameter(ParameterSetName = 'AllEpisodes', Mandatory)][string]$AllEpisodes,
    [Parameter(ParameterSetName = 'NowPlaying', Mandatory)][switch]$NowPlaying,
    [Parameter(ParameterSetName = 'History', Mandatory)][switch]$History,
    [Parameter(ParameterSetName = 'Actors', Mandatory)][switch]$Actors
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. "$PSScriptRoot/.PlexApi.ps1"

$section = if ($Type) { (Get-PlexSection -Name $Type).key } else { '1' }

switch ($PSCmdlet.ParameterSetName) {
    'NowPlaying' { Invoke-PlexApi -Path '/status/sessions' }
    'History' { Invoke-PlexApi -Path '/status/sessions/history/all' -All }
    'Search' { Invoke-PlexApi -Path "/search?query=$([uri]::EscapeDataString($Search))" }
    'AllEpisodes' { Invoke-PlexApi -Path "/library/metadata/$([uri]::EscapeDataString($AllEpisodes))/allLeaves" -All }
    'Actors' { Invoke-PlexApi -Path "/library/sections/$section/actor" -All }
    'Library' {
        $query = [Collections.Generic.List[string]]::new()
        if ($Title) { $query.Add("title=$([uri]::EscapeDataString($Title))") }
        if ($Year) { $query.Add("year=$([uri]::EscapeDataString($Year))") }
        if ($Resolution) { $query.Add("resolution=$([uri]::EscapeDataString($Resolution))") }
        # '>>=' is Plex's "on or after" operator for dates.
        if ($PSBoundParameters.ContainsKey('AddedAfter')) {
            $query.Add("addedAt>>=$(([DateTimeOffset]$AddedAfter).ToUnixTimeSeconds())")
        }

        $path = "/library/sections/$section/all"
        if ($query.Count) { $path += '?' + ($query -join '&') }
        $result = Invoke-PlexApi -Path $path -All

        if ($OriginalTitle -and $result.MediaContainer.PSObject.Properties['Metadata']) {
            $result.MediaContainer.Metadata = @($result.MediaContainer.Metadata | Where-Object {
                    $_.PSObject.Properties['originalTitle'] -and $_.originalTitle -and $_.originalTitle -ne $_.title
                })
            $result.MediaContainer.size = $result.MediaContainer.Metadata.Count
        }
        $result
    }
}
