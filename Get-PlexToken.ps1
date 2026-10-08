#Requires -Version 7.0
<#
.SYNOPSIS
    Signs in to plex.tv and returns an X-Plex-Token for the scripts in this folder.

.DESCRIPTION
    POSTs to https://plex.tv/api/v2/users/signin (the old /users/sign_in.xml endpoint is
    retired) with your Plex account username or email and password, plus the current
    6-digit code if the account has two-factor authentication.

    Each sign-in uses the same client identifier (see Get-PlexClientId in .PlexApi.ps1),
    so it shows up as one "PSPlexScripts" device under Authorized Devices on plex.tv.
    Removing that device revokes the token.

    The token is written to the output stream only. Put it in PlexToken in your
    environment (Set-PSEnvVars.ps1) and your password manager; never commit it.

.PARAMETER Credential
    Plex account username or email and password. Prompted for if not given.

.PARAMETER VerificationCode
    Current two-factor code. Prompted for when the account needs one and none was given.

.EXAMPLE
    $env:PlexToken = .\Get-PlexToken.ps1

.EXAMPLE
    .\Get-PlexToken.ps1 -Credential (Get-Credential hdurdle) -VerificationCode 123456
#>
[CmdletBinding()]
param(
    [pscredential]$Credential,
    [ValidatePattern('^\d{6}$')][string]$VerificationCode
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. "$PSScriptRoot/.PlexApi.ps1"

if (-not $Credential) { $Credential = Get-Credential -Message 'Plex account (username or email)' }

$signIn = {
    param([string]$Code)
    $body = @{
        login      = $Credential.UserName
        password   = $Credential.GetNetworkCredential().Password
        rememberMe = 'true'
    }
    if ($Code) { $body.verificationCode = $Code }
    Invoke-RestMethod -Method Post -Uri 'https://plex.tv/api/v2/users/signin' -Headers (Get-PlexHeader -NoToken) -Body $body
}

try {
    $user = & $signIn $VerificationCode
} catch [Microsoft.PowerShell.Commands.HttpResponseException] {
    $status = [int]$_.Exception.Response.StatusCode
    # 401 with no code on a 2FA account: ask for the code and try once more.
    if ($status -eq 401 -and -not $VerificationCode) {
        $VerificationCode = Read-Host 'Two-factor code (blank if the account has none)'
        if (-not $VerificationCode) { throw 'Plex sign-in failed: 401 Unauthorized. Check the username and password.' }
        $user = & $signIn $VerificationCode
    } else {
        throw "Plex sign-in failed: $status $($_.Exception.Response.ReasonPhrase)."
    }
}

if (-not $user.authToken) { throw 'Plex sign-in succeeded but returned no token.' }
Write-Verbose "Signed in as $($user.username)"
$user.authToken
