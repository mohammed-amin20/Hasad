# End-to-end test of the corrected runner in a DISPOSABLE environment only.
#   * local throwaway PostgreSQL 17 cluster
#   * local mock CLI shim (never contacts Supabase; no network)
#   * synthetic Auth UUIDs, synthetic secret file
# No DEV, no remote writes, no real operator identity.

$ErrorActionPreference = 'Stop'
$root   = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)   # security/candidates
$pgBin  = 'C:\Program Files\PostgreSQL\17\bin'
$psql   = Join-Path $pgBin 'psql.exe'
$runner = Join-Path $root 'run_initial_company_bootstrap_operator.ps1'
$mock   = Join-Path $root 'tests\mock_supabase.cmd'
$setup  = Join-Path $root 'initial_company_bootstrap_harness_setup.sql'
$checks = Join-Path $root 'tests\disposable_bootstrap_assertions.sql'

$pgRoot  = Join-Path $env:LOCALAPPDATA ('Temp\opencode\hasad-runner-e2e-' + [guid]::NewGuid().ToString('N'))
$data    = Join-Path $pgRoot 'data'
$log     = Join-Path $pgRoot 'server.log'
$port    = Get-Random -Minimum 56000 -Maximum 64000
$started = $false
$postgres = $null

$owner  = '00000000-0000-0000-0000-000000000001'
$secret = Join-Path $pgRoot 'owner.uuid'

$failures = New-Object System.Collections.Generic.List[string]
$passes = 0
function Assert-True([bool]$Condition, [string]$Label) {
  if ($Condition) { $script:passes++; Write-Host "PASS: $Label" }
  else { $script:failures.Add($Label); Write-Host "FAIL: $Label" }
}

function Invoke-Psql([string[]]$PsqlArgs) {
  $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
  try {
    $out = & $psql -X -w -h 127.0.0.1 -p $port -U postgres -d postgres -v ON_ERROR_STOP=1 @PsqlArgs 2>&1
    return [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = (($out | Out-String).Trim()) }
  } finally { $ErrorActionPreference = $prev }
}

function Invoke-Runner([string[]]$RunnerArgs) {
  $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
  try {
    $out = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $runner @RunnerArgs 2>&1
    return [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = (($out | Out-String).Trim()) }
  } finally { $ErrorActionPreference = $prev }
}

New-Item -ItemType Directory -Path $pgRoot -Force | Out-Null
try {
  & (Join-Path $pgBin 'initdb.exe') -D $data -U postgres -A trust --no-locale | Out-Null
  if ($LASTEXITCODE -ne 0) { throw 'DISPOSABLE_INITDB_FAILED' }

  $postgres = Start-Process -FilePath (Join-Path $pgBin 'postgres.exe') `
    -ArgumentList @('-D', $data, '-p', "$port", '-h', '127.0.0.1') `
    -RedirectStandardError $log -PassThru
  $ready = $false
  foreach ($attempt in 1..60) {
    try { $probe = [Net.Sockets.TcpClient]::new('127.0.0.1', $port); $probe.Dispose(); $ready = $true; break }
    catch { Start-Sleep -Milliseconds 250 }
  }
  if (-not $ready) { throw 'DISPOSABLE_POSTGRES_START_FAILED' }
  $started = $true

  $setupResult = Invoke-Psql @('-f', $setup)
  if ($setupResult.ExitCode -ne 0) { throw ('HARNESS_SETUP_FAILED: ' + $setupResult.Output) }

  $env:HASAD_TEST_PGPORT = "$port"
  $env:HASAD_MOCK_DB_MODE = $null
  [IO.File]::WriteAllText($secret, $owner, [Text.UTF8Encoding]::new($false))

  # --- Case 1: CLI exits 0 but returns no payload (the reported incident) ---
  $env:HASAD_MOCK_DB_MODE = 'empty'
  $case1 = Invoke-Runner @('-PreflightOnly', '-OwnerSecretFile', $secret, '-TestCliPath', $mock)
  Assert-True ($case1.ExitCode -ne 0) 'empty CLI payload fails the run instead of crashing'
  Assert-True ($case1.Output -match 'PREFLIGHT_PAYLOAD_MISSING') 'empty CLI payload raises a specific diagnostic code'
  Assert-True ($case1.Output -notmatch 'Cannot index into a null array') 'no raw null-array indexing error surfaces'
  Assert-True (Test-Path -LiteralPath $secret) 'failed preflight keeps the secret file for a clean retry'
  $count = Invoke-Psql @('-t', '-A', '-c', 'SELECT count(*) FROM hasad.companies;')
  Assert-True ($count.Output -eq '0') 'failed preflight wrote nothing'

  # --- Case 2: read-only preflight passes ---
  $env:HASAD_MOCK_DB_MODE = $null
  $case2 = Invoke-Runner @('-PreflightOnly', '-OwnerSecretFile', $secret, '-TestCliPath', $mock)
  Assert-True ($case2.ExitCode -eq 0) 'preflight passes against the disposable cluster'
  if ($case2.ExitCode -ne 0) { Write-Host '--- case2 output ---'; Write-Host $case2.Output }
  Assert-True ($case2.Output -match 'all read-only preflight guards satisfied') 'preflight reports every guard satisfied'
  Assert-True ($case2.Output -match 'PREFLIGHT ONLY: no write performed') 'preflight performs no write'
  $count = Invoke-Psql @('-t', '-A', '-c', 'SELECT count(*) FROM hasad.companies;')
  Assert-True ($count.Output -eq '0') 'preflight left the cluster untouched'
  Assert-True ($case2.Output -notmatch [regex]::Escape($owner)) 'owner UUID never appears in runner output'

  # --- Case 3: the single approved write on the disposable cluster ---
  $case3 = Invoke-Runner @('-Execute', '-Confirm', 'CONFIRM', '-OwnerSecretFile', $secret, '-TestCliPath', $mock)
  Assert-True ($case3.ExitCode -eq 0) 'execute completes on the disposable cluster'
  Assert-True ($case3.Output -match 'Bootstrap exit code: 0') 'write reports exit code 0'
  Assert-True ($case3.Output -match 'selected_owner_membership') 'post-write verification payload is present'
  Assert-True ($case3.Output -notmatch [regex]::Escape($owner)) 'owner UUID never appears in execute output'
  Assert-True (-not (Test-Path -LiteralPath $secret)) 'secret file deleted after the write attempt'

  $verify = Invoke-Psql @('-f', $checks)
  Assert-True ($verify.ExitCode -eq 0) 'six-record bootstrap assertions pass'
  if ($verify.ExitCode -ne 0) { Write-Host $verify.Output }

  # --- Case 4: duplicate bootstrap must be refused without new rows ---
  [IO.File]::WriteAllText($secret, $owner, [Text.UTF8Encoding]::new($false))
  $case4 = Invoke-Runner @('-Execute', '-Confirm', 'CONFIRM', '-OwnerSecretFile', $secret, '-TestCliPath', $mock)
  Assert-True ($case4.ExitCode -ne 0) 'duplicate bootstrap is refused'
  Assert-True ($case4.Output -match 'PREFLIGHT_BLOCKED') 'duplicate bootstrap reports a preflight block'
  Assert-True ($case4.Output -notmatch 'Bootstrap exit code') 'duplicate bootstrap never reaches the write'
  Assert-True (Test-Path -LiteralPath $secret) 'refused execution keeps the secret file'
  $verify2 = Invoke-Psql @('-f', $checks)
  Assert-True ($verify2.ExitCode -eq 0) 'row counts unchanged after the refused duplicate'
  if ($verify2.ExitCode -ne 0) { Write-Host $verify2.Output }

  # --- Case 5: execution gate and template guards ---
  $case5 = Invoke-Runner @('-Execute', '-OwnerSecretFile', $secret, '-TestCliPath', $mock)
  Assert-True ($case5.ExitCode -ne 0 -and $case5.Output -match 'EXPLICIT_CONFIRMATION_REQUIRED') 'execute without confirmation is refused'
  $case6 = Invoke-Runner @('-Execute', '-Confirm', 'yes', '-OwnerSecretFile', $secret, '-TestCliPath', $mock)
  Assert-True ($case6.ExitCode -ne 0 -and $case6.Output -match 'EXPLICIT_CONFIRMATION_REQUIRED') 'wrong confirmation token is refused'
  $review = Invoke-Runner @()
  Assert-True ($review.ExitCode -eq 0 -and $review.Output -match 'REVIEW ONLY') 'default mode stays review-only'
}
finally {
  if ($started -and $null -ne $postgres -and -not $postgres.HasExited) {
    Stop-Process -Id $postgres.Id -Force -ErrorAction SilentlyContinue
    $postgres.WaitForExit()
  }
  $env:HASAD_TEST_PGPORT = $null
  $env:HASAD_MOCK_DB_MODE = $null
  $tempRoot = [IO.Path]::GetFullPath((Join-Path $env:LOCALAPPDATA 'Temp\opencode')).TrimEnd('\') + '\'
  $target = [IO.Path]::GetFullPath($pgRoot)
  if ($target.StartsWith($tempRoot + 'hasad-runner-e2e-', [StringComparison]::OrdinalIgnoreCase)) {
    Remove-Item -LiteralPath $target -Recurse -Force -ErrorAction SilentlyContinue
  }
}

Write-Host ''
Write-Host ("RESULT: {0} passed, {1} failed" -f $passes, $failures.Count)
if ($failures.Count -gt 0) {
  $failures | ForEach-Object { Write-Host ("FAILED: {0}" -f $_) }
  exit 1
}
exit 0
