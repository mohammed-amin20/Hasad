# Hasad ERP V2 — local validation for the prepared Core-nine migration.
# Never connects to Supabase DEV or production. Uses a fresh local PostgreSQL
# cluster and removes it after catalog verification.

[CmdletBinding()]
param(
  [int]$Port = 55434,
  [string]$PgBin = 'C:\Program Files\PostgreSQL\17\bin'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$migration = Join-Path $repo 'supabase\migrations\20261027000400_v2_erp_core_master_fiscal_settings.sql'
$pre = Join-Path $PSScriptRoot 'poc_c1_c2_local_pre.sql'
$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$data = Join-Path $env:TEMP "opencode\hasad_core_nine_$stamp"
$pgProcess = $null

function Assert-True([bool]$Condition, [string]$Message) {
  if (-not $Condition) { throw "VALIDATION FAILED: $Message" }
}

function Invoke-PsqlFile([string]$File) {
  & (Join-Path $PgBin 'psql.exe') -X -h 127.0.0.1 -p $Port -U postgres `
    -d hasad_core_nine -v ON_ERROR_STOP=1 -f $File
  if ($LASTEXITCODE -ne 0) { throw "psql failed for $File" }
}

try {
  Assert-True (Test-Path -LiteralPath $migration -PathType Leaf) 'Core-nine migration is absent.'
  Assert-True (Test-Path -LiteralPath $pre -PathType Leaf) 'Local auth stub is absent.'
  Assert-True (-not (Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue)) "Port $Port is already in use."

  $sql = Get-Content -LiteralPath $migration -Raw
  $sqlWithoutComments = [regex]::Replace($sql, '(?m)^\s*--.*(?:\r?\n|$)', '')
  $tables = @([regex]::Matches($sqlWithoutComments, '(?im)^\s*CREATE\s+TABLE\s+hasad\.([a-z_]+)\s*\(') |
    ForEach-Object { $_.Groups[1].Value } | Sort-Object)
  $expectedTables = @('accounts','company_settings','doc_numbers','document_types','fiscal_periods','fiscal_years','module_account_map','parties','tax_rates')
  Assert-True ($tables.Count -eq 9 -and -not (Compare-Object $expectedTables $tables -SyncWindow 0)) 'Migration must create exactly the nine Core tables.'
  Assert-True (([regex]::Matches($sqlWithoutComments, 'ON\s+DELETE\s+RESTRICT')).Count -eq 18) 'Expected exactly 18 restrictive FKs.'
  Assert-True (([regex]::Matches($sqlWithoutComments, '(?im)^\s*CREATE\s+(UNIQUE\s+)?INDEX')).Count -eq 8) 'Expected exactly 8 explicit indexes.'
  Assert-True (([regex]::Matches($sqlWithoutComments, 'ENABLE\s+ROW\s+LEVEL\s+SECURITY')).Count -eq 9) 'Expected ENABLE RLS on nine tables.'
  Assert-True (([regex]::Matches($sqlWithoutComments, 'FORCE\s+ROW\s+LEVEL\s+SECURITY')).Count -eq 9) 'Expected FORCE RLS on nine tables.'
  Assert-True (-not ($sqlWithoutComments -match '(?im)^\s*(INSERT|UPDATE|DELETE|TRUNCATE)\b')) 'Migration must not contain DML.'
  foreach ($forbidden in @('CASCADE', 'CREATE POLICY', 'GRANT ', 'REVOKE ', 'CREATE FUNCTION', 'CREATE TRIGGER', 'CREATE PROCEDURE', 'DROP ', 'CREATE ROLE', 'ALTER ROLE', 'auth.', 'storage.')) {
    Assert-True (-not $sqlWithoutComments.Contains($forbidden)) "Forbidden SQL found: $forbidden"
  }
  Write-Output 'STATIC_CONTRACT=PASS'

  & (Join-Path $PgBin 'initdb.exe') -D $data -A trust -U postgres --encoding=UTF8 --locale=C *> $null
  if ($LASTEXITCODE -ne 0) { throw 'initdb failed.' }
  $stdout = Join-Path $env:TEMP "opencode\hasad_core_nine_$stamp.stdout.log"
  $stderr = Join-Path $env:TEMP "opencode\hasad_core_nine_$stamp.stderr.log"
  $pgProcess = Start-Process -FilePath (Join-Path $PgBin 'postgres.exe') `
    -ArgumentList @('-D', $data, '-p', "$Port", '-c', 'listen_addresses=127.0.0.1', '-c', 'logging_collector=off') `
    -NoNewWindow -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
  $ready = $false
  for ($i = 0; $i -lt 40; $i++) {
    & (Join-Path $PgBin 'pg_isready.exe') -h 127.0.0.1 -p $Port -U postgres -d postgres *> $null
    if ($LASTEXITCODE -eq 0) { $ready = $true; break }
    Start-Sleep -Milliseconds 500
  }
  Assert-True $ready 'Local PostgreSQL did not become ready.'
  & (Join-Path $PgBin 'createdb.exe') -h 127.0.0.1 -p $Port -U postgres hasad_core_nine
  if ($LASTEXITCODE -ne 0) { throw 'createdb failed.' }

  Invoke-PsqlFile $pre
  foreach ($name in @(
    '20261026000000_v2_foundation_schemas.sql',
    '20261026000100_v2_identity_tenancy_foundation.sql',
    '20261026000200_v2_permissions_foundation.sql',
    '20261026000210_v2_permission_catalogue_seed.sql',
    '20261027000300_v2_invitation_audit_structure.sql',
    '20261027000400_v2_erp_core_master_fiscal_settings.sql'
  )) {
    Invoke-PsqlFile (Join-Path $repo "supabase\migrations\$name")
  }

  $verify = @'
DO $verify$
DECLARE v_count int;
BEGIN
  SELECT count(*) INTO v_count
  FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
  WHERE n.nspname='hasad' AND c.relkind IN ('r','p')
    AND c.relname IN ('company_settings','accounts','module_account_map','fiscal_years','fiscal_periods','document_types','tax_rates','doc_numbers','parties');
  IF v_count <> 9 THEN RAISE EXCEPTION 'expected 9 core tables, found %', v_count; END IF;

  SELECT count(*) INTO v_count
  FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
  WHERE n.nspname='hasad' AND c.relkind IN ('r','p')
    AND c.relname IN ('company_settings','accounts','module_account_map','fiscal_years','fiscal_periods','document_types','tax_rates','doc_numbers','parties')
    AND c.relrowsecurity AND c.relforcerowsecurity;
  IF v_count <> 9 THEN RAISE EXCEPTION 'forced RLS missing on core tables'; END IF;

  SELECT count(*) INTO v_count
  FROM pg_constraint con
  WHERE con.contype='f'
    AND con.conrelid IN ('hasad.company_settings'::regclass,'hasad.accounts'::regclass,'hasad.module_account_map'::regclass,'hasad.fiscal_years'::regclass,'hasad.fiscal_periods'::regclass,'hasad.document_types'::regclass,'hasad.tax_rates'::regclass,'hasad.doc_numbers'::regclass,'hasad.parties'::regclass)
    AND con.confdeltype='r';
  IF v_count <> 18 THEN RAISE EXCEPTION 'expected 18 RESTRICT FKs, found %', v_count; END IF;

  SELECT count(*) INTO v_count
  FROM pg_class c WHERE c.relname IN ('accounts_company_parent_idx','module_account_map_company_account_idx','fiscal_years_company_status_idx','fiscal_periods_company_status_dates_idx','tax_rates_company_active_code_idx','parties_company_name_ar_idx','parties_company_customer_idx','parties_company_supplier_idx');
  IF v_count <> 8 THEN RAISE EXCEPTION 'expected 8 core indexes, found %', v_count; END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='accounts_company_parent_fkey')
     OR NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='fiscal_periods_company_year_fkey')
     OR NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='doc_numbers_company_document_type_fkey')
     OR NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='doc_numbers_company_fiscal_year_fkey') THEN
    RAISE EXCEPTION 'required tenant-safe composite FK missing';
  END IF;

  SELECT count(*) INTO v_count FROM information_schema.columns
  WHERE table_schema='hasad' AND table_name IN ('company_settings','accounts','module_account_map','fiscal_years','fiscal_periods','document_types','tax_rates','doc_numbers','parties');
  IF v_count <> 88 THEN RAISE EXCEPTION 'expected 88 core columns, found %', v_count; END IF;

  SELECT count(*) INTO v_count FROM pg_policy p
  WHERE p.polrelid IN ('hasad.company_settings'::regclass,'hasad.accounts'::regclass,'hasad.module_account_map'::regclass,'hasad.fiscal_years'::regclass,'hasad.fiscal_periods'::regclass,'hasad.document_types'::regclass,'hasad.tax_rates'::regclass,'hasad.doc_numbers'::regclass,'hasad.parties'::regclass);
  IF v_count <> 0 THEN RAISE EXCEPTION 'core policies must be absent'; END IF;

  SELECT count(*) INTO v_count FROM pg_trigger t
  WHERE t.tgrelid IN ('hasad.company_settings'::regclass,'hasad.accounts'::regclass,'hasad.module_account_map'::regclass,'hasad.fiscal_years'::regclass,'hasad.fiscal_periods'::regclass,'hasad.document_types'::regclass,'hasad.tax_rates'::regclass,'hasad.doc_numbers'::regclass,'hasad.parties'::regclass)
    AND NOT t.tgisinternal;
  IF v_count <> 0 THEN RAISE EXCEPTION 'core triggers must be absent'; END IF;

  SELECT count(*) INTO v_count
  FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
  WHERE n.nspname='hasad' AND c.relname IN ('company_settings','accounts','module_account_map','fiscal_years','fiscal_periods','document_types','tax_rates','doc_numbers','parties') AND c.relacl IS NOT NULL;
  IF v_count <> 0 THEN RAISE EXCEPTION 'core table ACLs must be absent'; END IF;

  IF (SELECT count(*) FROM hasad.company_settings) <> 0 OR (SELECT count(*) FROM hasad.accounts) <> 0 OR (SELECT count(*) FROM hasad.module_account_map) <> 0 OR (SELECT count(*) FROM hasad.fiscal_years) <> 0 OR (SELECT count(*) FROM hasad.fiscal_periods) <> 0 OR (SELECT count(*) FROM hasad.document_types) <> 0 OR (SELECT count(*) FROM hasad.tax_rates) <> 0 OR (SELECT count(*) FROM hasad.doc_numbers) <> 0 OR (SELECT count(*) FROM hasad.parties) <> 0 THEN
    RAISE EXCEPTION 'core tables must be empty';
  END IF;
  RAISE NOTICE 'PASS: Core-nine structural catalog matches the prepared contract';
END
$verify$;
'@
  & (Join-Path $PgBin 'psql.exe') -X -h 127.0.0.1 -p $Port -U postgres -d hasad_core_nine -v ON_ERROR_STOP=1 -c $verify
  if ($LASTEXITCODE -ne 0) { throw 'Catalog verification failed.' }
  Write-Output 'LOCAL_CATALOG=PASS'
}
finally {
  if ($pgProcess -and -not $pgProcess.HasExited) {
    & (Join-Path $PgBin 'pg_ctl.exe') -D $data -m fast stop *> $null
    Start-Sleep -Seconds 1
    if (-not $pgProcess.HasExited) { Stop-Process -Id $pgProcess.Id -Force -ErrorAction SilentlyContinue }
  }
  if (Test-Path -LiteralPath $data) { Remove-Item -LiteralPath $data -Recurse -Force -ErrorAction SilentlyContinue }
}
