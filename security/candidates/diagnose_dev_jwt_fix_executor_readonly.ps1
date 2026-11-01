[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$devRef = 'sxasnunzspkuwbxiddqd'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$cli = Join-Path $repoRoot 'node_modules\.bin\supabase.cmd'
$sqlPath = Join-Path $PSScriptRoot 'diagnose_dev_jwt_fix_executor_readonly.sql'
$linkedRefPath = Join-Path $repoRoot 'supabase\.temp\project-ref'
$expectedSqlSha256 = '53D4D817E9BE934B17C93DB344C5E62306AE678DF370CEC507316C4888C7A261'
if (-not (Test-Path -LiteralPath $cli -PathType Leaf)) { throw 'JWT_PREFLIGHT:CLI_MISSING' }
if ((Get-FileHash -LiteralPath $sqlPath -Algorithm SHA256).Hash -cne $expectedSqlSha256) {
  throw 'JWT_PREFLIGHT:SQL_HASH_MISMATCH'
}
if ((Get-Content -LiteralPath $linkedRefPath -Raw).Trim() -cne $devRef) {
  throw 'JWT_PREFLIGHT:LINKED_PROJECT_MISMATCH'
}
$sql = Get-Content -LiteralPath $sqlPath -Raw
$body = [regex]::Replace($sql,'(?m)^\s*--.*(?:\r?\n|$)','').Trim()
if (-not $body.StartsWith('WITH ') -or $body -notmatch '(?is)\bSELECT\b.+;\s*$' -or
    ([regex]::Matches($body,';')).Count -ne 1) {
  throw 'JWT_PREFLIGHT:PINNED_SQL_SHAPE_INVALID'
}
. (Join-Path $PSScriptRoot 'lib\hasad_cli.ps1')
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('hasad-jwt-preflight-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tempRoot | Out-Null
try {
  $oldTracking = $env:DO_NOT_TRACK
  $hadTracking = Test-Path Env:\DO_NOT_TRACK
  $env:DO_NOT_TRACK='1'
  try {
    $result = Invoke-HasadCliFile -CliPath $cli -Arguments @('--agent','yes','db','query','--linked',
      '--project-ref',$devRef,'--file',$sqlPath,'--output-format','json') `
      -StandardOutputPath (Join-Path $tempRoot 'out.json') -StandardErrorPath (Join-Path $tempRoot 'err.txt')
  } finally {
    if ($hadTracking) { $env:DO_NOT_TRACK=$oldTracking } else { Remove-Item Env:\DO_NOT_TRACK -ErrorAction SilentlyContinue }
  }
  if ($result.ExitCode -ne 0) {
    $raw = $result.StandardOutput + "`n" + $result.StandardError
    $state = if ($raw -match '(?i)SQLSTATE\s*[:= ]\s*([0-9A-Z]{5})') { $Matches[1] } else { 'NOT_EXPOSED' }
    $category = if ($raw -match '(?i)unauthorized|not authenticated|access token') { 'CLI_AUTHENTICATION_FAILURE' }
      elseif ($raw -match '(?i)telemetry|EPERM|FileSystem\.writeFile') { 'CLI_LOCAL_TELEMETRY_FAILURE' }
      elseif ($state -eq '42501') { 'POSTGRES_PRIVILEGE_DENIED' }
      elseif ($state -ne 'NOT_EXPOSED') { 'POSTGRES_SQL_ERROR' }
      else { 'CLI_FAILURE_UNCLASSIFIED' }
    Write-Output ("JWT_PREFLIGHT:SQLSTATE={0};CATEGORY={1}" -f $state,$category)
    throw 'JWT_PREFLIGHT:CLI_NONZERO_EXIT'
  }
  if ([string]::IsNullOrWhiteSpace($result.StandardOutput)) { throw 'JWT_PREFLIGHT:EMPTY_OUTPUT' }
  try { $envlp = $result.StandardOutput | ConvertFrom-Json -ErrorAction Stop }
  catch { throw 'JWT_PREFLIGHT:INVALID_JSON' }
  if ($envlp -isnot [pscustomobject] -or $envlp.rows -isnot [pscustomobject] -or
      @($envlp.PSObject.Properties.Name | Sort-Object) -join ',' -ne 'boundary,rows,warning') {
    throw 'JWT_PREFLIGHT:UNSUPPORTED_CLI_ENVELOPE'
  }
  $prop = $envlp.rows.PSObject.Properties['jwt_fix_executor_preflight']
  if ($null -eq $prop -or $prop.Value -isnot [pscustomobject]) { throw 'JWT_PREFLIGHT:RESULT_MISSING' }
  $data = $prop.Value
  if ($data.executor -isnot [pscustomobject]) { throw 'JWT_PREFLIGHT:AUTHORITY_RESULT_INVALID' }
  foreach ($name in @('executor','rpcs','resolver','policies','policy_counts','table_security','helper_boundary','exact_candidate_executor_preflight')) {
    if ($null -eq $data.PSObject.Properties[$name]) { throw 'JWT_PREFLIGHT:RESULT_INCOMPLETE' }
  }
  if ($data.rpcs -isnot [array] -or $data.rpcs.Count -ne 2 -or
      $data.policies -isnot [array] -or $data.policies.Count -ne 7 -or
      $data.resolver -isnot [array] -or $data.resolver.Count -ne 1) {
    throw 'JWT_PREFLIGHT:OBJECT_INVENTORY_MISMATCH'
  }
  $authorityFields = @('is_superuser','hasad_usage','hasad_create','hasad_api_usage',
    'hasad_api_create','member_hasad_rpc_owner','can_act_as_hasad_rpc_owner',
    'owns_hasad_schema','hasad_create_grant_option','can_replace_both_rpcs',
    'can_transfer_helper_owner','can_temporary_create_grant_and_revoke')
  foreach ($name in $authorityFields) {
    $field = $data.executor.PSObject.Properties[$name]
    if ($null -eq $field -or $field.Value -isnot [bool]) { throw 'JWT_PREFLIGHT:AUTHORITY_RESULT_INVALID' }
  }
  if ($data.exact_candidate_executor_preflight -isnot [bool]) { throw 'JWT_PREFLIGHT:RESULT_INCOMPLETE' }
  $safe = [ordered]@{ executor = [ordered]@{}; exact_candidate_executor_preflight = $data.exact_candidate_executor_preflight }
  foreach ($name in $authorityFields) { $safe.executor[$name] = $data.executor.$name }
  $safe | ConvertTo-Json -Depth 4
} finally {
  Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}
