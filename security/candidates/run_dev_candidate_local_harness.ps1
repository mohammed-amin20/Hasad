$ErrorActionPreference='Stop'
$root=Split-Path -Parent $MyInvocation.MyCommand.Path
$repo=Split-Path -Parent (Split-Path -Parent $root)
$pgBin='C:\Program Files\PostgreSQL\17\bin'
$psql=Join-Path $pgBin 'psql.exe'
$pgRoot=Join-Path $env:TEMP ('hasad-dev-candidate-' + [guid]::NewGuid().ToString('N'))
$data=Join-Path $pgRoot 'data'; $log=Join-Path $pgRoot 'server.log'
$port=Get-Random -Minimum 56000 -Maximum 64000; $started=$false
$candidate=Join-Path $root 'dev_company_product_access_candidate.sql'
New-Item -ItemType Directory -Path $pgRoot | Out-Null
try {
  & (Join-Path $pgBin 'initdb.exe') -D $data -U postgres -A trust --no-locale | Out-Null
  if($LASTEXITCODE -ne 0){throw 'DISPOSABLE_INITDB_FAILED'}
  & (Join-Path $pgBin 'pg_ctl.exe') -D $data -l $log -o "-p $port -h 127.0.0.1" -w start | Out-Null
  if($LASTEXITCODE -ne 0){throw 'DISPOSABLE_POSTGRES_START_FAILED'}
  $started=$true
  $base=@('-X','-w','-h','127.0.0.1','-p',"$port",'-U','postgres','-d','postgres','-v','ON_ERROR_STOP=1')
  & $psql @base -f (Join-Path $root 'dev_candidate_harness_setup.sql') | Out-Null
  if($LASTEXITCODE -ne 0){throw 'HARNESS_SCHEMA_SETUP_FAILED'}
  $invoker=& $psql @base -c 'SET ROLE authenticated; SELECT hasad_api.invoker_probe();' 2>&1
  if($LASTEXITCODE -eq 0 -or ($invoker -join "`n") -notmatch 'permission denied for (schema hasad|table companies)') {throw 'INVOKER_CONFLICT_NOT_REPRODUCED'}
  Write-Host 'PASS: SECURITY INVOKER privilege conflict reproduced with authenticated role'
  & $psql @base -c 'DROP FUNCTION hasad_api.invoker_probe();' | Out-Null
  if($LASTEXITCODE -ne 0){throw 'INVOKER_PROBE_CLEANUP_FAILED'}
  & $psql @base -f $candidate | Out-Null
  if($LASTEXITCODE -ne 0){throw 'EXACT_DEV_CANDIDATE_FAILED_TO_APPLY_LOCALLY'}
  Write-Host 'PASS: exact dev_company_product_access_candidate.sql applied to disposable PostgreSQL'
  & $psql @base -f (Join-Path $root 'dev_candidate_harness_fixtures.sql') | Out-Null
  if($LASTEXITCODE -ne 0){throw 'SYNTHETIC_LOCAL_FIXTURES_FAILED'}
  & $psql @base -f (Join-Path $root 'dev_candidate_security_assertions.sql')
  if($LASTEXITCODE -ne 0){throw 'CANDIDATE_SECURITY_ASSERTIONS_FAILED'}
  Write-Host 'PASS: exact candidate positive and negative PostgreSQL security checks'
}
finally {
  if($started){& (Join-Path $pgBin 'pg_ctl.exe') -D $data -m immediate -t 10 -w stop | Out-Null}
  $tempRoot=[IO.Path]::GetFullPath($env:TEMP).TrimEnd('\')+'\'
  $target=[IO.Path]::GetFullPath($pgRoot)
  if($target.StartsWith($tempRoot+'hasad-dev-candidate-', [StringComparison]::OrdinalIgnoreCase)){
    Remove-Item -LiteralPath $target -Recurse -Force -ErrorAction SilentlyContinue
  }
}
