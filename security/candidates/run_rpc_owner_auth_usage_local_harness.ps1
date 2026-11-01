$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$repo = (Resolve-Path (Join-Path $root '..\..')).Path
$pgBin = 'C:\Program Files\PostgreSQL\17\bin'
$psql = Join-Path $pgBin 'psql.exe'
$postgres = Join-Path $pgBin 'postgres.exe'
$pgCtl = Join-Path $pgBin 'pg_ctl.exe'
$supabase = Join-Path $repo 'node_modules\.bin\supabase.cmd'
$pgRoot = Join-Path $env:TEMP ('hasad-rpc-auth-usage-' + [guid]::NewGuid().ToString('N'))
$data = Join-Path $pgRoot 'data'
$log = Join-Path $pgRoot 'server.log'
$port = Get-Random -Minimum 56000 -Maximum 64000
$started = $false
$fallbackProcess = $null
New-Item -ItemType Directory -Path $pgRoot | Out-Null
try {
  & (Join-Path $pgBin 'initdb.exe') -D $data -U postgres -A trust --no-locale
  if ($LASTEXITCODE -ne 0) { throw 'initdb failed' }
  & $pgCtl -D $data -l $log -o "-p $port -h 127.0.0.1" -w start
  if ($LASTEXITCODE -ne 0) {
    # Some Windows sandboxes prevent pg_ctl from creating a restricted token.
    # Start the same disposable cluster directly, hidden, and retain its PID for cleanup.
    $fallbackProcess = Start-Process -FilePath $postgres `
      -ArgumentList @('-D', $data, '-p', "$port", '-h', '127.0.0.1') `
      -RedirectStandardOutput (Join-Path $pgRoot 'postgres.stdout.log') `
      -RedirectStandardError (Join-Path $pgRoot 'postgres.stderr.log') `
      -WindowStyle Hidden -PassThru
    $ready = $false
    for ($attempt = 0; $attempt -lt 40; $attempt++) {
      if ($fallbackProcess.HasExited) { break }
      & $psql -X -w -h 127.0.0.1 -p $port -U postgres -d postgres -c 'SELECT 1' *> $null
      if ($LASTEXITCODE -eq 0) { $ready = $true; break }
      Start-Sleep -Milliseconds 250
    }
    if (-not $ready) { throw 'disposable PostgreSQL 17 failed to start' }
  }
  $started = $true
  $base = @('-X','-w','-h','127.0.0.1','-p',"$port",'-U','postgres','-d','postgres','-v','ON_ERROR_STOP=1')
  & $psql @base -f (Join-Path $repo 'security\candidates\local_security_harness.sql')
  if ($LASTEXITCODE -ne 0) { throw 'local fixtures failed' }
  & $psql @base -c 'ALTER ROLE hasad_rpc_owner NOINHERIT; CREATE TABLE auth.users(id uuid primary key); GRANT EXECUTE ON FUNCTION auth.uid() TO authenticated, anon, hasad_rpc_owner;'
  if ($LASTEXITCODE -ne 0) { throw 'could not create pre-fix state' }
  & $psql @base -f (Join-Path $repo 'security\candidates\20261030000100_v2_candidate_hasad_api_company_product_read_v2.sql')
  if ($LASTEXITCODE -ne 0) { throw 'local RPC definitions failed to load' }
  & $psql @base -c 'REVOKE USAGE ON SCHEMA auth FROM hasad_rpc_owner;'
  if ($LASTEXITCODE -ne 0) { throw 'could not create pre-fix owner privilege state' }
  & $psql @base -c 'GRANT EXECUTE ON FUNCTION hasad_api.whoami(), hasad_api.products_list() TO authenticated;'
  if ($LASTEXITCODE -ne 0) { throw 'local test execute grants failed' }
  & $psql @base -f (Join-Path $repo 'security\candidates\rpc_owner_auth_usage_pregrant_assertions.sql')
  if ($LASTEXITCODE -ne 0) { throw 'expected pre-grant failure did not reproduce' }

  # Confirm the installed CLI rejects multiple commands in one prepared query.
  $cliStdout = Join-Path $pgRoot 'cli.stdout.txt'
  $cliStderr = Join-Path $pgRoot 'cli.stderr.txt'
  $candidate = Join-Path $repo 'security\candidates\dev_hasad_rpc_owner_auth_usage_candidate.sql'
  $multiStatementFixture = Join-Path $pgRoot 'multi_statement_transport_repro.sql'
  [IO.File]::WriteAllText($multiStatementFixture, "SELECT 1;`r`nSELECT 2;`r`n", [Text.UTF8Encoding]::new($false))
  $localDbUrl = "postgresql://postgres@127.0.0.1:$port/postgres?sslmode=disable"
  $previousDoNotTrack = $env:DO_NOT_TRACK
  $env:DO_NOT_TRACK = '1'
  try {
    . (Join-Path $repo 'security\candidates\lib\hasad_cli.ps1')
    $multiStatementResult = Invoke-HasadCliFile -CliPath $supabase `
      -Arguments @('db','query','--db-url',$localDbUrl,'--file',$multiStatementFixture,'--output-format','json','--agent','yes') `
      -StandardOutputPath $cliStdout -StandardErrorPath $cliStderr
    $multiStatementError = $multiStatementResult.StandardOutput + $multiStatementResult.StandardError
    $multiSqlState = if ($multiStatementError -match '(?i)SQLSTATE\s*[:= ]\s*([0-9A-Z]{5})') { $Matches[1] } else { 'unavailable' }
    if ($multiSqlState -eq 'unavailable' -and $multiStatementError -match '(?i)["'']code["'']\s*:\s*["'']?([0-9][0-9A-Z]{4})') {
      $multiSqlState = $Matches[1]
    }
    $multiCategory = if ($multiStatementError -match '(?i)multiple commands into a prepared statement') { 'MULTI_STATEMENT_REJECTED' }
      elseif ($multiStatementError -match '(?i)telemetry|FileSystem\.writeFile|EPERM') { 'CLI_TELEMETRY_WRITE_FAILURE' }
      elseif ($multiStatementError -match '(?i)tls|SSL') { 'LOCAL_TLS_MISMATCH' }
      elseif ($multiStatementError -match '(?i)connection refused|could not connect') { 'LOCAL_DATABASE_CONNECTION_FAILURE' }
      else { 'CLI_FAILURE_UNCLASSIFIED' }
    if ($multiStatementResult.ExitCode -eq 0 -or $multiCategory -ne 'MULTI_STATEMENT_REJECTED') {
      Write-Host ("CLI multi-statement diagnostic: exit={0}, SQLSTATE={1}, category={2}" -f $multiStatementResult.ExitCode,$multiSqlState,$multiCategory)
      throw 'Supabase CLI multi-statement SQLSTATE 42601 transport regression was not reproduced'
    }
    Write-Host ("PASS: Supabase db query rejected multi-statement file; CLI SQLSTATE={0}, category={1}" -f $multiSqlState,$multiCategory)

    $candidateCliResult = Invoke-HasadCliFile -CliPath $supabase `
      -Arguments @('db','query','--db-url',$localDbUrl,'--file',$candidate,'--output-format','json','--agent','yes') `
      -StandardOutputPath $cliStdout -StandardErrorPath $cliStderr
  } finally {
    if ($null -eq $previousDoNotTrack) { Remove-Item Env:\DO_NOT_TRACK -ErrorAction SilentlyContinue }
    else { $env:DO_NOT_TRACK = $previousDoNotTrack }
  }
  $candidateCliError = $candidateCliResult.StandardOutput + $candidateCliResult.StandardError
  if ($candidateCliResult.ExitCode -ne 0) {
    $sqlState = if ($candidateCliError -match '(?i)SQLSTATE\s*[:= ]\s*([0-9A-Z]{5})') { $Matches[1] } else { 'unavailable' }
    $failureCategory = if ($candidateCliError -match '(?i)telemetry|FileSystem\.writeFile|EPERM') { 'CLI_TELEMETRY_WRITE_FAILURE' }
      elseif ($candidateCliError -match '(?i)connection refused|could not connect') { 'LOCAL_DATABASE_CONNECTION_FAILURE' }
      elseif ($candidateCliError -match '(?i)multiple commands into a prepared statement') { 'MULTI_STATEMENT_REJECTED' }
      else { 'CLI_FAILURE_UNCLASSIFIED' }
    Write-Host ("CLI candidate diagnostic: SQLSTATE={0}, category={1}" -f $sqlState,$failureCategory)
    $firstDiagnosticLine = ($candidateCliError -split "`r?`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -First 1)
    $firstDiagnosticLine = [regex]::Replace($firstDiagnosticLine, '(?i)postgres(?:ql)?://[^\s"'']+', '<db-url>')
    $firstDiagnosticLine = [regex]::Replace($firstDiagnosticLine, '(?i)[A-Z]:\\[^\r\n"'']+', '<local-path>')
    $firstDiagnosticLine = [regex]::Replace($firstDiagnosticLine, '\b[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}\b', '<uuid>')
    $firstDiagnosticLine = [regex]::Replace($firstDiagnosticLine, '\b[A-Za-z0-9_-]{30,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\b', '<token>')
    Write-Host ("CLI sanitized first line: {0}" -f $firstDiagnosticLine)
    throw 'corrected single-statement candidate was rejected by local Supabase CLI'
  }
  Write-Host 'PASS: single-statement candidate applied through local Supabase db query'
  $env:DO_NOT_TRACK = '1'
  & $psql @base -c 'REVOKE USAGE ON SCHEMA auth FROM hasad_rpc_owner; REVOKE EXECUTE ON FUNCTION auth.uid() FROM PUBLIC, hasad_rpc_owner;'
  if ($LASTEXITCODE -ne 0) { throw 'could not prepare local postflight rollback case' }
  $uidExecAfterRevoke = & $psql @base -t -A -c "SELECT has_function_privilege('hasad_rpc_owner','auth.uid()','EXECUTE')"
  if ($LASTEXITCODE -ne 0 -or ($uidExecAfterRevoke | Out-String).Trim() -ne 'f') {
    throw 'local rollback fixture did not remove auth.uid execute'
  }
  $rollbackResult = Invoke-HasadCliFile -CliPath $supabase `
    -Arguments @('db','query','--db-url',$localDbUrl,'--file',$candidate,'--output-format','json','--agent','yes') `
    -StandardOutputPath $cliStdout -StandardErrorPath $cliStderr
  if ($rollbackResult.ExitCode -eq 0 -or
      ($rollbackResult.StandardOutput + $rollbackResult.StandardError) -notmatch 'auth.uid execute privilege changed') {
    $rollbackText = $rollbackResult.StandardOutput + $rollbackResult.StandardError
    $rollbackCode = if ($rollbackText -match '(?i)SQLSTATE\s*[:= ]\s*([0-9A-Z]{5})') { $Matches[1] } else { 'NOT_EXPOSED' }
    $rollbackCategory = if ($rollbackText -match '(?i)multiple commands into a prepared statement') { 'MULTI_STATEMENT_PREPARED_QUERY' }
      elseif ($rollbackText -match '(?i)telemetry|FileSystem\.writeFile|EPERM') { 'CLI_TELEMETRY_WRITE_FAILURE' }
      else { 'CANDIDATE_POSTFLIGHT_REJECTION' }
    Write-Host ("Rollback diagnostic: SQLSTATE={0}, category={1}" -f $rollbackCode,$rollbackCategory)
    throw 'candidate postflight failure was not reproduced'
  }
  $ownerUsageAfterRollback = & $psql @base -t -A -c "SELECT has_schema_privilege('hasad_rpc_owner','auth','USAGE')"
  if ($LASTEXITCODE -ne 0 -or ($ownerUsageAfterRollback | Out-String).Trim() -ne 'f') {
    throw 'postflight failure did not roll back the local grant'
  }
  Write-Host 'PASS: candidate postflight failure rolled back the grant atomically'
  & $psql @base -c 'GRANT EXECUTE ON FUNCTION auth.uid() TO hasad_rpc_owner;'
  if ($LASTEXITCODE -ne 0) { throw 'could not restore local auth.uid fixture privilege' }
  $candidateCliResult = Invoke-HasadCliFile -CliPath $supabase `
    -Arguments @('db','query','--db-url',$localDbUrl,'--file',$candidate,'--output-format','json','--agent','yes') `
    -StandardOutputPath $cliStdout -StandardErrorPath $cliStderr
  if ($candidateCliResult.ExitCode -ne 0) { throw 'candidate did not pass after restoring the local fixture' }
  if ($null -eq $previousDoNotTrack) { Remove-Item Env:\DO_NOT_TRACK -ErrorAction SilentlyContinue }
  else { $env:DO_NOT_TRACK = $previousDoNotTrack }
  Write-Host 'PASS: candidate succeeded after restoring the intended preflight state'
  & $psql @base -f (Join-Path $repo 'security\candidates\local_security_tests.sql')
  if ($LASTEXITCODE -ne 0) { throw 'post-grant positive/negative checks failed' }
  $diagnosticSql = Join-Path $repo 'security\candidates\diagnose_dev_rpc_auth_usage_readonly.sql'
  $diagnosticOutput = & $psql @base -t -A -f $diagnosticSql
  if ($LASTEXITCODE -ne 0) { throw 'read-only catalog diagnostic SQL failed on disposable PostgreSQL' }
  try { $diagnosticResult = (($diagnosticOutput | Out-String).Trim() | ConvertFrom-Json -ErrorAction Stop) }
  catch { throw 'read-only catalog diagnostic result was not valid JSON' }
  if (-not $diagnosticResult.current_state.rpc_owner_auth_schema_usage -or
      -not $diagnosticResult.current_state.rpc_owner_auth_uid_execute -or
      $diagnosticResult.current_state.rpc_owner_auth_users_select -or
      $diagnosticResult.executor_authority.executor_is_superuser -isnot [bool] -or
      $diagnosticResult.executor_authority.executor_is_auth_schema_owner -isnot [bool] -or
      $diagnosticResult.executor_authority.executor_in_auth_schema_owner_role -isnot [bool] -or
      $diagnosticResult.executor_authority.executor_has_auth_usage_grant_option -isnot [bool] -or
      $diagnosticResult.executor_authority.executor_can_grant_auth_usage -isnot [bool] -or
      -not $diagnosticResult.executor_authority.executor_can_grant_auth_usage -or
      -not $diagnosticResult.candidate_assertion_status.postflight_force_rls_preserved) {
    throw 'read-only catalog diagnostic result contradicted the local post-grant state'
  }
  Write-Host 'PASS: read-only catalog diagnostic reports the local post-grant state'
  Write-Host 'PASS: PostgreSQL 17 RPC auth schema privilege regression harness'
}
finally {
  if ($started) {
    if ($null -ne $fallbackProcess -and -not $fallbackProcess.HasExited) {
      Stop-Process -Id $fallbackProcess.Id -Force -ErrorAction SilentlyContinue
      Wait-Process -Id $fallbackProcess.Id -Timeout 10 -ErrorAction SilentlyContinue
    } else {
      & $pgCtl -D $data -m immediate -t 10 -w stop
    }
  }
  $tempRoot = [System.IO.Path]::GetFullPath($env:TEMP)
  $target = [System.IO.Path]::GetFullPath($pgRoot)
  if ($target.StartsWith((Join-Path $tempRoot 'hasad-rpc-auth-usage-'), [System.StringComparison]::OrdinalIgnoreCase)) {
    Remove-Item -LiteralPath $target -Recurse -Force -ErrorAction SilentlyContinue
  }
}
