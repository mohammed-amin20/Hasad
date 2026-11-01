# Hasad ERP V2 — local validation for the prepared C2 structural migration.
# Never connects to Supabase DEV or production. It applies the local auth stub
# and V2 migrations to a fresh local PostgreSQL cluster, verifies catalog shape,
# then stops and removes that cluster.

[CmdletBinding()]
param(
  [int]$Port = 55433,
  [string]$PgBin = 'C:\Program Files\PostgreSQL\17\bin'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$migration = Join-Path $repo 'supabase\migrations\20261027000300_v2_invitation_audit_structure.sql'
$pre = Join-Path $PSScriptRoot 'poc_c1_c2_local_pre.sql'
$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$data = Join-Path $env:TEMP "opencode\hasad_c2_structure_$stamp"
$pgProcess = $null

function Assert-True([bool]$Condition, [string]$Message) {
  if (-not $Condition) { throw "VALIDATION FAILED: $Message" }
}

function Invoke-PsqlFile([string]$File) {
  & (Join-Path $PgBin 'psql.exe') -X -h 127.0.0.1 -p $Port -U postgres `
    -d hasad_c2_structure -v ON_ERROR_STOP=1 -f $File
  if ($LASTEXITCODE -ne 0) { throw "psql failed for $File" }
}

try {
  Assert-True (Test-Path -LiteralPath $migration -PathType Leaf) 'C2 migration is absent.'
  Assert-True (Test-Path -LiteralPath $pre -PathType Leaf) 'Local auth stub is absent.'
  Assert-True (Test-Path -LiteralPath (Join-Path $PgBin 'initdb.exe') -PathType Leaf) 'PostgreSQL initdb is absent.'
  Assert-True (-not (Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue)) "Port $Port is already in use."

  $sql = Get-Content -LiteralPath $migration -Raw
  $sqlWithoutComments = [regex]::Replace($sql, '(?m)^\s*--.*(?:\r?\n|$)', '')
  $tables = @([regex]::Matches($sqlWithoutComments, '(?im)^\s*CREATE\s+TABLE\s+hasad\.([a-z_]+)\s*\(') |
    ForEach-Object { $_.Groups[1].Value } | Sort-Object)
  $expectedTables = @('audit_log', 'company_invitations')
  Assert-True ($tables.Count -eq 2 -and -not (Compare-Object $expectedTables $tables -SyncWindow 0)) 'Migration must create exactly the two approved C2 tables.'
  Assert-True (([regex]::Matches($sqlWithoutComments, 'ON\s+DELETE\s+RESTRICT')).Count -eq 7) 'Expected exactly 7 restrictive foreign keys.'
  Assert-True (([regex]::Matches($sqlWithoutComments, '(?im)^\s*CREATE\s+(UNIQUE\s+)?INDEX')).Count -eq 5) 'Expected exactly 5 explicit indexes.'
  Assert-True (([regex]::Matches($sqlWithoutComments, 'ENABLE\s+ROW\s+LEVEL\s+SECURITY')).Count -eq 2) 'Expected ENABLE RLS on two tables.'
  Assert-True (([regex]::Matches($sqlWithoutComments, 'FORCE\s+ROW\s+LEVEL\s+SECURITY')).Count -eq 2) 'Expected FORCE RLS on two tables.'
  Assert-True (-not ($sqlWithoutComments -match '(?im)^\s*(INSERT|UPDATE|DELETE|TRUNCATE)\b')) 'Migration must not contain DML.'
  foreach ($forbidden in @('CASCADE', 'CREATE POLICY', 'GRANT ', 'REVOKE ', 'CREATE FUNCTION', 'CREATE TRIGGER', 'CREATE PROCEDURE', 'DROP ', 'CREATE ROLE', 'ALTER ROLE', 'auth.', 'storage.')) {
    Assert-True (-not $sqlWithoutComments.Contains($forbidden)) "Forbidden SQL found: $forbidden"
  }
  Write-Output 'STATIC_CONTRACT=PASS'

  & (Join-Path $PgBin 'initdb.exe') -D $data -A trust -U postgres --encoding=UTF8 --locale=C *> $null
  if ($LASTEXITCODE -ne 0) { throw 'initdb failed.' }
  $stdout = Join-Path $env:TEMP "opencode\hasad_c2_structure_$stamp.stdout.log"
  $stderr = Join-Path $env:TEMP "opencode\hasad_c2_structure_$stamp.stderr.log"
  $pgProcess = Start-Process -FilePath (Join-Path $PgBin 'postgres.exe') `
    -ArgumentList @('-D', $data, '-p', "$Port", '-c', 'listen_addresses=127.0.0.1', '-c', 'logging_collector=off') `
    -NoNewWindow -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
  for ($i = 0; $i -lt 40; $i++) {
    & (Join-Path $PgBin 'pg_isready.exe') -h 127.0.0.1 -p $Port -U postgres -d postgres *> $null
    if ($LASTEXITCODE -eq 0) { break }
    Start-Sleep -Milliseconds 500
  }
  Assert-True ($LASTEXITCODE -eq 0) 'Local PostgreSQL did not become ready.'
  & (Join-Path $PgBin 'createdb.exe') -h 127.0.0.1 -p $Port -U postgres hasad_c2_structure
  if ($LASTEXITCODE -ne 0) { throw 'createdb failed.' }

  Invoke-PsqlFile $pre
  foreach ($name in @(
    '20261026000000_v2_foundation_schemas.sql',
    '20261026000100_v2_identity_tenancy_foundation.sql',
    '20261026000200_v2_permissions_foundation.sql',
    '20261026000210_v2_permission_catalogue_seed.sql',
    '20261027000300_v2_invitation_audit_structure.sql'
  )) {
    Invoke-PsqlFile (Join-Path $repo "supabase\migrations\$name")
  }

  $verify = @'
DO $verify$
DECLARE v_count int;
BEGIN
  SELECT count(*) INTO v_count
  FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'hasad' AND c.relkind IN ('r', 'p')
    AND c.relname IN ('company_invitations', 'audit_log');
  IF v_count <> 2 THEN RAISE EXCEPTION 'expected two C2 tables, found %', v_count; END IF;

  SELECT count(*) INTO v_count
  FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'hasad' AND c.relkind IN ('r', 'p')
    AND c.relname IN ('company_invitations', 'audit_log')
    AND c.relrowsecurity AND c.relforcerowsecurity;
  IF v_count <> 2 THEN RAISE EXCEPTION 'forced RLS missing on C2 tables'; END IF;

  SELECT count(*) INTO v_count
  FROM pg_constraint con
  WHERE con.contype = 'f'
    AND con.conrelid IN ('hasad.company_invitations'::regclass, 'hasad.audit_log'::regclass)
    AND con.confdeltype = 'r';
  IF v_count <> 7 THEN RAISE EXCEPTION 'expected seven RESTRICT FKs, found %', v_count; END IF;

  SELECT count(*) INTO v_count
  FROM pg_class c
  WHERE c.relname IN (
    'company_invitations_token_hash_key',
    'company_invitations_pending_email_key',
    'company_invitations_company_status_expiry_idx',
    'audit_log_company_time_idx',
    'audit_log_entity_idx'
  );
  IF v_count <> 5 THEN RAISE EXCEPTION 'expected five C2 indexes, found %', v_count; END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'company_invitations_company_role_fkey'
      AND conrelid = 'hasad.company_invitations'::regclass
  ) THEN RAISE EXCEPTION 'company/role same-company FK missing'; END IF;

  SELECT count(*) INTO v_count
  FROM pg_policy p
  WHERE p.polrelid IN ('hasad.company_invitations'::regclass, 'hasad.audit_log'::regclass);
  IF v_count <> 0 THEN RAISE EXCEPTION 'C2 policies must be absent'; END IF;

  SELECT count(*) INTO v_count
  FROM pg_trigger t
  WHERE t.tgrelid IN ('hasad.company_invitations'::regclass, 'hasad.audit_log'::regclass)
    AND NOT t.tgisinternal;
  IF v_count <> 0 THEN RAISE EXCEPTION 'C2 triggers must be absent'; END IF;

  SELECT count(*) INTO v_count
  FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'hasad'
    AND c.relname IN ('company_invitations', 'audit_log')
    AND c.relacl IS NOT NULL;
  IF v_count <> 0 THEN RAISE EXCEPTION 'C2 table ACLs must be absent'; END IF;

  IF (SELECT count(*) FROM hasad.company_invitations) <> 0
     OR (SELECT count(*) FROM hasad.audit_log) <> 0 THEN
    RAISE EXCEPTION 'C2 tables must be empty';
  END IF;

  RAISE NOTICE 'PASS: C2 structural catalog matches the prepared contract';
END
$verify$;
'@
  & (Join-Path $PgBin 'psql.exe') -X -h 127.0.0.1 -p $Port -U postgres -d hasad_c2_structure -v ON_ERROR_STOP=1 -c $verify
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
