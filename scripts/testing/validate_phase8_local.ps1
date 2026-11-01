# Runs Phase 8 structural tests against two isolated local PostgreSQL databases.
# Never connects to Supabase DEV or production. The auth.users fixture is local-only.
[CmdletBinding()]
param(
  [int]$Port = 55441,
  [string]$PgBin = 'C:\Program Files\PostgreSQL\17\bin'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$fixture = Join-Path $PSScriptRoot 'phase8_local_supabase_compat.sql'
$migrationDir = Join-Path $repo 'supabase\migrations'
$stamp = Get-Date -Format 'yyyyMMdd_HHmmss_fff'
$data = Join-Path $env:TEMP "hasad_phase8_local_$stamp"
$dbA = "phase8_a_$stamp"
$dbB = "phase8_b_$stamp"
$server = $null
$ready = $false
$pgctl = Join-Path $PgBin 'pg_ctl.exe'
$psql = Join-Path $PgBin 'psql.exe'
$createdb = Join-Path $PgBin 'createdb.exe'
$dropdb = Join-Path $PgBin 'dropdb.exe'
$postgres = Join-Path $PgBin 'postgres.exe'
$pgready = Join-Path $PgBin 'pg_isready.exe'

function Assert-True([bool]$Condition, [string]$Message) {
  if (-not $Condition) { throw "VALIDATION FAILED: $Message" }
}

function Invoke-PsqlFile([string]$Database, [string]$File) {
  & $psql -X -h 127.0.0.1 -p $Port -U postgres -d $Database `
    -v ON_ERROR_STOP=1 -f $File
  if ($LASTEXITCODE -ne 0) { throw "psql failed for $File in $Database" }
}

function New-TestDatabase([string]$Database, [string[]]$CandidateFiles) {
  & $createdb -h 127.0.0.1 -p $Port -U postgres $Database
  if ($LASTEXITCODE -ne 0) { throw "createdb failed for $Database" }
  Invoke-PsqlFile $Database $fixture
  foreach ($name in @(
    '20261026000000_v2_foundation_schemas.sql',
    '20261026000100_v2_identity_tenancy_foundation.sql',
    '20261026000200_v2_permissions_foundation.sql',
    '20261026000210_v2_permission_catalogue_seed.sql',
    '20261027000300_v2_invitation_audit_structure.sql',
    '20261027000400_v2_erp_core_master_fiscal_settings.sql',
    '20261028000500_v2_accounting_journals_structure.sql',
    '20261028000600_v2_inventory_structure.sql',
    '20261028000700_v2_sales_purchases_structure.sql'
  )) { Invoke-PsqlFile $Database (Join-Path $migrationDir $name) }
  foreach ($name in $CandidateFiles) {
    Invoke-PsqlFile $Database (Join-Path $migrationDir $name)
  }
}

$catalogAssertions = @'
DO $phase8$
DECLARE
  is_case_b boolean := to_regclass('hasad.expense_documents') IS NOT NULL;
  target_names text[] := CASE WHEN to_regclass('hasad.expense_documents') IS NULL THEN
    ARRAY['cashboxes','bank_accounts','payment_documents','payment_allocations','reconciliation_statements','reconciliation_items']
  ELSE ARRAY['cashboxes','bank_accounts','payment_documents','payment_allocations','reconciliation_statements','reconciliation_items','expense_categories','expense_documents','expense_document_lines','expense_attachments','expense_receipt_dedup'] END;
  expected_tables integer := CASE WHEN to_regclass('hasad.expense_documents') IS NULL THEN 6 ELSE 11 END;
  expected_fks integer := CASE WHEN to_regclass('hasad.expense_documents') IS NULL THEN 19 ELSE 37 END;
  expected_checks integer := CASE WHEN to_regclass('hasad.expense_documents') IS NULL THEN 8 ELSE 17 END;
  expected_uniques integer := CASE WHEN to_regclass('hasad.expense_documents') IS NULL THEN 8 ELSE 16 END;
  expected_pks integer := CASE WHEN to_regclass('hasad.expense_documents') IS NULL THEN 6 ELSE 11 END;
  expected_indexes integer := CASE WHEN to_regclass('hasad.expense_documents') IS NULL THEN 24 ELSE 40 END;
  expected_columns integer := CASE WHEN to_regclass('hasad.expense_documents') IS NULL THEN 60 ELSE 110 END;
  table_name text;
  column_spec record;
  actual_column_names text[];
  got integer;
BEGIN
  SELECT count(*) INTO got FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
    WHERE n.nspname='hasad' AND c.relkind='r' AND c.relname=ANY(target_names);
  IF got <> expected_tables THEN RAISE EXCEPTION 'table count %, expected %',got,expected_tables; END IF;

  SELECT count(*) INTO got FROM pg_attribute a JOIN pg_class c ON c.oid=a.attrelid
    JOIN pg_namespace n ON n.oid=c.relnamespace
    WHERE n.nspname='hasad' AND c.relname=ANY(target_names) AND a.attnum>0 AND NOT a.attisdropped;
  IF got <> expected_columns THEN RAISE EXCEPTION 'column count %, expected %',got,expected_columns; END IF;
  FOR column_spec IN SELECT * FROM (VALUES
    ('cashboxes',ARRAY['id','company_id','code','name_ar','account_id','is_active']::text[]),
    ('bank_accounts',ARRAY['id','company_id','code','name_ar','account_id','bank_name','branch_no','account_no','iban','is_active']::text[]),
    ('payment_documents',ARRAY['id','company_id','doc_kind','status','party_id','employee_id','from_account_id','to_account_id','amount','doc_type_id','fiscal_year_id','doc_no','reversal_of_id','idempotency_key','tender_method','tender_reference','posted_at']::text[]),
    ('payment_allocations',ARRAY['id','company_id','payment_id','target_kind','sales_document_id','purchase_document_id','expense_document_id','amount','status','supersedes_id']::text[]),
    ('reconciliation_statements',ARRAY['id','company_id','account_id','statement_date','opening_balance','closing_balance','status','closed_at','closed_by']::text[]),
    ('reconciliation_items',ARRAY['id','company_id','statement_id','value_date','description','amount','journal_line_id','is_external']::text[]),
    ('expense_categories',ARRAY['id','company_id','code','name_ar','account_id','is_active']::text[]),
    ('expense_documents',ARRAY['id','company_id','settlement','party_id','container_account_id','doc_date','vat_mode','doc_type_id','fiscal_year_id','doc_no','external_ref','reversal_of_id','idempotency_key','net','tax','gross','status','posted_at']::text[]),
    ('expense_document_lines',ARRAY['id','company_id','document_id','line_no','category_id','amount','tax_rate','net','tax','gross','account_id']::text[]),
    ('expense_attachments',ARRAY['id','company_id','expense_document_id','storage_path','content_hash','byte_size','mime','uploaded_by','uploaded_at']::text[]),
    ('expense_receipt_dedup',ARRAY['id','company_id','party_id','external_ref','expense_document_id','status']::text[])
  ) expected(table_name,column_names) LOOP
    IF column_spec.table_name = ANY(target_names) THEN
      SELECT array_agg(a.attname ORDER BY a.attnum) INTO actual_column_names
        FROM pg_attribute a JOIN pg_class c ON c.oid=a.attrelid JOIN pg_namespace n ON n.oid=c.relnamespace
        WHERE n.nspname='hasad' AND c.relname=column_spec.table_name AND a.attnum>0 AND NOT a.attisdropped;
      IF actual_column_names IS DISTINCT FROM column_spec.column_names THEN
        RAISE EXCEPTION 'columns mismatch for %: got %, expected %',column_spec.table_name,actual_column_names,column_spec.column_names;
      END IF;
    END IF;
  END LOOP;

  SELECT count(*) INTO got FROM pg_constraint co JOIN pg_class c ON c.oid=co.conrelid
    JOIN pg_namespace n ON n.oid=c.relnamespace
    WHERE n.nspname='hasad' AND c.relname=ANY(target_names) AND co.contype='f';
  IF got <> expected_fks THEN RAISE EXCEPTION 'FK count %, expected %',got,expected_fks; END IF;
  IF EXISTS (SELECT 1 FROM pg_constraint co JOIN pg_class c ON c.oid=co.conrelid
      JOIN pg_namespace n ON n.oid=c.relnamespace
      WHERE n.nspname='hasad' AND c.relname=ANY(target_names) AND co.contype='f' AND co.confdeltype <> 'r')
    THEN RAISE EXCEPTION 'candidate FK without ON DELETE RESTRICT'; END IF;
  IF EXISTS (SELECT 1 FROM pg_constraint co JOIN pg_class c ON c.oid=co.conrelid
      JOIN pg_namespace n ON n.oid=c.relnamespace
      WHERE n.nspname='hasad' AND c.relname=ANY(target_names) AND co.contype='f'
        AND array_length(co.conkey,1)>1 AND (
          NOT EXISTS (SELECT 1 FROM unnest(co.conkey) k(attnum) JOIN pg_attribute a ON a.attrelid=co.conrelid AND a.attnum=k.attnum WHERE a.attname='company_id')
          OR NOT EXISTS (SELECT 1 FROM unnest(co.confkey) k(attnum) JOIN pg_attribute a ON a.attrelid=co.confrelid AND a.attnum=k.attnum WHERE a.attname='company_id')
        )
    ) THEN RAISE EXCEPTION 'composite candidate FK lacks source company_id'; END IF;

  SELECT count(*) INTO got FROM pg_constraint co JOIN pg_class c ON c.oid=co.conrelid JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='hasad' AND c.relname=ANY(target_names) AND co.contype='c';
  IF got <> expected_checks THEN RAISE EXCEPTION 'check count %, expected %',got,expected_checks; END IF;
  SELECT count(*) INTO got FROM pg_constraint co JOIN pg_class c ON c.oid=co.conrelid JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='hasad' AND c.relname=ANY(target_names) AND co.contype='u';
  IF got <> expected_uniques THEN RAISE EXCEPTION 'unique constraint count %, expected %',got,expected_uniques; END IF;
  SELECT count(*) INTO got FROM pg_constraint co JOIN pg_class c ON c.oid=co.conrelid JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='hasad' AND c.relname=ANY(target_names) AND co.contype='p';
  IF got <> expected_pks THEN RAISE EXCEPTION 'PK count %, expected %',got,expected_pks; END IF;

  SELECT count(*) INTO got FROM pg_index i JOIN pg_class c ON c.oid=i.indrelid JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='hasad' AND c.relname=ANY(target_names);
  IF got <> expected_indexes THEN RAISE EXCEPTION 'index count %, expected %',got,expected_indexes; END IF;
  IF EXISTS (SELECT 1 FROM (VALUES
      ('payment_documents_company_idempotency_key_key'),('payment_documents_company_doc_no_key'),
      ('payment_documents_company_party_idx'),('payment_documents_company_date_idx'),
      ('payment_allocations_payment_idx'),('payment_allocations_sales_idx'),
      ('payment_allocations_purchase_idx'),('payment_allocations_expense_idx'),
      ('reconciliation_items_statement_idx'),('reconciliation_items_journal_line_idx')
    ) x(index_name) WHERE NOT EXISTS (SELECT 1 FROM pg_class i WHERE i.relname=x.index_name AND i.relkind='i'))
    THEN RAISE EXCEPTION 'required 00800 index missing'; END IF;
  IF is_case_b AND EXISTS (SELECT 1 FROM (VALUES
      ('expense_documents_company_idempotency_key_key'),('expense_documents_company_doc_no_key'),('expense_document_lines_category_idx')
    ) x(index_name) WHERE NOT EXISTS (SELECT 1 FROM pg_class i WHERE i.relname=x.index_name AND i.relkind='i'))
    THEN RAISE EXCEPTION 'required 00900 index missing'; END IF;

  SELECT count(*) INTO got FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='hasad' AND c.relname=ANY(target_names) AND c.relrowsecurity AND c.relforcerowsecurity;
  IF got <> expected_tables THEN RAISE EXCEPTION 'forced RLS count %, expected %',got,expected_tables; END IF;
  SELECT count(*) INTO got FROM pg_policy p JOIN pg_class c ON c.oid=p.polrelid JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='hasad' AND c.relname=ANY(target_names);
  IF got <> 0 THEN RAISE EXCEPTION 'candidate policy count %',got; END IF;
  SELECT count(*) INTO got FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='hasad' AND c.relname=ANY(target_names) AND NOT t.tgisinternal;
  IF got <> 0 THEN RAISE EXCEPTION 'candidate non-internal trigger count %',got; END IF;
  SELECT count(*) INTO got FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='hasad' AND c.relname=ANY(target_names) AND c.relacl IS NOT NULL;
  IF got <> 0 THEN RAISE EXCEPTION 'candidate ACL count %',got; END IF;
  FOREACH table_name IN ARRAY target_names LOOP
    EXECUTE format('SELECT count(*) FROM hasad.%I', table_name) INTO got;
    IF got <> 0 THEN RAISE EXCEPTION 'candidate table % has % rows',table_name,got; END IF;
  END LOOP;

  IF is_case_b AND NOT EXISTS (SELECT 1 FROM pg_constraint co JOIN pg_class c ON c.oid=co.conrelid JOIN pg_namespace n ON n.oid=c.relnamespace JOIN pg_class p ON p.oid=co.confrelid
      WHERE n.nspname='hasad' AND c.relname='payment_allocations' AND co.conname='payment_allocations_company_expense_fkey'
        AND co.contype='f' AND p.relname='expense_documents' AND co.confdeltype='r'
        AND pg_get_constraintdef(co.oid) LIKE 'FOREIGN KEY (company_id, expense_document_id) REFERENCES hasad.expense_documents(company_id, id) ON DELETE RESTRICT%')
    THEN RAISE EXCEPTION 'expense allocation FK missing or malformed'; END IF;
  IF is_case_b AND NOT EXISTS (SELECT 1 FROM pg_constraint co JOIN pg_class c ON c.oid=co.conrelid JOIN pg_namespace n ON n.oid=c.relnamespace
      WHERE n.nspname='hasad' AND c.relname='expense_documents' AND co.conname='expense_documents_company_id_id_key'
        AND co.contype='u' AND pg_get_constraintdef(co.oid)='UNIQUE (company_id, id)')
    THEN RAISE EXCEPTION 'expense_documents composite unique target missing'; END IF;
  IF NOT is_case_b AND EXISTS (SELECT 1 FROM pg_constraint co WHERE co.conname='payment_allocations_company_expense_fkey')
    THEN RAISE EXCEPTION 'expense allocation FK unexpectedly present in case A'; END IF;
END
$phase8$;
'@

try {
  Assert-True (Test-Path -LiteralPath $fixture -PathType Leaf) 'missing local compatibility fixture'
  $expected008 = 'EF076C57F723113A1689405EFFD6B047A3ED5675EC5613D1E00388C1332207BE'
  $expected009 = '49AA093E04A5C2F113E6051BFD45DB5B02C04A92F340DF3B5DBBEFC9349F94CA'
  $actual008 = (Get-FileHash (Join-Path $migrationDir '20261029000800_v2_cash_banking_payments_recon_structure.sql') -Algorithm SHA256).Hash
  $actual009 = (Get-FileHash (Join-Path $migrationDir '20261029000900_v2_expenses_structure.sql') -Algorithm SHA256).Hash
  Assert-True ($actual008 -eq $expected008) '00800 hash mismatch'
  Assert-True ($actual009 -eq $expected009) '00900 hash mismatch'

  & (Join-Path $PgBin 'initdb.exe') -D $data -A trust -U postgres --encoding=UTF8 --locale=C
  if ($LASTEXITCODE -ne 0) { throw 'initdb failed' }
  $server = Start-Process -FilePath $postgres -WindowStyle Hidden -PassThru `
    -ArgumentList @('-D', $data, '-h', '127.0.0.1', '-p', "$Port") `
    -RedirectStandardOutput (Join-Path $data 'server.out.log') `
    -RedirectStandardError (Join-Path $data 'server.err.log')
  $ready = $false
  for ($i=0; $i -lt 40; $i++) {
    & $pgready -h 127.0.0.1 -p $Port -U postgres -d postgres | Out-Null
    if ($LASTEXITCODE -eq 0) { $ready = $true; break }
    Start-Sleep -Milliseconds 500
  }
  Assert-True $ready 'disposable PostgreSQL 17 server did not become ready'

  $candidate008 = '20261029000800_v2_cash_banking_payments_recon_structure.sql'
  $candidate009 = '20261029000900_v2_expenses_structure.sql'
  New-TestDatabase $dbA @($candidate008)
  & $psql -X -h 127.0.0.1 -p $Port -U postgres -d $dbA -v ON_ERROR_STOP=1 -c $catalogAssertions
  if ($LASTEXITCODE -ne 0) { throw 'CASE A catalog assertions failed' }
  Write-Output 'CASE_A=PASS (9 baseline migrations + 00800; six tables, 60 columns, 19 FKs, 24 indexes, forced RLS)'

  New-TestDatabase $dbB @($candidate008,$candidate009)
  & $psql -X -h 127.0.0.1 -p $Port -U postgres -d $dbB -v ON_ERROR_STOP=1 -c $catalogAssertions
  if ($LASTEXITCODE -ne 0) { throw 'CASE B catalog assertions failed' }
  Write-Output 'CASE_B=PASS (9 baseline migrations + 00800 + corrected 00900; 11 tables, 110 columns, 37 FKs, 40 indexes, forced RLS)'

  $negativeTests = @'
BEGIN;
INSERT INTO auth.users(id) VALUES
 ('00000000-0000-0000-0000-000000000010'),('00000000-0000-0000-0000-000000000020');
INSERT INTO hasad.user_profiles(id) VALUES
 ('00000000-0000-0000-0000-000000000010'),('00000000-0000-0000-0000-000000000020');
INSERT INTO hasad.companies(id,created_by) VALUES
 ('00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000010'),
 ('00000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000020');
INSERT INTO hasad.document_types(id,company_id,code,name_ar,issuance) VALUES
 ('00000000-0000-0000-0000-000000000031','00000000-0000-0000-0000-000000000001','TEST','Test','posting'),
 ('00000000-0000-0000-0000-000000000032','00000000-0000-0000-0000-000000000002','TEST','Test','posting');
INSERT INTO hasad.fiscal_years(id,company_id,start_date,end_date) VALUES
 ('00000000-0000-0000-0000-000000000041','00000000-0000-0000-0000-000000000001','2026-01-01','2026-12-31'),
 ('00000000-0000-0000-0000-000000000042','00000000-0000-0000-0000-000000000002','2026-01-01','2026-12-31');
INSERT INTO hasad.payment_documents(id,company_id,doc_kind,amount,doc_type_id,fiscal_year_id) VALUES
 ('00000000-0000-0000-0000-000000000051','00000000-0000-0000-0000-000000000001','payment',1.00,'00000000-0000-0000-0000-000000000031','00000000-0000-0000-0000-000000000041');
INSERT INTO hasad.expense_documents(id,company_id,settlement,doc_date,vat_mode,doc_type_id,fiscal_year_id) VALUES
 ('00000000-0000-0000-0000-000000000061','00000000-0000-0000-0000-000000000002','credit','2026-01-01','inclusive','00000000-0000-0000-0000-000000000032','00000000-0000-0000-0000-000000000042');

DO $negative$
DECLARE got_name text;
BEGIN
  BEGIN
    INSERT INTO hasad.payment_allocations(id,company_id,payment_id,target_kind,expense_document_id,amount)
    VALUES ('00000000-0000-0000-0000-000000000071','00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000051','expense','00000000-0000-0000-0000-000000000099',1.00);
    RAISE EXCEPTION 'nonexistent expense target was accepted';
  EXCEPTION WHEN foreign_key_violation THEN
    GET STACKED DIAGNOSTICS got_name = CONSTRAINT_NAME;
    IF got_name <> 'payment_allocations_company_expense_fkey' THEN RAISE EXCEPTION 'wrong FK rejected nonexistent target: %',got_name; END IF;
    RAISE NOTICE 'PASS: nonexistent expense document rejected by %',got_name;
  END;
  BEGIN
    INSERT INTO hasad.payment_allocations(id,company_id,payment_id,target_kind,expense_document_id,amount)
    VALUES ('00000000-0000-0000-0000-000000000072','00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000051','expense','00000000-0000-0000-0000-000000000061',1.00);
    RAISE EXCEPTION 'cross-company expense target was accepted';
  EXCEPTION WHEN foreign_key_violation THEN
    GET STACKED DIAGNOSTICS got_name = CONSTRAINT_NAME;
    IF got_name <> 'payment_allocations_company_expense_fkey' THEN RAISE EXCEPTION 'wrong FK rejected cross-company target: %',got_name; END IF;
    RAISE NOTICE 'PASS: cross-company expense document rejected by %',got_name;
  END;
END
$negative$;
ROLLBACK;
'@
  & $psql -X -h 127.0.0.1 -p $Port -U postgres -d $dbB -v ON_ERROR_STOP=1 -c $negativeTests
  if ($LASTEXITCODE -ne 0) { throw 'FK negative tests failed' }
  Write-Output 'FK_NEGATIVE_TESTS=PASS (nonexistent and cross-company targets rejected)'

  & $psql -X -h 127.0.0.1 -p $Port -U postgres -d $dbB -v ON_ERROR_STOP=1 -c $catalogAssertions
  if ($LASTEXITCODE -ne 0) { throw 'CASE B post-rollback catalog assertions failed' }
  Write-Output 'POST_TEST_ROWS=PASS (all synthetic rows rolled back)'
  Write-Output "HASH_00800=$actual008"
  Write-Output "HASH_00900=$actual009"
}
finally {
  if ($ready) {
    foreach ($db in @($dbA,$dbB)) {
      & $dropdb --if-exists -h 127.0.0.1 -p $Port -U postgres $db 2>$null
    }
  }
  if ($server -and -not $server.HasExited) {
    & $pgctl -D $data -m fast -w stop
    if ($LASTEXITCODE -ne 0) { throw 'Could not cleanly stop disposable PostgreSQL server' }
    $server.WaitForExit()
  }
  if (Test-Path -LiteralPath $data) {
    $resolvedData = (Resolve-Path -LiteralPath $data).Path
    $resolvedTemp = (Resolve-Path -LiteralPath $env:TEMP).Path
    if (-not $resolvedData.StartsWith($resolvedTemp,[StringComparison]::OrdinalIgnoreCase) -or
        (Split-Path -Leaf $resolvedData) -ne "hasad_phase8_local_$stamp") {
      throw "Refusing unexpected cluster cleanup path: $resolvedData"
    }
    Remove-Item -LiteralPath $resolvedData -Recurse -Force
  }
}
