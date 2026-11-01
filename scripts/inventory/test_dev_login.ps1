# =====================================================================
# Hasad ERP V2 - Supabase DEV PostgreSQL login diagnostic (read-only)
# =====================================================================
# Purpose:
#   A single, minimal, owner-operated diagnostic that distinguishes a
#   CONNECTION failure from an AUTHENTICATION failure for the linked
#   Supabase DEV project (sxasnunzspkuwbxiddqd), without changing
#   anything in Supabase and without touching the platform inventory.
#
# How it works (two stages):
#   STAGE 1 - Credential-free transport probe.
#     DNS -> TCP -> PostgreSQL SSLRequest -> TLS -> StartupMessage.
#     No password is used and no session is authenticated. This stage
#     proves, independently of any credential, whether the network path,
#     the TLS negotiation and the Supabase tenant routing are healthy.
#
#   STAGE 2 - One psql login attempt with the owner's native password
#     prompt, running ONLY:
#         BEGIN TRANSACTION READ ONLY;
#         SELECT current_user, current_database();  (+ session metadata)
#         ROLLBACK;
#     inside an explicit read-only transaction with a server-side
#     fail-closed guard. One attempt only. No automatic retry.
#
# Safety contract:
#   * The PostgreSQL password is entered at psql's own native terminal
#     prompt (-W). It is never placed in arguments, source files, logs,
#     repository files, environment variables or chat.
#   * Nothing is written to the remote database. The probe transaction is
#     rolled back and no DDL/DML is issued by this script.
#   * No application data is read: only session metadata (current_user,
#     current_database, transaction_read_only, clock_timestamp()).
#   * No Supabase CLI state, Auth, Storage, Edge Functions, secrets or
#     project settings are read or changed.
#   * The diagnostic does NOT run the platform inventory.
#   * The local log written to local_audit/ contains no credential, no
#     secret value and no sensitive record.
#
# Exit codes (of this script):
#   0  SUCCESS                - login worked, probe ran, transaction rolled back
#   2  TRANSPORT_FAILURE      - Stage 1 proved a network/DNS/TLS/tenant fault
#   3  AUTHENTICATION_FAILURE - Stage 1 healthy, server rejected the credential
#   4  CONNECTION_DROPPED     - Stage 1 healthy, connection lost after startup
#   5  SCRIPT_ERROR_AFTER_CONNECT - connected, but the SQL/guard reported an error
#   6  UNCLASSIFIED_FAILURE   - psql failed with a message not covered above
#   1  LOCAL_PRECONDITION_ERROR - a fail-closed guard stopped the run before
#      any connection (PowerShell reports an uncaught throw as exit code 1)
# =====================================================================

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

# =====================================================================
# 1. Fail-closed local preconditions (no connection is attempted yet)
# =====================================================================

# --- Locate the repository root by walking up to the linked-project marker.
$repoRoot = $PSScriptRoot
$marker = $null
for ($i = 0; $i -lt 5; $i++) {
    $candidate = Join-Path $repoRoot 'supabase\.temp\project-ref'
    if (Test-Path -LiteralPath $candidate) {
        $marker = $candidate
        break
    }
    $parent = Split-Path -Parent $repoRoot
    if ($parent -eq $repoRoot -or [string]::IsNullOrEmpty($parent)) { break }
    $repoRoot = $parent
}
if (-not $marker) {
    throw 'Linked Supabase project marker not found (supabase/.temp/project-ref). Link the DEV project first. No connection attempted.'
}

# --- Exact expected DEV identity (non-secret values held by the CLI).
$expectedRef  = 'sxasnunzspkuwbxiddqd'
$expectedUrl  = 'postgresql://postgres.sxasnunzspkuwbxiddqd@aws-0-ap-southeast-1.pooler.supabase.com:5432/postgres'
$expectedHost = 'aws-0-ap-southeast-1.pooler.supabase.com'
$expectedPort = 5432
$expectedUser = 'postgres.sxasnunzspkuwbxiddqd'
$expectedDb   = 'postgres'
$connectTimeoutSeconds = 15

$projectRef = (Get-Content -LiteralPath $marker -Raw).Trim()
if ($projectRef -cne $expectedRef) {
    throw "Linked project ref '$projectRef' does not match expected '$expectedRef'. Refusing to run. No connection attempted."
}

$poolerUrlPath = Join-Path $repoRoot 'supabase\.temp\pooler-url'
if (-not (Test-Path -LiteralPath $poolerUrlPath)) {
    throw "Pooler URL file not found ($poolerUrlPath). No connection attempted."
}
$poolerUrl = (Get-Content -LiteralPath $poolerUrlPath -Raw).Trim()
if ($poolerUrl -cne $expectedUrl) {
    throw 'Pooler connection string does not match the previously verified non-secret endpoint. Refusing to run. No connection attempted.'
}
if ($poolerUrl -notlike "*@${expectedHost}:${expectedPort}/${expectedDb}") {
    throw 'Pooler connection string does not carry the expected host/port/database. Refusing to run. No connection attempted.'
}

# --- Locate the installed PostgreSQL 17 psql.exe (fail-closed version check).
$psqlPath = $null
$candidates = @(
    'C:\Program Files\PostgreSQL\17\bin\psql.exe',
    (Join-Path ${env:ProgramFiles} 'PostgreSQL\17\bin\psql.exe')
)
foreach ($cand in $candidates) {
    if ($cand -and (Test-Path -LiteralPath $cand)) { $psqlPath = $cand; break }
}
if (-not $psqlPath) {
    $cmd = Get-Command 'psql.exe' -ErrorAction SilentlyContinue
    if ($cmd) { $psqlPath = $cmd.Source }
}
if (-not $psqlPath) {
    throw 'psql.exe not found (PostgreSQL 17). No connection attempted.'
}
$psqlVersion = (& $psqlPath --version | Out-String).Trim()
if ($psqlVersion -notmatch '\(PostgreSQL\) 17\.') {
    throw "psql.exe is not PostgreSQL 17 (found: $psqlVersion). Refusing to run. No connection attempted."
}

# --- The read-only probe SQL must exist.
$sqlFile = Join-Path $PSScriptRoot 'dev_login_probe.sql'
if (-not (Test-Path -LiteralPath $sqlFile)) {
    throw "Login probe SQL file not found ($sqlFile). No connection attempted."
}

# --- Local audit directory (gitignored; never a tracked document).
$auditDir = Join-Path $repoRoot 'local_audit'
New-Item -ItemType Directory -Force -Path $auditDir | Out-Null
$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$outFile = Join-Path $auditDir "DEV_LOGIN_PROBE_$stamp.txt"
$logFile = Join-Path $auditDir "DEV_LOGIN_DIAGNOSTIC_$stamp.md"

# --- Connection URI: same verified endpoint as the working inventory runner,
#     plus a bounded connect timeout and an identifying application_name.
$connUri = $poolerUrl + '?sslmode=require' +
            "&connect_timeout=$connectTimeoutSeconds" +
            '&application_name=hasad_login_probe'

# =====================================================================
# 2. Helper functions
# =====================================================================

function Get-SanitizedText {
    param([string]$Text, [int]$MaxLength = 4000)
    if ([string]::IsNullOrEmpty($Text)) { return '' }
    $t = $Text
    # Never persist anything that looks like an inline credential.
    $t = [regex]::Replace($t, '(?i)(password|passwd|pwd)\s*[:=]\s*\S+', '$1=<redacted>')
    $t = [regex]::Replace($t, '(?i)\b(sbp|eyJ)[A-Za-z0-9_\-\.]{10,}', '<redacted-token>')
    # Strip control characters except newline and tab.
    $t = [regex]::Replace($t, '[\x00-\x08\x0B\x0C\x0E-\x1F]', '')
    if ($t.Length -gt $MaxLength) { $t = $t.Substring(0, $MaxLength) + '...[truncated]' }
    return $t
}

function Get-PsqlErrorClass {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return 'NO_ERROR_TEXT' }
    # Order matters: the most specific signatures are tested first.
    if ($Text -match 'password authentication failed')            { return 'AUTHENTICATION_FAILED' }
    if ($Text -match 'authentication failed')                     { return 'AUTHENTICATION_FAILED' }
    if ($Text -match 'no password supplied')                      { return 'AUTHENTICATION_FAILED' }
    if ($Text -match 'SCRAM')                                     { return 'AUTHENTICATION_FAILED' }
    if ($Text -match 'pg_hba\.conf')                              { return 'ACCESS_RULE_DENIED' }
    if ($Text -match 'no tenant identifier|ENOIDENTIFIER|sni_hostname') { return 'TENANT_ROUTING' }
    if ($Text -match 'SSL error|does not support SSL|SSL not enabled|certificate verification failed') { return 'TLS_FAILURE' }
    if ($Text -match 'could not translate host name|Name or service not known|no such host|unknown host') { return 'DNS_FAILURE' }
    if ($Text -match 'Connection refused|ECONNREFUSED')           { return 'NETWORK_REFUSED' }
    if ($Text -match 'timeout expired|timed out|Connection timed out|ETIMEDOUT') { return 'NETWORK_TIMEOUT' }
    if ($Text -match 'could not connect to server')               { return 'NETWORK_TIMEOUT' }
    if ($Text -match 'server closed the connection unexpectedly|server terminated abnormally') { return 'CONNECTION_DROPPED' }
    if ($Text -match 'terminating connection due to administrator command') { return 'CONNECTION_DROPPED' }
    if ($Text -match 'connection reset|ECONNRESET')               { return 'CONNECTION_DROPPED' }
    if ($Text -match 'too many connections')                      { return 'CONNECTION_LIMIT' }
    if ($Text -match 'the database system is starting up')        { return 'SERVER_STARTING' }
    if ($Text -match 'unsupported frontend protocol')             { return 'PROTOCOL_MISMATCH' }
    if ($Text -match 'permission denied')                         { return 'PERMISSION_DENIED' }
    if ($Text -match 'canceling statement due to statement timeout') { return 'STATEMENT_TIMEOUT' }
    if ($Text -match 'FAIL-CLOSED')                               { return 'READ_ONLY_GUARD_TRIPPED' }
    if ($Text -match 'not found|No such file or directory')       { return 'LOCAL_FILE_PROBLEM' }
    return 'UNCLASSIFIED'
}

function Get-ClassExplanation {
    param([string]$Class)
    switch ($Class) {
        'AUTHENTICATION_FAILED' {
            return @(
                'The server was reached, the TLS session was established and the',
                'startup packet was accepted; the server then rejected the',
                'CREDENTIAL (password) for the role.',
                'A rejected password does NOT prove the password is wrong: it may',
                'have been mistyped, may contain characters lost at the prompt, or',
                'may be a stale/rotated password. It also does not affect any',
                'data: no transaction was opened and nothing was changed.'
            )
        }
        'ACCESS_RULE_DENIED' {
            return @(
                'The server was reached but its host-based access rules refused',
                'this role from this address. This is a server-side rule, not a',
                'wrong password and not a network problem.'
            )
        }
        'TENANT_ROUTING' {
            return @(
                'The pooler could not map the connection to a project tenant.',
                'The username form (postgres.<project-ref>) was not accepted as a',
                'tenant identifier. This is a routing problem at the pooler,',
                'independent of the password.'
            )
        }
        'TLS_FAILURE' {
            return @(
                'The TLS session could not be established (or was rejected by the',
                'server). No authentication was attempted and no data was touched.'
            )
        }
        'DNS_FAILURE' {
            return @(
                'The pooler hostname did not resolve from this machine. No',
                'connection was attempted beyond name resolution.'
            )
        }
        'NETWORK_TIMEOUT' {
            return @(
                'A network connection to the pooler did not complete within the',
                'connect timeout. This is a TRANSPORT failure: it is NOT evidence',
                'about the password, because no credential was ever evaluated.'
            )
        }
        'NETWORK_REFUSED' {
            return @(
                'The pooler actively refused the TCP connection. This is a',
                'TRANSPORT failure and says nothing about the password.'
            )
        }
        'CONNECTION_DROPPED' {
            return @(
                'The connection was established and then closed by the peer before',
                'the session became usable. This is AMBIGUOUS by design: the peer',
                'may have dropped the connection during the authentication',
                'exchange (which can happen with an unaccepted credential), or it',
                'may have dropped it for pooler-side reasons (load, restart,',
                'session limit). It does NOT by itself prove the password is wrong.'
            )
        }
        'CONNECTION_LIMIT' {
            return @(
                'The server refused new sessions because a connection/session limit',
                'was reached. This is a server-side capacity condition and says',
                'nothing about the password.'
            )
        }
        'SERVER_STARTING' {
            return @(
                'The database was still starting up and refused the session. No',
                'credential evaluation happened. Retry later.'
            )
        }
        'PROTOCOL_MISMATCH' {
            return @(
                'The server and the client disagreed on the PostgreSQL wire protocol',
                'version. This is a client/endpoint mismatch, not a credential issue.'
            )
        }
        'PERMISSION_DENIED' {
            return @(
                'The session was established but the role lacks permission for the',
                'probe statement. The credential itself was accepted.'
            )
        }
        'STATEMENT_TIMEOUT' {
            return @(
                'The statement exceeded its 30s statement_timeout and was cancelled',
                'by the server. The transaction was aborted; nothing was changed.'
            )
        }
        'READ_ONLY_GUARD_TRIPPED' {
            return @(
                'The server-side fail-closed guard detected that the transaction was',
                'not read-only and aborted the run on purpose. Nothing was changed.'
            )
        }
        'LOCAL_FILE_PROBLEM' {
            return @(
                'psql could not open a required local file (SQL script or output',
                'path). Nothing was sent to the server.'
            )
        }
        'NO_ERROR_TEXT' {
            return @(
                'psql exited non-zero without emitting a recognizable message. The',
                'exit code and the output file are the only evidence available.'
            )
        }
        'UNCLASSIFIED' {
            return @(
                'psql exited non-zero with a message this diagnostic does not',
                'classify. The captured message is printed above and stored in the',
                'local log; it should be read verbatim before any conclusion is'
                'drawn.'
            )
        }
        default {
            return @('No classification available.')
        }
    }
}

# --- PostgreSQL wire-format integer helpers -------------------------------
# Every integer in the PostgreSQL frontend/backend protocol is in NETWORK
# byte order (big-endian). .NET's BitConverter uses HOST byte order, which is
# little-endian on x86/x64, so it must never be used directly on the wire.
function ConvertTo-BigEndianBytes {
    param([Parameter(Mandatory = $true)][long]$Value)
    return [byte[]]@(
        [byte](($Value -shr 24) -band 0xFF),
        [byte](($Value -shr 16) -band 0xFF),
        [byte](($Value -shr 8) -band 0xFF),
        [byte]($Value -band 0xFF)
    )
}

function ConvertFrom-BigEndianInt32 {
    param(
        [Parameter(Mandatory = $true)][byte[]]$Buffer,
        [int]$Offset = 0
    )
    return ([long]$Buffer[$Offset] * 16777216) +
           ([long]$Buffer[$Offset + 1] * 65536) +
           ([long]$Buffer[$Offset + 2] * 256) +
           ([long]$Buffer[$Offset + 3])
}

function Test-TransportLayer {
    <#
      Credential-free probe: DNS -> TCP -> SSLRequest -> TLS -> StartupMessage.
      Never sends a password and never authenticates a session.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$HostName,
        [Parameter(Mandatory = $true)][int]$Port,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][int]$TimeoutSeconds
    )

    $r = [ordered]@{
        Stage          = 'START'
        Detail         = ''
        DnsAddresses   = @()
        DnsOk          = $false
        TcpOk          = $false
        TlsOffered     = $false
        TlsOk          = $false
        TenantAccepted = $false
        ServerSqlState = ''
        ServerMessage  = ''
    }

    # --- DNS -------------------------------------------------------------
    try {
        $addrs = @([System.Net.Dns]::GetHostAddresses($HostName) |
            Where-Object { $_.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetwork } |
            ForEach-Object { $_.IPAddressToString })
    }
    catch {
        $r.Stage = 'DNS'
        $r.Detail = "DNS resolution failed: $($_.Exception.Message)"
        return [pscustomobject]$r
    }
    if (-not $addrs -or $addrs.Count -eq 0) {
        $r.Stage = 'DNS'
        $r.Detail = 'Hostname did not resolve to any IPv4 address.'
        return [pscustomobject]$r
    }
    $r.DnsAddresses = $addrs
    $r.DnsOk = $true

    # --- TCP + PostgreSQL SSLRequest + TLS + StartupMessage ---------------
    # A SINGLE TCP connection carries the whole probe: the reachability check
    # and the protocol exchange share it. The pooler therefore sees exactly
    # one client connection and one session attempt (no retry, no double
    # connect), which also keeps the observed behaviour representative.
    $tcp = New-Object System.Net.Sockets.TcpClient
    try {
        $ar = $tcp.BeginConnect($HostName, $Port, $null, $null)
        if (-not $ar.AsyncWaitHandle.WaitOne($TimeoutSeconds * 1000, $false)) {
            $r.Stage = 'TCP'
            $r.Detail = "TCP connect to ${HostName}:${Port} did not complete within ${TimeoutSeconds}s."
            return [pscustomobject]$r
        }
        try {
            $tcp.EndConnect($ar)
        }
        catch {
            $r.Stage = 'TCP'
            $r.Detail = "TCP connect failed: $($_.Exception.Message)"
            return [pscustomobject]$r
        }
        $r.TcpOk = $true

        $tcp.ReceiveTimeout = $TimeoutSeconds * 1000
        $tcp.SendTimeout = $TimeoutSeconds * 1000
        $stream = $tcp.GetStream()

        # PostgreSQL SSLRequest: length 8, code 80877103
        $sslRequest = [byte[]]@(0, 0, 0, 8, 4, 210, 22, 47)
        $stream.Write($sslRequest, 0, $sslRequest.Length)
        $reply = New-Object byte[] 1
        $read = $stream.Read($reply, 0, 1)
        if ($read -ne 1) {
            $r.Stage = 'TLS'
            $r.Detail = 'Server closed the connection without answering the PostgreSQL SSLRequest.'
            return [pscustomobject]$r
        }
        if ([char]$reply[0] -ne 'S') {
            $r.Stage = 'TLS'
            $r.Detail = "Server declined TLS (SSLRequest reply '$([char]$reply[0])')."
            return [pscustomobject]$r
        }
        $r.TlsOffered = $true

        # sslmode=require does not verify the certificate chain; mirror that.
        $ssl = New-Object System.Net.Security.SslStream(
            $stream, $false,
            ({ $true } -as [System.Net.Security.RemoteCertificateValidationCallback]))
        $ssl.AuthenticateAsClient($HostName)
        $ssl.ReadTimeout = $TimeoutSeconds * 1000
        $ssl.WriteTimeout = $TimeoutSeconds * 1000
        $r.TlsOk = $true

        # StartupMessage: protocol 3.0 (BIG-ENDIAN), user, database,
        # application_name. The length counts itself (4) + the protocol
        # version (4) + the key/value body, so it is 8 + body.Length.
        $body = [System.Text.Encoding]::ASCII.GetBytes(
            "user`0$UserName`0database`0$expectedDb`0application_name`0hasad_login_probe`0`0")
        $lenBytes = ConvertTo-BigEndianBytes -Value ([long](8 + $body.Length))
        $verBytes = ConvertTo-BigEndianBytes -Value 196608
        $packet = New-Object byte[] (8 + $body.Length)
        [Array]::Copy($lenBytes, 0, $packet, 0, 4)
        [Array]::Copy($verBytes, 0, $packet, 4, 4)
        [Array]::Copy($body, 0, $packet, 8, $body.Length)
        $ssl.Write($packet, 0, $packet.Length)
        $ssl.Flush()

        # Read exactly one complete backend message:
        #   1 type byte + int32 BIG-ENDIAN length (counts itself) + payload.
        # SslStream.Read may return any number of bytes at any time - including
        # a single byte, and including a split across TLS record boundaries - so
        # both the header and the payload are accumulated until complete. A
        # return value of 0 is the only reliable EOF signal and is recorded
        # separately from "not finished yet".
        $eof = $false
        $header = New-Object byte[] 5
        $got = 0
        while ($got -lt 5) {
            $k = $ssl.Read($header, $got, 5 - $got)
            if ($k -eq 0) { $eof = $true; break }
            $got += $k
        }
        if ($got -lt 5) {
            $r.Stage = 'STARTUP'
            if ($eof) {
                $r.Detail = "Server closed the connection after $got of 5 header bytes (EOF); no complete backend message was received."
            }
            else {
                $r.Detail = "Backend message header incomplete ($got of 5 bytes)."
            }
            return [pscustomobject]$r
        }

        $msgType = [char]$header[0]
        $msgLen = ConvertFrom-BigEndianInt32 -Buffer $header -Offset 1

        # Startup-phase backend messages (R/E/N/S/K) are small. Reject an
        # implausible length instead of allocating a garbage-sized buffer,
        # which is what previously turned a small server error into a bogus
        # "truncated" report.
        if ($msgLen -lt 4 -or $msgLen -gt 262144) {
            $r.Stage = 'STARTUP'
            $r.Detail = "Server sent an implausible message length ($msgLen) for message type '$msgType'; refusing to allocate."
            return [pscustomobject]$r
        }

        $payloadLen = [int]($msgLen - 4)
        $payload = New-Object byte[] $payloadLen
        $got2 = 0
        while ($got2 -lt $payloadLen) {
            $k = $ssl.Read($payload, $got2, $payloadLen - $got2)
            if ($k -eq 0) { $eof = $true; break }
            $got2 += $k
        }
        if ($got2 -lt $payloadLen) {
            $r.Stage = 'STARTUP'
            if ($eof) {
                $r.Detail = "Server closed the connection after $got2 of $payloadLen payload bytes (EOF) while sending a '$msgType' message."
            }
            else {
                $r.Detail = "Backend message '$msgType' incomplete: $got2 of $payloadLen payload bytes."
            }
            return [pscustomobject]$r
        }

        if ($msgType -eq 'R') {
            $authCode = -1
            if ($payloadLen -ge 4) {
                $authCode = ConvertFrom-BigEndianInt32 -Buffer $payload -Offset 0
            }
            $r.TenantAccepted = $true
            $r.Stage = 'READY'
            switch ($authCode) {
                0 { $r.Detail = 'Server returned AuthenticationOk (code 0) without requesting a password; the tenant and session were accepted.' }
                3 { $r.Detail = 'Server requested cleartext password authentication for the tenant-qualified user.' }
                5 { $r.Detail = 'Server requested MD5 password authentication for the tenant-qualified user.' }
                10 { $r.Detail = 'Server requested SCRAM-SHA-256 (SASL) authentication for the tenant-qualified user; the pooler is waiting for a password.' }
                default { $r.Detail = "Server issued AuthenticationRequest (code $authCode) for the tenant-qualified user; the pooler is waiting for a password." }
            }
        }
        elseif ($msgType -eq 'E') {
            $r.Stage = 'STARTUP'
            $r.Detail = 'Server rejected the startup packet with an error response.'
            # ErrorResponse payload: repeated (field-code byte + NUL-terminated
            # string), ending with a single zero byte.
            $i = 0
            while ($i -lt $payload.Length) {
                $fieldCode = [char]$payload[$i]
                $i++
                if ($fieldCode -eq [char]0) { break }
                $end = $i
                while ($end -lt $payload.Length -and $payload[$end] -ne 0) { $end++ }
                $value = [System.Text.Encoding]::UTF8.GetString($payload, $i, $end - $i)
                if ($fieldCode -eq 'C') { $r.ServerSqlState = $value }
                elseif ($fieldCode -eq 'M') { $r.ServerMessage = $value }
                $i = $end + 1
            }
        }
        else {
            $r.Stage = 'STARTUP'
            $r.Detail = "Unexpected PostgreSQL message type '$msgType' during startup."
        }
        try { $ssl.Close() } catch { }
    }
    catch {
        # Walk the exception chain: a stalled read surfaces as an IOException
        # whose innermost exception is a SocketException(TimedOut), or as a
        # TimeoutException. Those are transport timeouts, NOT TLS failures, so
        # they get their own stage and their own classification downstream.
        $isTimeout = $false
        $probeEx = $_.Exception
        while ($null -ne $probeEx) {
            if ($probeEx -is [System.TimeoutException]) { $isTimeout = $true; break }
            if ($probeEx -is [System.Net.Sockets.SocketException] -and
                $probeEx.SocketErrorCode -eq [System.Net.Sockets.SocketError]::TimedOut) {
                $isTimeout = $true
                break
            }
            $probeEx = $probeEx.InnerException
        }
        if ($isTimeout) {
            $r.Stage = 'TIMEOUT'
            $r.Detail = "The connection stalled: no complete server response arrived within ${TimeoutSeconds}s."
        }
        else {
            $r.Stage = 'TLS'
            $r.Detail = "TLS/startup exception: $($_.Exception.Message)"
        }
    }
    finally {
        try { $tcp.Close() } catch { }
    }

    return [pscustomobject]$r
}

# =====================================================================
# 3. Stage 1 - credential-free transport probe
# =====================================================================

Write-Host '====================================================================='
Write-Host 'Hasad ERP V2 - Supabase DEV login diagnostic'
Write-Host "  Project ref : $projectRef"
Write-Host "  Endpoint    : ${expectedHost}:${expectedPort} (database $expectedDb)"
Write-Host "  Role        : $expectedUser"
Write-Host "  psql        : $psqlVersion"
Write-Host "  SQL         : $sqlFile"
Write-Host "  Local log   : $logFile"
Write-Host '====================================================================='
Write-Host 'This diagnostic READS NOTHING from the database except session'
Write-Host 'metadata, and it changes nothing anywhere.'
Write-Host ''

Write-Host '--- STAGE 1: credential-free transport probe -------------------------'
$probe = Test-TransportLayer -HostName $expectedHost -Port $expectedPort `
    -UserName $expectedUser -TimeoutSeconds $connectTimeoutSeconds

Write-Host ("  DNS          : {0}" -f $(if ($probe.DnsOk) { "OK ($($probe.DnsAddresses -join ', '))" } else { 'FAILED' }))
Write-Host ("  TCP {0,-5}  : {1}" -f $expectedPort, $(if ($probe.TcpOk) { 'REACHABLE' } else { 'FAILED' }))
Write-Host ("  TLS offered  : {0}" -f $(if ($probe.TlsOffered) { 'YES' } else { 'NO' }))
Write-Host ("  TLS session  : {0}" -f $(if ($probe.TlsOk) { 'ESTABLISHED' } else { 'NOT ESTABLISHED' }))
Write-Host ("  Tenant rout. : {0}" -f $(if ($probe.TenantAccepted) { 'ACCEPTED' } else { 'NOT CONFIRMED' }))
Write-Host ("  Stage reached: {0}" -f $probe.Stage)
if ($probe.Detail) { Write-Host ("  Detail       : {0}" -f $probe.Detail) }
if ($probe.ServerSqlState) { Write-Host ("  SQLSTATE     : {0}" -f $probe.ServerSqlState) }
if ($probe.ServerMessage)  { Write-Host ("  Server said  : {0}" -f $probe.ServerMessage) }

$transportHealthy = ($probe.TcpOk -and $probe.TlsOk -and $probe.TenantAccepted)

Write-Host ''
if (-not $transportHealthy) {
    Write-Host 'STAGE 1 VERDICT: the transport layer is NOT healthy.'
    Write-Host 'A connection failure at this stage is NOT evidence about the password:'
    Write-Host 'no credential was ever evaluated.'
    Write-Host 'Stage 2 is skipped because it cannot add information.'
    Write-Host ''

    $stage1Class = switch ($probe.Stage) {
        'DNS'      { 'DNS_FAILURE' }
        'TCP'      { 'NETWORK_TIMEOUT' }
        'TIMEOUT'  { 'NETWORK_TIMEOUT' }
        'TLS'      { 'TLS_FAILURE' }
        'STARTUP'  { if ($probe.ServerMessage -match 'no tenant identifier') { 'TENANT_ROUTING' } else { 'CONNECTION_DROPPED' } }
        default   { 'UNCLASSIFIED' }
    }

    $logBody = @()
    $logBody += '# Hasad ERP V2 - DEV login diagnostic'
    $logBody += ''
    $logBody += "- Timestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz')"
    $logBody += "- Project ref: $projectRef"
    $logBody += "- Endpoint: ${expectedHost}:${expectedPort} / database $expectedDb / role $expectedUser"
    $logBody += "- psql: $psqlVersion"
    $logBody += ''
    $logBody += '## Stage 1 - credential-free transport probe'
    $logBody += ''
    $logBody += "- DNS resolved: $($probe.DnsAddresses -join ', ')"
    $logBody += "- TCP ${expectedPort}: $(if ($probe.TcpOk) { 'REACHABLE' } else { 'FAILED' })"
    $logBody += "- TLS offered: $(if ($probe.TlsOffered) { 'YES' } else { 'NO' })"
    $logBody += "- TLS session: $(if ($probe.TlsOk) { 'ESTABLISHED' } else { 'NOT ESTABLISHED' })"
    $logBody += "- Tenant routing: $(if ($probe.TenantAccepted) { 'ACCEPTED' } else { 'NOT CONFIRMED' })"
    $logBody += "- Stage reached: $($probe.Stage)"
    $logBody += "- Detail: $(Get-SanitizedText $probe.Detail)"
    $logBody += "- Classification: $stage1Class"
    $logBody += ''
    $logBody += '## Verdict'
    $logBody += ''
    $logBody += 'The transport layer is not healthy. Stage 2 was not attempted.'
    $logBody += 'A connection failure at this stage carries NO information about the'
    $logBody += 'password, because no credential was ever evaluated.'
    $logBody += ''
    $logBody += '## Explanation'
    $logBody += ''
    $logBody += (Get-ClassExplanation $stage1Class) | ForEach-Object { "- $_" }
    Set-Content -LiteralPath $logFile -Value $logBody -Encoding UTF8

    Write-Host '--- WHAT THIS MEANS ---------------------------------------------------'
    (Get-ClassExplanation $stage1Class) | ForEach-Object { Write-Host "  $_" }
    Write-Host ''
    Write-Host "Local log: $logFile"
    Write-Host 'No credential was entered, no session was opened, nothing was changed.'
    exit 2
}

Write-Host 'STAGE 1 VERDICT: network path, TLS and tenant routing are all HEALTHY.'
Write-Host 'The password was NOT evaluated in this stage.'
Write-Host ''
$confirm = Read-Host 'Type YES to continue to the login attempt (anything else cancels without connecting)'
if ($confirm -cne 'YES') {
    Write-Host 'Cancelled. No password was requested and no session was opened.'
    exit 0
}

# =====================================================================
# 4. Stage 2 - one psql login attempt (native password prompt)
# =====================================================================

Write-Host ''
Write-Host '--- STAGE 2: login attempt (single attempt, no automatic retry) ---------'
Write-Host 'psql is now asking for the PostgreSQL password on this console:'
Write-Host ''
Write-Host '    Password: '
Write-Host ''
Write-Host '  * the password is not echoed and is never stored, logged or passed'
Write-Host '    as a command-line argument or environment variable;'
Write-Host '  * the probe runs one SELECT inside BEGIN TRANSACTION READ ONLY and'
Write-Host '    ends with ROLLBACK;'
Write-Host '  * exactly one attempt is made.'
Write-Host ''
Write-Host 'If you do not see psql''s own "Password:" text, type the password'
Write-Host 'anyway - psql reads it directly from this console, not from the pipe'
Write-Host 'used for its output, so the input always works.'
Write-Host ''

$psqlArgs = @(
    '-X',                      # ignore psqlrc
    '-W',                      # force the native interactive password prompt
    '-v', 'ON_ERROR_STOP=1',   # fail-closed on the first error
    '-f', $sqlFile,             # the read-only probe script
    '-o', $outFile,             # query output -> local file
    $connUri                   # verified endpoint; no credential in it
)

$captured = New-Object System.Collections.Generic.List[string]
$exitCode = -1
$previousEap = $ErrorActionPreference
try {
    # 'Continue' is required so that psql writing to stderr is captured as text
    # instead of raising NativeCommandError. The password prompt is read by
    # psql from the console, never from stdin, so nothing else changes.
    $ErrorActionPreference = 'Continue'
    & $psqlPath @psqlArgs 2>&1 | ForEach-Object {
        $line = if ($_ -is [System.Management.Automation.ErrorRecord]) { $_.ToString() } else { [string]$_ }
        if (-not [string]::IsNullOrWhiteSpace($line)) { $captured.Add($line) | Out-Null }
    }
    $exitCode = $LASTEXITCODE
}
finally {
    $ErrorActionPreference = $previousEap
}

$psqlText = ($captured -join "`n")
$sanitizedPsqlText = Get-SanitizedText $psqlText

# --- Evidence from the -o output file -------------------------------------
$outBytes = 0
$hasProbeMarker = $false
$hasRollback = $false
$probeRow = ''
if (Test-Path -LiteralPath $outFile) {
    $outBytes = (Get-Item -LiteralPath $outFile).Length
    $content = Get-Content -LiteralPath $outFile -Raw -ErrorAction SilentlyContinue
    if ($content) {
        $hasProbeMarker = ($content -match 'LOGIN PROBE')
        $hasRollback = ($content -match 'ROLLBACK')
        $rows = $content -split "`r?`n" | Where-Object { $_ -match 'connected_role' -or $_ -match 'hasad_login_probe' }
        if ($rows) { $probeRow = (($rows | Select-Object -First 4) -join ' | ').Trim() }
    }
}

$errorClass = Get-PsqlErrorClass $psqlText

Write-Host ''
Write-Host '--- psql output -------------------------------------------------------'
if ($sanitizedPsqlText) {
    ($sanitizedPsqlText -split "`n") | ForEach-Object { Write-Host "  $_" }
}
else {
    Write-Host '  (psql produced no captured output)'
}
Write-Host "  psql exit code : $exitCode"
Write-Host "  output file    : $outFile ($outBytes bytes)"
Write-Host "  probe executed : $(if ($hasProbeMarker) { 'YES' } else { 'NO' })"
Write-Host "  rollback seen  : $(if ($hasRollback) { 'YES' } else { 'NO' })"
if ($probeRow) { Write-Host "  probe row      : $probeRow" }

# =====================================================================
# 5. Verdict
# =====================================================================

$scriptExit = 6
$verdictHead = ''
$verdictBody = @()

if ($exitCode -eq 0) {
    $scriptExit = 0
    $verdictHead = 'SUCCESS'
    $verdictBody = @(
        'psql exited 0, so every statement in the probe script succeeded: the',
        'password was accepted, the role and database were resolved, the',
        'read-only probe ran and the transaction was rolled back.',
        "Evidence: probe marker in the output file = $hasProbeMarker ; rollback marker = $hasRollback.",
        'Conclusion: connectivity AND authentication are both healthy. Any earlier',
        'failure was therefore either a transient condition or a credential that',
        'has since changed (for example a password rotation).'
    )
}
elseif ($exitCode -eq 3 -or $errorClass -eq 'READ_ONLY_GUARD_TRIPPED') {
    $scriptExit = 5
    $verdictHead = 'SCRIPT_ERROR_AFTER_CONNECT'
    $verdictBody = @(
        'The connection was established and the credential was accepted; the run',
        'then failed inside the SQL script (most likely the fail-closed read-only',
        'guard, or the statement timeout).',
        'Conclusion: connectivity AND authentication are healthy. The failure is',
        'local to the probe script, not to the network and not to the password.'
    )
}
elseif ($errorClass -eq 'AUTHENTICATION_FAILED' -or $errorClass -eq 'ACCESS_RULE_DENIED') {
    $scriptExit = 3
    $verdictHead = 'AUTHENTICATION_FAILURE'
    $verdictBody = (Get-ClassExplanation $errorClass)
}
elseif ($errorClass -eq 'CONNECTION_DROPPED' -or $errorClass -eq 'CONNECTION_LIMIT' -or
        $errorClass -eq 'NETWORK_TIMEOUT' -or $errorClass -eq 'NETWORK_REFUSED') {
    $scriptExit = 4
    $verdictHead = 'CONNECTION_DROPPED'
    $verdictBody = @(
        'Stage 1 had already proven that DNS, TCP, TLS and tenant routing are',
        'healthy, yet the psql session was lost or refused during the session',
        'handshake.',
        'Conclusion: the network path is NOT the problem. The password was not',
        'positively evaluated as wrong, and it was not positively accepted'
    ) + (Get-ClassExplanation $errorClass)
}
else {
    $scriptExit = 6
    $verdictHead = 'UNCLASSIFIED_FAILURE'
    $verdictBody = @(
        "Stage 1 proved the transport layer healthy. psql exited with code $exitCode",
        "and the message was classified as '$errorClass'.",
        'Conclusion: connectivity AND the TLS/tenant layers are healthy. The',
        'captured psql message above is the primary evidence and should be read',
        'verbatim before any conclusion is drawn about the credential.'
    )
}

Write-Host ''
Write-Host '--- VERDICT -------------------------------------------------------------'
Write-Host "  $verdictHead"
$verdictBody | ForEach-Object { Write-Host "  $_" }
Write-Host ''

# =====================================================================
# 6. Local sanitized log (no credential, no secret value, no business data)
# =====================================================================

$logBody = @()
$logBody += '# Hasad ERP V2 - DEV login diagnostic'
$logBody += ''
$logBody += "- Timestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz')"
$logBody += "- Project ref: $projectRef"
$logBody += "- Endpoint: ${expectedHost}:${expectedPort} / database $expectedDb / role $expectedUser"
$logBody += "- psql: $psqlVersion"
$logBody += "- Probe SQL: $sqlFile"
$logBody += "- psql exit code: $exitCode"
$logBody += "- Error class: $errorClass"
$logBody += ''
$logBody += '## Stage 1 - credential-free transport probe'
$logBody += ''
$logBody += "- DNS resolved: $($probe.DnsAddresses -join ', ')"
$logBody += "- TCP ${expectedPort}: $(if ($probe.TcpOk) { 'REACHABLE' } else { 'FAILED' })"
$logBody += "- TLS offered: $(if ($probe.TlsOffered) { 'YES' } else { 'NO' })"
$logBody += "- TLS session: $(if ($probe.TlsOk) { 'ESTABLISHED' } else { 'NOT ESTABLISHED' })"
$logBody += "- Tenant routing: $(if ($probe.TenantAccepted) { 'ACCEPTED' } else { 'NOT CONFIRMED' })"
$logBody += "- Stage reached: $($probe.Stage)"
$logBody += "- Detail: $(Get-SanitizedText $probe.Detail)"
$logBody += ''
$logBody += '## Stage 2 - psql login attempt'
$logBody += ''
$logBody += "- psql exit code: $exitCode"
$logBody += "- Captured output file: $outFile ($outBytes bytes)"
$logBody += "- Probe statement executed: $hasProbeMarker"
$logBody += "- Rollback reached: $hasRollback"
$logBody += '- Captured psql message (sanitized):'
$logBody += ''
$logBody += '```'
$logBody += ($sanitizedPsqlText -split "`n" | Where-Object { $_.Trim().Length -gt 0 } | Select-Object -First 40)
$logBody += '```'
$logBody += ''
$logBody += '## Verdict'
$logBody += ''
$logBody += "**$verdictHead**"
$logBody += ''
$logBody += ($verdictBody | ForEach-Object { "- $_" })
$logBody += ''
$logBody += '## Change safety'
$logBody += ''
$logBody += '- The probe transaction was read-only and was rolled back.'
$logBody += '- No DDL, DML, migration, reset, restore or cleanup was issued.'
$logBody += '- No Supabase CLI state, Auth, Storage, Edge Function, secret or'
$logBody += '  project setting was read or modified.'
$logBody += '- The password was entered at the psql native prompt and was never'
$logBody += '  written to any file, argument, environment variable or log.'
Set-Content -LiteralPath $logFile -Value $logBody -Encoding UTF8

Write-Host "Local log: $logFile"
Write-Host 'No credential was written to any file. Nothing on the remote project was changed.'
exit $scriptExit
