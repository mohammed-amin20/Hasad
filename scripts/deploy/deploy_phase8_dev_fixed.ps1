[CmdletBinding()]
param(
    [switch]$PreflightOnly,
    [switch]$StageAOnly,
    [switch]$HistoryOnly,
    [switch]$StageBOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$HistoryValidationPath = Join-Path $PSScriptRoot 'phase8_history_validation.ps1'
if (-not (Test-Path -LiteralPath $HistoryValidationPath -PathType Leaf)) { throw 'Phase 8 local history validator is unavailable.' }
. $HistoryValidationPath

$RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$MigrationDir = Join-Path $RepoRoot 'supabase\migrations'
$Cli = Join-Path $RepoRoot 'node_modules\@supabase\cli-windows-x64\bin\supabase.exe'
$RefFile = Join-Path $RepoRoot 'supabase\.temp\project-ref'
$PoolerUrlFile = Join-Path $RepoRoot 'supabase\.temp\pooler-url'
$ExpectedRef = 'sxasnunzspkuwbxiddqd'
$V008 = '20261029000800'
$V009 = '20261029000900'
$File008 = '20261029000800_v2_cash_banking_payments_recon_structure.sql'
$File009 = '20261029000900_v2_expenses_structure.sql'
$Hash008 = 'EF076C57F723113A1689405EFFD6B047A3ED5675EC5613D1E00388C1332207BE'
$Hash009 = '49AA093E04A5C2F113E6051BFD45DB5B02C04A92F340DF3B5DBBEFC9349F94CA'
$PriorVersions = @('20261026000000','20261026000100','20261026000200','20261026000210',
    '20261027000300','20261027000400','20261028000500','20261028000600','20261028000700')
$Tables008 = @('cashboxes','bank_accounts','payment_documents','payment_allocations','reconciliation_statements','reconciliation_items')
$Tables009 = @('expense_categories','expense_documents','expense_document_lines','expense_attachments','expense_receipt_dedup')
$AllPhase8Tables = @($Tables008 + $Tables009)
$ExpectedPooler = 'postgresql://postgres.sxasnunzspkuwbxiddqd@aws-0-ap-southeast-1.pooler.supabase.com:5432/postgres'

function Assert-Hash([string]$Path, [string]$Expected, [string]$Label) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "$Label migration file is missing." }
    $Actual = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
    if ($Actual -cne $Expected) { throw "$Label migration SHA-256 mismatch; refusing to continue." }
}

function Restore-009Migration([string]$StagedPath, [string]$DestinationPath) {
    if (-not (Test-Path -LiteralPath $StagedPath -PathType Leaf)) { return }
    Assert-Hash $StagedPath $Hash009 'Isolated 00900'
    if (Test-Path -LiteralPath $DestinationPath -PathType Leaf) {
        $DestinationHash = (Get-FileHash -LiteralPath $DestinationPath -Algorithm SHA256).Hash
        if ($DestinationHash -cne $Hash009) { throw "00900 destination changed while isolated. Approved copy preserved at $StagedPath; inspect before proceeding." }
        Remove-Item -LiteralPath $StagedPath -Force
        return
    }
    Move-Item -LiteralPath $StagedPath -Destination $DestinationPath
    Assert-Hash $DestinationPath $Hash009 'Restored 00900'
}

function Invoke-Cli([string[]]$CliArgs, [string]$Operation) {
    $Output = @()
    $Text = ''
    $Code = $null
    $InvocationFailure = $null

    # In PowerShell 7.3+, this preference can turn a native non-zero exit into
    # a terminating PowerShell error when ErrorActionPreference is Stop. Shadow
    # it locally so stderr capture cannot bypass reading the process exit code.
    $NativePreference = Get-Variable -Name PSNativeCommandUseErrorActionPreference -ErrorAction SilentlyContinue
    $HadNativePreference = $null -ne $NativePreference
    if ($HadNativePreference) { $SavedNativePreference = $NativePreference.Value }
    $HadTelemetrySetting = Test-Path Env:SUPABASE_TELEMETRY_DISABLED
    if ($HadTelemetrySetting) { $SavedTelemetrySetting = $env:SUPABASE_TELEMETRY_DISABLED }
    try {
        if ($HadNativePreference) { $PSNativeCommandUseErrorActionPreference = $false }
        $env:SUPABASE_TELEMETRY_DISABLED = '1'
        try {
            $Output = @(& $Cli @CliArgs 2>&1)
            # Read immediately after the process invocation; PowerShell
            # formatting/capture operations below do not replace this code.
            $Code = $LASTEXITCODE
        }
        catch {
            $InvocationFailure = $_
        }
    }
    finally {
        if ($HadNativePreference) { $PSNativeCommandUseErrorActionPreference = $SavedNativePreference }
        if ($HadTelemetrySetting) { $env:SUPABASE_TELEMETRY_DISABLED = $SavedTelemetrySetting }
        else { Remove-Item Env:SUPABASE_TELEMETRY_DISABLED -ErrorAction SilentlyContinue }
    }

    if ($null -ne $InvocationFailure) {
        $Text = $InvocationFailure.ToString()
        $Category = Get-Phase8CliFailureCategory -DiagnosticText $Text -ExitCode -1 -InvocationFailed
        throw "$Operation could not complete (category $Category; native exit code unavailable). Stop and inspect local CLI availability before any retry. Raw diagnostics were suppressed."
    }

    $Text = ($Output | Out-String)
    if ($Code -ne 0) {
        $Category = Get-Phase8CliFailureCategory -DiagnosticText $Text -ExitCode $Code
        throw "$Operation failed (native exit code $Code; category $Category). Stop and inspect remote state before any retry. Raw CLI output was suppressed."
    }
    return $Text
}

function Get-History([string[]]$ExpectedApplied, [string[]]$ExpectedPending) {
    $Text = Invoke-Cli @('migration','list','--linked') 'Linked migration history query'
    $AllowedVersions = @($PriorVersions + $V008 + $V009)
    $null = Assert-SupabaseMigrationState -Text $Text -ExpectedApplied $ExpectedApplied -ExpectedPending $ExpectedPending -AllowedVersions $AllowedVersions
    return $Text
}

function Invoke-ReadonlyCatalog([string]$Sql, [string]$PassMarker) {
    $Captured = [System.Collections.Generic.List[string]]::new()
    $PreviousEap = $ErrorActionPreference
    $Code = -1
    try {
        # Match the repository's approved psql runner: native stderr is captured
        # as text, while -W continues to read the password directly from console.
        $ErrorActionPreference = 'Continue'
        & $Psql -X -W -v ON_ERROR_STOP=1 -c $Sql $PoolerUrl 2>&1 | ForEach-Object {
            $Line = if ($_ -is [System.Management.Automation.ErrorRecord]) { $_.ToString() } else { [string]$_ }
            if (-not [string]::IsNullOrWhiteSpace($Line)) { $Captured.Add($Line) | Out-Null }
        }
        $Code = $LASTEXITCODE
    }
    finally { $ErrorActionPreference = $PreviousEap }

    $Text = $Captured -join "`n"
    $MarkerFound = $Text.Contains($PassMarker)
    $Category = Get-Phase8PsqlFailureCategory -DiagnosticText $Text -ExitCode $Code -PassMarkerFound $MarkerFound
    if ($Category -ne 'PASS') {
        throw "Read-only remote catalog verification failed: $Category (psql exit $Code). No raw psql diagnostics were emitted. Stop."
    }
    return $Text
}

function New-CatalogSql([string]$Stage) {
    $ExpectedTablesRaw = if ($Stage -eq 'baseline') { @() } elseif ($Stage -eq '008') { $Tables008 } else { $AllPhase8Tables }
    $ExpectedTableSelection = ConvertTo-Phase8TableSelection -Value $ExpectedTablesRaw -AllowEmpty:($Stage -eq 'baseline')
    if ($ExpectedTableSelection.Values -isnot [string[]] -or $ExpectedTableSelection.Count -ne $ExpectedTableSelection.Values.Length) {
        throw 'Expected Phase 8 table selection has an invalid collection shape.'
    }
    $ExpectedTables = $ExpectedTableSelection.Values
    $ExpectedTableCount = if ($Stage -eq 'baseline') { 33 } elseif ($Stage -eq '008') { 39 } else { 44 }
    $ExpectedPhaseCount = if ($Stage -eq 'baseline') { 0 } elseif ($Stage -eq '008') { 6 } else { 11 }
    $ExpectedColumns = if ($Stage -eq 'baseline') { 0 } elseif ($Stage -eq '008') { 60 } else { 110 }
    $ExpectedFks = if ($Stage -eq 'baseline') { 0 } elseif ($Stage -eq '008') { 19 } else { 37 }
    $ExpectedIndexes = if ($Stage -eq 'baseline') { 0 } elseif ($Stage -eq '008') { 24 } else { 40 }
    $StageValue = $Stage.ToUpperInvariant()
    $ExpectedPhaseNames = if ($ExpectedTableSelection.Count -eq 0) { 'ARRAY[]::text[]' } else { 'ARRAY[' + (($ExpectedTables | ForEach-Object { "'$_'" }) -join ',') + ']' }
    $ExpectedExpenseCheck = if ($Stage -eq 'all') { @'
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='payment_allocations_company_expense_fkey'
    AND conrelid='hasad.payment_allocations'::regclass AND confdeltype='r') THEN
    RAISE EXCEPTION 'payment_allocations_company_expense_fkey missing or not ON DELETE RESTRICT'; END IF;
'@ } else { '' }
    return @"
BEGIN TRANSACTION READ ONLY;
DO `$phase8_catalog`$
DECLARE v_tables integer; v_phase integer; v_expected_phase integer; v_columns integer; v_fks integer; v_indexes integer;
  v_bad integer; v_rows bigint; r record;
BEGIN
  IF current_setting('transaction_read_only') <> 'on' THEN RAISE EXCEPTION 'read-only guard failed'; END IF;
  SELECT count(*) INTO v_tables FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
    WHERE n.nspname='hasad' AND c.relkind IN ('r','p');
  SELECT count(*) INTO v_phase FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
    WHERE n.nspname='hasad' AND c.relkind IN ('r','p') AND c.relname = ANY(ARRAY['cashboxes','bank_accounts','payment_documents','payment_allocations','reconciliation_statements','reconciliation_items','expense_categories','expense_documents','expense_document_lines','expense_attachments','expense_receipt_dedup']);
  SELECT count(*) INTO v_expected_phase FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
    WHERE n.nspname='hasad' AND c.relkind IN ('r','p') AND c.relname = ANY($ExpectedPhaseNames);
  IF v_tables <> $ExpectedTableCount OR v_phase <> $ExpectedPhaseCount OR v_expected_phase <> $ExpectedPhaseCount THEN RAISE EXCEPTION 'table baseline/count mismatch: total %, phase %, expected-name matches %',v_tables,v_phase,v_expected_phase; END IF;
  IF '$StageValue'='BASELINE' AND EXISTS (SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='hasad' AND c.relname = ANY(ARRAY['cashboxes','bank_accounts','payment_documents','payment_allocations','reconciliation_statements','reconciliation_items','expense_categories','expense_documents','expense_document_lines','expense_attachments','expense_receipt_dedup'])) THEN RAISE EXCEPTION 'Phase 8 table already exists'; END IF;
  SELECT count(*) INTO v_columns FROM information_schema.columns WHERE table_schema='hasad' AND table_name = ANY(ARRAY['cashboxes','bank_accounts','payment_documents','payment_allocations','reconciliation_statements','reconciliation_items','expense_categories','expense_documents','expense_document_lines','expense_attachments','expense_receipt_dedup']);
  SELECT count(*) INTO v_fks FROM pg_constraint con JOIN pg_class c ON c.oid=con.conrelid JOIN pg_namespace n ON n.oid=c.relnamespace WHERE con.contype='f' AND n.nspname='hasad' AND c.relname = ANY(ARRAY['cashboxes','bank_accounts','payment_documents','payment_allocations','reconciliation_statements','reconciliation_items','expense_categories','expense_documents','expense_document_lines','expense_attachments','expense_receipt_dedup']) AND con.confdeltype='r';
  SELECT count(*) INTO v_indexes FROM pg_index i JOIN pg_class t ON t.oid=i.indrelid JOIN pg_namespace n ON n.oid=t.relnamespace WHERE n.nspname='hasad' AND t.relname = ANY(ARRAY['cashboxes','bank_accounts','payment_documents','payment_allocations','reconciliation_statements','reconciliation_items','expense_categories','expense_documents','expense_document_lines','expense_attachments','expense_receipt_dedup']);
  IF v_columns <> $ExpectedColumns OR v_fks <> $ExpectedFks OR v_indexes <> $ExpectedIndexes THEN RAISE EXCEPTION 'columns/FKs/indexes mismatch: %/%/%',v_columns,v_fks,v_indexes; END IF;
  SELECT count(*) INTO v_bad FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='hasad' AND c.relname = ANY(ARRAY['cashboxes','bank_accounts','payment_documents','payment_allocations','reconciliation_statements','reconciliation_items','expense_categories','expense_documents','expense_document_lines','expense_attachments','expense_receipt_dedup']) AND NOT (c.relrowsecurity AND c.relforcerowsecurity);
  IF v_bad <> 0 THEN RAISE EXCEPTION 'RLS is not enabled and forced on every Phase 8 table'; END IF;
  IF EXISTS (SELECT 1 FROM pg_policy p JOIN pg_class c ON c.oid=p.polrelid JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='hasad' AND c.relname = ANY(ARRAY['cashboxes','bank_accounts','payment_documents','payment_allocations','reconciliation_statements','reconciliation_items','expense_categories','expense_documents','expense_document_lines','expense_attachments','expense_receipt_dedup'])) THEN RAISE EXCEPTION 'unexpected application policy'; END IF;
  IF EXISTS (SELECT 1 FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='hasad' AND c.relname = ANY(ARRAY['cashboxes','bank_accounts','payment_documents','payment_allocations','reconciliation_statements','reconciliation_items','expense_categories','expense_documents','expense_document_lines','expense_attachments','expense_receipt_dedup']) AND NOT t.tgisinternal) THEN RAISE EXCEPTION 'unexpected application trigger'; END IF;
  IF EXISTS (SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace CROSS JOIN LATERAL aclexplode(COALESCE(c.relacl,acldefault('r',c.relowner))) a WHERE n.nspname='hasad' AND c.relname = ANY(ARRAY['cashboxes','bank_accounts','payment_documents','payment_allocations','reconciliation_statements','reconciliation_items','expense_categories','expense_documents','expense_document_lines','expense_attachments','expense_receipt_dedup']) AND a.grantee<>c.relowner) THEN RAISE EXCEPTION 'unexpected non-owner table grant'; END IF;
  FOR r IN SELECT c.oid,c.relname FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='hasad' AND c.relname = ANY(ARRAY['cashboxes','bank_accounts','payment_documents','payment_allocations','reconciliation_statements','reconciliation_items','expense_categories','expense_documents','expense_document_lines','expense_attachments','expense_receipt_dedup']) LOOP
    EXECUTE format('SELECT count(*) FROM %s',r.oid::regclass) INTO v_rows;
    IF v_rows<>0 THEN RAISE EXCEPTION 'unexpected rows in hasad.%',r.relname; END IF;
  END LOOP;
  $ExpectedExpenseCheck
  RAISE NOTICE 'PHASE8_CATALOG_${StageValue}_PASS';
END
`$phase8_catalog`$;
ROLLBACK;
"@
}


if (-not (Test-Path -LiteralPath $Cli -PathType Leaf)) { throw 'Local Supabase CLI is unavailable.' }
if (($PreflightOnly -and $StageAOnly) -or ($PreflightOnly -and $HistoryOnly) -or
    ($PreflightOnly -and $StageBOnly) -or ($StageAOnly -and $HistoryOnly) -or
    ($StageAOnly -and $StageBOnly) -or ($HistoryOnly -and $StageBOnly)) {
    throw 'PreflightOnly, StageAOnly, HistoryOnly and StageBOnly are mutually exclusive.'
}
if (-not (Test-Path -LiteralPath $RefFile -PathType Leaf) -or (Get-Content -LiteralPath $RefFile -Raw).Trim() -cne $ExpectedRef) { throw 'Local linked project ref does not match authorized DEV.' }
Assert-Hash (Join-Path $MigrationDir $File008) $Hash008 '00800'
Assert-Hash (Join-Path $MigrationDir $File009) $Hash009 '00900'

Push-Location $RepoRoot
$Staged009 = $null
$Original009 = Join-Path $MigrationDir $File009
try {
    $null = Invoke-Cli @('--version') 'Supabase CLI version check'
    $StartingApplied = if ($StageBOnly) { @($PriorVersions + $V008) } else { $PriorVersions }
    $StartingPending = if ($StageBOnly) { @($V009) } else { @($V008,$V009) }
    $null = Get-History -ExpectedApplied $StartingApplied -ExpectedPending $StartingPending

    # This mode deliberately exits before psql setup, isolation, catalog SQL,
    # dry-run, or push. It validates only the exact expected linked history.
    if ($HistoryOnly) {
        Write-Output 'HISTORY_ONLY_PASS: nine baseline migrations match; 00800 and 00900 are local-only pending. No psql, migration isolation or push was run.'
        return
    }

    # Reuse the repository's established read-only psql catalog-query path and
    # previously verified non-secret endpoint. Password stays in psql's prompt.
    $PsqlCandidates = @('C:\Program Files\PostgreSQL\17\bin\psql.exe',(Join-Path $env:ProgramFiles 'PostgreSQL\17\bin\psql.exe'))
    $Psql = @($PsqlCandidates | Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Leaf) } | Select-Object -First 1)[0]
    if (-not $Psql) { $PsqlCommand = Get-Command psql.exe -ErrorAction SilentlyContinue; if ($PsqlCommand) { $Psql = $PsqlCommand.Source } }
    if (-not $Psql -or -not (Test-Path -LiteralPath $PoolerUrlFile -PathType Leaf)) { throw 'Existing verified read-only catalog-query prerequisites are unavailable; stopping.' }
    $PoolerUrl = (Get-Content -LiteralPath $PoolerUrlFile -Raw).Trim()
    if ($PoolerUrl -cne $ExpectedPooler) { throw 'Configured pooler endpoint does not match the repository verified DEV endpoint; stopping.' }
    $PoolerUrl += '?sslmode=require'

    if ($StageBOnly) {
        # Stage B is a separate entry path: demand verified Stage A history and
        # its full catalog/security contract before considering 00900.
        $null = Invoke-ReadonlyCatalog (New-CatalogSql '008') 'PHASE8_CATALOG_008_PASS'
        $null = Get-History -ExpectedApplied @($PriorVersions + $V008) -ExpectedPending @($V009)
        $DryB = Invoke-Cli @('db','push','--linked','--dry-run','--skip-vault','--yes') '00900 dry-run'
        Assert-Phase8DryRun -Text $DryB -ExpectedFilename $File009
        # Close the history race between dry-run and push. Since 00800 must be
        # applied and 00900 must be the sole pending version, push cannot select 00800.
        $null = Get-History -ExpectedApplied @($PriorVersions + $V008) -ExpectedPending @($V009)
        $null = Invoke-Cli @('db','push','--linked','--skip-vault','--yes') '00900 deployment'
        $null = Invoke-ReadonlyCatalog (New-CatalogSql 'all') 'PHASE8_CATALOG_ALL_PASS'
        $null = Get-History -ExpectedApplied @($PriorVersions + $V008 + $V009) -ExpectedPending @()
        Write-Output 'STAGE_B_ONLY_PASS: 00900 verified; all eleven migrations and Phase 8 catalog checks passed.'
        return
    }

    $null = Invoke-ReadonlyCatalog (New-CatalogSql 'baseline') 'PHASE8_CATALOG_BASELINE_PASS'
    if ($PreflightOnly) { Write-Output 'PREFLIGHT_ONLY_PASS: hashes, DEV ref, history and 33-table baseline verified; no files isolated and no push run.'; return }

    $Staged009 = Join-Path ([System.IO.Path]::GetTempPath()) ("hasad-phase8-00900-{0}.sql" -f [guid]::NewGuid().ToString('N'))
    Move-Item -LiteralPath $Original009 -Destination $Staged009
    Assert-Hash $Staged009 $Hash009 'Isolated 00900'
    try {
        $null = Get-History -ExpectedApplied $PriorVersions -ExpectedPending @($V008)
        $DryA = Invoke-Cli @('db','push','--linked','--dry-run','--skip-vault','--yes') '00800 dry-run'
        Assert-Phase8DryRun -Text $DryA -ExpectedFilename $File008
        $null = Invoke-Cli @('db','push','--linked','--skip-vault','--yes') '00800 deployment'
        $null = Invoke-ReadonlyCatalog (New-CatalogSql '008') 'PHASE8_CATALOG_008_PASS'
        $null = Get-History -ExpectedApplied @($PriorVersions + $V008) -ExpectedPending @()
    }
    finally {
        Restore-009Migration $Staged009 $Original009
    }

    Assert-Hash $Original009 $Hash009 'Restored 00900'
    $null = Get-History -ExpectedApplied @($PriorVersions + $V008) -ExpectedPending @($V009)
    if ($StageAOnly) {
        Write-Output 'STAGE_A_ONLY_PASS: 00800 verified; 00900 restored and remains pending. Stage B was not run.'
        return
    }
    $DryB = Invoke-Cli @('db','push','--linked','--dry-run','--skip-vault','--yes') '00900 dry-run'
    Assert-Phase8DryRun -Text $DryB -ExpectedFilename $File009
    $null = Invoke-Cli @('db','push','--linked','--skip-vault','--yes') '00900 deployment'
    $null = Invoke-ReadonlyCatalog (New-CatalogSql 'all') 'PHASE8_CATALOG_ALL_PASS'
    $null = Get-History -ExpectedApplied @($PriorVersions + $V008 + $V009) -ExpectedPending @()
    Write-Output 'PHASE 8 DEV deployment and read-only catalog/history verification completed.'
}
finally {
    try { if ($Staged009) { Restore-009Migration $Staged009 $Original009 } }
    finally { Pop-Location }
}
