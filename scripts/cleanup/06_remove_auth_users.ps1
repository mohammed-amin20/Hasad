# =====================================================================
# Hasad ERP V2 - DEV CLEANUP SCRIPT 06: Auth-user DRY_RUN preflight
# =====================================================================
# Target : Supabase DEV project sxasnunzspkuwbxiddqd
# Status : DRY_RUN ONLY. This script contains no deletion or EXECUTE path.
# Method : Supported Supabase Auth Admin getUserById endpoint (HTTP GET).
# Safety : Reads exactly four UUIDs only from the private, git-ignored Stage 5
#          audit output. It never logs UUIDs, user data, raw API responses,
#          credentials, tokens, or request errors. No SQL is used.
# =====================================================================

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNull()]
    [System.Security.SecureString]$ServiceRoleKey,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$SupabaseUrl,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$ProjectRef
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ExpectedProjectRef = 'sxasnunzspkuwbxiddqd'
$ExpectedHost = "$ExpectedProjectRef.supabase.co"
$AuditAttestation = 'STAGE5_AUTH_ID_AUDIT_SXASNUNZSPKUWBXIDDQD_COMPLETE'
$AuditVerdict = 'exact_count=4; mapping=complete_unique; no_personal_fields_selected'
$AuditPath = Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'local_audit\DEV_STAGE5_AUTH_IDS_20261025_210115.txt'

function Write-SafeLog {
    param([Parameter(Mandatory = $true)][string]$Message)
    Write-Host $Message
}

function Stop-Safe {
    param([Parameter(Mandatory = $true)][string]$Message)
    Write-SafeLog "AUTH DRY_RUN FAILED: $Message"
    exit 1
}

function Get-RedactedAuthRequestFailure {
    param([Parameter(Mandatory = $true)][System.Management.Automation.ErrorRecord]$ErrorRecord)

    # PowerShell 5 and 7 expose HTTP failures through different exception
    # types. Extract only the numeric status; never surface the exception,
    # endpoint, response body, headers, or target identifier.
    $StatusCode = $null
    $ResponseProperty = $ErrorRecord.Exception.PSObject.Properties['Response']
    $Response = if ($null -ne $ResponseProperty) { $ResponseProperty.Value } else { $null }
    $StatusProperty = if ($null -ne $Response) { $Response.PSObject.Properties['StatusCode'] } else { $null }
    if ($null -ne $StatusProperty -and $null -ne $StatusProperty.Value) {
        try { $StatusCode = [int]$StatusProperty.Value } catch { $StatusCode = $null }
    }
    if ($null -ne $StatusCode) {
        switch ($StatusCode) {
            { $_ -in 401, 403 } { return "credential or authorization failure (HTTP $StatusCode)" }
            404                { return 'target user missing (HTTP 404)' }
            429                { return 'rate limited (HTTP 429)' }
            default            { return "unexpected HTTP status (HTTP $StatusCode)" }
        }
    }

    $WebException = $ErrorRecord.Exception
    while ($null -ne $WebException -and -not ($WebException -is [System.Net.WebException])) {
        $WebException = $WebException.InnerException
    }
    if ($WebException -is [System.Net.WebException]) {
        switch ($WebException.Status) {
            ([System.Net.WebExceptionStatus]::NameResolutionFailure) { return 'DNS failure (no HTTP status)' }
            ([System.Net.WebExceptionStatus]::TrustFailure)          { return 'TLS failure (no HTTP status)' }
            ([System.Net.WebExceptionStatus]::Timeout)               { return 'timeout failure (no HTTP status)' }
            ([System.Net.WebExceptionStatus]::ConnectFailure)        { return 'network connection failure (no HTTP status)' }
            default                                                   { return 'network/TLS/DNS/timeout failure (no HTTP status)' }
        }
    }
    if ($ErrorRecord.Exception -is [System.Threading.Tasks.TaskCanceledException]) {
        return 'timeout failure (no HTTP status)'
    }
    return 'network/TLS/DNS/timeout failure (no HTTP status)'
}

function ConvertFrom-Base64UrlJson {
    param([Parameter(Mandatory = $true)][string]$Value)

    $Padded = $Value.Replace('-', '+').Replace('_', '/')
    switch ($Padded.Length % 4) {
        2 { $Padded += '==' }
        3 { $Padded += '=' }
        1 { throw 'invalid base64url length' }
    }
    return ([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($Padded)) | ConvertFrom-Json -ErrorAction Stop)
}

function Get-SupportedAdminCredentialType {
    param([Parameter(Mandatory = $true)][string]$Credential)

    # Return only non-sensitive classifications. Legacy service-role JWTs are
    # documented to require a service_role claim; a project-ref claim is not
    # guaranteed, so an absent ref is not rejected. A present mismatched ref is.
    if ($Credential -match '^sb_publishable_') {
        return 'publishable_or_anon'
    }
    if ($Credential -match '^sb_secret_') {
        if ($Credential -match '^sb_secret_[A-Za-z0-9_-]+$') {
            return 'secret_key'
        }
        return 'secret_key_rejected'
    }
    if ($Credential -notmatch '^eyJ[A-Za-z0-9_-]*\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$') {
        return 'unknown_format'
    }
    try {
        $Payload = ConvertFrom-Base64UrlJson -Value (($Credential -split '\.')[1])
    } catch {
        return 'jwt_wrong_service_role'
    }
    try {
        $RoleProperty = $Payload.PSObject.Properties['role']
        if ($null -eq $RoleProperty -or $RoleProperty.Value -ne 'service_role') {
            if ($null -ne $RoleProperty -and $RoleProperty.Value -eq 'anon') {
                return 'publishable_or_anon'
            }
            return 'jwt_wrong_service_role'
        }
        $RefProperty = $Payload.PSObject.Properties['ref']
        if ($null -ne $RefProperty -and
            ([string]::IsNullOrWhiteSpace([string]$RefProperty.Value) -or $RefProperty.Value -ne $ExpectedProjectRef)) {
            return 'jwt_project_ref_mismatch'
        }
        return 'legacy_service_role_jwt'
    } finally {
        Remove-Variable Payload -ErrorAction SilentlyContinue
    }

    # Unreachable; retained as a fail-closed guard if the logic is changed.
    return 'unknown_format'
}

if ($ProjectRef -cne $ExpectedProjectRef) {
    Stop-Safe 'project reference mismatch'
}

try {
    $BaseUri = [Uri]$SupabaseUrl
} catch {
    Stop-Safe 'Supabase URL is malformed'
}
if ($BaseUri.Scheme -ne 'https' -or $BaseUri.Host -cne $ExpectedHost -or
    -not [string]::IsNullOrEmpty($BaseUri.UserInfo) -or
    -not [string]::IsNullOrEmpty($BaseUri.Query) -or
    -not [string]::IsNullOrEmpty($BaseUri.Fragment)) {
    Stop-Safe 'Supabase URL does not identify the expected DEV project'
}

if ($ServiceRoleKey.Length -eq 0) {
    Stop-Safe 'credential is missing'
}
if (-not (Test-Path -LiteralPath $AuditPath -PathType Leaf)) {
    Stop-Safe 'private Stage 5 Auth-ID audit is missing'
}

try {
    $AuditText = Get-Content -LiteralPath $AuditPath -Raw -ErrorAction Stop
} catch {
    Stop-Safe 'private Stage 5 Auth-ID audit cannot be read'
}

if (([regex]::Matches($AuditText, [regex]::Escape($AuditAttestation))).Count -ne 1 -or
    ([regex]::Matches($AuditText, [regex]::Escape($AuditVerdict))).Count -ne 1 -or
    ([regex]::Matches($AuditText, 'linked_auth_user_id')).Count -ne 1 -or
    $AuditText -match '(?im)^\s*(ERROR|FATAL)\b') {
    Stop-Safe 'private Stage 5 Auth-ID audit attestation is invalid'
}

$UuidPattern = '(?i)(?<![0-9a-f])[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}(?![0-9a-f])'
$Ids = @([regex]::Matches($AuditText, $UuidPattern) | ForEach-Object { $_.Value.ToLowerInvariant() })
if ($Ids.Count -ne 4 -or @($Ids | Sort-Object -Unique).Count -ne 4) {
    Stop-Safe 'private Stage 5 Auth-ID audit does not contain exactly four unique UUIDs'
}

$SecretPtr = [IntPtr]::Zero
$PlainServiceRoleKey = $null
$Headers = $null
$CredentialType = $null
try {
    # Convert only in process memory. Secret keys are deliberately never sent
    # as Bearer tokens because they are opaque API keys, not JWTs.
    $SecretPtr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($ServiceRoleKey)
    $PlainServiceRoleKey = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($SecretPtr)
    if ([string]::IsNullOrEmpty($PlainServiceRoleKey)) {
        Stop-Safe 'credential is missing'
    }
    $CredentialType = Get-SupportedAdminCredentialType -Credential $PlainServiceRoleKey
    switch ($CredentialType) {
        'secret_key'               { break }
        'legacy_service_role_jwt'  { break }
        'publishable_or_anon'      { Stop-Safe 'publishable/anon key is not suitable for Auth Admin' }
        'secret_key_rejected'      { Stop-Safe 'recognized sb_secret key was rejected by local validation' }
        'jwt_wrong_service_role'   { Stop-Safe 'JWT-shaped key has wrong or missing service_role claim' }
        'jwt_project_ref_mismatch' { Stop-Safe 'JWT-shaped key has a mismatched project-ref claim' }
        default                    { Stop-Safe 'credential has an unknown format' }
    }
    $Headers = @{ apikey = $PlainServiceRoleKey; Accept = 'application/json' }
    if ($CredentialType -eq 'legacy_service_role_jwt') {
        $Headers.Authorization = "Bearer $PlainServiceRoleKey"
    }

    $VerifiedCount = 0
    foreach ($Id in $Ids) {
        $Endpoint = "$($BaseUri.AbsoluteUri.TrimEnd('/'))/auth/v1/admin/users/$Id"
        try {
            $Response = Invoke-RestMethod -Method Get -Uri $Endpoint -Headers $Headers -TimeoutSec 30 -ErrorAction Stop
        } catch {
            Stop-Safe (Get-RedactedAuthRequestFailure -ErrorRecord $_)
        }
        if ($null -eq $Response -or $null -eq $Response.id -or $Response.id.ToString().ToLowerInvariant() -cne $Id) {
            Stop-Safe 'Auth Admin preflight response did not verify a target user'
        }
        $VerifiedCount++
        Remove-Variable Response -ErrorAction SilentlyContinue
    }

    if ($VerifiedCount -ne 4) {
        Stop-Safe 'target-user verification count mismatch'
    }
    Write-SafeLog "AUTH DRY_RUN PASSED: project=$ExpectedProjectRef; verified_users=$VerifiedCount/4; no deletion attempted"
} finally {
    if ($SecretPtr -ne [IntPtr]::Zero) {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($SecretPtr)
    }
    Remove-Variable PlainServiceRoleKey, Headers, CredentialType, AuditText, Ids -ErrorAction SilentlyContinue
}
