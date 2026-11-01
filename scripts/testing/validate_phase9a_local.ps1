# Runs Phase 9A structural validation against fresh disposable local PostgreSQL.
# Never connects to Supabase DEV or production. Synthetic local data only.
[CmdletBinding()]
param(
  [int]$Port = 55442,
  [string]$PgBin = 'C:\Program Files\PostgreSQL\17\bin'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$fixture = Join-Path $PSScriptRoot 'phase8_local_supabase_compat.sql'
$migrationDir = Join-Path $repo 'supabase\migrations'
$candidate = '20261029001000_v2_phase9a_employee_org_structure.sql'
$baseline = @(
  '20261026000000_v2_foundation_schemas.sql',
  '20261026000100_v2_identity_tenancy_foundation.sql',
  '20261026000200_v2_permissions_foundation.sql',
  '20261026000210_v2_permission_catalogue_seed.sql',
  '20261027000300_v2_invitation_audit_structure.sql',
  '20261027000400_v2_erp_core_master_fiscal_settings.sql',
  '20261028000500_v2_accounting_journals_structure.sql',
  '20261028000600_v2_inventory_structure.sql',
  '20261028000700_v2_sales_purchases_structure.sql',
  '20261029000800_v2_cash_banking_payments_recon_structure.sql',
  '20261029000900_v2_expenses_structure.sql'
)
$stamp = Get-Date -Format 'yyyyMMdd_HHmmss_fff'
$data = Join-Path $env:TEMP "hasad_phase9a_local_$stamp"
$db = "phase9a_$stamp"
$missingDb = "phase9a_missing_$stamp"
$server = $null
$ready = $false
$createdPrimaryDb = $false
$createdMissingDb = $false
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
  & $psql -X -h 127.0.0.1 -p $Port -U postgres -d $Database -v ON_ERROR_STOP=1 -f $File
  if ($LASTEXITCODE -ne 0) { throw "psql failed for $File in $Database" }
}

function Invoke-PsqlText([string]$Database, [string]$Sql) {
  & $psql -X -h 127.0.0.1 -p $Port -U postgres -d $Database -v ON_ERROR_STOP=1 -c $Sql
  if ($LASTEXITCODE -ne 0) { throw "psql command failed in $Database" }
}

$catalogAssertions = @'
DO $phase9a$
DECLARE
  target_names text[] := ARRAY['departments','job_titles','employees'];
  got integer;
  table_name text;
  actual_columns text[];
  expected_columns text[];
  actual_types text[];
  expected_types text[];
  actual_not_null boolean[];
  expected_not_null boolean[];
  actual_defaults text[];
  expected_defaults text[];
BEGIN
  SELECT count(*) INTO got
  FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'hasad' AND c.relkind = 'r';
  IF got <> 47 THEN RAISE EXCEPTION 'hasad table count %, expected 47', got; END IF;

  SELECT count(*) INTO got
  FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'hasad' AND c.relkind = 'r' AND c.relname = ANY(target_names);
  IF got <> 3 THEN RAISE EXCEPTION 'target table count %, expected 3', got; END IF;

  FOREACH table_name IN ARRAY target_names LOOP
    expected_columns := CASE table_name
      WHEN 'departments' THEN ARRAY['id','company_id','code','name_ar','is_active']
      WHEN 'job_titles' THEN ARRAY['id','company_id','code','name_ar','is_active']
      WHEN 'employees' THEN ARRAY['id','company_id','employee_code','name_ar','status','hire_date','termination_date','department_id','job_title_id']
    END;
    expected_types := CASE table_name
      WHEN 'departments' THEN ARRAY['uuid','uuid','text','text','boolean']
      WHEN 'job_titles' THEN ARRAY['uuid','uuid','text','text','boolean']
      WHEN 'employees' THEN ARRAY['uuid','uuid','text','text','text','date','date','uuid','uuid']
    END;
    expected_not_null := CASE table_name
      WHEN 'departments' THEN ARRAY[true,true,true,true,true]
      WHEN 'job_titles' THEN ARRAY[true,true,true,true,true]
      WHEN 'employees' THEN ARRAY[true,true,true,true,true,true,false,false,false]
    END;
    expected_defaults := CASE table_name
      WHEN 'departments' THEN ARRAY['<NULL>','<NULL>','<NULL>','<NULL>','true']
      WHEN 'job_titles' THEN ARRAY['<NULL>','<NULL>','<NULL>','<NULL>','true']
      WHEN 'employees' THEN ARRAY['<NULL>','<NULL>','<NULL>','<NULL>','<NULL>','<NULL>','<NULL>','<NULL>','<NULL>']
    END;
    SELECT array_agg(a.attname ORDER BY a.attnum),
           array_agg(format_type(a.atttypid, a.atttypmod) ORDER BY a.attnum),
           array_agg(a.attnotnull ORDER BY a.attnum),
           array_agg(COALESCE(pg_get_expr(d.adbin, d.adrelid), '<NULL>') ORDER BY a.attnum)
    INTO actual_columns, actual_types, actual_not_null, actual_defaults
    FROM pg_attribute a JOIN pg_class c ON c.oid = a.attrelid
    JOIN pg_namespace n ON n.oid = c.relnamespace
    LEFT JOIN pg_attrdef d ON d.adrelid = a.attrelid AND d.adnum = a.attnum
    WHERE n.nspname = 'hasad' AND c.relname = table_name
      AND a.attnum > 0 AND NOT a.attisdropped;
    IF actual_columns IS DISTINCT FROM expected_columns THEN
      RAISE EXCEPTION 'columns mismatch for %: got %, expected %', table_name, actual_columns, expected_columns;
    END IF;
    IF actual_types IS DISTINCT FROM expected_types THEN
      RAISE EXCEPTION 'types mismatch for %: got %, expected %', table_name, actual_types, expected_types;
    END IF;
    IF actual_not_null IS DISTINCT FROM expected_not_null THEN
      RAISE EXCEPTION 'nullability mismatch for %: got %, expected %', table_name, actual_not_null, expected_not_null;
    END IF;
    IF actual_defaults IS DISTINCT FROM expected_defaults THEN
      RAISE EXCEPTION 'defaults mismatch for %: got %, expected %', table_name, actual_defaults, expected_defaults;
    END IF;
  END LOOP;

  SELECT count(*) INTO got FROM pg_constraint co JOIN pg_class c ON c.oid = co.conrelid
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'hasad' AND c.relname = ANY(target_names) AND co.contype = 'p';
  IF got <> 3 THEN RAISE EXCEPTION 'PK count %, expected 3', got; END IF;
  SELECT count(*) INTO got FROM pg_constraint co JOIN pg_class c ON c.oid = co.conrelid
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'hasad' AND c.relname = ANY(target_names) AND co.contype = 'u';
  IF got <> 6 THEN RAISE EXCEPTION 'unique count %, expected 6', got; END IF;
  SELECT count(*) INTO got FROM pg_constraint co JOIN pg_class c ON c.oid = co.conrelid
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'hasad' AND c.relname = ANY(target_names) AND co.contype = 'f';
  IF got <> 5 THEN RAISE EXCEPTION 'FK count %, expected 5', got; END IF;
  SELECT count(*) INTO got FROM pg_constraint co JOIN pg_class c ON c.oid = co.conrelid
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'hasad' AND c.relname = ANY(target_names) AND co.contype = 'c';
  IF got <> 9 THEN RAISE EXCEPTION 'CHECK count %, expected 9', got; END IF;
  SELECT count(*) INTO got FROM pg_index i JOIN pg_class c ON c.oid = i.indrelid
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'hasad' AND c.relname = ANY(target_names);
  IF got <> 9 THEN RAISE EXCEPTION 'index count %, expected 9', got; END IF;

  IF EXISTS (
    SELECT 1 FROM pg_constraint co JOIN pg_class c ON c.oid = co.conrelid
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'hasad' AND c.relname = ANY(target_names)
      AND co.contype = 'f' AND co.confdeltype <> 'r'
  ) THEN RAISE EXCEPTION 'target FK without ON DELETE RESTRICT'; END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint co JOIN pg_class c ON c.oid = co.conrelid
    JOIN pg_namespace n ON n.oid = c.relnamespace JOIN pg_class p ON p.oid = co.confrelid
    WHERE n.nspname = 'hasad' AND c.relname = 'employees'
      AND co.conname = 'employees_company_department_fkey' AND p.relname = 'departments'
      AND pg_get_constraintdef(co.oid) = 'FOREIGN KEY (company_id, department_id) REFERENCES hasad.departments(company_id, id) ON DELETE RESTRICT'
  ) THEN RAISE EXCEPTION 'department composite FK missing or malformed'; END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint co JOIN pg_class c ON c.oid = co.conrelid
    JOIN pg_namespace n ON n.oid = c.relnamespace JOIN pg_class p ON p.oid = co.confrelid
    WHERE n.nspname = 'hasad' AND c.relname = 'employees'
      AND co.conname = 'employees_company_job_title_fkey' AND p.relname = 'job_titles'
      AND pg_get_constraintdef(co.oid) = 'FOREIGN KEY (company_id, job_title_id) REFERENCES hasad.job_titles(company_id, id) ON DELETE RESTRICT'
  ) THEN RAISE EXCEPTION 'job-title composite FK missing or malformed'; END IF;
  SELECT count(*) INTO got FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'hasad' AND c.relname = ANY(target_names)
      AND c.relrowsecurity AND c.relforcerowsecurity;
  IF got <> 3 THEN RAISE EXCEPTION 'forced RLS count %, expected 3', got; END IF;
  SELECT count(*) INTO got FROM pg_policy p JOIN pg_class c ON c.oid = p.polrelid
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'hasad' AND c.relname = ANY(target_names);
  IF got <> 0 THEN RAISE EXCEPTION 'policy count %, expected 0', got; END IF;
  SELECT count(*) INTO got FROM pg_trigger t JOIN pg_class c ON c.oid = t.tgrelid
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'hasad' AND c.relname = ANY(target_names) AND NOT t.tgisinternal;
  IF got <> 0 THEN RAISE EXCEPTION 'non-internal trigger count %, expected 0', got; END IF;
  SELECT count(*) INTO got FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'hasad' AND c.relname = ANY(target_names) AND c.relacl IS NOT NULL;
  IF got <> 0 THEN RAISE EXCEPTION 'table ACL count %, expected 0', got; END IF;
END
$phase9a$;
'@

$negativeTests = @'
BEGIN;
INSERT INTO auth.users(id) VALUES
  ('00000000-0000-0000-0000-000000000101'),
  ('00000000-0000-0000-0000-000000000102');
INSERT INTO hasad.user_profiles(id) VALUES
  ('00000000-0000-0000-0000-000000000101'),
  ('00000000-0000-0000-0000-000000000102');
INSERT INTO hasad.companies(id, created_by) VALUES
  ('00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000101'),
  ('00000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000102');
INSERT INTO hasad.departments(id, company_id, code, name_ar) VALUES
  ('00000000-0000-0000-0000-000000000011', '00000000-0000-0000-0000-000000000001', 'HR', 'الموارد البشرية'),
  ('00000000-0000-0000-0000-000000000012', '00000000-0000-0000-0000-000000000002', 'OPS', 'العمليات');
INSERT INTO hasad.job_titles(id, company_id, code, name_ar) VALUES
  ('00000000-0000-0000-0000-000000000021', '00000000-0000-0000-0000-000000000001', 'MGR', 'مدير'),
  ('00000000-0000-0000-0000-000000000022', '00000000-0000-0000-0000-000000000002', 'CLK', 'موظف');
INSERT INTO hasad.employees(id, company_id, employee_code, name_ar, status, hire_date, termination_date, department_id, job_title_id) VALUES
  ('00000000-0000-0000-0000-000000000031', '00000000-0000-0000-0000-000000000001', 'E-001', 'اختبار', 'active', '2026-01-01', NULL, '00000000-0000-0000-0000-000000000011', '00000000-0000-0000-0000-000000000021'),
  ('00000000-0000-0000-0000-000000000032', '00000000-0000-0000-0000-000000000001', 'E-002', 'موقوف', 'suspended', '2026-01-01', NULL, NULL, NULL),
  ('00000000-0000-0000-0000-000000000033', '00000000-0000-0000-0000-000000000001', 'E-003', 'منته', 'terminated', '2026-01-01', '2026-01-31', NULL, NULL);

DO $negative$
DECLARE got_name text;
BEGIN
  BEGIN INSERT INTO hasad.departments(id, company_id, code, name_ar) VALUES ('00000000-0000-0000-0000-000000000041','00000000-0000-0000-0000-000000000001','   ','اسم'); RAISE EXCEPTION 'blank department code accepted'; EXCEPTION WHEN check_violation THEN GET STACKED DIAGNOSTICS got_name = CONSTRAINT_NAME; IF got_name <> 'departments_code_nonblank_check' THEN RAISE; END IF; END;
  BEGIN INSERT INTO hasad.departments(id, company_id, code, name_ar) VALUES ('00000000-0000-0000-0000-000000000042','00000000-0000-0000-0000-000000000001','D2',E'\t'); RAISE EXCEPTION 'blank department name accepted'; EXCEPTION WHEN check_violation THEN GET STACKED DIAGNOSTICS got_name = CONSTRAINT_NAME; IF got_name <> 'departments_name_ar_nonblank_check' THEN RAISE; END IF; END;
  BEGIN INSERT INTO hasad.job_titles(id, company_id, code, name_ar) VALUES ('00000000-0000-0000-0000-000000000043','00000000-0000-0000-0000-000000000001',E'\n','اسم'); RAISE EXCEPTION 'blank job-title code accepted'; EXCEPTION WHEN check_violation THEN GET STACKED DIAGNOSTICS got_name = CONSTRAINT_NAME; IF got_name <> 'job_titles_code_nonblank_check' THEN RAISE; END IF; END;
  BEGIN INSERT INTO hasad.job_titles(id, company_id, code, name_ar) VALUES ('00000000-0000-0000-0000-000000000044','00000000-0000-0000-0000-000000000001','T2','  '); RAISE EXCEPTION 'blank job-title name accepted'; EXCEPTION WHEN check_violation THEN GET STACKED DIAGNOSTICS got_name = CONSTRAINT_NAME; IF got_name <> 'job_titles_name_ar_nonblank_check' THEN RAISE; END IF; END;
  BEGIN INSERT INTO hasad.employees(id, company_id, employee_code, name_ar, status, hire_date) VALUES ('00000000-0000-0000-0000-000000000045','00000000-0000-0000-0000-000000000001',' ','اسم','active','2026-01-01'); RAISE EXCEPTION 'blank employee code accepted'; EXCEPTION WHEN check_violation THEN GET STACKED DIAGNOSTICS got_name = CONSTRAINT_NAME; IF got_name <> 'employees_employee_code_nonblank_check' THEN RAISE; END IF; END;
  BEGIN INSERT INTO hasad.employees(id, company_id, employee_code, name_ar, status, hire_date) VALUES ('00000000-0000-0000-0000-000000000046','00000000-0000-0000-0000-000000000001','E-004',E'\t','active','2026-01-01'); RAISE EXCEPTION 'blank employee name accepted'; EXCEPTION WHEN check_violation THEN GET STACKED DIAGNOSTICS got_name = CONSTRAINT_NAME; IF got_name <> 'employees_name_ar_nonblank_check' THEN RAISE; END IF; END;
  BEGIN INSERT INTO hasad.employees(id, company_id, employee_code, name_ar, status, hire_date) VALUES ('00000000-0000-0000-0000-000000000047','00000000-0000-0000-0000-000000000001','E-005','اسم','invalid','2026-01-01'); RAISE EXCEPTION 'invalid status accepted'; EXCEPTION WHEN check_violation THEN GET STACKED DIAGNOSTICS got_name = CONSTRAINT_NAME; IF got_name <> 'employees_status_check' THEN RAISE; END IF; END;
  BEGIN INSERT INTO hasad.employees(id, company_id, employee_code, name_ar, status, hire_date) VALUES ('00000000-0000-0000-0000-000000000048','00000000-0000-0000-0000-000000000001','E-006','اسم','terminated','2026-01-01'); RAISE EXCEPTION 'terminated without date accepted'; EXCEPTION WHEN check_violation THEN GET STACKED DIAGNOSTICS got_name = CONSTRAINT_NAME; IF got_name <> 'employees_termination_status_check' THEN RAISE; END IF; END;
  BEGIN INSERT INTO hasad.employees(id, company_id, employee_code, name_ar, status, hire_date, termination_date) VALUES ('00000000-0000-0000-0000-000000000049','00000000-0000-0000-0000-000000000001','E-007','اسم','active','2026-01-01','2026-01-02'); RAISE EXCEPTION 'active with date accepted'; EXCEPTION WHEN check_violation THEN GET STACKED DIAGNOSTICS got_name = CONSTRAINT_NAME; IF got_name <> 'employees_termination_status_check' THEN RAISE; END IF; END;
  BEGIN INSERT INTO hasad.employees(id, company_id, employee_code, name_ar, status, hire_date, termination_date) VALUES ('00000000-0000-0000-0000-000000000050','00000000-0000-0000-0000-000000000001','E-008','اسم','terminated','2026-02-01','2026-01-31'); RAISE EXCEPTION 'termination before hire accepted'; EXCEPTION WHEN check_violation THEN GET STACKED DIAGNOSTICS got_name = CONSTRAINT_NAME; IF got_name <> 'employees_termination_date_check' THEN RAISE; END IF; END;
  BEGIN INSERT INTO hasad.employees(id, company_id, employee_code, name_ar, status, hire_date, department_id) VALUES ('00000000-0000-0000-0000-000000000051','00000000-0000-0000-0000-000000000001','E-009','اسم','active','2026-01-01','00000000-0000-0000-0000-000000000012'); RAISE EXCEPTION 'cross-company department accepted'; EXCEPTION WHEN foreign_key_violation THEN GET STACKED DIAGNOSTICS got_name = CONSTRAINT_NAME; IF got_name <> 'employees_company_department_fkey' THEN RAISE; END IF; END;
  BEGIN INSERT INTO hasad.employees(id, company_id, employee_code, name_ar, status, hire_date, job_title_id) VALUES ('00000000-0000-0000-0000-000000000052','00000000-0000-0000-0000-000000000001','E-010','اسم','active','2026-01-01','00000000-0000-0000-0000-000000000022'); RAISE EXCEPTION 'cross-company job title accepted'; EXCEPTION WHEN foreign_key_violation THEN GET STACKED DIAGNOSTICS got_name = CONSTRAINT_NAME; IF got_name <> 'employees_company_job_title_fkey' THEN RAISE; END IF; END;
  BEGIN DELETE FROM hasad.companies WHERE id = '00000000-0000-0000-0000-000000000001'; RAISE EXCEPTION 'referenced company deletion accepted'; EXCEPTION WHEN foreign_key_violation THEN NULL; END;
  BEGIN DELETE FROM hasad.departments WHERE id = '00000000-0000-0000-0000-000000000011'; RAISE EXCEPTION 'referenced department deletion accepted'; EXCEPTION WHEN foreign_key_violation THEN NULL; END;
  BEGIN DELETE FROM hasad.job_titles WHERE id = '00000000-0000-0000-0000-000000000021'; RAISE EXCEPTION 'referenced job title deletion accepted'; EXCEPTION WHEN foreign_key_violation THEN NULL; END;
END
$negative$;
ROLLBACK;
'@

$existingCatalogFingerprint = @'
WITH catalog_rows AS (
  SELECT format('table:%s:%s:%s:%s:%s', c.relname, c.relkind, c.relrowsecurity, c.relforcerowsecurity, COALESCE(c.relacl::text, '')) AS item
  FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'hasad' AND c.relkind = 'r' AND c.relname NOT IN ('departments','job_titles','employees')
  UNION ALL
  SELECT format('column:%s:%s:%s:%s:%s:%s', c.relname, a.attname, format_type(a.atttypid, a.atttypmod), a.attnotnull, COALESCE(pg_get_expr(d.adbin, d.adrelid), ''), a.attnum)
  FROM pg_attribute a JOIN pg_class c ON c.oid = a.attrelid JOIN pg_namespace n ON n.oid = c.relnamespace
  LEFT JOIN pg_attrdef d ON d.adrelid = a.attrelid AND d.adnum = a.attnum
  WHERE n.nspname = 'hasad' AND c.relkind = 'r' AND c.relname NOT IN ('departments','job_titles','employees') AND a.attnum > 0 AND NOT a.attisdropped
  UNION ALL
  SELECT format('constraint:%s:%s:%s', c.relname, co.conname, pg_get_constraintdef(co.oid))
  FROM pg_constraint co JOIN pg_class c ON c.oid = co.conrelid JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'hasad' AND c.relname NOT IN ('departments','job_titles','employees')
  UNION ALL
  SELECT format('index:%s:%s', c.relname, pg_get_indexdef(i.indexrelid))
  FROM pg_index i JOIN pg_class c ON c.oid = i.indrelid JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'hasad' AND c.relname NOT IN ('departments','job_titles','employees')
  UNION ALL
  SELECT format('schema:hasad:%s', COALESCE(nspacl::text, '')) FROM pg_namespace WHERE nspname = 'hasad'
  UNION ALL
  SELECT format('function:%s:%s', n.nspname, pg_get_function_identity_arguments(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace WHERE n.nspname IN ('hasad','hasad_api')
)
SELECT md5(COALESCE(string_agg(item, E'\n' ORDER BY item), '')) FROM catalog_rows;
'@

try {
  Assert-True (Test-Path -LiteralPath $fixture -PathType Leaf) 'missing local compatibility fixture'
  foreach ($exe in @($pgctl, $psql, $createdb, $dropdb, $postgres, $pgready)) { Assert-True (Test-Path -LiteralPath $exe -PathType Leaf) "missing PostgreSQL executable: $exe" }
  foreach ($name in $baseline + @($candidate)) { Assert-True (Test-Path -LiteralPath (Join-Path $migrationDir $name) -PathType Leaf) "missing migration: $name" }

  & (Join-Path $PgBin 'initdb.exe') -D $data -A trust -U postgres --encoding=UTF8 --locale=C
  if ($LASTEXITCODE -ne 0) { throw 'initdb failed' }
  $server = Start-Process -FilePath $postgres -WindowStyle Hidden -PassThru -ArgumentList @('-D', $data, '-h', '127.0.0.1', '-p', "$Port") -RedirectStandardOutput (Join-Path $data 'server.out.log') -RedirectStandardError (Join-Path $data 'server.err.log')
  for ($i = 0; $i -lt 40; $i++) { & $pgready -h 127.0.0.1 -p $Port -U postgres -d postgres | Out-Null; if ($LASTEXITCODE -eq 0) { $ready = $true; break }; Start-Sleep -Milliseconds 500 }
  Assert-True $ready 'disposable PostgreSQL server did not become ready'

  & $createdb -h 127.0.0.1 -p $Port -U postgres $db
  if ($LASTEXITCODE -ne 0) { throw 'createdb failed for validation database' }
  $createdPrimaryDb = $true
  Invoke-PsqlFile $db $fixture
  foreach ($name in $baseline) { Invoke-PsqlFile $db (Join-Path $migrationDir $name) }
  $baselineCount = (& $psql -X -A -t -h 127.0.0.1 -p $Port -U postgres -d $db -c "SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='hasad' AND c.relkind='r';").Trim()
  Assert-True ($baselineCount -eq '44') "baseline hasad table count $baselineCount, expected 44"
  $baselineFingerprint = (& $psql -X -A -t -h 127.0.0.1 -p $Port -U postgres -d $db -c $existingCatalogFingerprint).Trim()
  Write-Output "BASELINE_HASAD_CATALOG_MD5=$baselineFingerprint"
  Invoke-PsqlFile $db (Join-Path $migrationDir $candidate)
  $postCandidateFingerprint = (& $psql -X -A -t -h 127.0.0.1 -p $Port -U postgres -d $db -c $existingCatalogFingerprint).Trim()
  Assert-True ($postCandidateFingerprint -eq $baselineFingerprint) 'candidate changed the existing hasad catalog'
  Invoke-PsqlText $db $catalogAssertions
  Invoke-PsqlText $db $negativeTests
  Invoke-PsqlText $db $catalogAssertions
  Write-Output 'PHASE9A_LOCAL=PASS (44 baseline tables -> 47; 3 target tables, 19 columns, 3 PK, 6 UNIQUE, 5 FK, 9 CHECK, 9 indexes, forced RLS, zero policies/grants/triggers)'

  & $createdb -h 127.0.0.1 -p $Port -U postgres $missingDb
  if ($LASTEXITCODE -ne 0) { throw 'createdb failed for prerequisite database' }
  $createdMissingDb = $true
  $savedErrorActionPreference = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  & $psql -X -h 127.0.0.1 -p $Port -U postgres -d $missingDb -v ON_ERROR_STOP=1 -f (Join-Path $migrationDir $candidate) 2>&1 | Out-Null
  $missingPrerequisiteExit = $LASTEXITCODE
  $ErrorActionPreference = $savedErrorActionPreference
  Assert-True ($missingPrerequisiteExit -ne 0) 'candidate unexpectedly succeeded without the hasad schema prerequisite'
  $unexpected = (& $psql -X -A -t -h 127.0.0.1 -p $Port -U postgres -d $missingDb -c "SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='hasad' AND c.relkind='r';").Trim()
  Assert-True ($unexpected -eq '0') "missing-prerequisite database retained $unexpected hasad table(s)"
  Write-Output 'PREREQUISITE_FAILURE=PASS (missing hasad schema rejected without partial tables)'
  $hash = (Get-FileHash (Join-Path $migrationDir $candidate) -Algorithm SHA256).Hash
  Write-Output "MIGRATION_SHA256=$hash"
}
finally {
  try {
    if ($ready -and $createdPrimaryDb) { & $dropdb --if-exists -h 127.0.0.1 -p $Port -U postgres $db 2>$null }
    if ($ready -and $createdMissingDb) { & $dropdb --if-exists -h 127.0.0.1 -p $Port -U postgres $missingDb 2>$null }
  }
  finally {
    if ($server -and -not $server.HasExited) { & $pgctl -D $data -m fast -w stop; if ($LASTEXITCODE -ne 0) { throw 'Could not stop disposable PostgreSQL server' }; $server.WaitForExit() }
    if (Test-Path -LiteralPath $data) {
      $resolvedData = (Resolve-Path -LiteralPath $data).Path
      $resolvedTemp = (Resolve-Path -LiteralPath $env:TEMP).Path
      if (-not $resolvedData.StartsWith($resolvedTemp, [StringComparison]::OrdinalIgnoreCase) -or (Split-Path -Leaf $resolvedData) -ne "hasad_phase9a_local_$stamp") { throw "Refusing unexpected cluster cleanup path: $resolvedData" }
      Remove-Item -LiteralPath $resolvedData -Recurse -Force
    }
  }
}
