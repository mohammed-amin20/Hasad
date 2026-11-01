$ErrorActionPreference = 'Stop'
$testsRoot = $PSScriptRoot
$candidateRoot = Split-Path -Parent $testsRoot
$verifier = Join-Path $candidateRoot 'verify_dev_rpc_auth_privileges_readonly.ps1'
$sqlPath = Join-Path $candidateRoot 'verify_dev_rpc_auth_privileges_readonly.sql'
$mockCli = Join-Path $testsRoot 'mock_rpc_privilege_cli.cmd'
$powershell = (Get-Command powershell.exe -ErrorAction Stop).Source
$temp = Join-Path ([IO.Path]::GetTempPath()) ('hasad-rpc-verifier-test-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $temp -Force | Out-Null
$capturePath = Join-Path $temp 'captured-arguments.json'
$script:passes = 0
$script:failures = New-Object System.Collections.Generic.List[string]

function Assert-True([bool]$condition, [string]$label) {
  if ($condition) { $script:passes++; Write-Host "PASS: $label" }
  else { $script:failures.Add($label); Write-Host "FAIL: $label" }
}

function Invoke-Verifier([string]$mode) {
  $env:HASAD_RPC_VERIFY_CAPTURE = $capturePath
  $env:HASAD_RPC_VERIFY_MOCK_MODE = $mode
  $previous = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  try {
    $output = @(& $powershell -NoProfile -ExecutionPolicy Bypass -File $verifier -TestCliPath $mockCli 2>&1)
    [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = ($output | Out-String) }
  } finally { $ErrorActionPreference = $previous }
}

try {
  $sql = Get-Content -LiteralPath $sqlPath -Raw
  Assert-True (-not [string]::IsNullOrWhiteSpace($sql)) 'SQL payload is nonempty'
  Assert-True ($sql -match '^\s*--[^\r\n]*\r?\n\s*SELECT\b' -and $sql.TrimEnd().EndsWith(';')) 'SQL payload is a complete SELECT ending in semicolon'
  Assert-True ($sql.Contains("has_function_privilege('hasad_rpc_owner', 'auth.uid()', 'EXECUTE')")) 'quoted auth.uid privilege expression remains intact'
  Assert-True ($sql -notmatch '(?im)^\s*(GRANT|REVOKE|CREATE|ALTER|DROP|INSERT|UPDATE|DELETE|TRUNCATE|CALL|DO)\b') 'SQL payload contains no write or DDL statement'

  Remove-Item -LiteralPath $capturePath -Force -ErrorAction SilentlyContinue
  $success = Invoke-Verifier 'success'
  Assert-True ($success.ExitCode -eq 0) 'mock CLI success parses and returns catalog result'
  $captured = Get-Content -LiteralPath $capturePath -Raw | ConvertFrom-Json
  $expected = @('--agent','yes','db','query','--linked','--project-ref','sxasnunzspkuwbxiddqd','--file',$sqlPath,'--output-format','json')
  Assert-True (@($captured.arguments).Count -eq $expected.Count -and
    -not (Compare-Object -ReferenceObject $expected -DifferenceObject @($captured.arguments))) 'CLI receives exactly the expected argument vector'
  $bytes = [IO.File]::ReadAllBytes($sqlPath)
  $sha = [Security.Cryptography.SHA256]::Create()
  try { $expectedHash = ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '') }
  finally { $sha.Dispose() }
  Assert-True ($captured.sql_length_bytes -eq $bytes.Length -and $captured.sql_sha256 -eq $expectedHash -and $captured.sql_complete) 'CLI opens the exact complete SQL file without printing or capturing its text'
  Assert-True ($success.Output -match 'rpc_owner_auth_uid_execute' -and $success.Output -match '"total"\s*:\s*47' -and
    $success.Output -match 'whoami' -and $success.Output -match 'products_list' -and
    $success.Output -notmatch 'boundary|warning|fixture_table') 'observed object envelope yields concise sanitized summary'

  $missing = Invoke-Verifier 'missing_rows'
  Assert-True ($missing.ExitCode -ne 0 -and $missing.Output -match 'UNSUPPORTED_CLI_JSON_STRUCTURE') 'missing-rows object triggers structure-only diagnostic'
  Assert-True ($missing.Output -match '"top_level_type"\s*:\s*"object"' -and $missing.Output -match '"property_names"' -and $missing.Output -match '"data"') 'diagnostic reports top-level type and property names without values'
  Assert-True ($missing.Output -notmatch 'MOCK_PRIVATE_DETAIL|rpc_owner_auth_schema_usage.*false|rpc_owner_auth_uid_execute.*true') 'structure diagnostic contains no JSON values'

  $cliError = Invoke-Verifier 'error'
  Assert-True ($cliError.ExitCode -ne 0 -and $cliError.Output -match 'CLI_ERROR_ENVELOPE') 'CLI error envelope is rejected'
  Assert-True ($cliError.Output -notmatch 'MOCK_PRIVATE_DETAIL|MockError') 'CLI error details remain hidden'

  $incomplete = Invoke-Verifier 'incomplete'
  Assert-True ($incomplete.ExitCode -ne 0 -and $incomplete.Output -match 'RESULT_INCOMPLETE') 'incomplete privilege result fails closed'

  $sqlstateFailure = Invoke-Verifier 'sqlstate_42501'
  Assert-True ($sqlstateFailure.ExitCode -ne 0 -and $sqlstateFailure.Output -match 'SQLSTATE=42501;CATEGORY=POSTGRES_PRIVILEGE_DENIED') 'CLI error reports sanitized SQLSTATE and safe category'
  Assert-True ($sqlstateFailure.Output -notmatch 'MOCK_PRIVATE_DETAIL|permission denied') 'CLI failure diagnostic omits raw message details'

  foreach ($mode in @('unexpected_rpc','short_rls')) {
    $invalidCatalog = Invoke-Verifier $mode
    Assert-True ($invalidCatalog.ExitCode -ne 0) "$mode catalog fails closed"
  }

  $mixed = Invoke-Verifier 'mixed'
  Assert-True ($mixed.ExitCode -eq 0 -and $mixed.Output -match 'rpc_owner_auth_uid_execute') 'stderr notice does not corrupt successful JSON on stdout'
  Assert-True ($mixed.Output -notmatch 'Mock initialization notice') 'stderr notice is not printed with parsed result'

  foreach ($mode in @('empty','malformed','nonzero')) {
    $bad = Invoke-Verifier $mode
    Assert-True ($bad.ExitCode -ne 0) "$mode CLI output fails closed"
    Assert-True ($bad.Output -match 'RPC_PRIVILEGE_VERIFY_FAILED' -and $bad.Output -notmatch 'not-json|SELECT|auth.uid') "$mode failure is sanitized"
  }
} finally {
  Remove-Item Env:\HASAD_RPC_VERIFY_CAPTURE -ErrorAction SilentlyContinue
  Remove-Item Env:\HASAD_RPC_VERIFY_MOCK_MODE -ErrorAction SilentlyContinue
  Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host ("RESULT: {0} passed, {1} failed" -f $script:passes, $script:failures.Count)
if ($script:failures.Count -gt 0) { exit 1 }
exit 0
