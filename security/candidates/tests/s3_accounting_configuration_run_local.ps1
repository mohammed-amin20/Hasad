# Disposable PostgreSQL 17 verification for the review-only S3 accounting
# configuration candidate. It never connects to Supabase or another remote DB.
$ErrorActionPreference = 'Stop'
$candidates = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$pgBin = 'C:\Program Files\PostgreSQL\17\bin'
$psql = Join-Path $pgBin 'psql.exe'
$createdb = Join-Path $pgBin 'createdb.exe'
$tempBase = Join-Path $env:LOCALAPPDATA 'Temp\opencode'
$root = Join-Path $tempBase ('hasad-s3-accounting-config-' + [guid]::NewGuid().ToString('N'))
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

function Initialize-HarnessDatabase([string[]] $dbArgs) {
  Initialize-AuthHarness $dbArgs
  foreach ($migration in @(
    'supabase\migrations\20261026000000_v2_foundation_schemas.sql',
    'supabase\migrations\20261026000100_v2_identity_tenancy_foundation.sql',
    'supabase\migrations\20261026000200_v2_permissions_foundation.sql',
    'supabase\migrations\20261026000210_v2_permission_catalogue_seed.sql',
    'supabase\migrations\20261027000300_v2_invitation_audit_structure.sql',
    'supabase\migrations\20261027000400_v2_erp_core_master_fiscal_settings.sql'
  )) {
    Invoke-SqlFile $dbArgs (Join-Path $repo $migration) "migration $migration"
  }
  Invoke-SqlFile $dbArgs (Join-Path $PSScriptRoot 's3_accounting_configuration_harness_fixtures.sql') 'configuration fixtures'
}

function Invoke-ConfigurationCandidate([string[]] $dbArgs) {
  & $psql @dbArgs `
    -c "SET hasad_s3_config.open_period_nos = '[10]'" `
    -c "SET hasad_s3_config.ar_control_code = 'TEST-AR'" `
    -c "SET hasad_s3_config.sales_revenue_code = 'TEST-REV'" `
    -c "SET hasad_s3_config.cogs_code = 'TEST-COGS'" `
    -c "SET hasad_s3_config.inventory_control_code = 'TEST-INV'" `
    -f (Join-Path $candidates 'dev_s3_abo_amen_accounting_configuration_candidate.sql')
}

function Invoke-NumberingConfigurationCandidate([string[]] $dbArgs) {
  & $psql @dbArgs `
    -c "SET hasad_s3_config.open_period_nos = '[10]'" `
    -c "SET hasad_s3_config.ar_control_code = '1100'" `
    -c "SET hasad_s3_config.sales_revenue_code = '4100'" `
    -c "SET hasad_s3_config.cogs_code = '5100'" `
    -c "SET hasad_s3_config.inventory_control_code = '1200'" `
    -f (Join-Path $candidates 'dev_s3_abo_amen_accounting_configuration_candidate.sql')
}

function Initialize-NumberingDatabase([string[]] $dbArgs) {
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
    Invoke-SqlFile $dbArgs (Join-Path $repo $migration) "numbering migration $migration"
  }
  Invoke-SqlFile $dbArgs (Join-Path $PSScriptRoot 'customers_direct_read_setup.sql') 'numbering direct read setup'
  Invoke-SqlFile $dbArgs (Join-Path $candidates 'dev_sales_draft_atomic_candidate.sql') 'S2 draft candidate'
  Invoke-SqlFile $dbArgs (Join-Path $PSScriptRoot 's3_posting_harness_fixtures.sql') 'S3 posting fixture'
  Invoke-SqlFile $dbArgs (Join-Path $PSScriptRoot 's3_accounting_configuration_numbering_setup.sql') 'numbering Abo Amen selector setup'
}

function Initialize-ChartDatabase([string[]] $dbArgs) {
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
    Invoke-SqlFile $dbArgs (Join-Path $repo $migration) "chart migration $migration"
  }
  Invoke-SqlFile $dbArgs (Join-Path $PSScriptRoot 's3_accounting_configuration_chart_harness_fixtures.sql') 'chart fixtures'
}

function Invoke-ChartCandidate([string[]] $dbArgs) {
  & $psql @dbArgs -f (Join-Path $candidates 'dev_s3_abo_amen_chart_of_accounts_candidate.sql')
}

function Initialize-JePeriodsDatabase([string[]] $dbArgs) {
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
    Invoke-SqlFile $dbArgs (Join-Path $repo $migration) "JE/period migration $migration"
  }
  Invoke-SqlFile $dbArgs (Join-Path $PSScriptRoot 's3_je_fiscal_periods_harness_fixtures.sql') 'JE/period fixtures'
}

function Invoke-JePeriodsCandidate([string[]] $dbArgs) {
  & $psql @dbArgs `
    -c "SET hasad_s3_config.open_period_nos = '[10]'" `
    -f (Join-Path $candidates 'dev_s3_abo_amen_je_fiscal_periods_candidate.sql')
}

function Initialize-SiPrefixDatabase([string[]] $dbArgs) {
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
    Invoke-SqlFile $dbArgs (Join-Path $repo $migration) "SI prefix migration $migration"
  }
  Invoke-SqlFile $dbArgs (Join-Path $PSScriptRoot 's3_si_prefix_harness_fixtures.sql') 'SI prefix fixtures'
}

function Invoke-SiPrefixCandidate([string[]] $dbArgs) {
  & $psql @dbArgs -f (Join-Path $candidates 'dev_s3_abo_amen_si_prefix_candidate.sql')
}

function Invoke-ExpectedChartFailure([string] $database, [string] $setupFile, [string] $expectedError) {
  & $createdb -h '127.0.0.1' -p "$port" -U postgres $database
  if ($LASTEXITCODE -ne 0) { throw "chart failure database creation failed: $database" }
  $failureArgs = $baseArgs + @('-d',$database)
  Initialize-ChartDatabase $failureArgs
  Invoke-SqlFile $failureArgs (Join-Path $PSScriptRoot $setupFile) "chart conflict setup $setupFile"
  $previousErrorAction = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  $failureOutput = (Invoke-ChartCandidate $failureArgs 2>&1 | Out-String)
  $failureExit = $LASTEXITCODE
  $ErrorActionPreference = $previousErrorAction
  if ($failureExit -eq 0 -or $failureOutput -notmatch $expectedError) {
    throw "chart candidate did not fail with ${expectedError}: $failureOutput"
  }
  Invoke-SqlFile $failureArgs (Join-Path $PSScriptRoot 's3_accounting_configuration_chart_rollback_assertions.sql') 'chart rollback assertions'
}

function Invoke-ExpectedJePeriodsFailure([string] $database) {
  & $createdb -h '127.0.0.1' -p "$port" -U postgres $database
  if ($LASTEXITCODE -ne 0) { throw "JE/period rollback database creation failed: $database" }
  $failureArgs = $baseArgs + @('-d',$database)
  Initialize-JePeriodsDatabase $failureArgs
  Invoke-SqlFile $failureArgs (Join-Path $PSScriptRoot 's3_je_fiscal_periods_rollback_setup.sql') 'JE/period conflict setup'
  $previousErrorAction = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  $failureOutput = (Invoke-JePeriodsCandidate $failureArgs 2>&1 | Out-String)
  $failureExit = $LASTEXITCODE
  $ErrorActionPreference = $previousErrorAction
  if ($failureExit -eq 0 -or $failureOutput -notmatch 'JE_DOCUMENT_TYPE_CONFLICT') {
    throw "JE/period candidate did not fail at expected conflict: $failureOutput"
  }
  Invoke-SqlFile $failureArgs (Join-Path $PSScriptRoot 's3_je_fiscal_periods_rollback_assertions.sql') 'JE/period rollback assertions'
}

function Invoke-ExpectedSiPrefixFailure([string] $database) {
  & $createdb -h '127.0.0.1' -p "$port" -U postgres $database
  if ($LASTEXITCODE -ne 0) { throw "SI prefix rollback database creation failed: $database" }
  $failureArgs = $baseArgs + @('-d',$database)
  Initialize-SiPrefixDatabase $failureArgs
  Invoke-SqlFile $failureArgs (Join-Path $PSScriptRoot 's3_si_prefix_conflict_setup.sql') 'SI prefix conflict setup'
  $previousErrorAction = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  $failureOutput = (Invoke-SiPrefixCandidate $failureArgs 2>&1 | Out-String)
  $failureExit = $LASTEXITCODE
  $ErrorActionPreference = $previousErrorAction
  if ($failureExit -eq 0 -or $failureOutput -notmatch 'SI_PREFIX_CONFLICT') {
    throw "SI prefix candidate did not fail at expected conflict: $failureOutput"
  }
  Invoke-SqlFile $failureArgs (Join-Path $PSScriptRoot 's3_si_prefix_rollback_assertions.sql') 'SI prefix rollback assertions'
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
  for ($i=0; $i -lt 40; $i++) {
    $previousErrorAction = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    & $psql @postgresArgs -c 'SELECT 1' *> $null
    $psqlExit = $LASTEXITCODE
    $ErrorActionPreference = $previousErrorAction
    if ($psqlExit -eq 0) { $ready = $true; break }
    Start-Sleep -Milliseconds 250
  }
  if (-not $ready) { throw 'local PostgreSQL did not become ready' }

  # Success then rerun-safety database.
  Initialize-HarnessDatabase $postgresArgs
  Invoke-ConfigurationCandidate $postgresArgs
  if ($LASTEXITCODE -ne 0) { throw 'initial configuration candidate run failed' }
  Invoke-ConfigurationCandidate $postgresArgs
  if ($LASTEXITCODE -ne 0) { throw 'idempotent configuration candidate rerun failed' }
  Invoke-SqlFile $postgresArgs (Join-Path $PSScriptRoot 's3_accounting_configuration_harness_assertions.sql') 'configuration assertions'

  # Separate database: a JE conflict must roll every preceding candidate write back.
  $rollbackDb = 'hasad_s3_config_rollback'
  & $createdb -h '127.0.0.1' -p "$port" -U postgres $rollbackDb
  if ($LASTEXITCODE -ne 0) { throw 'rollback harness database creation failed' }
  $rollbackArgs = $baseArgs + @('-d',$rollbackDb)
  Initialize-HarnessDatabase $rollbackArgs
  Invoke-SqlFile $rollbackArgs (Join-Path $PSScriptRoot 's3_accounting_configuration_harness_rollback_setup.sql') 'rollback conflict setup'
  $previousErrorAction = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  $rollbackOutput = (Invoke-ConfigurationCandidate $rollbackArgs 2>&1 | Out-String)
  $rollbackExit = $LASTEXITCODE
  $ErrorActionPreference = $previousErrorAction
  if ($rollbackExit -eq 0 -or $rollbackOutput -notmatch 'JE_DOCUMENT_TYPE_CONFLICT') {
    throw "rollback candidate did not fail at the expected JE conflict: $rollbackOutput"
  }
  Invoke-SqlFile $rollbackArgs (Join-Path $PSScriptRoot 's3_accounting_configuration_harness_rollback_assertions.sql') 'rollback assertions'

  # Separate full posting database: fiscal-year-derived numbers must reset
  # without colliding with the company-wide official document-number index.
  $numberingDb = 'hasad_s3_numbering'
  & $createdb -h '127.0.0.1' -p "$port" -U postgres $numberingDb
  if ($LASTEXITCODE -ne 0) { throw 'numbering harness database creation failed' }
  $numberingArgs = $baseArgs + @('-d',$numberingDb)
  Initialize-NumberingDatabase $numberingArgs
  Invoke-NumberingConfigurationCandidate $numberingArgs
  if ($LASTEXITCODE -ne 0) { throw 'numbering configuration candidate run failed' }
  Invoke-SqlFile $numberingArgs (Join-Path $candidates 'dev_s3_post_sales_invoice_candidate.sql') 'S3 posting candidate with corrected numbering'
  Invoke-SqlFile $numberingArgs (Join-Path $PSScriptRoot 's3_accounting_configuration_numbering_assertions.sql') 'yearly numbering assertions'

  # Approved five-account chart: exact values, idempotency, tenant isolation,
  # and three independent conflict/rollback paths.
  $chartDb = 'hasad_s3_chart_success'
  & $createdb -h '127.0.0.1' -p "$port" -U postgres $chartDb
  if ($LASTEXITCODE -ne 0) { throw 'chart success database creation failed' }
  $chartArgs = $baseArgs + @('-d',$chartDb)
  Initialize-ChartDatabase $chartArgs
  Invoke-ChartCandidate $chartArgs
  if ($LASTEXITCODE -ne 0) { throw 'approved chart candidate initial run failed' }
  Invoke-ChartCandidate $chartArgs
  if ($LASTEXITCODE -ne 0) { throw 'approved chart candidate rerun failed' }
  Invoke-SqlFile $chartArgs (Join-Path $PSScriptRoot 's3_accounting_configuration_chart_harness_assertions.sql') 'chart assertions'
  Invoke-ExpectedChartFailure 'hasad_s3_chart_name_conflict' 's3_accounting_configuration_chart_name_conflict_setup.sql' 'ACCOUNT_CONFLICT'
  Invoke-ExpectedChartFailure 'hasad_s3_chart_type_conflict' 's3_accounting_configuration_chart_type_conflict_setup.sql' 'ACCOUNT_CONFLICT'
  Invoke-ExpectedChartFailure 'hasad_s3_chart_mapping_conflict' 's3_accounting_configuration_chart_mapping_conflict_setup.sql' 'ACCOUNT_MAPPING_CONFLICT'

  # Proposed October-only fiscal opening: rerun safety, no side effects, tenant
  # isolation, and a JE-conflict rollback after period writes are attempted.
  $jePeriodsDb = 'hasad_s3_je_periods_success'
  & $createdb -h '127.0.0.1' -p "$port" -U postgres $jePeriodsDb
  if ($LASTEXITCODE -ne 0) { throw 'JE/period success database creation failed' }
  $jePeriodsArgs = $baseArgs + @('-d',$jePeriodsDb)
  Initialize-JePeriodsDatabase $jePeriodsArgs
  Invoke-JePeriodsCandidate $jePeriodsArgs
  if ($LASTEXITCODE -ne 0) { throw 'JE/period candidate initial run failed' }
  Invoke-JePeriodsCandidate $jePeriodsArgs
  if ($LASTEXITCODE -ne 0) { throw 'JE/period candidate rerun failed' }
  Invoke-SqlFile $jePeriodsArgs (Join-Path $PSScriptRoot 's3_je_fiscal_periods_harness_assertions.sql') 'JE/period assertions'
  Invoke-ExpectedJePeriodsFailure 'hasad_s3_je_periods_conflict'

  # Minimal SI prefix candidate: NULL-to-SI, safe rerun, tenant isolation and
  # conflicting-prefix rollback with no financial side effects.
  $siPrefixDb = 'hasad_s3_si_prefix_success'
  & $createdb -h '127.0.0.1' -p "$port" -U postgres $siPrefixDb
  if ($LASTEXITCODE -ne 0) { throw 'SI prefix success database creation failed' }
  $siPrefixArgs = $baseArgs + @('-d',$siPrefixDb)
  Initialize-SiPrefixDatabase $siPrefixArgs
  Invoke-SiPrefixCandidate $siPrefixArgs
  if ($LASTEXITCODE -ne 0) { throw 'SI prefix candidate initial run failed' }
  Invoke-SiPrefixCandidate $siPrefixArgs
  if ($LASTEXITCODE -ne 0) { throw 'SI prefix candidate rerun failed' }
  Invoke-SqlFile $siPrefixArgs (Join-Path $PSScriptRoot 's3_si_prefix_harness_assertions.sql') 'SI prefix assertions'
  Invoke-ExpectedSiPrefixFailure 'hasad_s3_si_prefix_conflict'
  Write-Host 'PASS: local S3 accounting configuration harness'
}
finally {
  if ($server -and -not $server.HasExited) { Stop-Process -Id $server.Id -Force }
  Start-Sleep -Milliseconds 500
  Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
}
