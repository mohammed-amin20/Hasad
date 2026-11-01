[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$devRef = 'sxasnunzspkuwbxiddqd'
$expectedSqlSha256 = '6987F8C4009297706370DBF0CF2CCA8890B5A69C83711E76E587D8482E551851'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$cli = Join-Path $repoRoot 'node_modules\.bin\supabase.cmd'
$sqlPath = Join-Path $PSScriptRoot 'diagnose_dev_rpc_auth_usage_readonly.sql'
$linkedRefPath = Join-Path $repoRoot 'supabase\.temp\project-ref'

if (-not (Test-Path -LiteralPath $cli -PathType Leaf)) { throw 'RPC_DIAGNOSTIC_FAILED:SUPABASE_CLI_MISSING' }
if (-not (Test-Path -LiteralPath $sqlPath -PathType Leaf)) { throw 'RPC_DIAGNOSTIC_FAILED:SQL_FILE_MISSING' }
if ((Get-FileHash -LiteralPath $sqlPath -Algorithm SHA256).Hash -cne $expectedSqlSha256) {
  throw 'RPC_DIAGNOSTIC_FAILED:SQL_HASH_MISMATCH'
}
if (-not (Test-Path -LiteralPath $linkedRefPath -PathType Leaf) -or
    (Get-Content -LiteralPath $linkedRefPath -Raw).Trim() -cne $devRef) {
  throw 'RPC_DIAGNOSTIC_FAILED:LINKED_PROJECT_MISMATCH'
}

$sql = Get-Content -LiteralPath $sqlPath -Raw
$body = [regex]::Replace($sql, '(?m)^\s*--.*(?:\r?\n|$)', '').Trim()
if ($body -notmatch '(?m)^WITH\b[\s\S]+^SELECT\b' -or -not $body.EndsWith(';') -or
    ([regex]::Matches($body, ';')).Count -ne 1 -or
    $sql -match '(?im)^\s*(GRANT|REVOKE|CREATE|ALTER|DROP|INSERT|UPDATE|DELETE|TRUNCATE|CALL|DO)\b') {
  throw 'RPC_DIAGNOSTIC_FAILED:SQL_NOT_READ_ONLY_SINGLE_SELECT'
}

. (Join-Path $PSScriptRoot 'lib\hasad_cli.ps1')

function Get-SafeFailureCategory {
  param([AllowNull()][string]$Text)
  $sqlState = 'NOT_EXPOSED'
  if ($Text -match '(?i)SQLSTATE\s*[:= ]\s*([0-9A-Z]{5})') { $sqlState = $Matches[1] }
  elseif ($Text -match '(?i)["''](?:sqlstate|code)["'']\s*:\s*["'']([0-9A-Z]{5})["'']') { $sqlState = $Matches[1] }

  $category = if ($Text -match '(?i)multiple commands into a prepared statement') { 'CLI_MULTI_STATEMENT_PREPARED_QUERY' }
    elseif ($Text -match 'FAIL-CLOSED: restricted RPC owner role state') { 'CANDIDATE_ROLE_STATE' }
    elseif ($Text -match 'FAIL-CLOSED: auth schema is missing') { 'CANDIDATE_AUTH_SCHEMA_MISSING' }
    elseif ($Text -match 'FAIL-CLOSED: direct auth\.users SELECT boundary') { 'CANDIDATE_AUTH_USERS_SELECT_BOUNDARY' }
    elseif ($Text -match 'FAIL-CLOSED: proposed privilege already exists') { 'CANDIDATE_GRANT_ALREADY_PRESENT' }
    elseif ($Text -match 'FAIL-CLOSED: required auth schema privilege missing') { 'CANDIDATE_GRANT_POSTCONDITION' }
    elseif ($Text -match 'FAIL-CLOSED: auth\.uid execute privilege changed') { 'CANDIDATE_AUTH_UID_EXECUTE' }
    elseif ($Text -match 'FAIL-CLOSED: anonymous RPC execute boundary mismatch') { 'CANDIDATE_ANON_RPC_EXECUTE' }
    elseif ($Text -match 'FAIL-CLOSED: API RPC owner/security mode mismatch') { 'CANDIDATE_RPC_METADATA' }
    elseif ($Text -match 'FAIL-CLOSED: hasad table RLS boundary mismatch') { 'CANDIDATE_RLS_BOUNDARY' }
    elseif ($sqlState -eq '42501') { 'POSTGRES_PRIVILEGE_DENIED' }
    elseif ($Text -match '(?i)telemetry|FileSystem\.writeFile|EPERM') { 'CLI_TELEMETRY_WRITE_FAILURE' }
    elseif ($Text -match '(?i)unauthorized|not authenticated|access token') { 'CLI_AUTHENTICATION_FAILURE' }
    elseif ($Text -match '(?i)connection refused|failed to connect|timeout|could not connect') { 'DATABASE_CONNECTION_FAILURE' }
    elseif ($sqlState -ne 'NOT_EXPOSED') { 'POSTGRES_SQL_ERROR' }
    else { 'CLI_FAILURE_UNCLASSIFIED' }
  [pscustomobject]@{ SqlState = $sqlState; Category = $category }
}

$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('hasad-rpc-auth-diagnostic-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
try {
  $hadDoNotTrack = Test-Path Env:\DO_NOT_TRACK
  $previousDoNotTrack = $env:DO_NOT_TRACK
  $env:DO_NOT_TRACK = '1'
  try {
    $cliResult = Invoke-HasadCliFile -CliPath $cli `
      -Arguments @('--agent','yes','db','query','--linked','--project-ref',$devRef,'--file',$sqlPath,'--output-format','json') `
      -StandardOutputPath (Join-Path $tempRoot 'stdout.json') `
      -StandardErrorPath (Join-Path $tempRoot 'stderr.txt')
  } finally {
    if ($hadDoNotTrack) { $env:DO_NOT_TRACK = $previousDoNotTrack }
    else { Remove-Item Env:\DO_NOT_TRACK -ErrorAction SilentlyContinue }
  }
  if ($cliResult.ExitCode -ne 0) {
    $failure = Get-SafeFailureCategory -Text ($cliResult.StandardOutput + "`n" + $cliResult.StandardError)
    Write-Output ("RPC_AUTH_DIAGNOSTIC:SQLSTATE={0};CATEGORY={1}" -f $failure.SqlState,$failure.Category)
    throw 'RPC_DIAGNOSTIC_FAILED:CLI_NONZERO_EXIT'
  }
  if ([string]::IsNullOrWhiteSpace($cliResult.StandardOutput)) { throw 'RPC_DIAGNOSTIC_FAILED:CLI_EMPTY_OUTPUT' }
  try { $envelope = $cliResult.StandardOutput | ConvertFrom-Json -ErrorAction Stop }
  catch { throw 'RPC_DIAGNOSTIC_FAILED:CLI_INVALID_JSON' }
  if ($envelope -isnot [pscustomobject] -or
      @($envelope.PSObject.Properties | ForEach-Object Name | Sort-Object) -join ',' -ne 'boundary,rows,warning' -or
      $envelope.rows -isnot [pscustomobject]) {
    throw 'RPC_DIAGNOSTIC_FAILED:CLI_ENVELOPE_INVALID'
  }
  $diagProperty = $envelope.rows.PSObject.Properties['rpc_auth_usage_diagnostic']
  if ($null -eq $diagProperty -or $diagProperty.Value -isnot [pscustomobject]) {
    throw 'RPC_DIAGNOSTIC_FAILED:RESULT_MISSING'
  }
  $result = $diagProperty.Value
  foreach ($name in @('executor_authority','jwt_claim_fix_preflight','current_state','candidate_assertion_status')) {
    if ($null -eq $result.PSObject.Properties[$name] -or $result.$name -isnot [pscustomobject]) {
      throw 'RPC_DIAGNOSTIC_FAILED:RESULT_INCOMPLETE'
    }
  }
  $current = $result.current_state
  $assertions = $result.candidate_assertion_status
  $safeOutput = [ordered]@{
    executor_authority = $result.executor_authority
    jwt_claim_fix_preflight = $result.jwt_claim_fix_preflight
    current_state = $current
    candidate_assertion_status = $assertions
  }
  $safeOutput | ConvertTo-Json -Depth 8
} finally {
  Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}
