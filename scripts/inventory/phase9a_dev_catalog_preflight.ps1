# Phase 9A DEV catalog preflight — READ ONLY.
# Prompts locally through psql -W. Never stores, prints, or accepts a password.
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$expectedRef = 'sxasnunzspkuwbxiddqd'
$expectedPooler = 'postgresql://postgres.sxasnunzspkuwbxiddqd@aws-0-ap-southeast-1.pooler.supabase.com:5432/postgres'
$expectedFingerprint = '8bd9b1fa10f6329a1ad9cf621300dc59'
$refFile = Join-Path $repo 'supabase\.temp\project-ref'
$poolerFile = Join-Path $repo 'supabase\.temp\pooler-url'
$psql = 'C:\Program Files\PostgreSQL\17\bin\psql.exe'

if (-not (Test-Path -LiteralPath $refFile -PathType Leaf) -or (Get-Content -LiteralPath $refFile -Raw).Trim() -cne $expectedRef) { throw 'P9A_PREFLIGHT_FAIL: linked project is not authorized DEV.' }
if (-not (Test-Path -LiteralPath $poolerFile -PathType Leaf) -or (Get-Content -LiteralPath $poolerFile -Raw).Trim() -cne $expectedPooler) { throw 'P9A_PREFLIGHT_FAIL: approved read-only endpoint mismatch.' }
if (-not (Test-Path -LiteralPath $psql -PathType Leaf)) { throw 'P9A_PREFLIGHT_FAIL: psql executable unavailable.' }

$sql = @'
BEGIN TRANSACTION READ ONLY;
DO $p9a_pre$
DECLARE v_tables integer; v_targets integer; v_fingerprint text;
BEGIN
  IF current_setting('transaction_read_only') <> 'on' THEN RAISE EXCEPTION 'read-only guard failed'; END IF;
  SELECT count(*) INTO v_tables FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='hasad' AND c.relkind='r';
  IF v_tables <> 44 THEN RAISE EXCEPTION 'hasad table count %, expected 44', v_tables; END IF;
  SELECT count(*) INTO v_targets FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='hasad' AND c.relkind='r' AND c.relname=ANY(ARRAY['departments','job_titles','employees']);
  IF v_targets <> 0 THEN RAISE EXCEPTION 'Phase 9A table exists before deployment'; END IF;
  SELECT md5(COALESCE(string_agg(item, E'\n' ORDER BY item), '')) INTO v_fingerprint FROM (
    SELECT format('table:%s:%s:%s:%s:%s', c.relname, c.relkind, c.relrowsecurity, c.relforcerowsecurity, COALESCE(c.relacl::text, '')) AS item FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='hasad' AND c.relkind='r'
    UNION ALL SELECT format('column:%s:%s:%s:%s:%s:%s', c.relname, a.attname, format_type(a.atttypid,a.atttypmod), a.attnotnull, COALESCE(pg_get_expr(d.adbin,d.adrelid),''), a.attnum) FROM pg_attribute a JOIN pg_class c ON c.oid=a.attrelid JOIN pg_namespace n ON n.oid=c.relnamespace LEFT JOIN pg_attrdef d ON d.adrelid=a.attrelid AND d.adnum=a.attnum WHERE n.nspname='hasad' AND c.relkind='r' AND a.attnum>0 AND NOT a.attisdropped
    UNION ALL SELECT format('constraint:%s:%s:%s', c.relname, co.conname, pg_get_constraintdef(co.oid)) FROM pg_constraint co JOIN pg_class c ON c.oid=co.conrelid JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='hasad'
    UNION ALL SELECT format('index:%s:%s', c.relname, pg_get_indexdef(i.indexrelid)) FROM pg_index i JOIN pg_class c ON c.oid=i.indrelid JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='hasad'
    UNION ALL SELECT format('schema:hasad:%s', COALESCE(nspacl::text,'')) FROM pg_namespace WHERE nspname='hasad'
    UNION ALL SELECT format('function:%s:%s', n.nspname, pg_get_function_identity_arguments(p.oid)) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname IN ('hasad','hasad_api')
  ) catalog_rows;
  IF v_fingerprint <> '8bd9b1fa10f6329a1ad9cf621300dc59' THEN RAISE EXCEPTION 'existing hasad catalog fingerprint drifted'; END IF;
  RAISE NOTICE 'P9A_DEV_CATALOG_PREFLIGHT_PASS';
END
$p9a_pre$;
ROLLBACK;
'@

$previousEap = $ErrorActionPreference
try {
  $ErrorActionPreference = 'Continue'
  # -W prompts only in the operator's terminal. No password is passed to this script.
  $output = @(& $psql -X -W -v ON_ERROR_STOP=1 -c $sql "${expectedPooler}?sslmode=require" 2>&1)
  $exitCode = $LASTEXITCODE
}
finally { $ErrorActionPreference = $previousEap }

$text = $output | Out-String
if ($exitCode -ne 0 -or $text -notmatch 'P9A_DEV_CATALOG_PREFLIGHT_PASS') {
  throw 'P9A_PREFLIGHT_FAIL: read-only catalog validation did not pass. No deployment was run.'
}
Write-Output 'P9A_PREFLIGHT_PASS: DEV ref verified; 44 hasad tables; Phase 9A tables absent; approved schema/security fingerprint matched; transaction rolled back.'
