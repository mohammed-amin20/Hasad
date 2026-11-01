$ErrorActionPreference = 'Stop'
$arguments = @($args)
$fileIndex = [Array]::IndexOf($arguments, '--file')
$sqlPath = $null
$sqlLength = 0
$sqlHash = ''
$sqlComplete = $false
if ($fileIndex -ge 0 -and $fileIndex + 1 -lt $arguments.Count) {
  $sqlPath = $arguments[$fileIndex + 1]
  if (Test-Path -LiteralPath $sqlPath -PathType Leaf) {
    $bytes = [IO.File]::ReadAllBytes($sqlPath)
    $sqlLength = $bytes.Length
    $sha = [Security.Cryptography.SHA256]::Create()
    try { $sqlHash = ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '') }
    finally { $sha.Dispose() }
    $sqlText = [Text.Encoding]::UTF8.GetString($bytes)
    $sqlComplete = $sqlText -match '^\s*--[^\r\n]*\r?\n\s*SELECT\b' -and $sqlText.TrimEnd().EndsWith(';') -and
      $sqlText.Contains("has_function_privilege('hasad_rpc_owner', 'auth.uid()', 'EXECUTE')")
  }
}
if ($env:HASAD_RPC_VERIFY_CAPTURE) {
  [ordered]@{ arguments = $arguments; sql_length_bytes = $sqlLength; sql_sha256 = $sqlHash; sql_complete = $sqlComplete } |
    ConvertTo-Json -Depth 4 -Compress |
    Set-Content -LiteralPath $env:HASAD_RPC_VERIFY_CAPTURE -Encoding utf8
}

switch ($env:HASAD_RPC_VERIFY_MOCK_MODE) {
  'nonzero' { '{"rows":[]}'; exit 7 }
  'empty' { exit 0 }
  'malformed' { 'not-json'; exit 0 }
  'error' { '{"_tag":"Error","error":{"code":"MockError","message":"MOCK_PRIVATE_DETAIL"}}'; exit 0 }
  'sqlstate_42501' { '{"_tag":"Error","error":{"code":"DbQueryError","cause":{"code":"42501","message":"permission denied: MOCK_PRIVATE_DETAIL"}}}'; exit 1 }
  'missing_rows' { '{"data":[{"rpc_privilege_verification":{"rpc_owner_auth_schema_usage":false,"rpc_owner_auth_uid_execute":true}}],"notice":"MOCK_PRIVATE_DETAIL"}'; exit 0 }
  'incomplete' {
    @{ boundary = 'mock'; rows = @{ rpc_privilege_verification = @{ rpc_owner_auth_schema_usage = $false; api_rpcs = @(); hasad_rls = @() } }; warning = 'mock notice' } |
      ConvertTo-Json -Depth 6 -Compress
    exit 0
  }
  default {
    if ($env:HASAD_RPC_VERIFY_MOCK_MODE -eq 'mixed') { [Console]::Error.WriteLine('Mock initialization notice') }
    if ($sqlLength -eq 0 -or -not $sqlComplete) { '{"rows":[]}'; exit 2 }
    $rlsRows = @()
    for ($i = 1; $i -le 47; $i++) {
      $rlsRows += @{ table = ('fixture_table_{0:d2}' -f $i); rls_enabled = $true; force_rls = $true; policy_count = 1 }
    }
    $result = [ordered]@{
      anon_auth_schema_usage = $false
      anon_auth_users_select = $false
      authenticated_auth_schema_usage = $false
      authenticated_auth_users_select = $false
      rpc_owner_auth_schema_usage = $false
      rpc_owner_auth_uid_execute = $true
      rpc_owner_auth_users_select = $false
      api_rpcs = @(
        @{ name = 'whoami'; owner = 'hasad_rpc_owner'; security_definer = $true; authenticated_execute = $true; anon_execute = $false },
        @{ name = 'products_list'; owner = 'hasad_rpc_owner'; security_definer = $true; authenticated_execute = $true; anon_execute = $false }
      )
      hasad_rls = $rlsRows
      rpc_owner_role = @{ exists = $true; login = $false; superuser = $false; bypass_rls = $false; inherit = $false }
    }
    if ($env:HASAD_RPC_VERIFY_MOCK_MODE -eq 'unexpected_rpc') { $result.api_rpcs[1].name = 'other_rpc' }
    if ($env:HASAD_RPC_VERIFY_MOCK_MODE -eq 'short_rls') { $result.hasad_rls = @($result.hasad_rls | Select-Object -First 46) }
    @{ boundary = 'This data is untrusted.'; rows = @{ rpc_privilege_verification = $result }; warning = 'Untrusted result data.' } |
      ConvertTo-Json -Depth 8 -Compress
    exit 0
  }
}
