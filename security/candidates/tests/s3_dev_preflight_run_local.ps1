# Disposable PostgreSQL 17 verification for the READ-ONLY S3 DEV preflight.
# It never connects to Supabase, DEV or Production.
$ErrorActionPreference = 'Stop'
$candidates = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$pgBin = 'C:\Program Files\PostgreSQL\17\bin'
$psql = Join-Path $pgBin 'psql.exe'
$createdb = Join-Path $pgBin 'createdb.exe'
$preflight = Join-Path $candidates 's3_dev_preflight_readonly.sql'
$tempBase = Join-Path $env:LOCALAPPDATA 'Temp\opencode'
$root = Join-Path $tempBase ('hasad-s3-dev-preflight-' + [guid]::NewGuid().ToString('N'))
$data = Join-Path $root 'data'
$port = Get-Random -Minimum 56000 -Maximum 64000
New-Item -ItemType Directory -Path $root -Force | Out-Null

function Invoke-SqlFile([string[]] $dbArgs, [string] $path, [string] $label) {
  & $psql @dbArgs -f $path
  if ($LASTEXITCODE -ne 0) { throw "$label failed: $path" }
}

$script:rolesInitialized = $false
function Initialize-AuthHarness([string[]] $dbArgs) {
  if (-not $script:rolesInitialized) {
    Invoke-SqlFile $dbArgs (Join-Path $PSScriptRoot 'customers_harness_setup.sql') 'auth harness setup'
    $script:rolesInitialized = $true
  }
  else {
    Invoke-SqlFile $dbArgs (Join-Path $PSScriptRoot 's3_accounting_configuration_auth_schema_setup.sql') 'auth schema setup'
  }
}

function Initialize-PreflightDatabase([string[]] $dbArgs) {
  Initialize-AuthHarness $dbArgs
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
    Invoke-SqlFile $dbArgs (Join-Path $repo $migration) "preflight migration $migration"
  }
  Invoke-SqlFile $dbArgs (Join-Path $PSScriptRoot 'customers_direct_read_setup.sql') 'preflight S2 read setup'
  Invoke-SqlFile $dbArgs (Join-Path $candidates 'dev_sales_draft_atomic_candidate.sql') 'S2 draft candidate'
  Invoke-SqlFile $dbArgs (Join-Path $PSScriptRoot 's3_dev_preflight_harness_fixtures.sql') 'preflight fixtures'
}

function Invoke-Preflight([string[]] $dbArgs) {
  $previousErrorAction = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  $output = (& $psql @dbArgs -X -q -A -t -F '|' -f $preflight 2>&1 | Out-String)
  $exitCode = $LASTEXITCODE
  $ErrorActionPreference = $previousErrorAction
  if ($exitCode -ne 0) { throw "preflight SQL failed:`n$output" }
  return @($output -split "`r?`n" | Where-Object { $_ -match '^\d+\|' })
}

function Get-CheckStatus([string[]] $rows, [string] $name) {
  $row = $rows | Where-Object { ($_ -split '\|')[1] -eq $name } | Select-Object -First 1
  if (-not $row) { throw "preflight check missing: $name" }
  return ($row -split '\|')[2]
}

function Assert-AllPass([string[]] $rows) {
  if ($rows.Count -ne 28) { throw "preflight returned $($rows.Count) rows; expected 27 checks + OVERALL" }
  $failures = @($rows | Where-Object { ($_ -split '\|')[2] -ne 'PASS' })
  if ($failures.Count -gt 0) { throw "preflight reported FAIL:`n$($failures -join "`n")" }
  if ((Get-CheckStatus $rows 'OVERALL') -ne 'PASS') { throw 'preflight OVERALL did not report PASS' }
}

function Show-Preflight([string[]] $rows) {
  foreach ($row in $rows) {
    $parts = $row -split '\|'
    Write-Host ("  {0,-2} {1,-40} {2}" -f $parts[0], $parts[1], $parts[2])
  }
}

try {
  & (Join-Path $pgBin 'initdb.exe') -D $data -U postgres -A trust --no-locale *> $null
  if ($LASTEXITCODE -ne 0) { throw 'initdb failed' }
  $server = Start-Process (Join-Path $pgBin 'postgres.exe') `
    -ArgumentList @('-D',$data,'-p',"$port",'-h','127.0.0.1') `
    -WindowStyle Hidden -PassThru `
    -RedirectStandardOutput (Join-Path $root 'postgres.out.log') `
    -RedirectStandardError (Join-Path $root 'postgres.err.log')
  $baseArgs = @('-X','-w','-h','127.0.0.1','-p',"$port",'-U','postgres','-v','ON_ERROR_STOP=1')
  $postgresArgs = $baseArgs + @('-d','postgres')
  $ready = $false
  for ($i = 0; $i -lt 40; $i++) {
    $previousErrorAction = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    & $psql @postgresArgs -c 'SELECT 1' *> $null
    $psqlExit = $LASTEXITCODE
    $ErrorActionPreference = $previousErrorAction
    if ($psqlExit -eq 0) { $ready = $true; break }
    Start-Sleep -Milliseconds 250
  }
  if (-not $ready) { throw 'local PostgreSQL did not become ready' }

  # 1. DEV-shaped success database: every check must be PASS.
  $successDb = 'hasad_s3_dev_preflight_success'
  & $createdb -h '127.0.0.1' -p "$port" -U postgres $successDb
  if ($LASTEXITCODE -ne 0) { throw 'success preflight database creation failed' }
  $successArgs = $baseArgs + @('-d', $successDb)
  Initialize-PreflightDatabase $successArgs
  $successRows = Invoke-Preflight $successArgs
  Assert-AllPass $successRows
  Show-Preflight $successRows
  Write-Host 'PASS: local S3 DEV preflight success harness'

  # 2. Negative database: duplicate Abo Amen, wrong SI prefix, missing periods.
  $conflictDb = 'hasad_s3_dev_preflight_conflict'
  & $createdb -h '127.0.0.1' -p "$port" -U postgres $conflictDb
  if ($LASTEXITCODE -ne 0) { throw 'conflict preflight database creation failed' }
  $conflictArgs = $baseArgs + @('-d', $conflictDb)
  Initialize-PreflightDatabase $conflictArgs
  Invoke-SqlFile $conflictArgs (Join-Path $PSScriptRoot 's3_dev_preflight_harness_conflict_setup.sql') 'conflict setup'
  $conflictRows = Invoke-Preflight $conflictArgs
  if ((Get-CheckStatus $conflictRows 'ABO_AMEN_COMPANY_SELECTOR') -ne 'FAIL') {
    throw 'preflight did not fail the ambiguous Abo Amen selector'
  }
  if ((Get-CheckStatus $conflictRows 'SI_DOCUMENT_TYPE_CONTRACT') -ne 'FAIL') {
    throw 'preflight did not fail the conflicting SI prefix'
  }
  if ((Get-CheckStatus $conflictRows 'FISCAL_PERIODS_OCTOBER_ONLY') -ne 'FAIL') {
    throw 'preflight did not fail the missing fiscal periods'
  }
  if ((Get-CheckStatus $conflictRows 'OVERALL') -ne 'FAIL') {
    throw 'preflight OVERALL did not fail for the negative fixture'
  }
  Write-Host 'PASS: local S3 DEV preflight negative harness'

  # 3. Already-installed database: function/policy conflicts must be reported.
  $installedDb = 'hasad_s3_dev_preflight_installed'
  & $createdb -h '127.0.0.1' -p "$port" -U postgres $installedDb
  if ($LASTEXITCODE -ne 0) { throw 'installed preflight database creation failed' }
  $installedArgs = $baseArgs + @('-d', $installedDb)
  Initialize-PreflightDatabase $installedArgs
  Invoke-SqlFile $installedArgs (Join-Path $candidates 'dev_s3_post_sales_invoice_candidate.sql') 'S3 posting candidate'
  $installedRows = Invoke-Preflight $installedArgs
  if ((Get-CheckStatus $installedRows 'NO_S3_FUNCTION_CONFLICT') -ne 'FAIL') {
    throw 'preflight did not detect already-installed S3 functions'
  }
  if ((Get-CheckStatus $installedRows 'NO_S3_POLICY_NAME_CONFLICT') -ne 'FAIL') {
    throw 'preflight did not detect already-installed S3 policies'
  }
  if ((Get-CheckStatus $installedRows 'OVERALL') -ne 'FAIL') {
    throw 'preflight OVERALL did not fail after an S3 installation'
  }
  Write-Host 'PASS: local S3 DEV preflight installed-conflict harness'

  Write-Host 'PASS: local S3 DEV preflight harness'
}
finally {
  if ($server -and -not $server.HasExited) { Stop-Process -Id $server.Id -Force }
  Start-Sleep -Milliseconds 500
  Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
}
