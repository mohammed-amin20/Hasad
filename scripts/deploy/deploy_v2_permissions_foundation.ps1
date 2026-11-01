# Hasad ERP V2 — operator-run DEV deployment: permission foundation only
# Target: Supabase DEV sxasnunzspkuwbxiddqd via the linked Supabase CLI.
# Applies exactly:
#   20261026000200_v2_permissions_foundation.sql
#   20261026000210_v2_permission_catalogue_seed.sql
# No application grants, policies, functions, RPCs, role rows, or mappings.
#
# The operator must set SUPABASE_DB_PASSWORD in the process environment.
# The secret is never accepted as a parameter, printed, or written to disk.

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$Cli = Join-Path $RepoRoot 'node_modules\@supabase\cli-windows-x64\bin\supabase.exe'
$ProjectRef = 'sxasnunzspkuwbxiddqd'
$StructureVersion = '20261026000200'
$SeedVersion = '20261026000210'
$ExpectedPending = @($StructureVersion, $SeedVersion)
$StructurePath = Join-Path $RepoRoot 'supabase\migrations\20261026000200_v2_permissions_foundation.sql'
$SeedPath = Join-Path $RepoRoot 'supabase\migrations\20261026000210_v2_permission_catalogue_seed.sql'

if (-not (Test-Path -LiteralPath $Cli -PathType Leaf)) { throw 'Supabase CLI is unavailable.' }
if (-not (Test-Path -LiteralPath $StructurePath -PathType Leaf)) { throw 'Prepared structure migration is unavailable.' }
if (-not (Test-Path -LiteralPath $SeedPath -PathType Leaf)) { throw 'Prepared catalogue seed is unavailable.' }
if ([string]::IsNullOrWhiteSpace($env:SUPABASE_DB_PASSWORD)) {
    throw 'Set SUPABASE_DB_PASSWORD in the operator environment before running; never pass it as an argument.'
}

$Structure = Get-Content -LiteralPath $StructurePath -Raw
$Seed = Get-Content -LiteralPath $SeedPath -Raw
$StructureNoComments = [regex]::Replace($Structure, '(?m)^\s*--.*(?:\r?\n|$)', '')

$Tables = @([regex]::Matches($StructureNoComments, '(?im)^\s*CREATE\s+TABLE\s+hasad\.([a-z_]+)\s*\(') |
    ForEach-Object { $_.Groups[1].Value } | Sort-Object)
$ExpectedTables = @('permissions', 'role_permissions', 'user_permission_overrides') | Sort-Object
if ($Tables.Count -ne 3 -or (Compare-Object $ExpectedTables $Tables -SyncWindow 0)) {
    throw 'Structure migration does not contain exactly the three approved tables.'
}
if (([regex]::Matches($StructureNoComments, 'ON\s+DELETE\s+RESTRICT')).Count -ne 4 -or
    ([regex]::Matches($StructureNoComments, 'CREATE\s+INDEX')).Count -ne 2 -or
    ([regex]::Matches($StructureNoComments, 'ENABLE\s+ROW\s+LEVEL\s+SECURITY')).Count -ne 3 -or
    ([regex]::Matches($StructureNoComments, 'FORCE\s+ROW\s+LEVEL\s+SECURITY')).Count -ne 3) {
    throw 'Structure migration fails the approved FK, index, or forced-RLS counts.'
}
if ($StructureNoComments -match '(?im)^\s*(INSERT|UPDATE|DELETE)\s') {
    throw 'Structure migration must not contain DML.'
}
foreach ($Forbidden in @('TRUNCATE', 'CASCADE', 'IF EXISTS', 'CREATE POLICY', 'GRANT ', 'REVOKE ',
        'CREATE FUNCTION', 'CREATE TRIGGER', 'CREATE PROCEDURE', 'DROP ')) {
    if ($StructureNoComments -match [regex]::Escape($Forbidden)) {
        throw "Structure migration contains forbidden SQL: $Forbidden"
    }
}

$SeedRows = [regex]::Matches($Seed, "(?m)^\s*\('([a-z]+\.[a-z_]+)',\s*'([a-z]+)',$")
if ($SeedRows.Count -ne 37) { throw "Catalogue seed must contain exactly 37 rows; found $($SeedRows.Count)." }
if ($Seed -match '(?im)^\s*INSERT\s+INTO\s+hasad\.(roles|role_permissions|user_permission_overrides)') {
    throw 'Catalogue seed must not insert roles or role mappings.'
}

$LinkedPath = Join-Path $RepoRoot 'supabase\.temp\linked-project.json'
if (-not (Test-Path -LiteralPath $LinkedPath -PathType Leaf)) { throw 'Linked-project metadata is absent.' }
$Linked = Get-Content -LiteralPath $LinkedPath -Raw | ConvertFrom-Json
if ($Linked.ref -ne $ProjectRef) {
    throw "Linked project is not the approved DEV project ($ProjectRef)."
}

$PreflightSql = @'
DO $preflight$
DECLARE
  v_identity int;
  v_permissions int;
  v_unexpected text;
  v_count int;
BEGIN
  IF to_regclass('auth.users') IS NULL THEN
    RAISE EXCEPTION 'PREFLIGHT FAILED: auth.users is absent';
  END IF;
  SELECT count(*) INTO v_identity
  FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'hasad' AND c.relkind IN ('r', 'p')
    AND c.relname IN ('user_profiles', 'companies', 'roles', 'company_memberships');
  IF v_identity <> 4 THEN
    RAISE EXCEPTION 'PREFLIGHT FAILED: expected 4 identity tables, found %', v_identity;
  END IF;
  SELECT count(*) INTO v_permissions
  FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'hasad' AND c.relkind IN ('r', 'p')
    AND c.relname IN ('permissions', 'role_permissions', 'user_permission_overrides');
  IF v_permissions NOT IN (0, 3) THEN
    RAISE EXCEPTION 'PREFLIGHT FAILED: permission foundation is partially present (% of 3)', v_permissions;
  END IF;
  SELECT string_agg(c.relname, ', ' ORDER BY c.relname) INTO v_unexpected
  FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'hasad' AND c.relkind IN ('r', 'p')
    AND c.relname NOT IN ('user_profiles', 'companies', 'roles', 'company_memberships',
                          'permissions', 'role_permissions', 'user_permission_overrides');
  IF v_unexpected IS NOT NULL THEN
    RAISE EXCEPTION 'PREFLIGHT FAILED: unexpected hasad table(s): %', v_unexpected;
  END IF;

  SELECT count(*) INTO v_count
  FROM supabase_migrations.schema_migrations
  WHERE version IN ('20261026000000', '20261026000100');
  IF v_count <> 2 THEN
    RAISE EXCEPTION 'PREFLIGHT FAILED: expected the two prior migrations applied, found %', v_count;
  END IF;
  IF EXISTS (
    SELECT 1 FROM supabase_migrations.schema_migrations
    WHERE version IN ('20261026000200', '20261026000210')
  ) THEN
    RAISE EXCEPTION 'PREFLIGHT FAILED: a prepared permission migration is already in history; stop and inspect';
  END IF;

  RAISE NOTICE 'PREFLIGHT PASS: identity tables present; permission foundation absent or complete; prior history exact';
END
$preflight$;
'@

$VerifySql = @'
DO $verify$
DECLARE
  v_count int;
  v_missing text;
  v_unexpected text;
BEGIN
  SELECT count(*) INTO v_count
  FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'hasad' AND c.relkind IN ('r', 'p')
    AND c.relname IN ('user_profiles', 'companies', 'roles', 'company_memberships',
                      'permissions', 'role_permissions', 'user_permission_overrides');
  IF v_count <> 7 THEN
    RAISE EXCEPTION 'POST-DEPLOY FAILED: expected 7 V2 tables, found %', v_count;
  END IF;

  SELECT count(*) INTO v_count
  FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'hasad' AND c.relkind IN ('r', 'p')
    AND c.relname IN ('user_profiles', 'companies', 'roles', 'company_memberships',
                      'permissions', 'role_permissions', 'user_permission_overrides')
    AND c.relrowsecurity AND c.relforcerowsecurity;
  IF v_count <> 7 THEN
    RAISE EXCEPTION 'POST-DEPLOY FAILED: RLS is not forced on all 7 tables';
  END IF;

  SELECT count(*) INTO v_count
  FROM pg_policy p
  WHERE p.polrelid IN (
    SELECT c.oid FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'hasad'
      AND c.relname IN ('user_profiles', 'companies', 'roles', 'company_memberships',
                        'permissions', 'role_permissions', 'user_permission_overrides')
  );
  IF v_count <> 0 THEN
    RAISE EXCEPTION 'POST-DEPLOY FAILED: unexpected RLS policy exists';
  END IF;

  SELECT count(*) INTO v_count
  FROM pg_constraint con
  WHERE con.contype = 'f'
    AND con.conrelid IN ('hasad.role_permissions'::regclass, 'hasad.user_permission_overrides'::regclass)
    AND con.confdeltype = 'r';
  IF v_count <> 4 THEN
    RAISE EXCEPTION 'POST-DEPLOY FAILED: expected 4 restrictive permission FKs, found %', v_count;
  END IF;

  SELECT count(*) INTO v_count
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname IN ('hasad', 'hasad_api');
  IF v_count <> 0 THEN
    RAISE EXCEPTION 'POST-DEPLOY FAILED: unexpected function exists';
  END IF;

  SELECT count(*) INTO v_count
  FROM pg_trigger t
  WHERE t.tgrelid IN ('hasad.permissions'::regclass, 'hasad.role_permissions'::regclass,
                      'hasad.user_permission_overrides'::regclass)
    AND NOT t.tgisinternal;
  IF v_count <> 0 THEN
    RAISE EXCEPTION 'POST-DEPLOY FAILED: unexpected trigger exists';
  END IF;

  SELECT count(*) INTO v_count FROM hasad.permissions;
  IF v_count <> 37 THEN
    RAISE EXCEPTION 'POST-DEPLOY FAILED: expected 37 catalogue rows, found %', v_count;
  END IF;

  SELECT string_agg(e.code, ', ' ORDER BY e.code) INTO v_missing
  FROM (VALUES
    ('members.manage'), ('company.settings'), ('company.tax'), ('company.numbering'),
    ('company.templates'), ('coa.manage'), ('journals.create'), ('journals.post'),
    ('journals.reverse'), ('fiscal.manage'), ('fiscal.close'), ('parties.manage'),
    ('cash.create'), ('cash.post'), ('cash.allocate'), ('cash.reconcile'), ('cash.manage'),
    ('sales.create'), ('sales.post'), ('sales.reverse'), ('purchases.create'),
    ('purchases.post'), ('purchases.reverse'), ('inventory.manage'), ('inventory.post'),
    ('inventory.adjust'), ('expenses.create'), ('expenses.post'), ('expenses.reverse'),
    ('expenses.manage'), ('reports.view'), ('reports.export'), ('payroll.setup'),
    ('payroll.run'), ('payroll.reverse'), ('payroll.view'), ('payroll.payslip')
  ) AS e(code)
  LEFT JOIN hasad.permissions p ON p.code = e.code
  WHERE p.code IS NULL;
  IF v_missing IS NOT NULL THEN
    RAISE EXCEPTION 'POST-DEPLOY FAILED: missing catalogue codes: %', v_missing;
  END IF;

  SELECT string_agg(c.relname, ', ' ORDER BY c.relname) INTO v_unexpected
  FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'hasad' AND c.relkind IN ('r', 'p')
    AND c.relname NOT IN ('user_profiles', 'companies', 'roles', 'company_memberships',
                          'permissions', 'role_permissions', 'user_permission_overrides');
  IF v_unexpected IS NOT NULL THEN
    RAISE EXCEPTION 'POST-DEPLOY FAILED: unexpected hasad table(s): %', v_unexpected;
  END IF;

  IF (SELECT count(*) FROM hasad.role_permissions) <> 0 THEN
    RAISE EXCEPTION 'POST-DEPLOY FAILED: role_permissions must remain empty';
  END IF;
  IF (SELECT count(*) FROM hasad.user_permission_overrides) <> 0 THEN
    RAISE EXCEPTION 'POST-DEPLOY FAILED: user_permission_overrides must remain empty';
  END IF;

  SELECT count(*) INTO v_count
  FROM supabase_migrations.schema_migrations
  WHERE version IN ('20261026000000', '20261026000100', '20261026000200', '20261026000210');
  IF v_count <> 4 THEN
    RAISE EXCEPTION 'POST-DEPLOY FAILED: expected 4 applied migration versions, found %', v_count;
  END IF;

  RAISE NOTICE 'POST-DEPLOY PASS: 3 permission tables, 37 catalogue rows, 7 forced-RLS tables, zero policies/functions/triggers/role rows';
END
$verify$;
'@

Push-Location $RepoRoot
try {
    $Preflight = (& $Cli db query --linked $PreflightSql 2>&1 | Out-String)
    if ($LASTEXITCODE -ne 0 -or $Preflight -notmatch 'PREFLIGHT PASS') {
        throw "Read-only preflight failed. Stop.`n$Preflight"
    }

    $History = (& $Cli migration list --linked 2>&1 | Out-String)
    if ($LASTEXITCODE -ne 0) { throw "Migration-list verification failed. Stop.`n$History" }
    foreach ($Version in @('20261026000000', '20261026000100', '20261026000200', '20261026000210')) {
        if ($History -notmatch [regex]::Escape($Version)) {
            throw "Migration list does not show expected version $Version. Stop."
        }
    }

    $DryRun = (& $Cli db push --linked --dry-run --skip-vault --yes 2>&1 | Out-String)
    if ($LASTEXITCODE -ne 0) { throw "CLI dry run failed. Stop.`n$DryRun" }
    foreach ($Version in $ExpectedPending) {
        if ($DryRun -notmatch [regex]::Escape($Version)) {
            throw "Dry run does not list approved version $Version. Stop."
        }
    }

    & $Cli db push --linked --skip-vault --yes
    if ($LASTEXITCODE -ne 0) {
        throw 'CLI deployment failed. Do not run any follow-up migration; inspect and report.'
    }

    $Verification = (& $Cli db query --linked $VerifySql 2>&1 | Out-String)
    if ($LASTEXITCODE -ne 0 -or $Verification -notmatch 'POST-DEPLOY PASS') {
        throw "Post-deployment verification failed. Stop and report.`n$Verification"
    }

    Write-Output $Verification
    Write-Output 'DEPLOYMENT COMPLETE: structure and catalogue seed applied; application access remains denied.'
}
finally {
    Pop-Location
}
