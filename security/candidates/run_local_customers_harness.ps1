# Local-only disposable PostgreSQL verification for the corrected Unit S1
# (customer direct Data API write) candidate. No network, no Supabase, no
# repository mutation. Mirrors security/candidates/run_local_inventory_movements_harness.ps1.
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$pgBin = 'C:\Program Files\PostgreSQL\17\bin'
$psql = Join-Path $pgBin 'psql.exe'
$pgRoot = Join-Path $env:TEMP ('hasad-customers-' + [guid]::NewGuid().ToString('N'))
$data = Join-Path $pgRoot 'data'
$log = Join-Path $pgRoot 'server.log'
$port = Get-Random -Minimum 56000 -Maximum 64000
$started = $false
$serverProcess = $null
$serverOut = Join-Path $pgRoot 'server.stdout.log'
$serverErr = Join-Path $pgRoot 'server.stderr.log'
New-Item -ItemType Directory -Path $pgRoot | Out-Null
try {
  & (Join-Path $pgBin 'initdb.exe') -D $data -U postgres -A trust --no-locale
  if ($LASTEXITCODE -ne 0) { throw 'local initdb failed' }
  $serverProcess = Start-Process -FilePath (Join-Path $pgBin 'postgres.exe') `
    -ArgumentList @('-D', $data, '-p', "$port", '-h', '127.0.0.1') `
    -WindowStyle Hidden -PassThru -RedirectStandardOutput $serverOut `
    -RedirectStandardError $serverErr

  $psqlArgs = @('-X','-w','-h','127.0.0.1','-p',"$port",'-U','postgres','-d','postgres','-v','ON_ERROR_STOP=1')
  $ready = $false
  for ($attempt = 0; $attempt -lt 40; $attempt++) {
    if ($serverProcess.HasExited) {
      $details = Get-Content -LiteralPath $serverErr -Raw -ErrorAction SilentlyContinue
      throw "local PostgreSQL exited during startup: $details"
    }
    & $psql @psqlArgs -c 'SELECT 1' *> $null
    if ($LASTEXITCODE -eq 0) { $ready = $true; break }
    Start-Sleep -Milliseconds 250
  }
  if (-not $ready) { throw 'local PostgreSQL did not become ready' }
  $started = $true

  & $psql @psqlArgs -f (Join-Path $PSScriptRoot 'tests\customers_harness_setup.sql')
  if ($LASTEXITCODE -ne 0) { throw 'local client-role fixture setup failed' }

  foreach ($migration in @(
    'supabase\migrations\20261026000000_v2_foundation_schemas.sql',
    'supabase\migrations\20261026000100_v2_identity_tenancy_foundation.sql',
    'supabase\migrations\20261026000200_v2_permissions_foundation.sql',
    'supabase\migrations\20261026000210_v2_permission_catalogue_seed.sql',
    'supabase\migrations\20261027000300_v2_invitation_audit_structure.sql',
    'supabase\migrations\20261027000400_v2_erp_core_master_fiscal_settings.sql'
  )) {
    & $psql @psqlArgs -f (Join-Path $repo $migration)
    if ($LASTEXITCODE -ne 0) { throw "local migration fixture failed: $migration" }
  }

  & $psql @psqlArgs -f (Join-Path $PSScriptRoot 'tests\customers_harness_fixtures.sql')
  if ($LASTEXITCODE -ne 0) { throw 'local identity fixture rows failed' }
  & $psql @psqlArgs -f (Join-Path $PSScriptRoot 'tests\customers_direct_read_setup.sql')
  if ($LASTEXITCODE -ne 0) { throw 'local direct Data API read policy setup failed' }

  & $psql @psqlArgs -f (Join-Path $PSScriptRoot 'tests\customers_executor_feasibility.sql')
  if ($LASTEXITCODE -ne 0) { throw 'local executor feasibility probe failed' }

  & $psql @psqlArgs -f (Join-Path $PSScriptRoot 'dev_direct_data_api_customers_write_v2_candidate.sql')
  if ($LASTEXITCODE -ne 0) { throw 'customer write candidate failed local installation' }

  & $psql @psqlArgs -f (Join-Path $PSScriptRoot 'tests\customers_harness_assertions.sql')
  if ($LASTEXITCODE -ne 0) { throw 'local customer write assertions failed' }

  $hash = (Get-FileHash -LiteralPath (Join-Path $PSScriptRoot 'dev_direct_data_api_customers_write_v2_candidate.sql') -Algorithm SHA256).Hash
  Write-Output "PASS: unit S1 corrected customer write candidate local verification"
  Write-Output "candidate sha256: $hash"
}
finally {
  if ($started) {
    & (Join-Path $pgBin 'pg_ctl.exe') -D $data -m fast -t 10 -w stop
    if ($LASTEXITCODE -ne 0 -and $serverProcess -and -not $serverProcess.HasExited) {
      Stop-Process -Id $serverProcess.Id -Force
      $serverProcess.WaitForExit(10000) | Out-Null
    }
  }
  $tempRoot = [System.IO.Path]::GetFullPath($env:TEMP)
  $target = [System.IO.Path]::GetFullPath($pgRoot)
  if ($target.StartsWith((Join-Path $tempRoot 'hasad-customers-'), [System.StringComparison]::OrdinalIgnoreCase)) {
    Remove-Item -LiteralPath $target -Recurse -Force -ErrorAction SilentlyContinue
  }
}
