# Hasad ERP V2 C1/C2 local disposable PoC runner
# Target: disposable local PostgreSQL cluster only. Never connects to DEV.
#
# This runner:
#   1. creates a fresh local PostgreSQL cluster with trust auth on 127.0.0.1;
#   2. applies the Supabase auth/role stub and the four deployed migrations;
#   3. runs the read-only default-deny baseline;
#   4. installs the test-only RPC surface and fixtures;
#   5. runs the C1/C2 permission, tenancy, privilege and SECURITY DEFINER matrix;
#   6. writes a pass/fail evidence log under local_audit/;
#   7. stops and removes the disposable cluster.
#
# It does not read, write, or connect to the DEV project.

[CmdletBinding()]
param(
  [int]$Port = 55432,
  [string]$PgBin = 'C:\Program Files\PostgreSQL\17\bin'
)

$ErrorActionPreference = 'Continue'
$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$data = Join-Path $env:TEMP "opencode\hasad_poc_run_$stamp"
$auditDir = Join-Path $repo 'local_audit'
$log = Join-Path $auditDir "C1_C2_LOCAL_POC_$stamp.log"
$pre = Join-Path $PSScriptRoot 'poc_c1_c2_local_pre.sql'
$setup = Join-Path $PSScriptRoot 'poc_c1_c2_local_setup.sql'
$assertions = Join-Path $PSScriptRoot 'poc_c1_c2_local_assertions.sql'
$baseline = Join-Path $PSScriptRoot 'poc_c1_c2_default_deny.sql'
$migrations = @(
  '20261026000000_v2_foundation_schemas.sql',
  '20261026000100_v2_identity_tenancy_foundation.sql',
  '20261026000200_v2_permissions_foundation.sql',
  '20261026000210_v2_permission_catalogue_seed.sql'
)

New-Item -ItemType Directory -Force -Path $auditDir | Out-Null
Set-Content -LiteralPath $log -Value '' -NoNewline

function Log([string]$Message) {
  $line = "[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
  Write-Output $line
  Add-Content -LiteralPath $log -Value $line
}

function Invoke-PsqlFile([string]$File, [string[]]$Extra = @()) {
  $args = @(
    '-X', '-h', '127.0.0.1', '-p', "$Port", '-U', 'postgres',
    '-d', 'hasad_poc_c1_c2', '-v', 'ON_ERROR_STOP=1', '-f', $File
  ) + $Extra
  $out = & (Join-Path $PgBin 'psql.exe') @args 2>&1 | Out-String
  $code = $LASTEXITCODE
  Add-Content -LiteralPath $log -Value ("`n--- psql -f {0} (exit {1}) ---`n{2}" -f $File, $code, $out)
  if ($code -ne 0) {
    throw "psql failed for $File (exit $code)`n$out"
  }
  return $out
}

$script:passed = 0
$script:failed = 0
$script:results = @()

function Invoke-Case(
  [string]$Name,
  [string]$Sql,
  [bool]$ShouldSucceed,
  [string]$Contains = '',
  [string]$Equals = ''
) {
  $out = [string]((& (Join-Path $PgBin 'psql.exe') -X -h 127.0.0.1 -p $Port -U postgres `
    -d hasad_poc_c1_c2 -v ON_ERROR_STOP=1 -At -c $Sql 2>&1 | Out-String))
  $code = $LASTEXITCODE
  $ok = if ($ShouldSucceed) { $code -eq 0 } else { $code -ne 0 }
  $flatOutput = $out -replace "[\r\n]+", ' '
  if ($ok -and $Contains -ne '') {
    $ok = $flatOutput.Contains($Contains)
  }
  if ($ok -and $Equals -ne '') {
    # psql emits command tags (for example, SET) before scalar query output.
    # Assert that the expected scalar appears as a complete output line.
    $ok = $out -match ("(?m)^" + [regex]::Escape($Equals) + "\s*$")
  }
  if ($ok) { $script:passed++ } else { $script:failed++ }
  $status = if ($ok) { 'PASS' } else { 'FAIL' }
  $script:results += [pscustomobject]@{
    Case = $Name
    Status = $status
    Exit = $code
    Output = $out.Trim()
  }
  Log ("{0} | {1} | exit={2} | {3}" -f $status, $Name, $code, ($out.Trim() -replace "`r?`n", ' / '))
}

function SqlAs([string]$UserId, [string]$Body) {
  # Construct JSON in PostgreSQL rather than passing JSON double quotes through
  # PowerShell's native-command quoting layer.
  return "SELECT set_config('request.jwt.claims', jsonb_build_object('sub', '$UserId')::text, false); SET ROLE authenticated; $Body"
}

function SqlAnon([string]$Body) {
  return "SELECT set_config('request.jwt.claims', '', false); SET ROLE anon; $Body"
}

$A = '10000000-0000-0000-0000-000000000001'
$B = '20000000-0000-0000-0000-000000000001'
$ownerA = '00000000-0000-0000-0000-000000000001'
$memberA = '00000000-0000-0000-0000-000000000002'
$suspendedA = '00000000-0000-0000-0000-000000000003'
$revokedA = '00000000-0000-0000-0000-000000000004'
$adminA = '00000000-0000-0000-0000-000000000005'
$salesA = '00000000-0000-0000-0000-000000000006'
$warehouseA = '00000000-0000-0000-0000-000000000007'
$ownerB = '00000000-0000-0000-0000-000000000008'

$pgProc = $null

try {
  Log "POC_DATA=$data"
  Log "POC_LOG=$log"
  Log "POC_TARGET=local disposable PostgreSQL, no DEV connection"

  # initdb requires the target directory to be absent or empty. Keep its
  # redirected output outside that directory so redirection cannot make it
  # non-empty before initdb begins.
  $initOut = Join-Path $env:TEMP "opencode\hasad_poc_init_$stamp.out"
  $initErr = Join-Path $env:TEMP "opencode\hasad_poc_init_$stamp.err"
  $init = Start-Process -FilePath (Join-Path $PgBin 'initdb.exe') `
    -ArgumentList @('-D', $data, '-A', 'trust', '-U', 'postgres', '--encoding=UTF8', '--locale=C') `
    -NoNewWindow -Wait -PassThru -RedirectStandardOutput $initOut -RedirectStandardError $initErr
  if ($init.ExitCode -ne 0) {
    throw "initdb failed (exit $($init.ExitCode)): $(Get-Content -Raw $initErr)"
  }
  Log "initdb completed"

  $pgOut = Join-Path $data 'postgres.stdout.log'
  $pgErr = Join-Path $data 'postgres.stderr.log'
  $pgProc = Start-Process -FilePath (Join-Path $PgBin 'postgres.exe') `
    -ArgumentList @('-D', $data, '-p', "$Port", '-c', 'listen_addresses=127.0.0.1', '-c', 'logging_collector=off') `
    -NoNewWindow -PassThru -RedirectStandardOutput $pgOut -RedirectStandardError $pgErr
  Log "postgres pid=$($pgProc.Id) port=$Port"

  $ready = $false
  for ($i = 0; $i -lt 40; $i++) {
    & (Join-Path $PgBin 'pg_isready.exe') -h 127.0.0.1 -p $Port -U postgres -d postgres *> $null
    if ($LASTEXITCODE -eq 0) { $ready = $true; break }
    Start-Sleep -Milliseconds 500
  }
  if (-not $ready) {
    throw "local PostgreSQL did not become ready on port $Port"
  }
  Log "local PostgreSQL ready"

  $create = & (Join-Path $PgBin 'createdb.exe') -h 127.0.0.1 -p $Port -U postgres hasad_poc_c1_c2 2>&1 | Out-String
  if ($LASTEXITCODE -ne 0) { throw "createdb failed: $create" }
  Log "database hasad_poc_c1_c2 created"

  Invoke-PsqlFile $pre | Out-Null
  Log "Supabase auth/role stub applied"

  foreach ($m in $migrations) {
    $path = Join-Path $repo "supabase\migrations\$m"
    Invoke-PsqlFile $path | Out-Null
    Log "migration applied: $m"
  }

  $baselineOut = Invoke-PsqlFile $baseline @('-v', 'poc_project_ref=localtestpocabcdefgh')
  if ($baselineOut -notmatch 'PASS: default-deny baseline') {
    throw "default-deny baseline did not report PASS`n$baselineOut"
  }
  Log "default-deny baseline PASS"

  Invoke-PsqlFile $setup | Out-Null
  Log "test-only RPC surface and fixtures applied"

  Invoke-PsqlFile $assertions | Out-Null
  Log "structural assertions PASS"

  $cases = @(
    @{ Name = 'anon denied on RPC'; Sql = (SqlAnon 'SELECT hasad_api.poc_get_my_company();'); Success = $false; Contains = 'permission denied' },
    @{ Name = 'anon denied on direct table read'; Sql = (SqlAnon 'SELECT count(*) FROM hasad.companies;'); Success = $false; Contains = 'permission denied' },

    @{ Name = 'owner A reads own company via auth.uid()'; Sql = (SqlAs $ownerA 'SELECT hasad_api.poc_get_my_company();'); Success = $true; Contains = $A },
    @{ Name = 'member A reads own company via explicit id'; Sql = (SqlAs $memberA "SELECT hasad_api.poc_get_company('$A');"); Success = $true; Contains = $A },
    @{ Name = 'member A cannot read company B'; Sql = (SqlAs $memberA "SELECT hasad_api.poc_get_company('$B');"); Success = $false; Contains = 'DENIED' },
    @{ Name = 'owner A cannot read company B'; Sql = (SqlAs $ownerA "SELECT hasad_api.poc_get_company('$B');"); Success = $false; Contains = 'DENIED' },
    @{ Name = 'owner B reads only company B'; Sql = (SqlAs $ownerB 'SELECT hasad_api.poc_get_my_company();'); Success = $true; Contains = $B },
    @{ Name = 'suspended member denied'; Sql = (SqlAs $suspendedA 'SELECT hasad_api.poc_get_my_company();'); Success = $false; Contains = 'NO_ACTIVE_MEMBERSHIP' },
    @{ Name = 'revoked member denied'; Sql = (SqlAs $revokedA 'SELECT hasad_api.poc_get_my_company();'); Success = $false; Contains = 'NO_ACTIVE_MEMBERSHIP' },

    @{ Name = 'authenticated direct table read denied'; Sql = (SqlAs $ownerA 'SELECT count(*) FROM hasad.companies;'); Success = $false; Contains = 'permission denied' },
    @{ Name = 'authenticated direct table write denied'; Sql = (SqlAs $ownerA "INSERT INTO hasad.companies (id, created_by) VALUES ('30000000-0000-0000-0000-000000000001', '$ownerA');"); Success = $false; Contains = 'permission denied' },

    @{ Name = 'owner allow survives deny override'; Sql = (SqlAs $ownerA "SELECT hasad_api.poc_has_permission('$A','journals.post');"); Success = $true; Equals = 't' },
    @{ Name = 'deny override beats role grant'; Sql = (SqlAs $memberA "SELECT hasad_api.poc_has_permission('$A','journals.post');"); Success = $true; Equals = 'f' },
    @{ Name = 'allow override grants non-role code'; Sql = (SqlAs $memberA "SELECT hasad_api.poc_has_permission('$A','reports.export');"); Success = $true; Equals = 't' },
    @{ Name = 'default deny'; Sql = (SqlAs $memberA "SELECT hasad_api.poc_has_permission('$A','payroll.run');"); Success = $true; Equals = 'f' },
    @{ Name = 'fiscal.close admin allow override rejected'; Sql = (SqlAs $adminA "SELECT hasad_api.poc_has_permission('$A','fiscal.close');"); Success = $true; Equals = 'f' },
    @{ Name = 'fiscal.close owner allowed'; Sql = (SqlAs $ownerA "SELECT hasad_api.poc_has_permission('$A','fiscal.close');"); Success = $true; Equals = 't' },
    @{ Name = 'inventory.adjust admin role allowed'; Sql = (SqlAs $adminA "SELECT hasad_api.poc_has_permission('$A','inventory.adjust');"); Success = $true; Equals = 't' },
    @{ Name = 'inventory.adjust warehouse allow override rejected'; Sql = (SqlAs $warehouseA "SELECT hasad_api.poc_has_permission('$A','inventory.adjust');"); Success = $true; Equals = 'f' },
    @{ Name = 'cash.post sales allow override rejected'; Sql = (SqlAs $salesA "SELECT hasad_api.poc_has_permission('$A','cash.post');"); Success = $true; Equals = 'f' },
    @{ Name = 'inventory.adjust owner allowed'; Sql = (SqlAs $ownerA "SELECT hasad_api.poc_has_permission('$A','inventory.adjust');"); Success = $true; Equals = 't' },
    @{ Name = 'suspended permission denied'; Sql = (SqlAs $suspendedA "SELECT hasad_api.poc_has_permission('$A','journals.post');"); Success = $true; Equals = 'f' },
    @{ Name = 'revoked permission denied'; Sql = (SqlAs $revokedA "SELECT hasad_api.poc_has_permission('$A','journals.post');"); Success = $true; Equals = 'f' },
    @{ Name = 'cross-company permission denied'; Sql = (SqlAs $memberA "SELECT hasad_api.poc_has_permission('$B','reports.view');"); Success = $true; Equals = 'f' },

    @{ Name = 'owner writes note in own company'; Sql = (SqlAs $ownerA "SELECT hasad_api.poc_add_note('$A','owner note');"); Success = $true },
    @{ Name = 'accountant cannot write note without company.settings'; Sql = (SqlAs $memberA "SELECT hasad_api.poc_add_note('$A','member note');"); Success = $false; Contains = 'DENIED' },
    @{ Name = 'owner A cannot write note in company B'; Sql = (SqlAs $ownerA "SELECT hasad_api.poc_add_note('$B','cross tenant');"); Success = $false; Contains = 'DENIED' },

    @{ Name = 'owner writes audit event in own company'; Sql = (SqlAs $ownerA "SELECT hasad_api.poc_audit_write('$A','poc.owner.audit','note',NULL,'{}'::jsonb);"); Success = $true },
    @{ Name = 'active member writes audit event in own company'; Sql = (SqlAs $memberA "SELECT hasad_api.poc_audit_write('$A','poc.member.audit','note',NULL,'{}'::jsonb);"); Success = $true },
    @{ Name = 'member cannot write audit event for company B'; Sql = (SqlAs $memberA "SELECT hasad_api.poc_audit_write('$B','poc.cross.audit','note',NULL,'{}'::jsonb);"); Success = $false; Contains = 'DENIED' },

    @{ Name = 'authenticated direct audit insert denied'; Sql = (SqlAs $ownerA "INSERT INTO poc.audit_log (company_id, actor_user_id, action, entity) VALUES ('$A','$ownerA','forged','note');"); Success = $false; Contains = 'permission denied' },
    @{ Name = 'authenticated direct audit update denied'; Sql = (SqlAs $ownerA "UPDATE poc.audit_log SET action = 'forged';"); Success = $false; Contains = 'permission denied' },
    @{ Name = 'authenticated direct audit delete denied'; Sql = (SqlAs $ownerA 'DELETE FROM poc.audit_log;'); Success = $false; Contains = 'permission denied' },

    @{ Name = 'hostile search_path cannot shadow resolver'; Sql = (SqlAs $memberA "SET search_path = public, pg_catalog; SELECT hasad_api.poc_has_permission('$A','payroll.run');"); Success = $true; Equals = 'f' },

    @{ Name = 'audit actor is derived from auth.uid() for owner'; Sql = "SELECT poc.assert((SELECT count(*) FROM poc.audit_log WHERE company_id = '$A' AND actor_user_id = '$ownerA' AND action = 'poc.owner.audit') = 1, 'owner audit actor');"; Success = $true },
    @{ Name = 'audit actor is derived from auth.uid() for member'; Sql = "SELECT poc.assert((SELECT count(*) FROM poc.audit_log WHERE company_id = '$A' AND actor_user_id = '$memberA' AND action = 'poc.member.audit') = 1, 'member audit actor');"; Success = $true }
  )

  foreach ($c in $cases) {
    $caseSuccess = [bool]$c['Success']
    $caseContains = if ($null -ne $c['Contains']) { [string]$c['Contains'] } else { '' }
    $caseEquals = if ($null -ne $c['Equals']) { [string]$c['Equals'] } else { '' }
    Invoke-Case -Name ([string]$c['Name']) -Sql ([string]$c['Sql']) `
      -ShouldSucceed $caseSuccess -Contains $caseContains -Equals $caseEquals
  }

  Log ("SUMMARY passed={0} failed={1}" -f $script:passed, $script:failed)
  $script:results | Format-Table -AutoSize | Out-String | Add-Content -LiteralPath $log
  $script:results | Format-Table -AutoSize | Out-String | Write-Output

  if ($script:failed -gt 0) {
    throw "C1/C2 local PoC failed: $($script:failed) case(s)"
  }

  Log "C1/C2 local PoC: ALL CASES PASS"
}
catch {
  Log ("FATAL: " + $_.Exception.Message)
  throw
}
finally {
  if ($pgProc -and -not $pgProc.HasExited) {
    & (Join-Path $PgBin 'pg_ctl.exe') -D $data -m fast stop *> $null
    Start-Sleep -Seconds 1
    if (-not $pgProc.HasExited) {
      Stop-Process -Id $pgProc.Id -Force -ErrorAction SilentlyContinue
    }
  }
  if (Test-Path $data) {
    Remove-Item -LiteralPath $data -Recurse -Force -ErrorAction SilentlyContinue
  }
}
