# Disposable local PostgreSQL 17 verification for Unit S2 draft candidate only.
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$pgBin = 'C:\Program Files\PostgreSQL\17\bin'
$psql = Join-Path $pgBin 'psql.exe'
$root = Join-Path $env:TEMP ('hasad-sales-draft-' + [guid]::NewGuid().ToString('N'))
$data = Join-Path $root 'data'
$port = Get-Random -Minimum 56000 -Maximum 64000
New-Item -ItemType Directory -Path $root | Out-Null
try {
  & (Join-Path $pgBin 'initdb.exe') -D $data -U postgres -A trust --no-locale *> $null
  if ($LASTEXITCODE -ne 0) { throw 'initdb failed' }
  $server = Start-Process (Join-Path $pgBin 'postgres.exe') -ArgumentList @('-D',$data,'-p',"$port",'-h','127.0.0.1') -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $root 'out.log') -RedirectStandardError (Join-Path $root 'err.log')
  $args = @('-X','-w','-h','127.0.0.1','-p',"$port",'-U','postgres','-d','postgres','-v','ON_ERROR_STOP=1')
  $ready = $false
  for ($i=0; $i -lt 40; $i++) { & $psql @args -c 'SELECT 1' *> $null; if ($LASTEXITCODE -eq 0) { $ready=$true; break }; Start-Sleep -Milliseconds 250 }
  if (-not $ready) { throw 'local PostgreSQL did not become ready' }
  & $psql @args -f (Join-Path $PSScriptRoot 'tests\customers_harness_setup.sql')
  foreach ($migration in @(
    'supabase\migrations\20261026000000_v2_foundation_schemas.sql',
    'supabase\migrations\20261026000100_v2_identity_tenancy_foundation.sql',
    'supabase\migrations\20261026000200_v2_permissions_foundation.sql',
    'supabase\migrations\20261026000210_v2_permission_catalogue_seed.sql',
    'supabase\migrations\20261027000300_v2_invitation_audit_structure.sql',
    'supabase\migrations\20261027000400_v2_erp_core_master_fiscal_settings.sql',
    'supabase\migrations\20261028000600_v2_inventory_structure.sql',
    'supabase\migrations\20261028000700_v2_sales_purchases_structure.sql'
  )) { & $psql @args -f (Join-Path $repo $migration); if ($LASTEXITCODE -ne 0) { throw "migration failed: $migration" } }
  & $psql @args -f (Join-Path $PSScriptRoot 'tests\sales_draft_harness_fixtures.sql')
  & $psql @args -f (Join-Path $PSScriptRoot 'tests\customers_direct_read_setup.sql')
  & $psql @args -f (Join-Path $PSScriptRoot 'dev_sales_draft_atomic_candidate.sql')
  & $psql @args -f (Join-Path $PSScriptRoot 'tests\sales_draft_harness_assertions.sql')
  if ($LASTEXITCODE -ne 0) { throw 'S2 draft assertions failed' }
}
finally {
  if ($server -and -not $server.HasExited) { Stop-Process -Id $server.Id -Force }
  Start-Sleep -Milliseconds 500
  Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
}
