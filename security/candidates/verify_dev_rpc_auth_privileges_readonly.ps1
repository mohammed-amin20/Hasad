[CmdletBinding()]
param([string]$TestCliPath)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$devRef = 'sxasnunzspkuwbxiddqd'
$expectedSqlSha256 = '0F5E4F576FFB69F309A9AA1DA3FA7AF00DE21AED5F037B65D46D6B8466565ED1'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$cli = Join-Path $repoRoot 'node_modules\.bin\supabase.cmd'
$sqlPath = Join-Path $PSScriptRoot 'verify_dev_rpc_auth_privileges_readonly.sql'

if (-not (Test-Path -LiteralPath $cli -PathType Leaf)) {
  throw 'RPC_PRIVILEGE_VERIFY_FAILED:SUPABASE_CLI_MISSING'
}
if (-not (Test-Path -LiteralPath $sqlPath -PathType Leaf)) {
  throw 'RPC_PRIVILEGE_VERIFY_FAILED:SQL_FILE_MISSING'
}
if ((Get-FileHash -LiteralPath $sqlPath -Algorithm SHA256).Hash -cne $expectedSqlSha256) {
  throw 'RPC_PRIVILEGE_VERIFY_FAILED:SQL_HASH_MISMATCH'
}
$linkedRefPath = Join-Path $repoRoot 'supabase\.temp\project-ref'
if (-not (Test-Path -LiteralPath $linkedRefPath -PathType Leaf) -or
    (Get-Content -LiteralPath $linkedRefPath -Raw).Trim() -cne $devRef) {
  throw 'RPC_PRIVILEGE_VERIFY_FAILED:LINKED_PROJECT_MISMATCH'
}

if ($TestCliPath) {
  $testsRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot 'tests')).TrimEnd('\') + '\'
  $testCli = [IO.Path]::GetFullPath($TestCliPath)
  if (-not $testCli.StartsWith($testsRoot, [StringComparison]::OrdinalIgnoreCase) -or
      -not (Test-Path -LiteralPath $testCli -PathType Leaf)) {
    throw 'RPC_PRIVILEGE_VERIFY_FAILED:INVALID_TEST_CLI'
  }
  $cli = $testCli
}

# Validate the file transport source itself before launching any CLI process.
$sql = Get-Content -LiteralPath $sqlPath -Raw
$sqlBody = [regex]::Replace($sql, '(?m)^\s*--.*(?:\r?\n|$)', '').Trim()
if ([string]::IsNullOrWhiteSpace($sqlBody) -or $sqlBody -notmatch '^SELECT\b' -or
    -not $sqlBody.EndsWith(';') -or ([regex]::Matches($sqlBody, ';')).Count -ne 1 -or
    $sql -match '(?im)^\s*(GRANT|REVOKE|CREATE|ALTER|DROP|INSERT|UPDATE|DELETE|TRUNCATE|CALL|DO)\b') {
  throw 'RPC_PRIVILEGE_VERIFY_FAILED:SQL_NOT_READ_ONLY_SELECT'
}

. (Join-Path $PSScriptRoot 'lib\hasad_cli.ps1')

function Get-JsonStructure {
  param([AllowNull()]$Value)
  $nodes = New-Object System.Collections.Generic.List[object]
  function Add-Node {
    param([AllowNull()]$Current, [string]$Path, [int]$Depth)
    if ($nodes.Count -ge 128) { return }
    if ($null -eq $Current) {
      $nodes.Add([ordered]@{ path = $Path; type = 'null' })
      return
    }
    if ($Current -is [System.Array]) {
      $nodes.Add([ordered]@{ path = $Path; type = 'array'; length = $Current.Length })
      if ($Depth -lt 6) {
        for ($i = 0; $i -lt $Current.Length -and $nodes.Count -lt 128; $i++) {
          Add-Node -Current $Current[$i] -Path ($Path + '[' + $i + ']') -Depth ($Depth + 1)
        }
      }
      return
    }
    if ($Current -is [pscustomobject] -or $Current -is [System.Collections.IDictionary]) {
      $names = @($Current.PSObject.Properties | ForEach-Object { $_.Name } | Sort-Object -Unique)
      if ($Current -is [System.Collections.IDictionary]) { $names = @($Current.Keys | Sort-Object -Unique) }
      $safeNames = @($names | ForEach-Object { [regex]::Replace([string]$_, '[^A-Za-z0-9_.-]', '?') })
      $nodes.Add([ordered]@{ path = $Path; type = 'object'; property_names = $safeNames })
      if ($Depth -lt 6) {
        foreach ($name in $names) {
          if ($nodes.Count -ge 128) { break }
          $child = if ($Current -is [System.Collections.IDictionary]) { $Current[$name] } else { $Current.PSObject.Properties[[string]$name].Value }
          Add-Node -Current $child -Path ($Path + '.' + [regex]::Replace([string]$name, '[^A-Za-z0-9_.-]', '?')) -Depth ($Depth + 1)
        }
      }
      return
    }
    $scalarType = if ($Current -is [bool]) { 'boolean' } elseif ($Current -is [string]) { 'string' } elseif ($Current -is [ValueType]) { 'number' } else { 'scalar' }
    $nodes.Add([ordered]@{ path = $Path; type = $scalarType })
  }
  $rootType = if ($null -eq $Value) { 'null' } elseif ($Value -is [System.Array]) { 'array' } elseif ($Value -is [pscustomobject] -or $Value -is [System.Collections.IDictionary]) { 'object' } elseif ($Value -is [string]) { 'string' } elseif ($Value -is [bool]) { 'boolean' } elseif ($Value -is [ValueType]) { 'number' } else { 'scalar' }
  Add-Node -Current $Value -Path '$' -Depth 0
  [ordered]@{ top_level_type = $rootType; structure = $nodes.ToArray() }
}

function Stop-WithStructureDiagnostic {
  param([Parameter(Mandatory)]$Value)
  $diagnostic = [ordered]@{
    diagnostic = 'UNSUPPORTED_CLI_JSON_STRUCTURE'
    structure = Get-JsonStructure -Value $Value
  }
  Write-Output ($diagnostic | ConvertTo-Json -Depth 10)
  throw 'RPC_PRIVILEGE_VERIFY_FAILED:UNSUPPORTED_CLI_JSON_STRUCTURE'
}

function Get-SanitizedCliFailure {
  param([AllowNull()][string]$StandardOutput, [AllowNull()][string]$StandardError)
  $text = ([string]$StandardOutput) + "`n" + ([string]$StandardError)
  $sqlState = 'NOT_EXPOSED'
  if ($text -match '(?i)SQLSTATE\s*[:= ]\s*([0-9A-Z]{5})') { $sqlState = $Matches[1] }
  elseif ($text -match '(?i)["''](?:sqlstate|code)["'']\s*:\s*["'']([0-9A-Z]{5})["'']') { $sqlState = $Matches[1] }

  $category = if ($text -match '(?i)multiple commands into a prepared statement') { 'MULTI_STATEMENT_PREPARED_QUERY' }
    elseif ($sqlState -eq '42501' -or $text -match '(?i)permission denied') { 'POSTGRES_PRIVILEGE_DENIED' }
    elseif ($text -match '(?i)telemetry|FileSystem\.writeFile|EPERM') { 'CLI_TELEMETRY_WRITE_FAILURE' }
    elseif ($text -match '(?i)connection refused|failed to connect|timeout|could not connect') { 'DATABASE_CONNECTION_FAILURE' }
    elseif ($text -match '(?i)unauthorized|not authenticated|access token') { 'CLI_AUTHENTICATION_FAILURE' }
    elseif ($sqlState -ne 'NOT_EXPOSED') { 'POSTGRES_SQL_ERROR' }
    else { 'CLI_FAILURE_UNCLASSIFIED' }

  [pscustomobject]@{ SqlState = $sqlState; Category = $category }
}

$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('hasad-rpc-privilege-verify-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
try {
  $hadDoNotTrack = Test-Path Env:\DO_NOT_TRACK
  $previousDoNotTrack = $env:DO_NOT_TRACK
  $env:DO_NOT_TRACK = '1'
  try {
    $cliResult = Invoke-HasadCliFile -CliPath $cli `
      -Arguments @('--agent', 'yes', 'db', 'query', '--linked', '--project-ref', $devRef, '--file', $sqlPath, '--output-format', 'json') `
      -StandardOutputPath (Join-Path $tempRoot 'stdout.json') `
      -StandardErrorPath (Join-Path $tempRoot 'stderr.txt')
  } finally {
    if ($hadDoNotTrack) { $env:DO_NOT_TRACK = $previousDoNotTrack }
    else { Remove-Item Env:\DO_NOT_TRACK -ErrorAction SilentlyContinue }
  }

  if ($cliResult.ExitCode -ne 0) {
    $failure = Get-SanitizedCliFailure -StandardOutput $cliResult.StandardOutput -StandardError $cliResult.StandardError
    Write-Output ("RPC_PRIVILEGE_VERIFY_DIAGNOSTIC:SQLSTATE={0};CATEGORY={1}" -f $failure.SqlState,$failure.Category)
    throw 'RPC_PRIVILEGE_VERIFY_FAILED:CLI_NONZERO_EXIT'
  }
  if ([string]::IsNullOrWhiteSpace($cliResult.StandardOutput)) {
    throw 'RPC_PRIVILEGE_VERIFY_FAILED:CLI_EMPTY_OUTPUT'
  }

  try { $envelope = $cliResult.StandardOutput | ConvertFrom-Json -ErrorAction Stop }
  catch { throw 'RPC_PRIVILEGE_VERIFY_FAILED:CLI_INVALID_JSON' }
  if ($null -eq $envelope -or $envelope -isnot [pscustomobject]) {
    Stop-WithStructureDiagnostic -Value $envelope
  }
  if (($null -ne $envelope.PSObject.Properties['_tag'] -and [string]$envelope._tag -eq 'Error') -or
      ($null -ne $envelope.PSObject.Properties['error'] -and $null -ne $envelope.error)) {
    throw 'RPC_PRIVILEGE_VERIFY_FAILED:CLI_ERROR_ENVELOPE'
  }
  $topNames = @($envelope.PSObject.Properties | ForEach-Object Name | Sort-Object)
  if (($topNames -join ',') -ne 'boundary,rows,warning' -or
      $envelope.boundary -isnot [string] -or $envelope.warning -isnot [string] -or
      $envelope.rows -isnot [pscustomobject]) {
    Stop-WithStructureDiagnostic -Value $envelope
  }

  $resultProperty = $envelope.rows.PSObject.Properties['rpc_privilege_verification']
  if ($null -eq $resultProperty -or $resultProperty.Value -isnot [pscustomobject]) {
    throw 'RPC_PRIVILEGE_VERIFY_FAILED:RESULT_MISSING_OR_INVALID'
  }
  $result = $resultProperty.Value
  $requiredBooleans = @(
    'anon_auth_schema_usage', 'anon_auth_users_select',
    'authenticated_auth_schema_usage', 'authenticated_auth_users_select',
    'rpc_owner_auth_schema_usage', 'rpc_owner_auth_uid_execute',
    'rpc_owner_auth_users_select'
  )
  foreach ($property in $requiredBooleans) {
    $field = $result.PSObject.Properties[$property]
    if ($null -eq $field -or $field.Value -isnot [bool]) {
      throw 'RPC_PRIVILEGE_VERIFY_FAILED:PRIVILEGE_RESULT_INCOMPLETE_OR_INVALID'
    }
  }
  foreach ($property in @('api_rpcs', 'hasad_rls', 'rpc_owner_role')) {
    if ($null -eq $result.PSObject.Properties[$property]) {
      throw 'RPC_PRIVILEGE_VERIFY_FAILED:RESULT_INCOMPLETE'
    }
  }
  if ($result.api_rpcs -isnot [System.Array] -or $result.api_rpcs.Length -ne 2 -or
      $result.hasad_rls -isnot [System.Array] -or $result.hasad_rls.Length -ne 47 -or
      $result.rpc_owner_role -isnot [pscustomobject]) {
    throw 'RPC_PRIVILEGE_VERIFY_FAILED:RESULT_CARDINALITY_OR_TYPE_INVALID'
  }

  $role = $result.rpc_owner_role
  foreach ($property in @('exists', 'login', 'superuser', 'bypass_rls', 'inherit')) {
    $field = $role.PSObject.Properties[$property]
    if ($null -eq $field -or $field.Value -isnot [bool]) {
      throw 'RPC_PRIVILEGE_VERIFY_FAILED:RPC_OWNER_ROLE_INCOMPLETE'
    }
  }
  if (-not $role.exists) { throw 'RPC_PRIVILEGE_VERIFY_FAILED:RPC_OWNER_ROLE_MISSING' }

  $expectedRpcNames = @('whoami', 'products_list')
  $seenRpcNames = @{}
  foreach ($rpc in $result.api_rpcs) {
    if ($rpc -isnot [pscustomobject] -or $rpc.name -isnot [string] -or
        $rpc.name -notin $expectedRpcNames -or $seenRpcNames.ContainsKey($rpc.name) -or
        [string]::IsNullOrWhiteSpace([string]$rpc.owner) -or
        $rpc.authenticated_execute -isnot [bool] -or $rpc.anon_execute -isnot [bool] -or
        $rpc.security_definer -isnot [bool]) {
      throw 'RPC_PRIVILEGE_VERIFY_FAILED:RPC_METADATA_INVALID'
    }
    $seenRpcNames[$rpc.name] = $true
  }
  if ($seenRpcNames.Count -ne 2) { throw 'RPC_PRIVILEGE_VERIFY_FAILED:RPC_METADATA_INCOMPLETE' }

  $enabledCount = 0
  $forcedCount = 0
  $seenTables = @{}
  foreach ($table in $result.hasad_rls) {
    if ($table -isnot [pscustomobject] -or [string]::IsNullOrWhiteSpace([string]$table.table) -or
        $seenTables.ContainsKey([string]$table.table) -or $table.rls_enabled -isnot [bool] -or
        $table.force_rls -isnot [bool] -or $table.policy_count -isnot [ValueType] -or
        [int]$table.policy_count -lt 0) {
      throw 'RPC_PRIVILEGE_VERIFY_FAILED:RLS_METADATA_INVALID'
    }
    $seenTables[[string]$table.table] = $true
    if ($table.rls_enabled) { $enabledCount++ }
    if ($table.force_rls) { $forcedCount++ }
  }
  if ($seenTables.Count -ne 47) { throw 'RPC_PRIVILEGE_VERIFY_FAILED:RLS_METADATA_INCOMPLETE' }

  $safeSummary = [ordered]@{
    rpc_owner_auth_schema_usage = $result.rpc_owner_auth_schema_usage
    rpc_owner_auth_uid_execute = $result.rpc_owner_auth_uid_execute
    rpc_owner_auth_users_select = $result.rpc_owner_auth_users_select
    api_rpcs = @($result.api_rpcs | ForEach-Object {
      [ordered]@{ name = $_.name; owner = $_.owner; authenticated_execute = $_.authenticated_execute; anon_execute = $_.anon_execute }
    })
    rls_tables = [ordered]@{ total = 47; enabled = $enabledCount; forced = $forcedCount }
  }
  $safeSummary | ConvertTo-Json -Depth 6
}
finally {
  Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}
