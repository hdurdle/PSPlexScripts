#Requires -Version 7.0

<#
.SYNOPSIS
    Shared Plex API helper. Dot-source it; it does nothing when run on its own.

.DESCRIPTION
    Defines the functions every script in this folder uses:

        Get-PlexServerUrl    base URL of the Plex Media Server.
        Get-PlexClientId     the X-Plex-Client-Identifier sent with every request.
        Get-PlexHeader       request headers, including the token.
        Invoke-PlexApi       calls the server and returns the parsed MediaContainer
                             response. -All pages through large libraries. Retries 429
                             (any method) and 5xx (GET only) up to four attempts,
                             honouring Retry-After.
        Get-PlexItem         the results list (Metadata or Directory) of a response.
        Get-PlexSection      the library (section) for a name such as 'Film', or a key.

    Settings come from environment variables (see Set-PSEnvVars.example.ps1):

        PlexServer   host:port or URL of the server, e.g. plex.local:32400.
        PlexToken    X-Plex-Token. Get one with Get-PlexToken.ps1.

.EXAMPLE
    . "$PSScriptRoot/.PlexApi.ps1"
    (Invoke-PlexApi -Path '/library/sections').MediaContainer.Directory
#>

function Get-PlexServerUrl {
    [CmdletBinding()]
    param()

    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    $server = $env:PlexServer
    if (-not $server -or $server -match 'REPLACE_ME') {
        throw "PlexServer not set. Set `$env:PlexServer = 'host:32400' (or dot-source Set-PSEnvVars.ps1)."
    }
    if ($server -notmatch '^https?://') { $server = "http://$server" }
    $server.TrimEnd('/')
}

function Get-PlexClientId {
    [CmdletBinding()]
    param()

    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    # Derived rather than stored: the same ID on every run for this computer and user,
    # so sign-ins reuse one device entry on the Plex account. Reveals neither name.
    $seed = "PSPlexScripts|$([Environment]::MachineName)|$([Environment]::UserName)"
    $hash = [Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($seed))
    'psplexscripts-' + [Convert]::ToHexString($hash, 0, 8).ToLowerInvariant()
}

function Get-PlexHeader {
    [CmdletBinding()]
    param(
        # Leave out the token, for the plex.tv sign-in call.
        [switch]$NoToken
    )

    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    $headers = @{
        Accept                     = 'application/json'
        'X-Plex-Client-Identifier' = Get-PlexClientId
        'X-Plex-Product'           = 'PSPlexScripts'
        'X-Plex-Version'           = '2.0'
        'X-Plex-Device-Name'       = 'PSPlexScripts'
        'X-Plex-Platform'          = 'PowerShell'
        'X-Plex-Platform-Version'  = "$($PSVersionTable.PSVersion)"
    }
    if (-not $NoToken) {
        $token = $env:PlexToken
        if (-not $token -or $token -match 'REPLACE_ME') {
            throw 'PlexToken not set. Dot-source Set-PSEnvVars.ps1 first, or run Get-PlexToken.ps1.'
        }
        $headers['X-Plex-Token'] = $token
    }
    $headers
}

function ConvertFrom-PlexJson {
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Json)

    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    if (-not $Json) { return $null }
    # Item metadata has keys that differ only in case: "guid" (the plex:// GUID) and
    # "Guid" (agent IDs), "rating" (critic score) and "Rating" (the ratings list).
    # PowerShell's JSON parser is case-insensitive and rejects that, so each lowercase
    # key that clashes with a capitalised one gets a "plex" prefix: plexGuid, plexRating.
    $capitalised = [regex]::Matches($Json, '"([A-Z][A-Za-z]*)"\s*:') | ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique
    foreach ($name in $capitalised) {
        $lower = $name.ToLowerInvariant()
        $Json = $Json -creplace "`"$lower`"(\s*:)", "`"plex$name`"`$1"
    }
    $Json | ConvertFrom-Json -Depth 100
}

function Invoke-PlexApi {
    [CmdletBinding()]
    param(
        # Path and query string after the server URL, e.g. '/library/sections/1/all?resolution=720'.
        [Parameter(Mandatory)][string]$Path,
        [ValidateSet('Get', 'Put', 'Post', 'Delete')][string]$Method = 'Get',
        # Page through the results and return them as one MediaContainer.
        [switch]$All,
        [ValidateRange(1, 10000)][int]$PageSize = 1000
    )

    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    $baseUrl = Get-PlexServerUrl
    $headers = Get-PlexHeader

    $send = {
        param([string]$Uri, [hashtable]$ExtraHeaders)
        $request = @{ Method = $Method; Uri = $Uri; Headers = $headers + $ExtraHeaders }
        for ($attempt = 1; ; $attempt++) {
            try {
                return Invoke-WebRequest @request
            } catch [Microsoft.PowerShell.Commands.HttpResponseException] {
                $response = $_.Exception.Response
                $status = [int]$response.StatusCode
                # 429 is always safe to retry; 5xx only for GET, because a write may already have landed.
                $retryable = $status -eq 429 -or ($status -ge 500 -and $Method -eq 'Get')
                if (-not $retryable -or $attempt -ge 4) {
                    $hint = if ($status -eq 401) { ' Token rejected: run Get-PlexToken.ps1 and update PlexToken.' } else { '' }
                    throw "Plex $($Method.ToUpper()) $Path failed: $status $($response.ReasonPhrase).$hint"
                }
                $retryAfter = $response.Headers.RetryAfter
                $delay = if ($retryAfter -and $retryAfter.Delta) { [int]$retryAfter.Delta.TotalSeconds } else { [math]::Pow(2, $attempt) }
                Start-Sleep -Seconds ([math]::Min($delay, 60))
            }
        }
    }

    if (-not $All) {
        return ConvertFrom-PlexJson -Json (& $send "$baseUrl$Path" @{}).Content
    }

    # Paging uses X-Plex-Container-Start/Size headers; the reply's totalSize says when to stop.
    $result = $null
    $items = [Collections.Generic.List[object]]::new()
    $start = 0
    do {
        $page = ConvertFrom-PlexJson -Json (& $send "$baseUrl$Path" @{
                'X-Plex-Container-Start' = "$start"
                'X-Plex-Container-Size'  = "$PageSize"
            }).Content
        $container = $page.MediaContainer
        if (-not $result) { $result = $page }
        $listName = @('Metadata', 'Directory', 'Hub') | Where-Object { $container.PSObject.Properties[$_] } | Select-Object -First 1
        $got = @(if ($listName) { $container.$listName })
        foreach ($item in $got) { $items.Add($item) }
        $total = if ($container.PSObject.Properties['totalSize']) { [int]$container.totalSize } else { $items.Count }
        $start += $PageSize
    } while ($got.Count -gt 0 -and $items.Count -lt $total)

    if ($listName) { $result.MediaContainer.$listName = $items.ToArray() }
    $result.MediaContainer.size = $items.Count
    $result
}

function Get-PlexItem {
    [CmdletBinding()]
    param([Parameter(Mandatory, ValueFromPipeline)][AllowNull()][object]$Response)

    process {
        # A container with no results has no Metadata/Directory property at all, which
        # StrictMode would trip over. Emits nothing in that case.
        if (-not $Response -or -not $Response.PSObject.Properties['MediaContainer']) { return }
        $container = $Response.MediaContainer
        foreach ($name in 'Metadata', 'Directory', 'Hub') {
            if ($container.PSObject.Properties[$name]) { $container.$name; return }
        }
    }
}

function Get-PlexSection {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Name)

    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    $sections = (Invoke-PlexApi -Path '/library/sections').MediaContainer.Directory
    $match = $sections | Where-Object { $_.title -eq $Name -or $_.key -eq $Name }
    if (-not $match) {
        throw "No Plex library called '$Name'. Libraries: $(($sections.title | Sort-Object) -join ', ')"
    }
    @($match)[0]
}
