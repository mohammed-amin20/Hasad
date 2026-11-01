$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$pgBin = 'C:\Program Files\PostgreSQL\17\bin'
$psql = Join-Path $pgBin 'psql.exe'
$pgRoot = Join-Path $env:TEMP ('hasad-inventory-' + [guid]::NewGuid().ToString('N'))
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

  & $psql @psqlArgs -f (Join-Path $PSScriptRoot 'tests\inventory_movements_harness_setup.sql')
  if ($LASTEXITCODE -ne 0) { throw 'local fixture setup failed' }
  foreach ($migration in @(
    'supabase\migrations\20261026000000_v2_foundation_schemas.sql',
    'supabase\migrations\20261026000100_v2_identity_tenancy_foundation.sql',
    'supabase\migrations\20261026000200_v2_permissions_foundation.sql',
    'supabase\migrations\20261026000210_v2_permission_catalogue_seed.sql',
    'supabase\migrations\20261027000300_v2_invitation_audit_structure.sql',
    'supabase\migrations\20261028000600_v2_inventory_structure.sql'
  )) {
    & $psql @psqlArgs -f (Join-Path $repo $migration)
    if ($LASTEXITCODE -ne 0) { throw "local migration fixture failed: $migration" }
  }

  & $psql @psqlArgs -f (Join-Path $PSScriptRoot 'tests\inventory_movements_direct_read_setup.sql')
  if ($LASTEXITCODE -ne 0) { throw 'local direct Data API policy setup failed' }
  & $psql @psqlArgs -f (Join-Path $repo 'security\candidates\dev_direct_data_api_inventory_warehouses_stock_candidate.sql')
  if ($LASTEXITCODE -ne 0) { throw 'local stock-read policy setup failed' }

  & $psql @psqlArgs -f (Join-Path $PSScriptRoot 'dev_direct_data_api_inventory_movements_candidate.sql')
  if ($LASTEXITCODE -ne 0) { throw 'movement candidate failed local installation' }
  & $psql @psqlArgs -f (Join-Path $PSScriptRoot 'tests\inventory_movements_harness_assertions.sql')
  if ($LASTEXITCODE -ne 0) { throw 'local movement assertions failed' }

  # Race two authenticated issues against the final single unit. Both sessions
  # start together; exactly one may commit under the per-product transaction lock.
  & $psql @psqlArgs -c "UPDATE hasad.stock_levels SET qty = 1 WHERE company_id = '20000000-0000-0000-0000-000000000002' AND product_id = '60000000-0000-0000-0000-000000000002' AND warehouse_id = '70000000-0000-0000-0000-000000000003';"
  if ($LASTEXITCODE -ne 0) { throw 'concurrency fixture preparation failed' }
  $issueA = Join-Path $pgRoot 'concurrent-issue-a.sql'
  $issueB = Join-Path $pgRoot 'concurrent-issue-b.sql'
  @"
SET ROLE authenticated;
SELECT set_config('request.jwt.claims', '{"sub":"10000000-0000-0000-0000-000000000002"}', false);
SELECT (hasad.post_stock_issue('80000000-0000-0000-0000-00000000000b', '20000000-0000-0000-0000-000000000002', '70000000-0000-0000-0000-000000000003', '60000000-0000-0000-0000-000000000002', 1)).id;
"@ | Set-Content -LiteralPath $issueA -Encoding ascii
  @"
SET ROLE authenticated;
SELECT set_config('request.jwt.claims', '{"sub":"10000000-0000-0000-0000-000000000002"}', false);
SELECT (hasad.post_stock_issue('80000000-0000-0000-0000-00000000000c', '20000000-0000-0000-0000-000000000002', '70000000-0000-0000-0000-000000000003', '60000000-0000-0000-0000-000000000002', 1)).id;
"@ | Set-Content -LiteralPath $issueB -Encoding ascii
  $outA = Join-Path $pgRoot 'concurrent-issue-a.out'
  $outB = Join-Path $pgRoot 'concurrent-issue-b.out'
  $errA = Join-Path $pgRoot 'concurrent-issue-a.err'
  $errB = Join-Path $pgRoot 'concurrent-issue-b.err'
  $argsA = @('-X','-w','-h','127.0.0.1','-p',"$port",'-U','postgres','-d','postgres','-v','ON_ERROR_STOP=1','-f',$issueA)
  $argsB = @('-X','-w','-h','127.0.0.1','-p',"$port",'-U','postgres','-d','postgres','-v','ON_ERROR_STOP=1','-f',$issueB)
  $procA = Start-Process -FilePath $psql -ArgumentList $argsA -PassThru -WindowStyle Hidden -RedirectStandardOutput $outA -RedirectStandardError $errA
  $procB = Start-Process -FilePath $psql -ArgumentList $argsB -PassThru -WindowStyle Hidden -RedirectStandardOutput $outB -RedirectStandardError $errB
  $procA.WaitForExit()
  $procB.WaitForExit()
  $procA.Refresh()
  $procB.Refresh()
  $textA = (Get-Content -LiteralPath $outA -Raw) + (Get-Content -LiteralPath $errA -Raw)
  $textB = (Get-Content -LiteralPath $outB -Raw) + (Get-Content -LiteralPath $errB -Raw)
  $allOutput = @($textA, $textB)
  $successful = @($allOutput | Where-Object { $_ -match '80000000-0000-0000-0000-00000000000[b-c]' }).Count
  $insufficient = @($allOutput | Where-Object { $_ -match 'STOCK_INSUFFICIENT' }).Count
  if ($successful -ne 1 -or $insufficient -ne 1) {
    throw "concurrent issue result unexpected: committed=$successful insufficient=$insufficient; A=$textA; B=$textB"
  }
  $raceState = (& $psql @psqlArgs -At -c "SELECT qty::text || '|' || (SELECT count(*) FROM hasad.stock_movements WHERE id IN ('80000000-0000-0000-0000-00000000000b','80000000-0000-0000-0000-00000000000c'))::text FROM hasad.stock_levels WHERE company_id='20000000-0000-0000-0000-000000000002' AND product_id='60000000-0000-0000-0000-000000000002' AND warehouse_id='70000000-0000-0000-0000-000000000003'").Trim()
  if ($LASTEXITCODE -ne 0 -or $raceState -notmatch '^0(?:\.0+)?\|1$') { throw "concurrent issue corrupted final stock state: $raceState" }
  Write-Output 'PASS: concurrent last-unit issues allowed exactly one commit'
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
  if ($target.StartsWith((Join-Path $tempRoot 'hasad-inventory-'), [System.StringComparison]::OrdinalIgnoreCase)) {
    Remove-Item -LiteralPath $target -Recurse -Force -ErrorAction SilentlyContinue
  }
}
