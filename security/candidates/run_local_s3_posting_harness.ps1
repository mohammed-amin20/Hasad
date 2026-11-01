# Disposable local PostgreSQL 17 verification for the S2 + S3 SQL candidates.
# It never targets Supabase or any non-local database.
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$pgBin = 'C:\Program Files\PostgreSQL\17\bin'
$psql = Join-Path $pgBin 'psql.exe'
$tempBase = Join-Path $env:LOCALAPPDATA 'Temp\opencode'
$root = Join-Path $tempBase ('hasad-sales-posting-' + [guid]::NewGuid().ToString('N'))
$data = Join-Path $root 'data'
$port = Get-Random -Minimum 56000 -Maximum 64000
New-Item -ItemType Directory -Path $root -Force | Out-Null

try {
  & (Join-Path $pgBin 'initdb.exe') -D $data -U postgres -A trust --no-locale *> $null
  if ($LASTEXITCODE -ne 0) { throw 'initdb failed' }

  $server = Start-Process (Join-Path $pgBin 'postgres.exe') `
    -ArgumentList @('-D',$data,'-p',"$port",'-h','127.0.0.1') `
    -WindowStyle Hidden -PassThru `
    -RedirectStandardOutput (Join-Path $root 'postgres.out.log') `
    -RedirectStandardError (Join-Path $root 'postgres.err.log')
  $args = @('-X','-w','-h','127.0.0.1','-p',"$port",'-U','postgres','-d','postgres','-v','ON_ERROR_STOP=1')
  $ready = $false
  for ($i=0; $i -lt 40; $i++) {
    # A brief "starting up" connection error is expected while postgres boots.
    $previousErrorAction = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    & $psql @args -c 'SELECT 1' *> $null
    $psqlExit = $LASTEXITCODE
    $ErrorActionPreference = $previousErrorAction
    if ($psqlExit -eq 0) { $ready = $true; break }
    Start-Sleep -Milliseconds 250
  }
  if (-not $ready) { throw 'local PostgreSQL did not become ready' }

  & $psql @args -f (Join-Path $PSScriptRoot 'tests\customers_harness_setup.sql')
  if ($LASTEXITCODE -ne 0) { throw 'auth harness setup failed' }
  foreach ($migration in @(
    'supabase\migrations\20261026000000_v2_foundation_schemas.sql',
    'supabase\migrations\20261026000100_v2_identity_tenancy_foundation.sql',
    'supabase\migrations\20261026000200_v2_permissions_foundation.sql',
    'supabase\migrations\20261026000210_v2_permission_catalogue_seed.sql',
    'supabase\migrations\20261027000300_v2_invitation_audit_structure.sql',
    'supabase\migrations\20261027000400_v2_erp_core_master_fiscal_settings.sql',
    'supabase\migrations\20261028000500_v2_accounting_journals_structure.sql',
    'supabase\migrations\20261028000600_v2_inventory_structure.sql',
    'supabase\migrations\20261028000700_v2_sales_purchases_structure.sql'
  )) {
    & $psql @args -f (Join-Path $repo $migration)
    if ($LASTEXITCODE -ne 0) { throw "migration failed: $migration" }
  }

  foreach ($script in @(
    'tests\customers_direct_read_setup.sql',
    'dev_sales_draft_atomic_candidate.sql',
    'dev_s3_post_sales_invoice_candidate.sql',
    'tests\s3_posting_harness_fixtures.sql',
    'tests\s3_posting_harness_assertions.sql'
  )) {
    & $psql @args -f (Join-Path $PSScriptRoot $script)
    if ($LASTEXITCODE -ne 0) { throw "S3 harness script failed: $script" }
  }

  $lockOut = Join-Path $root 'concurrency-lock.out.log'
  $lockErr = Join-Path $root 'concurrency-lock.err.log'
  $lockScript = Join-Path $PSScriptRoot 'tests\s3_concurrency_lock.sql'
  # Start-Process serializes an argument array without preserving the quoting
  # required by this repository path's space. Pass one quoted command line.
  $lockArguments = (($args + @('-f', ('"' + $lockScript + '"'))) -join ' ')
  $lock = Start-Process -FilePath $psql `
    -ArgumentList $lockArguments `
    -WindowStyle Hidden -PassThru -RedirectStandardOutput $lockOut -RedirectStandardError $lockErr
  Start-Sleep -Milliseconds 700
  if ($lock.HasExited) { throw "concurrency lock session ended early: $(Get-Content $lockOut -Raw) $(Get-Content $lockErr -Raw)" }

  $attemptScript = Join-Path $PSScriptRoot 'tests\s3_concurrency_attempt.sql'
  $previousErrorAction = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  $attemptOutput = (& $psql @args -f $attemptScript 2>&1 | Out-String)
  $attemptExit = $LASTEXITCODE
  $ErrorActionPreference = $previousErrorAction
  if ($attemptExit -eq 0 -or $attemptOutput -notmatch '57014') {
    throw "concurrent posting attempt did not fail with expected SQLSTATE 57014: $attemptOutput"
  }
  $lock.WaitForExit()
  $lockErrors = Get-Content $lockErr -Raw -ErrorAction SilentlyContinue
  if ($lockErrors -match 'ERROR:|FATAL:') {
    throw "concurrency lock session failed: $(Get-Content $lockOut -Raw) $lockErrors"
  }

  & $psql @args -f (Join-Path $PSScriptRoot 'tests\s3_concurrency_finish.sql')
  if ($LASTEXITCODE -ne 0) { throw 'concurrent posting completion assertions failed' }
  Write-Host 'PASS: local S3 sales invoice posting harness'
}
finally {
  if ($server -and -not $server.HasExited) { Stop-Process -Id $server.Id -Force }
  Start-Sleep -Milliseconds 500
  Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
}
