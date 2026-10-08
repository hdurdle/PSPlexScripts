#Requires -Version 7.0
<#
.SYNOPSIS
    Lists titles that were added a while ago and have hardly been watched, using Tautulli.

.DESCRIPTION
    Read-only. Calls Tautulli's get_library_media_info for the library and returns
    titles added before -AddedBefore with fewer than -MaxPlays plays, oldest first.
    Good candidates for clearing out.

    Reads the Tautulli URL and API key from $env:TautulliUrl and $env:TautulliApiKey
    (see Set-PSEnvVars.ps1). Tautulli is separate from Plex: https://tautulli.com

.PARAMETER Type
    Library name as Tautulli shows it, e.g. TV or Film.

.PARAMETER MaxPlays
    Report titles with fewer plays than this.

.PARAMETER AddedBefore
    Only titles added before this date. Default: two years ago.

.EXAMPLE
    .\Get-PlexUnwatched.ps1 -Type TV -MaxPlays 1 | Format-Table Title, Added, Plays
#>
[CmdletBinding()]
param(
    [string]$Type = 'TV',
    [ValidateRange(1, [int]::MaxValue)][int]$MaxPlays = 5,
    [datetime]$AddedBefore = (Get-Date).AddYears(-2)
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$apiKey = $env:TautulliApiKey
if (-not $apiKey -or $apiKey -match 'REPLACE_ME') { throw 'TautulliApiKey not set. Dot-source Set-PSEnvVars.ps1 first.' }
$baseUrl = $env:TautulliUrl
if (-not $baseUrl -or $baseUrl -match 'REPLACE_ME') { throw 'TautulliUrl not set. Dot-source Set-PSEnvVars.ps1 first.' }
$baseUrl = $baseUrl.TrimEnd('/')

function Invoke-Tautulli([string]$Command, [hashtable]$Query = @{}) {
    $Query.apikey = $apiKey
    $Query.cmd = $Command
    $qs = ($Query.GetEnumerator() | ForEach-Object { "$($_.Key)=$([uri]::EscapeDataString([string]$_.Value))" }) -join '&'
    try {
        $res = Invoke-RestMethod -Uri "$baseUrl/api/v2?$qs" -TimeoutSec 120
    }
    catch {
        # The URL contains the API key, so report the command rather than the request.
        throw "Tautulli $Command failed: $($_.Exception.Message -replace [regex]::Escape($apiKey), '***')"
    }
    if ($res.response.result -ne 'success') { throw "Tautulli $Command failed: $($res.response.message)" }
    $res.response.data
}

$library = Invoke-Tautulli 'get_libraries' | Where-Object { $_.section_name -eq $Type }
if (-not $library) { throw "No Tautulli library called '$Type'. Libraries: $((Invoke-Tautulli 'get_libraries').section_name -join ', ')" }

$cutoff = ([DateTimeOffset]$AddedBefore).ToUnixTimeSeconds()
(Invoke-Tautulli 'get_library_media_info' @{ section_id = @($library)[0].section_id; length = 100000 }).data |
    Where-Object { [long]$_.added_at -lt $cutoff -and [int]$_.play_count -lt $MaxPlays } |
    Sort-Object { [long]$_.added_at } |
    ForEach-Object {
        [pscustomobject]@{
            Title      = $_.title
            Year       = $_.year
            Added      = [DateTimeOffset]::FromUnixTimeSeconds([long]$_.added_at).LocalDateTime.Date
            Plays      = [int]$_.play_count
            LastPlayed = if ($_.last_played) { [DateTimeOffset]::FromUnixTimeSeconds([long]$_.last_played).LocalDateTime } else { $null }
            RatingKey  = $_.rating_key
        }
    }
