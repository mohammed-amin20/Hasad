# Hasad ERP V2 — operator-run DEV deployment: identity foundation only
# Target: sxasnunzspkuwbxiddqd via the approved Session Pooler.
# Uses psql -W: the password is entered only into psql's prompt and is never
# stored, printed, passed on the command line, or written to this script.
# Applies only 20261026000100_v2_identity_tenancy_foundation.sql when all four
# tables are absent. Existing complete tables are verified, never recreated.

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$Psql = 'C:\Program Files\PostgreSQL\17\bin\psql.exe'
$Migration = Join-Path $RepoRoot 'supabase\migrations\20261026000100_v2_identity_tenancy_foundation.sql'
$PoolerHost = 'aws-0-ap-southeast-1.pooler.supabase.com'
$PoolerPort = '5432'
$PoolerUser = 'postgres.sxasnunzspkuwbxiddqd'
$DatabaseName = 'postgres'

if (-not (Test-Path -LiteralPath $Psql -PathType Leaf)) {
    throw 'psql executable is unavailable.'
}
if (-not (Test-Path -LiteralPath $Migration -PathType Leaf)) {
    throw 'Approved identity migration is unavailable.'
}

# Validate the locally approved migration before opening a database connection.
$MigrationText = Get-Content -LiteralPath $Migration -Raw
$ExecutableSql = [regex]::Replace($MigrationText, '(?m)^\s*--.*(?:\r?\n|$)', '')
$Tables = @([regex]::Matches($ExecutableSql, '(?im)^\s*CREATE\s+TABLE\s+hasad\.([a-z_]+)\s*\(') |
    ForEach-Object { $_.Groups[1].Value })
$ExpectedTables = @('user_profiles', 'companies', 'roles', 'company_memberships')
if ($Tables.Count -ne 4 -or (Compare-Object ($ExpectedTables | Sort-Object) ($Tables | Sort-Object) -SyncWindow 0)) {
    throw 'Local migration does not contain exactly the approved four tables.'
}
if (([regex]::Matches($ExecutableSql, 'ON\s+DELETE\s+RESTRICT')).Count -ne 7 -or
    ([regex]::Matches($ExecutableSql, 'ENABLE\s+ROW\s+LEVEL\s+SECURITY')).Count -ne 4 -or
    ([regex]::Matches($ExecutableSql, 'FORCE\s+ROW\s+LEVEL\s+SECURITY')).Count -ne 4) {
    throw 'Local migration fails the approved FK or RLS contract checks.'
}
foreach ($Forbidden in @('DROP ', 'TRUNCATE ', 'CASCADE', 'IF EXISTS', 'CREATE POLICY', 'GRANT ', 'REVOKE ', 'CREATE FUNCTION', 'CREATE TRIGGER', 'CREATE PROCEDURE', 'INSERT ', 'UPDATE ')) {
    if ($ExecutableSql -match [regex]::Escape($Forbidden)) {
        throw "Local migration contains forbidden SQL: $Forbidden"
    }
}
if ($ExecutableSql -match '(?im)^\s*DELETE\s+') {
    throw 'Local migration contains forbidden DELETE DML.'
}

$MigrationPathForPsql = $Migration.Replace('\', '/')
$TempSql = Join-Path $env:TEMP 'hasad_v2_identity_foundation_deploy.sql'

$PsqlScript = @'
\set ON_ERROR_STOP on

BEGIN TRANSACTION READ ONLY;
DO $preflight$
DECLARE
  v_target_count int;
  v_unexpected text;
BEGIN
  IF (SELECT count(*) FROM pg_namespace WHERE nspname IN ('hasad', 'hasad_api')) <> 2 THEN
    RAISE EXCEPTION 'PREFLIGHT FAILED: hasad and hasad_api must both exist';
  END IF;
  IF to_regclass('auth.users') IS NULL THEN
    RAISE EXCEPTION 'PREFLIGHT FAILED: auth.users is absent';
  END IF;
  SELECT count(*) INTO v_target_count
  FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
  WHERE n.nspname='hasad' AND c.relkind IN ('r','p')
    AND c.relname IN ('user_profiles','companies','roles','company_memberships');
  IF v_target_count NOT IN (0, 4) THEN
    RAISE EXCEPTION 'PREFLIGHT FAILED: identity foundation is partially present (% of 4 tables)', v_target_count;
  END IF;
  SELECT string_agg(c.relname, ', ' ORDER BY c.relname) INTO v_unexpected
  FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
  WHERE n.nspname='hasad' AND c.relkind IN ('r','p')
    AND c.relname NOT IN ('user_profiles','companies','roles','company_memberships');
  IF v_unexpected IS NOT NULL THEN
    RAISE EXCEPTION 'PREFLIGHT FAILED: unexpected hasad table(s): %', v_unexpected;
  END IF;
END
$preflight$;

SELECT (
  SELECT count(*) = 0
  FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
  WHERE n.nspname='hasad' AND c.relkind IN ('r','p')
    AND c.relname IN ('user_profiles','companies','roles','company_memberships')
) AS apply_identity_migration \gset
ROLLBACK;

\if :apply_identity_migration
  \i '__MIGRATION__'
\else
  \echo 'Identity foundation already present; verifying exact catalog shape without reapplying migration.'
\endif

DO $verify$
DECLARE
  v_table_count int;
  v_fk_count int;
  v_rls_count int;
  v_policy_count int;
  v_noninternal_trigger_count int;
  v_function_count int;
  v_granted_acl_count int;
BEGIN
  SELECT count(*) INTO v_table_count
  FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
  WHERE n.nspname='hasad' AND c.relkind IN ('r','p')
    AND c.relname IN ('user_profiles','companies','roles','company_memberships');
  IF v_table_count <> 4 THEN
    RAISE EXCEPTION 'POST-DEPLOY FAILED: expected 4 identity tables, found %', v_table_count;
  END IF;

  SELECT count(*) INTO v_fk_count
  FROM pg_constraint con
  WHERE con.contype='f'
    AND con.conrelid IN ('hasad.user_profiles'::regclass, 'hasad.companies'::regclass,
                         'hasad.roles'::regclass, 'hasad.company_memberships'::regclass)
    AND con.confdeltype='r';
  IF v_fk_count <> 7 THEN
    RAISE EXCEPTION 'POST-DEPLOY FAILED: expected 7 RESTRICT foreign keys, found %', v_fk_count;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint con
    WHERE con.conname='company_memberships_company_role_fkey'
      AND con.conrelid='hasad.company_memberships'::regclass
      AND con.confrelid='hasad.roles'::regclass
      AND con.confdeltype='r'
      AND array_length(con.conkey, 1)=2
      AND array_length(con.confkey, 1)=2
  ) THEN
    RAISE EXCEPTION 'POST-DEPLOY FAILED: same-company composite role FK is absent or incorrect';
  END IF;

  IF (SELECT count(*) FROM pg_constraint WHERE conname IN (
      'companies_status_check', 'roles_company_code_key', 'roles_company_id_id_key',
      'company_memberships_user_key', 'company_memberships_company_user_key',
      'company_memberships_role_required_for_non_owner_check',
      'company_memberships_status_check', 'company_memberships_revoked_at_check'
  )) <> 8 THEN
    RAISE EXCEPTION 'POST-DEPLOY FAILED: required unique/CHECK constraints missing';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_index i JOIN pg_class c ON c.oid=i.indexrelid
    WHERE c.relname='company_memberships_active_company_idx'
      AND i.indrelid='hasad.company_memberships'::regclass
      AND i.indpred IS NOT NULL
  ) THEN
    RAISE EXCEPTION 'POST-DEPLOY FAILED: active-membership partial index missing';
  END IF;

  SELECT count(*) INTO v_rls_count
  FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
  WHERE n.nspname='hasad'
    AND c.relname IN ('user_profiles','companies','roles','company_memberships')
    AND c.relrowsecurity AND c.relforcerowsecurity;
  IF v_rls_count <> 4 THEN
    RAISE EXCEPTION 'POST-DEPLOY FAILED: RLS is not enabled and forced on all 4 tables';
  END IF;

  SELECT count(*) INTO v_policy_count FROM pg_policy p
  WHERE p.polrelid IN ('hasad.user_profiles'::regclass, 'hasad.companies'::regclass,
                       'hasad.roles'::regclass, 'hasad.company_memberships'::regclass);
  IF v_policy_count <> 0 THEN
    RAISE EXCEPTION 'POST-DEPLOY FAILED: unexpected RLS policy exists';
  END IF;

  SELECT count(*) INTO v_noninternal_trigger_count FROM pg_trigger t
  WHERE t.tgrelid IN ('hasad.user_profiles'::regclass, 'hasad.companies'::regclass,
                      'hasad.roles'::regclass, 'hasad.company_memberships'::regclass)
    AND NOT t.tgisinternal;
  IF v_noninternal_trigger_count <> 0 THEN
    RAISE EXCEPTION 'POST-DEPLOY FAILED: unexpected non-internal trigger exists';
  END IF;

  SELECT count(*) INTO v_function_count FROM pg_proc p
  JOIN pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname IN ('hasad','hasad_api');
  IF v_function_count <> 0 THEN
    RAISE EXCEPTION 'POST-DEPLOY FAILED: unexpected function exists';
  END IF;

  SELECT count(*) INTO v_granted_acl_count FROM pg_class c
  JOIN pg_namespace n ON n.oid=c.relnamespace
  WHERE n.nspname='hasad'
    AND c.relname IN ('user_profiles','companies','roles','company_memberships')
    AND c.relacl IS NOT NULL;
  IF v_granted_acl_count <> 0 THEN
    RAISE EXCEPTION 'POST-DEPLOY FAILED: unexpected table ACL exists';
  END IF;
END
$verify$;

SELECT relname, relrowsecurity, relforcerowsecurity
FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
WHERE n.nspname='hasad'
  AND c.relname IN ('user_profiles','companies','roles','company_memberships')
ORDER BY relname;
'@

$PsqlScript.Replace('__MIGRATION__', $MigrationPathForPsql) |
    Set-Content -LiteralPath $TempSql -Encoding utf8

try {
    # Use the exact, qualified Session Pooler identity. A single positional
    # conninfo argument can be obscured by client/environment parsing; these
    # explicit arguments match the confirmed manual psql connection.
    $PreviousPgSslMode = $env:PGSSLMODE
    $env:PGSSLMODE = 'require'
    & $Psql -X -h $PoolerHost -p $PoolerPort -U $PoolerUser -d $DatabaseName -W -f $TempSql
    if ($LASTEXITCODE -ne 0) {
        throw 'Identity foundation deployment or verification failed. Stop before any other migration.'
    }
} finally {
    if ($null -eq $PreviousPgSslMode) {
        Remove-Item Env:PGSSLMODE -ErrorAction SilentlyContinue
    } else {
        $env:PGSSLMODE = $PreviousPgSslMode
    }
    Remove-Item -LiteralPath $TempSql -Force -ErrorAction SilentlyContinue
}
