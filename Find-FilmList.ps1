#Requires -Version 7.0
<#
.SYNOPSIS
    Searches a plain-text film list for a title.

.DESCRIPTION
    Read-only and offline. Returns the matching lines (Select-String regex) from a text
    file with one film per line, such as a folder listing of the film share. For the
    Plex library itself use Get-Plex.ps1 -Search.

.PARAMETER Term
    Text or regular expression to look for.

.PARAMETER Path
    The film list. Default: films.txt next to this script.

.EXAMPLE
    .\Find-FilmList.ps1 'Andromeda'
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory, Position = 0)][string]$Term,
    [string]$Path = (Join-Path $PSScriptRoot 'films.txt')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $Path)) { throw "Film list not found: $Path" }
Select-String -Pattern $Term -LiteralPath $Path
