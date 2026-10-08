#Requires -Version 7.0
<#
.SYNOPSIS
    Refreshes the metadata of titles featuring duplicated actors. Dry-run by default; pass -Execute.

.DESCRIPTION
    Finds actors that appear more than once in the library under the same name (see
    Get-PlexDuplicateActor.ps1) where one entry still has a TMDb or TheTVDB thumbnail,
    then asks Plex to refresh the metadata of every title that entry is credited on.
    The refresh rematches the cast against Plex's people database, which merges the
    duplicates.

    Without -Execute it only lists what it would refresh. With -Execute it sends
    PUT /library/metadata/{ratingKey}/refresh for each title, pausing between actors so
    the server's metadata queue keeps up, and logs each request to
    out/Repair-PlexDuplicateActor-<timestamp>.csv.

    A refresh only re-downloads metadata from the agent. It doesn't touch media files,
    but it does overwrite any metadata fields you edited by hand and didn't lock.

.PARAMETER Type
    Library name, e.g. Film or TV (see Get-PlexSections.ps1). Required, so the scope is explicit.

.PARAMETER DelaySeconds
    Pause after each actor's titles are queued. About 2 for films and 5 for TV worked before.

.PARAMETER Execute
    Send the refresh requests. Without it the script changes nothing.

.EXAMPLE
    .\Repair-PlexDuplicateActor.ps1 -Type TV

.EXAMPLE
    .\Repair-PlexDuplicateActor.ps1 -Type TV -Execute -DelaySeconds 5
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
param(
    [Parameter(Mandatory)][string]$Type,
    [ValidateRange(0, 300)][int]$DelaySeconds = 5,
    [switch]$Execute
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. "$PSScriptRoot/.PlexApi.ps1"

$section = Get-PlexSection -Name $Type
Write-Host "Getting actors in $($section.title)..."
$actors = @(Invoke-PlexApi -Path "/library/sections/$($section.key)/actor" -All | Get-PlexItem)

$dupeNames = @($actors | Group-Object -Property title | Where-Object Count -gt 1 | ForEach-Object Name)
$stale = @($actors | Where-Object {
        $_.title -in $dupeNames -and $_.PSObject.Properties['thumb'] -and $_.thumb -match 'tmdb\.org|thetvdb\.com'
    } | Sort-Object title)

if (-not $stale) { Write-Host 'No duplicated actors with an old-agent thumbnail.'; return }

$plan = foreach ($actor in $stale) {
    foreach ($item in @(Invoke-PlexApi -Path $actor.fastKey -All | Get-PlexItem)) {
        [pscustomobject]@{ Actor = $actor.title; Title = $item.title; RatingKey = $item.ratingKey }
    }
}
$plan = @($plan | Sort-Object Actor, Title -Unique)

Write-Host "$($stale.Count) duplicated actors, $($plan.Count) titles to refresh:"
$plan | Format-Table -AutoSize | Out-Host

if (-not $Execute) { Write-Host 'DRY-RUN. Re-run with -Execute to refresh these titles.' -ForegroundColor Magenta; return }

$outDir = Join-Path $PSScriptRoot 'out'
New-Item -ItemType Directory -Path $outDir -Force | Out-Null
$logPath = Join-Path $outDir "Repair-PlexDuplicateActor-$(Get-Date -Format yyyyMMdd-HHmmss).csv"

$refreshed = [Collections.Generic.HashSet[string]]::new()
foreach ($group in $plan | Group-Object Actor) {
    Write-Host "Refreshing titles for $($group.Name)"
    foreach ($row in $group.Group) {
        # A title shared by two duplicated actors only needs refreshing once.
        if (-not $refreshed.Add($row.RatingKey)) { continue }
        if ($PSCmdlet.ShouldProcess("$($row.Title) ($($row.RatingKey))", 'Refresh metadata')) {
            Invoke-PlexApi -Method Put -Path "/library/metadata/$($row.RatingKey)/refresh" | Out-Null
            [pscustomobject]@{ Time = (Get-Date).ToString('s'); Actor = $row.Actor; Title = $row.Title; RatingKey = $row.RatingKey; Action = 'Refresh' } |
                Export-Csv -Path $logPath -Append -NoTypeInformation
            Write-Host "  --> $($row.Title)"
        }
    }
    Start-Sleep -Seconds $DelaySeconds
}
Write-Host "Logged to $logPath"
