param([switch]$RunWithExistingAuthorizedAccount)
$ErrorActionPreference='Stop'
$devRef='sxasnunzspkuwbxiddqd'
$stage='identity'
$repoRoot=Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path))
$cli=Join-Path $repoRoot 'node_modules/.bin/supabase.cmd'
$http=[System.Net.Http.HttpClient]::new()
$http.Timeout=[TimeSpan]::FromSeconds(25)
$results=[ordered]@{}

function Read-SecretText([string]$Prompt) {
  $secure=Read-Host -Prompt $Prompt -AsSecureString
  $ptr=[Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
  try { return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr) }
  finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr) }
}
function Send-Request([string]$Method,[string]$Uri,[hashtable]$Headers) {
  $request=[System.Net.Http.HttpRequestMessage]::new([System.Net.Http.HttpMethod]::new($Method),$Uri)
  foreach($key in $Headers.Keys) { [void]$request.Headers.TryAddWithoutValidation($key,[string]$Headers[$key]) }
  if($Method -eq 'POST') { $request.Content=[System.Net.Http.StringContent]::new('{}',[Text.Encoding]::UTF8,'application/json') }
  $response=$script:http.SendAsync($request).GetAwaiter().GetResult()
  return [pscustomobject]@{
    Status=[int]$response.StatusCode
    Body=$response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
  }
}
function Read-CliJson($Lines) {
  $text=$Lines -join [Environment]::NewLine
  $start=$text.IndexOf('{'); $end=$text.LastIndexOf('}')
  if($start -lt 0 -or $end -le $start) { throw 'CLI_JSON_PARSE_FAILED' }
  return ConvertFrom-Json $text.Substring($start,$end-$start+1)
}

try {
  if(-not $RunWithExistingAuthorizedAccount) { throw 'EXPLICIT_READ_ONLY_TEST_SWITCH_REQUIRED' }
  if((Get-Content -Raw (Join-Path $repoRoot 'supabase/.temp/project-ref')).Trim() -ne $devRef) { throw 'ROOT_LINK_NOT_DEV' }
  $projects=@(& $cli projects list --output-format json 2>$null)
  if($LASTEXITCODE -ne 0) { throw 'PROJECT_IDENTITY_QUERY_FAILED' }
  $projectRows=Read-CliJson $projects
  $target=$projectRows | Where-Object { (($_.ref) -or ($_.id)) -and (($(if($_.ref){$_.ref}else{$_.id})) -eq $devRef) } | Select-Object -First 1
  if($null -eq $target -or $target.name -cne 'Hasad-erp-dev') { throw 'DEV_PROJECT_IDENTITY_MISMATCH' }
  $results.identity='PASS'
  Write-Host 'PASS: DEV reference and project name verified'

  $stage='catalog'
  $baselineOutput=@(& $cli db query --linked --project-ref $devRef --file (Join-Path $PSScriptRoot 'dev_security_preflight.sql') --output-format json 2>$null)
  if($LASTEXITCODE -ne 0) { throw 'READ_ONLY_CATALOG_QUERY_FAILED' }
  $baseline=(Read-CliJson $baselineOutput).rows[0].dev_security_baseline
  $role=$baseline.application_roles | Where-Object name -eq 'hasad_rpc_owner' | Select-Object -First 1
  $apiFunctions=@($baseline.functions | Where-Object schema -eq 'hasad_api')
  $internal=@($baseline.functions | Where-Object {$_.schema -eq 'hasad' -and $_.name -eq 'has_permission'})
  $badApiAcl=@($apiFunctions | Where-Object {$_.anon_execute -or $_.public_execute})
  $whoFn=$apiFunctions | Where-Object name -eq 'whoami' | Select-Object -First 1
  $productsFn=$apiFunctions | Where-Object name -eq 'products_list' | Select-Object -First 1
  $expectedPolicies=@('hasad_rpc_owner_memberships','hasad_rpc_owner_companies',
    'hasad_rpc_owner_company_settings','hasad_rpc_owner_roles',
    'hasad_rpc_owner_products_permission','hasad_rpc_owner_role_permissions',
    'hasad_rpc_owner_overrides','hasad_rpc_owner_products')
  $policyNames=@($baseline.policies | ForEach-Object name)
  $badTableGrants=@($baseline.application_table_grants | Where-Object {$_.schema -eq 'hasad' -and $_.grantee -in @('PUBLIC','anon','authenticated')})
  if($null -eq $role -or $role.login -or $role.superuser -or $role.inherit -or $role.bypass_rls -or $role.create_role -or $role.create_db -or
     $apiFunctions.Count -ne 2 -or $internal.Count -ne 1 -or $badApiAcl.Count -gt 0 -or
     -not $whoFn.authenticated_execute -or -not $productsFn.authenticated_execute -or
     $baseline.api_relations.Count -ne 0 -or $badTableGrants.Count -gt 0 -or
     $baseline.products_read_catalogue.Count -ne 1 -or $baseline.products_read_catalogue[0].module -ne 'products' -or
     $baseline.products_read_role_mappings.Count -ne 0 -or
     @($baseline.tables_rls | Where-Object {!$_.rls -or !$_.force_rls}).Count -gt 0 -or
     @($expectedPolicies | Where-Object {$_ -notin $policyNames}).Count -gt 0) { throw 'CATALOG_SECURITY_ASSERTION_FAILED' }
  $results.catalog='PASS'
  Write-Host 'PASS: restricted owner, forced RLS, exact client function grants, no direct app table grants and no automatic products.read mappings verified'

  $stage='existing_auth_jwt'
  $anonKey=Read-SecretText 'DEV anon/publishable API key (input hidden)'
  $jwt=Read-SecretText 'JWT from an already-authorized DEV Auth account (input hidden)'
  $base='https://sxasnunzspkuwbxiddqd.supabase.co'
  $authHeaders=@{apikey=$anonKey;Authorization=('Bearer '+$jwt);'Accept-Profile'='hasad_api';'Content-Profile'='hasad_api'}
  $who=Send-Request 'POST' ($base+'/rest/v1/rpc/whoami') $authHeaders
  if($who.Status -ne 200) { throw 'WHOAMI_POSTGREST_FAILED' }
  $context=$who.Body | ConvertFrom-Json
  if(-not $context.company_id -or [string]::IsNullOrWhiteSpace([string]$context.company_name)) { throw 'WHOAMI_RESPONSE_SHAPE_FAILED' }
  $results.whoami='PASS'
  Write-Host 'PASS: existing Auth JWT resolved an active server-side company context'

  $products=Send-Request 'POST' ($base+'/rest/v1/rpc/products_list') $authHeaders
  if($products.Status -eq 200) {
    $rows=@($products.Body | ConvertFrom-Json)
    if(@($rows | Where-Object {$_.company_id -ne $context.company_id}).Count -gt 0) { throw 'PRODUCT_COMPANY_SCOPE_FAILED' }
    $results.products='PASS'
    Write-Host 'PASS: products.read authorized; all returned products match the server-derived company'
  } else {
    $results.products='DENIED_FOR_THIS_ACCOUNT'
    Write-Host 'FAIL: products_list denied for this existing account; no permission was assigned'
  }

  $stage='anonymous_and_direct_endpoint'
  $anonHeaders=@{apikey=$anonKey;'Accept-Profile'='hasad_api';'Content-Profile'='hasad_api'}
  $anon=Send-Request 'POST' ($base+'/rest/v1/rpc/whoami') $anonHeaders
  if($anon.Status -lt 400) { throw 'ANON_RPC_NOT_DENIED' }
  $results.anon_rpc='PASS'
  $directHeaders=@{apikey=$anonKey;Authorization=('Bearer '+$jwt);'Accept-Profile'='hasad'}
  $direct=Send-Request 'GET' ($base+'/rest/v1/products?select=*') $directHeaders
  if($direct.Status -lt 400) { throw 'DIRECT_HASAD_ENDPOINT_NOT_DENIED' }
  $results.direct_hasad='PASS'
  Write-Host 'PASS: anonymous RPC and direct hasad table endpoint denied'

  $evidence=[ordered]@{evidence='OBSERVED';project_ref=$devRef;project_name='Hasad-erp-dev';
    observed_at_utc=[DateTime]::UtcNow.ToString('o');results=$results}
  $path=Join-Path $PSScriptRoot 'dev_company_product_access_verification.json'
  [IO.File]::WriteAllText($path,($evidence | ConvertTo-Json -Depth 5),[Text.UTF8Encoding]::new($false))
  Write-Host 'PASS: sanitized verification evidence saved; no token, key, company ID/name, or product data recorded'
  if($results.products -ne 'PASS') { exit 2 }
}
catch {
  Write-Error ('FAIL: read-only verification stopped at stage '+$stage+'; no database/config/Auth writes were made and response details are withheld.')
  exit 1
}
finally { $http.Dispose() }
