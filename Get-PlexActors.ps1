#Requires -Version 7.0
<#
.SYNOPSIS
    Lists the actors in a Plex library, optionally filtered by name.

.DESCRIPTION
    GET /library/sections/{key}/actor. Read-only. Returns Name, Key and FastKey for each
    actor; FastKey lists that actor's titles (Invoke-PlexApi -Path <FastKey>).

.PARAMETER Type
    Library name, e.g. Film or TV (see Get-PlexSections.ps1).

.PARAMETER Name
    Wildcard filter on the actor's name, e.g. '*Hanks*'.

.EXAMPLE
    .\Get-PlexActors.ps1 -Type Film -Name '*Hanks*'
#>
[CmdletBinding()]
param(
    [string]$Type = 'Film',
    [string]$Name = '*'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. "$PSScriptRoot/.PlexApi.ps1"

$section = Get-PlexSection -Name $Type
Invoke-PlexApi -Path "/library/sections/$($section.key)/actor" -All | Get-PlexItem |
    Where-Object { $_.title -like $Name } |
    ForEach-Object { [pscustomobject]@{ Name = $_.title; Key = $_.key; FastKey = $_.fastKey } }
