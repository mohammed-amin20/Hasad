# Hasad ERP V2 — guarded Phase 9A DEV deployment runner.
# The default mode performs no remote operation. -PreflightOnly is read-only;
# -Deploy is intentionally explicit and is for the owner-authorized operator's
# normal PowerShell 7 session only.
[CmdletBinding()]
param(
  [switch]$PreflightOnly,
  [switch]$Deploy,
  [switch]$CliCheckOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$ModeCount = 0
foreach ($Mode in @($PreflightOnly, $Deploy, $CliCheckOnly)) { if ($Mode) { $ModeCount++ } }
if ($ModeCount -ne 1) {
  throw 'Choose exactly one mode: -CliCheckOnly, -PreflightOnly (read-only), or -Deploy (explicit operator deployment).'
}

$RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$MigrationDir = Join-Path $RepoRoot 'supabase\migrations'
$Cli = Join-Path $RepoRoot 'node_modules\@supabase\cli-windows-x64\bin\supabase.exe'
$RefFile = Join-Path $RepoRoot 'supabase\.temp\project-ref'
$LinkedFile = Join-Path $RepoRoot 'supabase\.temp\linked-project.json'
$PoolerUrlFile = Join-Path $RepoRoot 'supabase\.temp\pooler-url'
$HistoryValidationPath = Join-Path $PSScriptRoot 'phase8_history_validation.ps1'
$ExpectedRef = 'sxasnunzspkuwbxiddqd'
$CandidateVersion = '20261029001000'
$CandidateFile = '20261029001000_v2_phase9a_employee_org_structure.sql'
$CandidateHash = '56FD068BF9B2F01568BE4BCCBF155ED3EA2CA1E15F404AFB375939F0712F704F'
$ExpectedBaselineCatalogMd5 = '8bd9b1fa10f6329a1ad9cf621300dc59'
$ExpectedPooler = 'postgresql://postgres.sxasnunzspkuwbxiddqd@aws-0-ap-southeast-1.pooler.supabase.com:5432/postgres'

if (-not (Test-Path -LiteralPath $HistoryValidationPath -PathType Leaf)) { throw 'Generic migration-history validator is unavailable.' }
. $HistoryValidationPath

function Assert-CandidateHash {
  $Path = Join-Path $MigrationDir $CandidateFile
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw 'Approved Phase 9A migration file is missing.' }
  $Actual = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
  if ($Actual -cne $CandidateHash) { throw 'Approved Phase 9A migration SHA-256 mismatch; refusing to continue.' }
}

function Get-ExpectedMigrationState {
  $Files = @(Get-ChildItem -LiteralPath $MigrationDir -Filter '*.sql' -File | Sort-Object Name)
  if ($Files.Count -ne 12) { throw "Local migration set has $($Files.Count) files, expected exactly 12." }
  $Versions = [System.Collections.Generic.List[string]]::new()
  foreach ($File in $Files) {
    if ($File.Name -notmatch '^(\d{14})_[A-Za-z0-9_.-]+\.sql$') { throw "Invalid migration filename: $($File.Name)" }
    $Versions.Add($Matches[1])
  }
  if (($Versions | Sort-Object -Unique).Count -ne 12) { throw 'Local migration versions are not unique.' }
  if ($Files[-1].Name -cne $CandidateFile -or $Versions[-1] -cne $CandidateVersion) { throw 'Phase 9A migration is not the sole last local migration.' }
  $Applied = @($Versions | Where-Object { $_ -cne $CandidateVersion })
  if ($Applied.Count -ne 11) { throw "Expected eleven baseline migrations, found $($Applied.Count)." }
  return [pscustomobject]@{ Applied = [string[]]$Applied; Pending = [string[]]@($CandidateVersion); Allowed = [string[]]$Versions }
}

function Assert-LinkedProject {
  if (-not (Test-Path -LiteralPath $RefFile -PathType Leaf)) { throw 'Local project-ref metadata is missing.' }
  if ((Get-Content -LiteralPath $RefFile -Raw).Trim() -cne $ExpectedRef) { throw 'Linked project ref does not match authorized DEV.' }
  if (-not (Test-Path -LiteralPath $LinkedFile -PathType Leaf)) { throw 'Local linked-project metadata is missing.' }
  $LinkedText = Get-Content -LiteralPath $LinkedFile -Raw
  if ($LinkedText -notmatch [regex]::Escape($ExpectedRef)) { throw 'Linked-project metadata does not identify authorized DEV.' }
}

function Get-Psql {
  $Candidates = @('C:\Program Files\PostgreSQL\17\bin\psql.exe', (Join-Path $env:ProgramFiles 'PostgreSQL\17\bin\psql.exe'))
  $Psql = @($Candidates | Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Leaf) } | Select-Object -First 1)[0]
  if (-not $Psql) { $Command = Get-Command psql.exe -ErrorAction SilentlyContinue; if ($Command) { $Psql = $Command.Source } }
  if (-not $Psql) { throw 'psql is unavailable.' }
  return $Psql
}

function Get-PoolerUrl {
  if (-not (Test-Path -LiteralPath $PoolerUrlFile -PathType Leaf)) { throw 'Read-only pooler metadata is missing.' }
  $Url = (Get-Content -LiteralPath $PoolerUrlFile -Raw).Trim()
  if ($Url -cne $ExpectedPooler) { throw 'Configured pooler endpoint does not match the approved DEV endpoint.' }
  return "$Url?sslmode=require"
}


function Invoke-Cli([string[]]$CliArgs, [string]$Operation) {
    $Output = @()
    $Text = ''
    $ExitCode = $null
    $InvocationFailure = $null

    $PreviousEap = $ErrorActionPreference

    $NativePreference = Get-Variable `
        -Name PSNativeCommandUseErrorActionPreference `
        -ErrorAction SilentlyContinue

    $HadNativePreference = $null -ne $NativePreference

    if ($HadNativePreference) {
        $SavedNativePreference = $NativePreference.Value
    }

    $HadTelemetry = Test-Path Env:SUPABASE_TELEMETRY_DISABLED

    if ($HadTelemetry) {
        $SavedTelemetry = $env:SUPABASE_TELEMETRY_DISABLED
    }

    try {
        # Avoid treating native stderr notices as terminating errors.
        $ErrorActionPreference = 'Continue'

        if ($HadNativePreference) {
            $PSNativeCommandUseErrorActionPreference = $false
        }

        $env:SUPABASE_TELEMETRY_DISABLED = '1'

        try {
            $Output = @(& $Cli @CliArgs 2>&1)
            $ExitCode = $LASTEXITCODE
        }
        catch {
            $InvocationFailure = $_
        }
    }
    finally {
        $ErrorActionPreference = $PreviousEap

        if ($HadNativePreference) {
            $PSNativeCommandUseErrorActionPreference = $SavedNativePreference
        }

        if ($HadTelemetry) {
            $env:SUPABASE_TELEMETRY_DISABLED = $SavedTelemetry
        }
        else {
            Remove-Item Env:SUPABASE_TELEMETRY_DISABLED `
                -ErrorAction SilentlyContinue
        }
    }

    if ($null -ne $InvocationFailure) {
        $Text = $InvocationFailure.ToString()

        $Category = Get-Phase8CliFailureCategory `
            -DiagnosticText $Text `
            -ExitCode -1 `
            -InvocationFailed

        throw "$Operation failed (category $Category). Stop and inspect remote state before retry; raw diagnostics were suppressed."
    }

    $Text = $Output | Out-String

    if ($ExitCode -ne 0) {
        $Category = Get-Phase8CliFailureCategory `
            -DiagnosticText $Text `
            -ExitCode $ExitCode

        throw "$Operation failed (category $Category). Stop and inspect remote state before retry; raw diagnostics were suppressed."
    }

    return $Text
}


if ($CliCheckOnly) {
  if (-not (Test-Path -LiteralPath $Cli -PathType Leaf)) { throw 'Local Supabase CLI is unavailable.' }
  $VersionText = Invoke-Cli @('--version') 'Supabase CLI version check'
  $VersionMatch = [regex]::Match($VersionText, '(?m)^\s*(?:supabase\s+)?v?(\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.-]+)?)\s*$')
  if (-not $VersionMatch.Success) { throw 'Supabase CLI version check returned success but no parseable installed version.' }
  Write-Output "CLI_CHECK_PASS: Supabase CLI $($VersionMatch.Groups[1].Value) is executable. No Supabase or PostgreSQL connection was attempted."
  return
}

function Assert-History([string[]]$ExpectedApplied, [string[]]$ExpectedPending, [string[]]$Allowed) {
  $History = Invoke-Cli @('migration', 'list', '--linked') 'Linked migration-history query'

  # Ignore only the two well-known Supabase CLI update-message lines.
  # Their placement depends on stderr/stdout ordering, and the URL may be
  # emitted as a plain link or as Markdown. All other lines remain subject
  # to the strict migration-history parser.
  $AnsiEscape = [string][char]27 + '\[[0-9;]*[ -/]*[@-~]'
  $History = [regex]::Replace($History, $AnsiEscape, '')
  $Lines = @($History -split '\r?\n' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
  $NoticePattern = '^A new version of Supabase CLI is available: v[0-9]+\.[0-9]+\.[0-9]+ \(currently installed v[0-9]+\.[0-9]+\.[0-9]+\)$'
  $Url = 'https://supabase.com/docs/guides/cli/getting-started#updating-the-supabase-cli'
  $AdvicePrefix = 'We recommend updating regularly for new features and bug fixes: '
  $NoticeCount = 0
  $AdviceCount = 0
  $Remaining = [System.Collections.Generic.List[string]]::new()
  foreach ($Line in $Lines) {
    $Trimmed = $Line.Trim()
    if ($Trimmed -cmatch $NoticePattern) { $NoticeCount++; continue }
    if ($Trimmed.StartsWith($AdvicePrefix, [StringComparison]::Ordinal)) {
      $Target = $Trimmed.Substring($AdvicePrefix.Length)
      if ($Target -ceq $Url -or $Target -ceq ('[' + $Url + '](' + $Url + ')')) {
        $AdviceCount++
        continue
      }
    }
    $Remaining.Add($Line)
  }

  if ($NoticeCount -ne $AdviceCount -or $NoticeCount -gt 1) {
    throw 'Malformed Supabase migration list: incomplete or duplicate CLI update notice.'
  }

  $CleanHistory = $Remaining -join "`n"
  $null = Assert-SupabaseMigrationState -Text $CleanHistory -ExpectedApplied $ExpectedApplied -ExpectedPending $ExpectedPending -AllowedVersions $Allowed
}

function Invoke-ReadonlyCatalog([string]$Sql, [string]$Marker) {
  $Psql = Get-Psql
  $PoolerUrl = Get-PoolerUrl
  $Captured = [System.Collections.Generic.List[string]]::new()
  $PreviousEap = $ErrorActionPreference
  try {
    $ErrorActionPreference = 'Continue'
    & $Psql -X -W -v ON_ERROR_STOP=1 -c $Sql $PoolerUrl 2>&1 | ForEach-Object {
      $Line = if ($_ -is [System.Management.Automation.ErrorRecord]) { $_.ToString() } else { [string]$_ }
      if (-not [string]::IsNullOrWhiteSpace($Line)) { $Captured.Add($Line) | Out-Null }
    }
    $ExitCode = $LASTEXITCODE
  }
  finally { $ErrorActionPreference = $PreviousEap }
  $Text = $Captured -join "`n"
  $Category = Get-Phase8PsqlFailureCategory -DiagnosticText $Text -ExitCode $ExitCode -PassMarkerFound:$Text.Contains($Marker)
  if ($Category -ne 'PASS') { throw "Read-only catalog verification failed (category $Category). Stop and inspect remote state before retry; raw diagnostics were suppressed." }
}

function New-CatalogSql([ValidateSet('Pre','Post')][string]$Stage) {
  $ExpectedTableCount = if ($Stage -eq 'Pre') { 44 } else { 47 }
  $ExpectedTargetCount = if ($Stage -eq 'Pre') { 0 } else { 3 }
  $PostChecks = if ($Stage -eq 'Post') { @'
  SELECT count(*) INTO v_count FROM information_schema.columns WHERE table_schema='hasad' AND table_name = ANY(v_targets);
  IF v_count <> 19 THEN RAISE EXCEPTION 'Phase 9A column count %, expected 19', v_count; END IF;
  SELECT count(*) INTO v_count FROM pg_constraint co JOIN pg_class c ON c.oid=co.conrelid JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='hasad' AND c.relname=ANY(v_targets) AND co.contype='p';
  IF v_count <> 3 THEN RAISE EXCEPTION 'Phase 9A PK count %, expected 3', v_count; END IF;
  SELECT count(*) INTO v_count FROM pg_constraint co JOIN pg_class c ON c.oid=co.conrelid JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='hasad' AND c.relname=ANY(v_targets) AND co.contype='u';
  IF v_count <> 6 THEN RAISE EXCEPTION 'Phase 9A UNIQUE count %, expected 6', v_count; END IF;
  SELECT count(*) INTO v_count FROM pg_constraint co JOIN pg_class c ON c.oid=co.conrelid JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='hasad' AND c.relname=ANY(v_targets) AND co.contype='f';
  IF v_count <> 5 THEN RAISE EXCEPTION 'Phase 9A FK count %, expected 5', v_count; END IF;
  SELECT count(*) INTO v_count FROM pg_constraint co JOIN pg_class c ON c.oid=co.conrelid JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='hasad' AND c.relname=ANY(v_targets) AND co.contype='c';
  IF v_count <> 9 THEN RAISE EXCEPTION 'Phase 9A CHECK count %, expected 9', v_count; END IF;
  SELECT count(*) INTO v_count FROM pg_index i JOIN pg_class c ON c.oid=i.indrelid JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='hasad' AND c.relname=ANY(v_targets);
  IF v_count <> 9 THEN RAISE EXCEPTION 'Phase 9A index count %, expected 9', v_count; END IF;
  IF EXISTS (SELECT 1 FROM pg_constraint co JOIN pg_class c ON c.oid=co.conrelid JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='hasad' AND c.relname=ANY(v_targets) AND co.contype='f' AND co.confdeltype<>'r') THEN RAISE EXCEPTION 'Phase 9A FK is not ON DELETE RESTRICT'; END IF;
  IF EXISTS (SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='hasad' AND c.relname=ANY(v_targets) AND NOT (c.relrowsecurity AND c.relforcerowsecurity)) THEN RAISE EXCEPTION 'Phase 9A RLS is not enabled and forced'; END IF;
  IF EXISTS (SELECT 1 FROM pg_policy p JOIN pg_class c ON c.oid=p.polrelid JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='hasad' AND c.relname=ANY(v_targets)) THEN RAISE EXCEPTION 'Phase 9A policy exists'; END IF;
  IF EXISTS (SELECT 1 FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='hasad' AND c.relname=ANY(v_targets) AND NOT t.tgisinternal) THEN RAISE EXCEPTION 'Phase 9A trigger exists'; END IF;
  IF EXISTS (SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='hasad' AND c.relname=ANY(v_targets) AND c.relacl IS NOT NULL) THEN RAISE EXCEPTION 'Phase 9A table ACL exists'; END IF;
  IF EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname IN ('hasad','hasad_api')) THEN RAISE EXCEPTION 'unexpected hasad or hasad_api function exists'; END IF;
  FOR v_target IN SELECT unnest(v_targets) LOOP
    EXECUTE format('SELECT count(*) FROM hasad.%I', v_target) INTO v_rows;
    IF v_rows <> 0 THEN RAISE EXCEPTION 'Phase 9A table % has rows', v_target; END IF;
  END LOOP;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint co WHERE co.conname='employees_company_department_fkey' AND pg_get_constraintdef(co.oid)='FOREIGN KEY (company_id, department_id) REFERENCES hasad.departments(company_id, id) ON DELETE RESTRICT') THEN RAISE EXCEPTION 'employees_company_department_fkey is missing or malformed'; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint co WHERE co.conname='employees_company_job_title_fkey' AND pg_get_constraintdef(co.oid)='FOREIGN KEY (company_id, job_title_id) REFERENCES hasad.job_titles(company_id, id) ON DELETE RESTRICT') THEN RAISE EXCEPTION 'employees_company_job_title_fkey is missing or malformed'; END IF;
'@ } else { @'
  IF v_target_count <> 0 THEN RAISE EXCEPTION 'Phase 9A table exists before deployment'; END IF;
'@ }
  $Marker = if ($Stage -eq 'Pre') { 'PHASE9A_PREFLIGHT_PASS' } else { 'PHASE9A_POSTDEPLOY_PASS' }
  return @"
BEGIN TRANSACTION READ ONLY;
DO `$phase9a_catalog`$
DECLARE
  v_targets text[] := ARRAY['departments','job_titles','employees'];
  v_count integer; v_target_count integer; v_fingerprint text; v_rows bigint; v_target text;
BEGIN
  IF current_setting('transaction_read_only') <> 'on' THEN RAISE EXCEPTION 'read-only guard failed'; END IF;
  SELECT count(*) INTO v_count FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='hasad' AND c.relkind='r';
  IF v_count <> $ExpectedTableCount THEN RAISE EXCEPTION 'hasad table count %, expected $ExpectedTableCount', v_count; END IF;
  SELECT count(*) INTO v_target_count FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='hasad' AND c.relkind='r' AND c.relname=ANY(v_targets);
  IF v_target_count <> $ExpectedTargetCount THEN RAISE EXCEPTION 'Phase 9A table count %, expected $ExpectedTargetCount', v_target_count; END IF;
  SELECT md5(COALESCE(string_agg(item, E'\n' ORDER BY item), '')) INTO v_fingerprint FROM (
    SELECT format('table:%s:%s:%s:%s:%s', c.relname, c.relkind, c.relrowsecurity, c.relforcerowsecurity, COALESCE(c.relacl::text, '')) AS item FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='hasad' AND c.relkind='r' AND c.relname<>ALL(v_targets)
    UNION ALL SELECT format('column:%s:%s:%s:%s:%s:%s', c.relname, a.attname, format_type(a.atttypid,a.atttypmod), a.attnotnull, COALESCE(pg_get_expr(d.adbin,d.adrelid),''), a.attnum) FROM pg_attribute a JOIN pg_class c ON c.oid=a.attrelid JOIN pg_namespace n ON n.oid=c.relnamespace LEFT JOIN pg_attrdef d ON d.adrelid=a.attrelid AND d.adnum=a.attnum WHERE n.nspname='hasad' AND c.relkind='r' AND c.relname<>ALL(v_targets) AND a.attnum>0 AND NOT a.attisdropped
    UNION ALL SELECT format('constraint:%s:%s:%s', c.relname, co.conname, pg_get_constraintdef(co.oid)) FROM pg_constraint co JOIN pg_class c ON c.oid=co.conrelid JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='hasad' AND c.relname<>ALL(v_targets)
    UNION ALL SELECT format('index:%s:%s', c.relname, pg_get_indexdef(i.indexrelid)) FROM pg_index i JOIN pg_class c ON c.oid=i.indrelid JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='hasad' AND c.relname<>ALL(v_targets)
    UNION ALL SELECT format('schema:hasad:%s', COALESCE(nspacl::text,'')) FROM pg_namespace WHERE nspname='hasad'
    UNION ALL SELECT format('function:%s:%s', n.nspname, pg_get_function_identity_arguments(p.oid)) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname IN ('hasad','hasad_api')
  ) catalog_rows;
  IF v_fingerprint <> '$ExpectedBaselineCatalogMd5' THEN RAISE EXCEPTION 'existing hasad catalog fingerprint drifted'; END IF;
  $PostChecks
  RAISE NOTICE '$Marker';
END
`$phase9a_catalog`$;
ROLLBACK;
"@
}

function Invoke-Preflight([pscustomobject]$State) {
  Assert-CandidateHash
  Assert-LinkedProject
  if (-not (Test-Path -LiteralPath $Cli -PathType Leaf)) { throw 'Local Supabase CLI is unavailable.' }
  $null = Invoke-Cli @('--version') 'Supabase CLI version check'
  Assert-History $State.Applied $State.Pending $State.Allowed
  Invoke-ReadonlyCatalog (New-CatalogSql 'Pre') 'PHASE9A_PREFLIGHT_PASS'
  $DryRun = Invoke-Cli @('db','push','--linked','--dry-run','--skip-vault','--yes') 'Phase 9A dry-run'
  Assert-Phase8DryRun -Text $DryRun -ExpectedFilename $CandidateFile
  Write-Output 'PREFLIGHT_PASS: approved hash, DEV ref, exact 11-applied/01000-pending history, 44-table baseline, drift fingerprint, and single-file dry-run verified. No deployment was run.'
}

Push-Location $RepoRoot
try {
  $State = Get-ExpectedMigrationState
  Invoke-Preflight $State
  if ($PreflightOnly) { return }

  # Close the race between dry-run and the only state-changing command.
  Assert-CandidateHash
  Assert-LinkedProject
  Assert-History $State.Applied $State.Pending $State.Allowed
  Invoke-ReadonlyCatalog (New-CatalogSql 'Pre') 'PHASE9A_PREFLIGHT_PASS'
  $DryRun = Invoke-Cli @('db','push','--linked','--dry-run','--skip-vault','--yes') 'Phase 9A final dry-run'
  Assert-Phase8DryRun -Text $DryRun -ExpectedFilename $CandidateFile
  Assert-CandidateHash
  Assert-LinkedProject
  Assert-History $State.Applied $State.Pending $State.Allowed
  $null = Invoke-Cli @('db','push','--linked','--skip-vault','--yes') 'Phase 9A deployment'
  Invoke-ReadonlyCatalog (New-CatalogSql 'Post') 'PHASE9A_POSTDEPLOY_PASS'
  Assert-History @($State.Applied + $CandidateVersion) @() $State.Allowed
  Write-Output 'DEPLOY_PASS: Phase 9A 01000 is deployed and verified. No retry is permitted without remote-state inspection.'
}
finally { Pop-Location }
