# Hasad ERP V2 — Phase 8 local validation for candidate structural migrations.
# Never connects to Supabase DEV or production.

[CmdletBinding()]
param(
  [int]$Port = 55436,
  [string]$PgBin = 'C:\Program Files\PostgreSQL\17\bin'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$pre = Join-Path $PSScriptRoot 'poc_c1_c2_local_pre.sql'
$candidates = @(
  '20261029000800_v2_cash_banking_payments_recon_structure.sql',
  '20261029000900_v2_expenses_structure.sql'
)
$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$data = Join-Path $env:TEMP "opencode\hasad_phase8_$stamp"
$pgProcess = $null

function Assert-True([bool]$Condition, [string]$Message) {
  if (-not $Condition) { throw "VALIDATION FAILED: $Message" }
}

function Invoke-PsqlFile([string]$File) {
  & (Join-Path $PgBin 'psql.exe') -X -h 127.0.0.1 -p $Port -U postgres `
    -d hasad_phase8 -v ON_ERROR_STOP=1 -f $File | Out-Null
  if ($LASTEXITCODE -ne 0) { throw "psql failed for $File" }
}

try {
  foreach ($c in $candidates) {
    $p = Join-Path $repo "supabase\migrations\$c"
    Assert-True (Test-Path -LiteralPath $p -PathType Leaf) "Missing candidate $c"
    $sql = Get-Content -LiteralPath $p -Raw
    $sqlNo = [regex]::Replace($sql, '(?m)^\s*--.*(?:\r?\n|$)', '')
    Assert-True (-not ($sqlNo -match '(?im)^\s*(INSERT|UPDATE|DELETE|TRUNCATE)')) "DML in $c"
    foreach ($f in @('CASCADE','CREATE POLICY','GRANT ','REVOKE ','CREATE FUNCTION','CREATE TRIGGER','CREATE PROCEDURE','DROP ','CREATE ROLE','ALTER ROLE')) {
      Assert-True (-not $sqlNo.Contains($f)) "Forbidden $f in $c"
    }
    Assert-True (([regex]::Matches($sqlNo, 'ENABLE\s+ROW\s+LEVEL\s+SECURITY')).Count -gt 0) "No RLS in $c"
    Assert-True (([regex]::Matches($sqlNo, 'FORCE\s+ROW\s+LEVEL\s+SECURITY')).Count -gt 0) "No FORCE RLS in $c"
    Assert-True (([regex]::Matches($sqlNo, 'ON\s+DELETE\s+RESTRICT')).Count -gt 0) "No ON DELETE RESTRICT in $c"
    Write-Output "STATIC_$c=PASS"
  }

  & (Join-Path $PgBin 'initdb.exe') -D $data -A trust -U postgres --encoding=UTF8 --locale=C | Out-Null
  if ($LASTEXITCODE -ne 0) { throw 'initdb failed' }
  $stdout = Join-Path $env:TEMP "opencode\hasad_phase8_$stamp.out.log"
  $stderr = Join-Path $env:TEMP "opencode\hasad_phase8_$stamp.err.log"
  $pgProcess = Start-Process -FilePath (Join-Path $PgBin 'postgres.exe') `
    -ArgumentList @('-D', $data, '-p', "$Port", '-c', 'listen_addresses=127.0.0.1', '-c', 'logging_collector=off') `
    -NoNewWindow -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
  $ready = $false
  for ($i = 0; $i -lt 40; $i++) {
    & (Join-Path $PgBin 'pg_isready.exe') -h 127.0.0.1 -p $Port -U postgres -d postgres | Out-Null
    if ($LASTEXITCODE -eq 0) { $ready = $true; break }
    Start-Sleep -Milliseconds 500
  }
  Assert-True $ready 'Local PostgreSQL not ready'
  & (Join-Path $PgBin 'createdb.exe') -h 127.0.0.1 -p $Port -U postgres hasad_phase8 | Out-Null
  if ($LASTEXITCODE -ne 0) { throw 'createdb failed' }

  Invoke-PsqlFile $pre
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
  )) {
    Invoke-PsqlFile (Join-Path $repo "supabase\migrations\$name")
  }
  foreach ($c in $candidates) {
    Invoke-PsqlFile (Join-Path $repo "supabase\migrations\$c")
  }

  $verify = @'
DO $verify$
DECLARE v_count int;
BEGIN
  SELECT count(*) INTO v_count FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
  WHERE n.nspname='hasad' AND c.relkind IN ('r','p') AND c.relname IN ('cashboxes','bank_accounts','payment_documents','payment_allocations','reconciliation_statements','reconciliation_items');
  IF v_count <> 6 THEN RAISE EXCEPTION 'cash/bank: expected 6'; END IF;
  SELECT count(*) INTO v_count FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
  WHERE n.nspname='hasad' AND c.relkind IN ('r','p') AND c.relname IN ('expense_categories','expense_documents','expense_document_lines','expense_attachments','expense_receipt_dedup');
  IF v_count <> 5 THEN RAISE EXCEPTION 'expenses: expected 5'; END IF;
  SELECT count(*) INTO v_count FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
  WHERE n.nspname='hasad' AND c.relname IN ('cashboxes','bank_accounts','payment_documents','payment_allocations','reconciliation_statements','reconciliation_items','expense_categories','expense_documents','expense_document_lines','expense_attachments','expense_receipt_dedup')
    AND c.relrowsecurity AND c.relforcerowsecurity;
  IF v_count <> 11 THEN RAISE EXCEPTION 'phase8: forced RLS missing'; END IF;
  SELECT count(*) INTO v_count FROM pg_policy p JOIN pg_class c ON c.oid=p.polrelid JOIN pg_namespace n ON n.oid=c.relnamespace
  WHERE n.nspname='hasad' AND c.relname IN ('cashboxes','bank_accounts','payment_documents','payment_allocations','reconciliation_statements','reconciliation_items','expense_categories','expense_documents','expense_document_lines','expense_attachments','expense_receipt_dedup');
  IF v_count <> 0 THEN RAISE EXCEPTION 'phase8: policies present'; END IF;
  SELECT count(*) INTO v_count FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid JOIN pg_namespace n ON n.oid=c.relnamespace
  WHERE n.nspname='hasad' AND c.relname IN ('cashboxes','bank_accounts','payment_documents','payment_allocations','reconciliation_statements','reconciliation_items','expense_categories','expense_documents','expense_document_lines','expense_attachments','expense_receipt_dedup')
    AND NOT t.tgisinternal;
  IF v_count <> 0 THEN RAISE EXCEPTION 'phase8: triggers present'; END IF;
  SELECT count(*) INTO v_count FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
  WHERE n.nspname='hasad' AND c.relkind IN ('r','p') AND c.relname IN ('cashboxes','bank_accounts','payment_documents','payment_allocations','reconciliation_statements','reconciliation_items','expense_categories','expense_documents','expense_document_lines','expense_attachments','expense_receipt_dedup')
    AND c.relacl IS NOT NULL;
  IF v_count <> 0 THEN RAISE EXCEPTION 'phase8: ACLs present'; END IF;
  RAISE NOTICE 'PASS: Phase 8 candidate structures';
END
$verify$;
'@
  & (Join-Path $PgBin 'psql.exe') -X -h 127.0.0.1 -p $Port -U postgres -d hasad_phase8 -v ON_ERROR_STOP=1 -c $verify | Out-Null
  if ($LASTEXITCODE -ne 0) { throw 'catalog verification failed' }
  Write-Output 'LOCAL_CATALOG_PHASE8=PASS'
}
finally {
  if ($pgProcess -and -not $pgProcess.HasExited) {
    & (Join-Path $PgBin 'pg_ctl.exe') -D $data -m fast stop | Out-Null
    Start-Sleep -Seconds 1
    if (-not $pgProcess.HasExited) { Stop-Process -Id $pgProcess.Id -Force -ErrorAction SilentlyContinue }
  }
  if (Test-Path -LiteralPath $data) { Remove-Item -LiteralPath $data -Recurse -Force -ErrorAction SilentlyContinue }
}
