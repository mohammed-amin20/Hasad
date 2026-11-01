$ErrorActionPreference = 'Continue'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$repo = (Resolve-Path (Join-Path $root '..\..')).Path
$pgBin = 'C:\Program Files\PostgreSQL\17\bin'
$psql = Join-Path $pgBin 'psql.exe'
$postgres = Join-Path $pgBin 'postgres.exe'
$pgCtl = Join-Path $pgBin 'pg_ctl.exe'
$supabase = Join-Path $repo 'node_modules\.bin\supabase.cmd'
$pgRoot = Join-Path $env:TEMP ('hasad-jwt-claims-' + [guid]::NewGuid().ToString('N'))
$data = Join-Path $pgRoot 'data'
$log = Join-Path $pgRoot 'server.log'
$port = Get-Random -Minimum 56000 -Maximum 64000
$started = $false
$fallbackProcess = $null
New-Item -ItemType Directory -Path $pgRoot | Out-Null
try {
  foreach ($tool in @($psql,$postgres,$pgCtl,(Join-Path $pgBin 'initdb.exe'),$supabase)) {
    if (-not (Test-Path -LiteralPath $tool -PathType Leaf)) { throw 'LOCAL_HARNESS_REQUIRED_TOOL_MISSING' }
  }

  $setupText = Get-Content -LiteralPath (Join-Path $root 'local_security_harness.sql') -Raw
  $setupText = [regex]::Replace($setupText,
    '(?m)^GRANT USAGE ON SCHEMA auth TO authenticated, anon, hasad_rpc_owner;\r?\n','')
  $setupText = [regex]::Replace($setupText,
    '(?m)^GRANT EXECUTE ON FUNCTION auth\.uid\(\) TO authenticated, anon, hasad_rpc_owner;\r?\n','')
  if ($setupText -match '(?im)^\s*GRANT\s+USAGE\s+ON\s+SCHEMA\s+auth\b') {
    throw 'LOCAL_FIXTURE_UNEXPECTED_AUTH_SCHEMA_GRANT'
  }
  $setupFile = Join-Path $pgRoot 'synthetic_setup.sql'
  [IO.File]::WriteAllText($setupFile,$setupText,[Text.UTF8Encoding]::new($false))

  $rpcCandidate = Join-Path $root '20261030000100_v2_candidate_hasad_api_company_product_read_v2.sql'
  $rpcText = Get-Content -LiteralPath $rpcCandidate -Raw
  $rpcText = [regex]::Replace($rpcText,
    '(?m)^GRANT USAGE ON SCHEMA hasad, auth, hasad_api TO hasad_rpc_owner;\r?\n',
    'GRANT USAGE ON SCHEMA hasad, hasad_api TO hasad_rpc_owner;' + "`r`n")
  $rpcText = [regex]::Replace($rpcText,
    '(?m)^GRANT EXECUTE ON FUNCTION auth\.uid\(\) TO hasad_rpc_owner;\r?\n','')
  if ($rpcText -match '(?im)^\s*GRANT\s+(?:USAGE\s+ON\s+SCHEMA\s+auth|EXECUTE\s+ON\s+FUNCTION\s+auth\.uid)') {
    throw 'LOCAL_RPC_FIXTURE_UNEXPECTED_AUTH_GRANT'
  }
  $rpcFile = Join-Path $pgRoot 'synthetic_rpc_setup.sql'
  [IO.File]::WriteAllText($rpcFile,$rpcText,[Text.UTF8Encoding]::new($false))

  & (Join-Path $pgBin 'initdb.exe') -D $data -U postgres -A trust --no-locale *> $null
  if ($LASTEXITCODE -ne 0) { throw 'LOCAL_POSTGRES_INIT_FAILED' }
  & $pgCtl -D $data -l $log -o "-p $port -h 127.0.0.1" -w start *> $null
  if ($LASTEXITCODE -ne 0) {
    $fallbackProcess = Start-Process -FilePath $postgres `
      -ArgumentList @('-D',$data,'-p',"$port",'-h','127.0.0.1') `
      -RedirectStandardOutput (Join-Path $pgRoot 'postgres.stdout.log') `
      -RedirectStandardError (Join-Path $pgRoot 'postgres.stderr.log') `
      -WindowStyle Hidden -PassThru
    $ready = $false
    for ($attempt=0; $attempt -lt 40; $attempt++) {
      if ($fallbackProcess.HasExited) { break }
      & $psql -X -w -h 127.0.0.1 -p $port -U postgres -d postgres -c 'SELECT 1' *> $null
      if ($LASTEXITCODE -eq 0) { $ready=$true; break }
      Start-Sleep -Milliseconds 250
    }
    if (-not $ready) { throw 'LOCAL_POSTGRES_START_FAILED' }
  }
  $started = $true
  $base = @('-X','-w','-h','127.0.0.1','-p',"$port",'-U','postgres','-d','postgres','-v','ON_ERROR_STOP=1')
  & $psql @base -f $setupFile *> $null
  if ($LASTEXITCODE -ne 0) { throw 'LOCAL_SYNTHETIC_FIXTURE_FAILED' }
  & $psql @base -f $rpcFile *> $null
  if ($LASTEXITCODE -ne 0) { throw 'LOCAL_SYNTHETIC_RPC_SETUP_FAILED' }
  & $psql @base -f (Join-Path $root 'rpc_jwt_claim_local_setup.sql') *> $null
  if ($LASTEXITCODE -ne 0) { throw 'LOCAL_JWT_FIXTURE_SETUP_FAILED' }
  & $psql @base -c 'GRANT EXECUTE ON FUNCTION hasad_api.whoami(),hasad_api.products_list() TO authenticated;' *> $null
  if ($LASTEXITCODE -ne 0) { throw 'LOCAL_SYNTHETIC_RPC_GRANTS_FAILED' }

  $before = & $psql @base -t -A -c "SELECT NOT has_schema_privilege('hasad_rpc_owner','auth','USAGE') AND NOT has_table_privilege('authenticated','auth.users','SELECT') AND NOT has_table_privilege('anon','auth.users','SELECT')"
  if ($LASTEXITCODE -ne 0 -or ($before | Out-String).Trim() -ne 't') {
    throw 'LOCAL_FIXTURE_AUTH_BOUNDARY_NOT_ESTABLISHED'
  }
  Write-Host 'PASS: synthetic pre-fix state has no auth schema USAGE for RPC owner'

  $preflightSql = Join-Path $root 'diagnose_dev_rpc_auth_usage_readonly.sql'
  $preflightOutput = & $psql @base -t -A -f $preflightSql
  if ($LASTEXITCODE -ne 0) { throw 'LOCAL_READ_ONLY_EXECUTOR_PREFLIGHT_SQL_FAILED' }
  try { $preflightResult = (($preflightOutput | Out-String).Trim() | ConvertFrom-Json -ErrorAction Stop) }
  catch { throw 'LOCAL_READ_ONLY_EXECUTOR_PREFLIGHT_JSON_INVALID' }
  if (-not $preflightResult.jwt_claim_fix_preflight.executor_can_apply_candidate -or
      $preflightResult.jwt_claim_fix_preflight.api_auth_uid_reference_count -ne 2 -or
      $preflightResult.jwt_claim_fix_preflight.permission_resolver_auth_uid_reference_count -ne 0 -or
      $preflightResult.jwt_claim_fix_preflight.rpc_owner_auth_uid_policy_count -ne 7 -or
      $preflightResult.jwt_claim_fix_preflight.hasad_force_rls_count -ne 47) {
    throw 'LOCAL_READ_ONLY_EXECUTOR_PREFLIGHT_ASSERTION_FAILED'
  }
  Write-Host 'PASS: read-only preflight detects local executor authority and all auth.uid dependencies'

  $jwtPreflightSql = Join-Path $root 'diagnose_dev_jwt_fix_executor_readonly.sql'
  $jwtPreflightOutput = & $psql @base -t -A -f $jwtPreflightSql
  if ($LASTEXITCODE -ne 0) { throw 'LOCAL_JWT_READ_ONLY_PREFLIGHT_SQL_FAILED' }
  try { $jwtPreflightResult = (($jwtPreflightOutput | Out-String).Trim() | ConvertFrom-Json -ErrorAction Stop) }
  catch { throw 'LOCAL_JWT_READ_ONLY_PREFLIGHT_JSON_INVALID' }
  if ($jwtPreflightResult.exact_candidate_executor_preflight -ne $true -or
      @($jwtPreflightResult.rpcs).Count -ne 2 -or
      @($jwtPreflightResult.policies).Count -ne 7 -or
      @($jwtPreflightResult.resolver).Count -ne 1 -or
      $jwtPreflightResult.policy_counts.auth_uid_policies -ne 7 -or
      $jwtPreflightResult.policy_counts.alterable_auth_uid_policies -ne 7 -or
      $jwtPreflightResult.table_security.table_count -ne 47 -or
      $jwtPreflightResult.table_security.force_rls_count -ne 47 -or
      $jwtPreflightResult.helper_boundary.rpc_owner_auth_usage -ne $false -or
      $jwtPreflightResult.executor.can_replace_both_rpcs -ne $true -or
      $jwtPreflightResult.executor.can_temporary_create_grant_and_revoke -ne $true) {
    throw 'LOCAL_JWT_READ_ONLY_PREFLIGHT_ASSERTION_FAILED'
  }
  Write-Host 'PASS: candidate-specific catalog preflight inventories exact RPCs, policies, and executor authority'

  $candidate = Join-Path $root 'dev_rpc_jwt_claim_identity_fix_candidate.sql'
  $candidateText = Get-Content -LiteralPath $candidate -Raw
  if ($candidateText -match '(?im)^\s*GRANT\s+USAGE\s+ON\s+SCHEMA\s+auth\b' -or
      $candidateText -match '(?im)^\s*GRANT\s+SELECT\s+ON\s+auth\.users') {
    throw 'JWT_FIX_CANDIDATE_CONTAINS_FORBIDDEN_GRANT'
  }
  $localDbUrl = "postgresql://postgres@127.0.0.1:$port/postgres?sslmode=disable"
  $stdout = Join-Path $pgRoot 'candidate.stdout.json'
  $stderr = Join-Path $pgRoot 'candidate.stderr.txt'
  $oldTracking = $env:DO_NOT_TRACK
  $env:DO_NOT_TRACK='1'
  try {
    . (Join-Path $root 'lib\hasad_cli.ps1')
    $cliResult = Invoke-HasadCliFile -CliPath $supabase `
      -Arguments @('db','query','--db-url',$localDbUrl,'--file',$candidate,'--output-format','json','--agent','yes') `
      -StandardOutputPath $stdout -StandardErrorPath $stderr
  } finally {
    if ($null -eq $oldTracking) { Remove-Item Env:\DO_NOT_TRACK -ErrorAction SilentlyContinue }
    else { $env:DO_NOT_TRACK=$oldTracking }
  }
  if ($cliResult.ExitCode -ne 0) {
    $raw = $cliResult.StandardOutput + "`n" + $cliResult.StandardError
    $state = if ($raw -match '(?i)SQLSTATE\s*[:= ]\s*([0-9A-Z]{5})') { $Matches[1] } else { 'NOT_EXPOSED' }
    Write-Host ("FAIL: local candidate rejected; SQLSTATE={0}" -f $state)
    throw 'LOCAL_JWT_FIX_CANDIDATE_REJECTED'
  }
  Write-Host 'PASS: Supabase CLI applied the single-statement JWT fix to disposable PostgreSQL'

  & $psql @base -f (Join-Path $root 'rpc_jwt_claim_identity_local_tests.sql')
  if ($LASTEXITCODE -ne 0) { throw 'LOCAL_JWT_SECURITY_REGRESSION_FAILED' }
  Write-Host 'PASS: JWT claim authentication and security regression suite'
}
finally {
  if ($started) {
    if ($null -ne $fallbackProcess -and -not $fallbackProcess.HasExited) {
      Stop-Process -Id $fallbackProcess.Id -Force -ErrorAction SilentlyContinue
      Wait-Process -Id $fallbackProcess.Id -Timeout 10 -ErrorAction SilentlyContinue
    } else { & $pgCtl -D $data -m immediate -t 10 -w stop *> $null }
  }
  $tempRoot=[IO.Path]::GetFullPath($env:TEMP)
  $target=[IO.Path]::GetFullPath($pgRoot)
  if ($target.StartsWith((Join-Path $tempRoot 'hasad-jwt-claims-'),[StringComparison]::OrdinalIgnoreCase)) {
    Remove-Item -LiteralPath $target -Recurse -Force -ErrorAction SilentlyContinue
  }
}
