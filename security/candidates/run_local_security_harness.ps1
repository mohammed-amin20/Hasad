$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$pgBin = 'C:\Program Files\PostgreSQL\17\bin'
$psql = Join-Path $pgBin 'psql.exe'
$pgRoot = Join-Path $env:TEMP ('hasad-security-' + [guid]::NewGuid().ToString('N'))
$data = Join-Path $pgRoot 'data'
$log = Join-Path $pgRoot 'server.log'
$port = Get-Random -Minimum 56000 -Maximum 64000
$started = $false
New-Item -ItemType Directory -Path $pgRoot | Out-Null
try {
  & (Join-Path $pgBin 'initdb.exe') -D $data -U postgres -A trust --no-locale
  if ($LASTEXITCODE -ne 0) { throw 'initdb failed' }
  & (Join-Path $pgBin 'pg_ctl.exe') -D $data -l $log -o "-p $port -h 127.0.0.1" -w start
  if ($LASTEXITCODE -ne 0) { throw 'local disposable PostgreSQL failed to start' }
  $started = $true

  Write-Host 'HARNESS: creating restricted roles and fixtures'
  & $psql -X -w -h 127.0.0.1 -p $port -U postgres -d postgres -v ON_ERROR_STOP=1 -f (Join-Path $root 'local_security_harness.sql')
  if ($LASTEXITCODE -ne 0) { throw 'harness schema/setup failed' }

  $invokerOutput = & $psql -X -w -h 127.0.0.1 -p $port -U postgres -d postgres -v ON_ERROR_STOP=1 -c 'SET ROLE authenticated; SELECT hasad_api.invoker_probe();' 2>&1
  if ($LASTEXITCODE -eq 0 -or ($invokerOutput -join "`n") -notmatch 'permission denied for (schema hasad|table companies)') {
    throw "SECURITY INVOKER privilege conflict was not reproduced: $($invokerOutput -join ' ')"
  }
  Write-Host 'PASS: SECURITY INVOKER privilege conflict reproduced'

  Write-Host 'HARNESS: loading review-only SECURITY DEFINER candidate'
  & $psql -X -w -h 127.0.0.1 -p $port -U postgres -d postgres -v ON_ERROR_STOP=1 -f (Join-Path $root '20261030000100_v2_candidate_hasad_api_company_product_read_v2.sql')
  if ($LASTEXITCODE -ne 0) { throw 'review candidate did not load' }
  & $psql -X -w -h 127.0.0.1 -p $port -U postgres -d postgres -v ON_ERROR_STOP=1 -c 'GRANT EXECUTE ON FUNCTION hasad_api.whoami(), hasad_api.products_list() TO authenticated;'
  if ($LASTEXITCODE -ne 0) { throw 'could not grant local test execution to authenticated' }

  Write-Host 'HARNESS: running positive and negative security assertions'
  & $psql -X -w -h 127.0.0.1 -p $port -U postgres -d postgres -v ON_ERROR_STOP=1 -f (Join-Path $root 'local_security_tests.sql')
  if ($LASTEXITCODE -ne 0) { throw 'security assertions failed' }
  Write-Host 'PASS: all local PostgreSQL security assertions completed'
}
finally {
  if ($started) {
    & (Join-Path $pgBin 'pg_ctl.exe') -D $data -m immediate -t 10 -w stop
  }
  $tempRoot = [System.IO.Path]::GetFullPath($env:TEMP)
  $target = [System.IO.Path]::GetFullPath($pgRoot)
  if ($target.StartsWith((Join-Path $tempRoot 'hasad-security-'), [System.StringComparison]::OrdinalIgnoreCase)) {
    Remove-Item -LiteralPath $target -Recurse -Force -ErrorAction SilentlyContinue
  }
}
