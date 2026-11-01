# Local-only mock of the Supabase CLI used by the disposable runner test.
# It never contacts Supabase: `db query --file` is executed by a local psql
# against a throwaway PostgreSQL 17 cluster identified by HASAD_TEST_PGPORT.

$ErrorActionPreference = 'Stop'
$argv = @($args)

if ($argv.Count -eq 0) { exit 64 }

switch ($argv[0]) {
  'projects' {
    '{"projects":[{"id":"sxasnunzspkuwbxiddqd","ref":"sxasnunzspkuwbxiddqd","name":"Hasad-erp-dev","linked":true}],"message":""}'
    exit 0
  }
  'db' {
    if ($env:HASAD_MOCK_DB_MODE -eq 'empty') {
      # Simulates a successful exit with an empty payload: the exact condition
      # that previously produced "Cannot index into a null array".
      exit 0
    }
    $file = $null
    for ($i = 0; $i -lt $argv.Count; $i++) {
      if ($argv[$i] -eq '--file') { $file = $argv[$i + 1] }
    }
    if (-not $file -or -not (Test-Path -LiteralPath $file)) {
      '{"_tag":"Error","error":{"code":"MockMissingFile","message":"no --file supplied"}}'
      exit 1
    }
    $psql = Join-Path 'C:\Program Files\PostgreSQL\17\bin' 'psql.exe'
    $out = & $psql -X -w -h 127.0.0.1 -p $env:HASAD_TEST_PGPORT -U postgres -d postgres `
      -v ON_ERROR_STOP=1 -t -A -f $file 2>&1
    $code = $LASTEXITCODE
    $payload = ($out | Out-String).Trim()
    (@{ rows = @(@{ payload = $payload }); message = '' } | ConvertTo-Json -Depth 4 -Compress)
    exit $code
  }
  default { exit 64 }
}
