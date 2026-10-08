#Requires -Version 7.0
<#
.SYNOPSIS
    Lists the libraries (sections) on the Plex server.

.DESCRIPTION
    GET /library/sections. Read-only. Returns title, key and type (movie, show, artist)
    for each library. Server and token come from PlexServer and PlexToken
    (see .PlexApi.ps1).

.EXAMPLE
    .\Get-PlexSections.ps1
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. "$PSScriptRoot/.PlexApi.ps1"

(Invoke-PlexApi -Path '/library/sections').MediaContainer.Directory |
    Select-Object -Property title, key, type
