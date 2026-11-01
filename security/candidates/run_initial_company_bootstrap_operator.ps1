<#
  Hasad ERP V2 â€” initial company bootstrap operator runner (REVIEW-ONLY by default).

  Approved target: Hasad-erp-dev / sxasnunzspkuwbxiddqd (DEV only).
  Approved SQL   : 20261030000200_v2_initial_company_bootstrap_operator.sql
  Approved SHA   : 5C331CC5F022F6DA11C4B0D0FB9180D6C9D9195C1E118939C298E9FDF65DD76A
  Approved values: company name "Abo Amen", role code "owner", membership active,
                   is_owner true, exactly one explicitly selected existing Auth user,
                   no role permissions, no products.read.

  Modes:
    (default)          prints guards only; no network, no identity, no write
    -PreflightOnly     read-only DEV checks for the selected identity; no write
    -Execute           the single approved one-time write, gated by -Confirm CONFIRM

  Identity input (never selected automatically, never printed):
    -OwnerSecretFile <path>   read the UUID from a private local file
    (omitted)                 hidden interactive prompt in the operator's console

  The operator UUID is never written to stdout, logs, or the repository. Only
  sanitized boolean/numeric results are printed.
#>
[CmdletBinding()]
param(
  [switch]$Execute,
  [switch]$PreflightOnly,
  [string]$OwnerSecretFile,
  [string]$Confirm,
  [string]$TestCliPath
)

$ErrorActionPreference = 'Stop'

# ---- Approved, pinned constants (must not be changed without a new approval) ----
$devRef      = 'sxasnunzspkuwbxiddqd'
$devName     = 'Hasad-erp-dev'
$approvedSha = '5C331CC5F022F6DA11C4B0D0FB9180D6C9D9195C1E118939C298E9FDF65DD76A'
$companyName = 'Abo Amen'
$roleCode    = 'owner'

$repoRoot  = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$candidate = Join-Path $PSScriptRoot '20261030000200_v2_initial_company_bootstrap_operator.sql'
$cli       = Join-Path $repoRoot 'node_modules/.bin/supabase.cmd'

if (-not (Test-Path -LiteralPath (Join-Path $repoRoot 'supabase/migrations'))) { throw 'REPO_ROOT_UNRESOLVED' }
if (-not (Test-Path -LiteralPath $cli)) { throw 'SUPABASE_CLI_NOT_FOUND' }

. (Join-Path $PSScriptRoot 'lib/hasad_cli.ps1')

if ($Execute -and $PreflightOnly) { throw 'MODE_CONFLICT_EXECUTE_AND_PREFLIGHT' }

# ---- Guard 0: test-only CLI override, restricted to the local tests folder ----
if ($TestCliPath) {
  $testsRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot 'tests')).TrimEnd('\') + '\'
  $resolvedTest = [IO.Path]::GetFullPath($TestCliPath)
  if (-not $resolvedTest.StartsWith($testsRoot, [StringComparison]::OrdinalIgnoreCase)) { throw 'TEST_CLI_PATH_OUTSIDE_TESTS' }
  if (-not (Test-Path -LiteralPath $resolvedTest)) { throw 'TEST_CLI_NOT_FOUND' }
  $cli = $resolvedTest
}

# ---- Guard 1: approved SQL identity (checked in every mode, including review) ----
if (-not (Test-Path -LiteralPath $candidate)) { throw 'CANDIDATE_SQL_MISSING' }
$actualSha = (Get-FileHash -LiteralPath $candidate -Algorithm SHA256).Hash
if ($actualSha -ne $approvedSha) { throw 'CANDIDATE_SHA256_MISMATCH' }
if (Test-Path -LiteralPath (Join-Path $repoRoot 'supabase/migrations/20261030000200_v2_initial_company_bootstrap_operator.sql')) {
  throw 'CANDIDATE_MUST_NOT_BE_AN_ACTIVE_MIGRATION'
}

if (-not ($Execute -or $PreflightOnly)) {
  Write-Host 'REVIEW ONLY: no operator identity collected and no remote command executed.'
  Write-Host ("Candidate SHA-256 : {0}" -f $actualSha)
  Write-Host ("Pinned company    : {0}" -f $companyName)
  Write-Host ("Pinned role code  : {0}" -f $roleCode)
  Write-Host 'Approved scope    : exactly 6 rows for 1 explicitly selected existing Auth user; no role permissions; no products.read.'
  exit 0
}

# ---- Guard 2: execution gate ----
if ($Execute -and $Confirm -cne 'CONFIRM') { throw 'EXPLICIT_CONFIRMATION_REQUIRED' }

# ---- Private local scratch area for transient SQL and CLI payloads ----
$runDir = Join-Path $env:LOCALAPPDATA ('Temp\opencode\hasad-initial-bootstrap-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $runDir -Force | Out-Null
$aclArg = '{0}\{1}:(OI)(CI)F' -f $env:USERDOMAIN, $env:USERNAME
& icacls $runDir /inheritance:r /grant:r $aclArg *> $null
if ($LASTEXITCODE -ne 0) { Remove-Item -LiteralPath $runDir -Recurse -Force -ErrorAction SilentlyContinue; throw 'SECURE_TEMP_ACL_FAILED' }

function Write-PrivateSql([string]$path, [string]$text) {
  [IO.File]::WriteAllText($path, $text, [Text.UTF8Encoding]::new($false))
}

function Invoke-Query {
  param([string]$SqlPath, [string]$Tag)
  Invoke-HasadCliFile -CliPath $cli `
    -Arguments @('db', 'query', '--linked', '--project-ref', $devRef, '--file', $SqlPath, '--output-format', 'json') `
    -StandardOutputPath (Join-Path $runDir ($Tag + '.stdout')) `
    -StandardErrorPath  (Join-Path $runDir ($Tag + '.stderr'))
}

# ---- Guard 3: linked DEV project identity ----
function Assert-DevTarget {
  $refFile = Join-Path $repoRoot 'supabase/.temp/project-ref'
  if (-not (Test-Path -LiteralPath $refFile)) { throw 'ROOT_LINK_NOT_DEV' }
  if ((Get-Content -Raw -LiteralPath $refFile).Trim() -ne $devRef) { throw 'ROOT_LINK_NOT_DEV' }

  $r = Invoke-HasadCliFile -CliPath $cli `
    -Arguments @('projects', 'list', '--output-format', 'json') `
    -StandardOutputPath (Join-Path $runDir 'projects.stdout') `
    -StandardErrorPath  (Join-Path $runDir 'projects.stderr')
  if ($r.ExitCode -ne 0) { throw 'PROJECT_IDENTITY_QUERY_FAILED' }

  $parsed = $null
  try { $parsed = $r.StandardOutput | ConvertFrom-Json } catch { throw 'PROJECT_IDENTITY_UNPARSEABLE' }
  if ($null -eq $parsed -or $null -eq $parsed.projects) { throw 'PROJECT_IDENTITY_UNPARSEABLE' }

  $target = @($parsed.projects) | Where-Object { $_.ref -eq $devRef } | Select-Object -First 1
  if ($null -eq $target -or $target.name -cne $devName -or -not $target.linked) { throw 'DEV_PROJECT_IDENTITY_MISMATCH' }
}

function Read-OwnerId {
  if ($OwnerSecretFile) {
    if (-not (Test-Path -LiteralPath $OwnerSecretFile)) { throw 'OWNER_SECRET_FILE_NOT_FOUND' }
    $raw = (Get-Content -Raw -LiteralPath $OwnerSecretFile).Trim()
  } else {
    if (-not [Environment]::UserInteractive) { throw 'NO_INTERACTIVE_CONSOLE_FOR_HIDDEN_OWNER_PROMPT' }
    $sec = Read-Host -Prompt 'Explicit existing Auth UUID for the designated initial owner (hidden)' -AsSecureString
    $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec)
    try { $raw = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr) }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr); $sec = $null }
  }
  if ([string]::IsNullOrWhiteSpace($raw)) { throw 'OWNER_ID_EMPTY' }
  try { [void][guid]::Parse($raw) } catch { throw 'OWNER_ID_INVALID' }
  return $raw
}

# ---- Read-only preflight (base64 payload: safe against JSON escaping/pretty-print) ----
$preflightSql = @'
SELECT 'HASAD_PREFLIGHT_B64=' || replace(encode(convert_to(jsonb_build_object(
  'companies', (SELECT count(*) FROM hasad.companies),
  'company_settings', (SELECT count(*) FROM hasad.company_settings),
  'roles', (SELECT count(*) FROM hasad.roles),
  'company_memberships', (SELECT count(*) FROM hasad.company_memberships),
  'user_profiles', (SELECT count(*) FROM hasad.user_profiles),
  'audit_log', (SELECT count(*) FROM hasad.audit_log),
  'products_read_role_mappings', (SELECT count(*) FROM hasad.role_permissions WHERE permission_code = 'products.read'),
  'products_read_user_overrides', (SELECT count(*) FROM hasad.user_permission_overrides WHERE permission_code = 'products.read'),
  'hasad_tables', (SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace WHERE n.nspname = 'hasad' AND c.relkind = 'r'),
  'force_rls_tables', (SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace WHERE n.nspname = 'hasad' AND c.relkind = 'r' AND c.relrowsecurity AND c.relforcerowsecurity),
  'anon_hasad_table_grants', (SELECT count(*) FROM information_schema.role_table_grants WHERE table_schema = 'hasad' AND grantee = 'anon'),
  'authenticated_hasad_table_grants', (SELECT count(*) FROM information_schema.role_table_grants WHERE table_schema = 'hasad' AND grantee = 'authenticated'),
  'owner_auth_exists', (SELECT count(*) = 1 FROM auth.users u WHERE u.id = '__OWNER_UUID__'::uuid),
  'owner_email_confirmed', (SELECT COALESCE((SELECT (to_jsonb(u) ->> 'email_confirmed_at') IS NOT NULL FROM auth.users u WHERE u.id = '__OWNER_UUID__'::uuid), false)),
  'owner_banned', (SELECT COALESCE((SELECT (to_jsonb(u) ->> 'banned_until') IS NOT NULL AND (to_jsonb(u) ->> 'banned_until')::timestamptz > now() FROM auth.users u WHERE u.id = '__OWNER_UUID__'::uuid), false)),
  'owner_has_profile', (SELECT EXISTS (SELECT 1 FROM hasad.user_profiles p WHERE p.id = '__OWNER_UUID__'::uuid)),
  'owner_has_membership', (SELECT EXISTS (SELECT 1 FROM hasad.company_memberships m WHERE m.user_id = '__OWNER_UUID__'::uuid))
)::text, 'UTF8'), 'base64'), chr(10), '') AS payload;
'@

$postVerifySql = @'
SELECT 'HASAD_POST_B64=' || replace(encode(convert_to(jsonb_build_object(
  'companies_total', (SELECT count(*) FROM hasad.companies),
  'companies_named_abo_amen', (SELECT count(*) FROM hasad.company_settings WHERE btrim(name_ar) = 'Abo Amen'),
  'companies_active', (SELECT count(*) FROM hasad.companies WHERE status = 'active'),
  'company_settings_total', (SELECT count(*) FROM hasad.company_settings),
  'roles_total', (SELECT count(*) FROM hasad.roles),
  'owner_role_rows', (SELECT count(*) FROM hasad.roles WHERE code = 'owner' AND is_system = false),
  'role_permission_mappings_total', (SELECT count(*) FROM hasad.role_permissions),
  'products_read_role_mappings', (SELECT count(*) FROM hasad.role_permissions WHERE permission_code = 'products.read'),
  'products_read_user_overrides', (SELECT count(*) FROM hasad.user_permission_overrides WHERE permission_code = 'products.read'),
  'memberships_total', (SELECT count(*) FROM hasad.company_memberships),
  'owner_memberships_active', (SELECT count(*) FROM hasad.company_memberships WHERE is_owner AND status = 'active' AND revoked_at IS NULL),
  'selected_owner_membership', (SELECT count(*) FROM hasad.company_memberships m WHERE m.user_id = '__OWNER_UUID__'::uuid AND m.is_owner AND m.status = 'active' AND m.company_id = (SELECT id FROM hasad.companies) AND m.role_id = (SELECT id FROM hasad.roles WHERE code = 'owner')),
  'user_profiles_total', (SELECT count(*) FROM hasad.user_profiles),
  'selected_owner_profile', (SELECT count(*) FROM hasad.user_profiles p WHERE p.id = '__OWNER_UUID__'::uuid),
  'other_profiles', (SELECT count(*) FROM hasad.user_profiles p WHERE p.id <> '__OWNER_UUID__'::uuid),
  'other_memberships', (SELECT count(*) FROM hasad.company_memberships m WHERE m.user_id <> '__OWNER_UUID__'::uuid),
  'audit_company_created', (SELECT count(*) FROM hasad.audit_log WHERE action = 'company.created' AND entity_type = 'company' AND details = '{}'::jsonb),
  'audit_total', (SELECT count(*) FROM hasad.audit_log),
  'force_rls_tables', (SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace WHERE n.nspname = 'hasad' AND c.relkind = 'r' AND c.relrowsecurity AND c.relforcerowsecurity),
  'anon_hasad_table_grants', (SELECT count(*) FROM information_schema.role_table_grants WHERE table_schema = 'hasad' AND grantee = 'anon'),
  'authenticated_hasad_table_grants', (SELECT count(*) FROM information_schema.role_table_grants WHERE table_schema = 'hasad' AND grantee = 'authenticated')
)::text, 'UTF8'), 'base64'), chr(10), '') AS payload;
'@

$ownerId = $null
$candidateCopy = $null
$writeAttempted = $false
try {
  Assert-DevTarget
  Write-Host 'PASS: linked DEV project identity verified (sxasnunzspkuwbxiddqd / Hasad-erp-dev).'

  $ownerId = Read-OwnerId
  Write-Host 'PASS: one explicitly supplied owner UUID accepted (value intentionally not displayed).'

  $preflightPath = Join-Path $runDir 'preflight.sql'
  Write-PrivateSql $preflightPath $preflightSql.Replace('__OWNER_UUID__', $ownerId)
  $pre = Invoke-Query -SqlPath $preflightPath -Tag 'preflight'

  if ($pre.ExitCode -ne 0) {
    throw ('BEFORE_PREFLIGHT_QUERY_FAILED:exit={0}:stdout={1}:stderr={2}' -f $pre.ExitCode, $pre.OutputLength, $pre.ErrorLength)
  }
  $p = ConvertFrom-HasadBase64Payload -Text $pre.StandardOutput -Marker 'HASAD_PREFLIGHT_B64='
  if ($null -eq $p) {
    throw ('PREFLIGHT_PAYLOAD_MISSING:exit={0}:stdout={1}:stderr={2}' -f $pre.ExitCode, $pre.OutputLength, $pre.ErrorLength)
  }

  Write-Host '--- Read-only preflight (sanitized) ---'
  $p | ConvertTo-Json -Depth 4

  $failures = New-Object System.Collections.Generic.List[string]
  foreach ($k in @('companies', 'company_settings', 'roles', 'company_memberships', 'user_profiles', 'audit_log')) {
    if ((Get-HasadPayloadInt -Payload $p -Name $k) -ne 0) { $failures.Add("SURFACE_NOT_EMPTY:$k") }
  }
  if ((Get-HasadPayloadInt -Payload $p -Name 'products_read_role_mappings') -ne 0) { $failures.Add('PRODUCTS_READ_ROLE_MAPPING_PRESENT') }
  if ((Get-HasadPayloadInt -Payload $p -Name 'products_read_user_overrides') -ne 0) { $failures.Add('PRODUCTS_READ_USER_OVERRIDE_PRESENT') }
  if ((Get-HasadPayloadInt -Payload $p -Name 'force_rls_tables') -ne (Get-HasadPayloadInt -Payload $p -Name 'hasad_tables')) { $failures.Add('FORCE_RLS_REGRESSION') }
  if ((Get-HasadPayloadInt -Payload $p -Name 'anon_hasad_table_grants') -ne 0) { $failures.Add('ANON_GRANT_PRESENT') }
  if ((Get-HasadPayloadInt -Payload $p -Name 'authenticated_hasad_table_grants') -ne 0) { $failures.Add('AUTHENTICATED_GRANT_PRESENT') }
  if (-not (Get-HasadPayloadBool -Payload $p -Name 'owner_auth_exists')) { $failures.Add('OWNER_AUTH_ID_NOT_FOUND') }
  if (Get-HasadPayloadBool -Payload $p -Name 'owner_has_profile') { $failures.Add('OWNER_PROFILE_ALREADY_EXISTS') }
  if (Get-HasadPayloadBool -Payload $p -Name 'owner_has_membership') { $failures.Add('OWNER_MEMBERSHIP_ALREADY_EXISTS') }
  if (-not (Get-HasadPayloadBool -Payload $p -Name 'owner_email_confirmed')) { $failures.Add('OWNER_EMAIL_NOT_CONFIRMED') }
  if (Get-HasadPayloadBool -Payload $p -Name 'owner_banned') { $failures.Add('OWNER_BANNED') }

  if ($failures.Count -ne 0) { throw ('PREFLIGHT_BLOCKED:' + ($failures -join ',')) }
  Write-Host 'PASS: all read-only preflight guards satisfied.'

  if ($PreflightOnly) {
    Write-Host 'PREFLIGHT ONLY: no write performed. Re-run with -Execute -Confirm CONFIRM to apply the approved bootstrap.'
    exit 0
  }

  # ---- The single approved write ----
  $templateText = Get-Content -Raw -LiteralPath $candidate
  $replacements = [ordered]@{
    '__OWNER_AUTH_USER_ID__' = $ownerId
    '__COMPANY_ID__'         = [guid]::NewGuid().ToString()
    '__OWNER_ROLE_ID__'      = [guid]::NewGuid().ToString()
    '__MEMBERSHIP_ID__'      = [guid]::NewGuid().ToString()
    '__AUDIT_ID__'           = [guid]::NewGuid().ToString()
    '__COMPANY_NAME_AR__'    = $companyName
    '__OWNER_ROLE_CODE__'    = $roleCode
  }
  foreach ($entry in $replacements.GetEnumerator()) {
    $templateText = $templateText.Replace($entry.Key, ([string]$entry.Value).Replace("'", "''"))
  }
  if ($templateText -match '__[A-Z0-9_]+__') { throw 'TEMPLATE_TOKEN_UNRESOLVED' }
  if ((Get-FileHash -LiteralPath $candidate -Algorithm SHA256).Hash -ne $approvedSha) { throw 'CANDIDATE_SHA256_MISMATCH_AT_EXECUTION' }

  $candidateCopy = Join-Path $runDir 'bootstrap.sql'
  Write-PrivateSql $candidateCopy $templateText

  Write-Host 'Executing the approved one-time bootstrap (single attempt, no retry).'
  $writeAttempted = $true
  $run = Invoke-Query -SqlPath $candidateCopy -Tag 'bootstrap'
  Write-Host ("Bootstrap exit code: {0}" -f $run.ExitCode)

  # Verification must run and report even when the write result is ambiguous.
  $verifyPath = Join-Path $runDir 'verify.sql'
  Write-PrivateSql $verifyPath $postVerifySql.Replace('__OWNER_UUID__', $ownerId)
  $post = Invoke-Query -SqlPath $verifyPath -Tag 'verify'
  $postPayload = $null
  if ($post.ExitCode -eq 0) { $postPayload = ConvertFrom-HasadBase64Payload -Text $post.StandardOutput -Marker 'HASAD_POST_B64=' }

  Write-Host '--- Read-only post-bootstrap verification (sanitized) ---'
  if ($null -ne $postPayload) { $postPayload | ConvertTo-Json -Depth 4 }
  else { Write-Host ('POST_BOOTSTRAP_PAYLOAD_MISSING:exit={0}:stdout={1}:stderr={2}' -f $post.ExitCode, $post.OutputLength, $post.ErrorLength) }

  if ($run.ExitCode -ne 0) { throw ('BOOTSTRAP_EXECUTION_FAILED_NO_RETRY:exit={0}:stdout={1}:stderr={2}' -f $run.ExitCode, $run.OutputLength, $run.ErrorLength) }
  if ($null -eq $postPayload) { throw 'POST_BOOTSTRAP_NOT_VERIFIED' }
}
finally {
  if ($OwnerSecretFile -and $writeAttempted -and (Test-Path -LiteralPath $OwnerSecretFile)) {
    Remove-Item -LiteralPath $OwnerSecretFile -Force -ErrorAction SilentlyContinue
  }
  if (Test-Path -LiteralPath $runDir) {
    Get-ChildItem -LiteralPath $runDir -File -ErrorAction SilentlyContinue | ForEach-Object {
      $l = $_.Length
      if ($l -gt 0) {
        try { [IO.File]::WriteAllText($_.FullName, ('0' * [int]$l), [Text.UTF8Encoding]::new($false)) } catch {}
      }
    }
    Remove-Item -LiteralPath $runDir -Recurse -Force -ErrorAction SilentlyContinue
  }
  $ownerId = $null
  $p = $null
}
