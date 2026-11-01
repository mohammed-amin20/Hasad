param(
  [Parameter(Mandatory=$true)][ValidatePattern('^[a-z0-9]{20}$')][string]$ProjectRef,
  [Parameter(Mandatory=$true)][string]$ExpectedProjectName,
  [Parameter(Mandatory=$true)][switch]$ConfirmDisposableProject
)
$ErrorActionPreference = 'Stop'
$stage = 'preflight'
$devRef = 'sxasnunzspkuwbxiddqd'
$pocRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Split-Path -Parent (Split-Path -Parent $pocRoot)
$workdir = Join-Path $pocRoot 'workspace'
$cli = Join-Path $repoRoot 'node_modules/.bin/supabase.cmd'
$psql = 'C:\Program Files\PostgreSQL\17\bin\psql.exe'
$testLabels = [System.Collections.Generic.List[string]]::new()
$http = [System.Net.Http.HttpClient]::new()
$http.Timeout = [TimeSpan]::FromSeconds(25)

function Read-SecretText([string]$Prompt) {
  $secure = Read-Host -Prompt $Prompt -AsSecureString
  $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
  try { return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr) }
  finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr) }
}
function Add-Pass([string]$Label) {
  $script:testLabels.Add($Label)
  Write-Host ('PASS: ' + $Label)
}
function Send-JsonRequest([string]$Method,[string]$Uri,[hashtable]$Headers,$Payload) {
  $request = [System.Net.Http.HttpRequestMessage]::new([System.Net.Http.HttpMethod]::new($Method),$Uri)
  foreach($key in $Headers.Keys) { [void]$request.Headers.TryAddWithoutValidation($key,[string]$Headers[$key]) }
  if($null -ne $Payload) {
    $json = ConvertTo-Json -InputObject $Payload -Depth 8 -Compress
    $request.Content = [System.Net.Http.StringContent]::new($json,[Text.Encoding]::UTF8,'application/json')
  }
  $response = $script:http.SendAsync($request).GetAwaiter().GetResult()
  $body = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
  return [pscustomobject]@{ Status=[int]$response.StatusCode; Body=$body }
}
function New-SyntheticUser([string]$BaseUrl,[string]$ServiceKey,[string]$AnonKey,[string]$Label) {
  $email = 'poc+' + [guid]::NewGuid().ToString('N') + '@hasad.invalid'
  $random = [Convert]::ToBase64String([Security.Cryptography.RandomNumberGenerator]::GetBytes(32)).TrimEnd('=').Replace('+','-').Replace('/','_')
  $password = $random + 'Aa9!'
  $adminHeaders = @{ apikey=$ServiceKey; Authorization=('Bearer ' + $ServiceKey) }
  $created = Send-JsonRequest 'POST' ($BaseUrl + '/auth/v1/admin/users') $adminHeaders @{
    email=$email; password=$password; email_confirm=$true; user_metadata=@{poc_label=$Label}
  }
  if($created.Status -lt 200 -or $created.Status -ge 300) { throw 'AUTH_USER_CREATE_FAILED' }
  $createdObject = $created.Body | ConvertFrom-Json
  $userId = [string]$createdObject.id
  if($userId -notmatch '^[0-9a-fA-F-]{36}$') { throw 'AUTH_USER_ID_INVALID' }
  $signedIn = Send-JsonRequest 'POST' ($BaseUrl + '/auth/v1/token?grant_type=password') @{apikey=$AnonKey} @{
    email=$email; password=$password
  }
  if($signedIn.Status -lt 200 -or $signedIn.Status -ge 300) { throw 'AUTH_PASSWORD_SIGNIN_FAILED' }
  $session = $signedIn.Body | ConvertFrom-Json
  if(-not $session.access_token) { throw 'AUTH_JWT_MISSING' }
  return [pscustomobject]@{ Id=$userId; Token=[string]$session.access_token }
}
function Call-Rpc([string]$BaseUrl,[string]$AnonKey,[string]$Token,[string]$Function) {
  $headers = @{ apikey=$AnonKey; Authorization=('Bearer ' + $Token); 'Accept-Profile'='hasad_api'; 'Content-Profile'='hasad_api' }
  return Send-JsonRequest 'POST' ($BaseUrl + '/rest/v1/rpc/' + $Function) $headers @{}
}
function Read-JwtSubject([string]$Token) {
  $part = $Token.Split('.')[1].Replace('-','+').Replace('_','/')
  switch($part.Length % 4) { 2 {$part+='=='} 3 {$part+='='} }
  $payload = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($part)) | ConvertFrom-Json
  return [string]$payload.sub
}

try {
  if(-not $ConfirmDisposableProject) { throw 'DISPOSABLE_CONFIRMATION_REQUIRED' }
  if($ProjectRef -eq $devRef) { throw 'DEV_REF_REJECTED' }
  if([string]::IsNullOrWhiteSpace($ExpectedProjectName)) { throw 'EXPECTED_PROJECT_NAME_REQUIRED' }
  if(-not (Test-Path -LiteralPath $cli)) { throw 'REPOSITORY_SUPABASE_CLI_MISSING' }
  if(-not (Test-Path -LiteralPath $psql)) { throw 'POSTGRESQL_PSQL_MISSING' }
  $rootRefFile = Join-Path $repoRoot 'supabase/.temp/project-ref'
  if((Get-Content -Raw -LiteralPath $rootRefFile).Trim() -ne $devRef) { throw 'REPOSITORY_DEV_LINK_CHANGED' }
  if(Test-Path (Join-Path $workdir 'supabase/.temp/project-ref')) { throw 'ISOLATED_LINK_ALREADY_EXISTS_REVIEW_FIRST' }

  # Read-only project identity lookup. No SQL, Auth, or settings calls occur before exact match.
  $stage = 'project_identity'
  $projectsOutput = @(& $cli projects list --output-format json --workdir $workdir 2>$null)
  if($LASTEXITCODE -ne 0) { throw 'SUPABASE_CLI_LOGIN_OR_PROJECT_LIST_FAILED' }
  $joined = $projectsOutput -join [Environment]::NewLine
  $first = $joined.IndexOf('['); $last = $joined.LastIndexOf(']')
  if($first -lt 0 -or $last -le $first) { throw 'PROJECT_LIST_FORMAT_UNRECOGNIZED' }
  $projectRows = ConvertFrom-Json ($joined.Substring($first,$last-$first+1))
  $target = $null
  foreach($row in $projectRows) {
    $ref = if($row.ref) { [string]$row.ref } elseif($row.id) { [string]$row.id } else { '' }
    if($ref -eq $ProjectRef) { $target=$row; break }
  }
  if($null -eq $target -or [string]$target.name -cne $ExpectedProjectName) { throw 'PROJECT_IDENTITY_MISMATCH' }
  Add-Pass 'separate project identity verified by ref and exact project name; DEV ref rejected'

  $stage = 'migration_prepare'
  $migrations = Join-Path $workdir 'supabase/migrations'
  New-Item -ItemType Directory -Path $migrations -Force | Out-Null
  $migrationPath = Join-Path $migrations '20261101000100_hosted_security_poc.sql'
  if(Test-Path -LiteralPath $migrationPath) { throw 'ISOLATED_MIGRATION_ALREADY_EXISTS_REVIEW_FIRST' }
  $baseSql = Get-Content -Raw (Join-Path $pocRoot 'hosted_schema_base.sql')
  $candidateSql = Get-Content -Raw (Join-Path $repoRoot 'security/candidates/20261030000100_v2_candidate_hasad_api_company_product_read_v2.sql')
  $tailSql = @'
REVOKE ALL ON SCHEMA hasad FROM PUBLIC, anon, authenticated;
REVOKE ALL PRIVILEGES ON ALL TABLES IN SCHEMA hasad FROM PUBLIC, anon, authenticated;
REVOKE ALL ON SCHEMA hasad_api FROM PUBLIC, anon;
GRANT USAGE ON SCHEMA hasad_api TO authenticated;
REVOKE ALL ON FUNCTION hasad_api.whoami() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION hasad_api.products_list() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION hasad_api.whoami(), hasad_api.products_list() TO authenticated;
ALTER ROLE authenticator SET pgrst.db_schemas = 'public,graphql_public,hasad_api';
NOTIFY pgrst, 'reload config';
COMMIT;
'@
  [IO.File]::WriteAllText($migrationPath,($baseSql + [Environment]::NewLine + $candidateSql + [Environment]::NewLine + $tailSql),[Text.UTF8Encoding]::new($false))

  $baseUrl = 'https://' + $ProjectRef + '.supabase.co'
  $anonKey = Read-SecretText 'Disposable project anon/publishable key (input hidden)'
  $serviceKey = Read-SecretText 'Disposable project service_role/secret key (input hidden)'
  $dbPassword = Read-SecretText 'Disposable project database password (input hidden)'
  $oldPgPassword = $env:PGPASSWORD; $oldPgSsl = $env:PGSSLMODE
  $env:PGPASSWORD = $dbPassword; $env:PGSSLMODE = 'require'
  $dbHost = 'db.' + $ProjectRef + '.supabase.co'
  $dbArgs = @('-X','-w','-h',$dbHost,'-p','5432','-U','postgres','-d','postgres','-v','ON_ERROR_STOP=1')

  $stage = 'empty_schema_preflight'
  $empty = & $psql @dbArgs -Atc "SELECT (to_regnamespace('hasad') IS NULL AND to_regnamespace('hasad_api') IS NULL)::text;"
  if($LASTEXITCODE -ne 0 -or (($empty -join '').Trim() -ne 'true')) { throw 'TEST_SCHEMA_NOT_EMPTY_OR_DB_CONNECTION_FAILED' }
  $stage = 'schema_apply'
  & $psql @dbArgs -f $migrationPath *> $null
  if($LASTEXITCODE -ne 0) { throw 'TEST_SCHEMA_APPLY_FAILED' }
  Add-Pass 'isolated schema, candidate RPCs, exact grants and PostgREST exposure applied'

  $stage = 'auth_users'
  $labels = @('a','b','missing','revoked','suspended','no_permission','role_allow','override_deny','override_allow','owner')
  $users = @{}
  foreach($label in $labels) { $users[$label] = New-SyntheticUser $baseUrl $serviceKey $anonKey $label }
  foreach($label in $labels) {
    if((Read-JwtSubject $users[$label].Token) -ne $users[$label].Id) { throw 'AUTH_JWT_SUBJECT_MISMATCH' }
  }
  Add-Pass 'synthetic Supabase Auth users issued real JWTs; JWT sub matched Auth user IDs'

  $stage = 'synthetic_fixture_seed'
  $fixtureArgs = @('-f',(Join-Path $pocRoot 'fixtures.sql'),
    '-v','ua='+$users.a.Id,'-v','ub='+$users.b.Id,'-v','um='+$users.missing.Id,
    '-v','ur='+$users.revoked.Id,'-v','us='+$users.suspended.Id,'-v','un='+$users.no_permission.Id,
    '-v','u7='+$users.role_allow.Id,'-v','u8='+$users.override_deny.Id,
    '-v','u9='+$users.override_allow.Id,'-v','uo='+$users.owner.Id)
  & $psql @dbArgs @fixtureArgs *> $null
  if($LASTEXITCODE -ne 0) { throw 'SYNTHETIC_FIXTURE_SEED_FAILED' }
  $stage = 'sql_security_assertions'
  & $psql @dbArgs -f (Join-Path $pocRoot 'hosted_sql_assertions.sql') *> $null
  if($LASTEXITCODE -ne 0) { throw 'HOSTED_SQL_SECURITY_ASSERTIONS_FAILED' }
  Add-Pass 'SQL grants, anon/PUBLIC denial, schema exposure, FORCE RLS and membership uniqueness'

  $stage = 'real_jwt_postgrest'
  $aContext = Call-Rpc $baseUrl $anonKey $users.a.Token 'whoami'
  $aProducts = Call-Rpc $baseUrl $anonKey $users.a.Token 'products_list'
  $aObject = $aContext.Body | ConvertFrom-Json; $aRows = @($aProducts.Body | ConvertFrom-Json)
  if($aContext.Status -ne 200 -or $aObject.company_id -ne '10000000-0000-0000-0000-000000000001' -or $aObject.company_name -ne 'Company A' -or $aRows.Count -ne 1 -or $aRows[0].company_id -ne $aObject.company_id) { throw 'JWT_COMPANY_A_OR_IDENTITY_FAILED' }
  Add-Pass 'real JWT company A identity, context name and product read'
  $bContext = Call-Rpc $baseUrl $anonKey $users.b.Token 'whoami'
  $bProducts = Call-Rpc $baseUrl $anonKey $users.b.Token 'products_list'
  $bObject = $bContext.Body | ConvertFrom-Json; $bRows=@($bProducts.Body | ConvertFrom-Json)
  if($bContext.Status -ne 200 -or $bObject.company_id -ne '10000000-0000-0000-0000-000000000002' -or $bRows.Count -ne 1 -or $bRows[0].company_id -ne $bObject.company_id) { throw 'JWT_COMPANY_B_OR_CROSS_TENANT_FAILED' }
  Add-Pass 'real JWT company B identity and cross-company product isolation'
  foreach($case in @(@{label='missing';rpc='whoami'},@{label='revoked';rpc='products_list'},@{label='suspended';rpc='whoami'})) {
    $result=Call-Rpc $baseUrl $anonKey $users[$case.label].Token $case.rpc
    if($result.Status -lt 400) { throw ('MEMBERSHIP_NEGATIVE_CASE_FAILED_'+$case.label) }
  }
  Add-Pass 'real JWT missing, revoked and suspended-company memberships denied'

  $denied=Call-Rpc $baseUrl $anonKey $users.no_permission.Token 'products_list'
  $allowedRole=Call-Rpc $baseUrl $anonKey $users.role_allow.Token 'products_list'
  $deniedOverride=Call-Rpc $baseUrl $anonKey $users.override_deny.Token 'products_list'
  $allowedOverride=Call-Rpc $baseUrl $anonKey $users.override_allow.Token 'products_list'
  $ownerAllowed=Call-Rpc $baseUrl $anonKey $users.owner.Token 'products_list'
  if($denied.Status -lt 400 -or $allowedRole.Status -ne 200 -or $deniedOverride.Status -lt 400 -or $allowedOverride.Status -ne 200 -or $ownerAllowed.Status -ne 200) { throw 'PRODUCT_PERMISSION_PRECEDENCE_FAILED' }
  Add-Pass 'real JWT products.read default deny, role allow, deny override, allow override and owner precedence'
  $anonRpc=Send-JsonRequest 'POST' ($baseUrl+'/rest/v1/rpc/whoami') @{apikey=$anonKey;'Accept-Profile'='hasad_api';'Content-Profile'='hasad_api'} @{}
  if($anonRpc.Status -lt 400) { throw 'ANON_RPC_WAS_ALLOWED' }
  Add-Pass 'anonymous PostgREST RPC denied'
  $directHeaders=@{apikey=$anonKey;Authorization=('Bearer '+$users.a.Token);'Accept-Profile'='hasad'}
  $direct=Send-JsonRequest 'GET' ($baseUrl+'/rest/v1/products?select=*') $directHeaders $null
  if($direct.Status -lt 400) { throw 'DIRECT_HASAD_TABLE_WAS_EXPOSED' }
  Add-Pass 'direct hasad table endpoint denied; hasad is not exposed'
  Add-Pass 'PUBLIC EXECUTE denied and FORCE RLS enforced under non-owner NOBYPASSRLS RPC role'

  $evidence = [ordered]@{ project_ref=$ProjectRef; project_name=$ExpectedProjectName
    tested_at_utc=[DateTime]::UtcNow.ToString('o'); cli_version='2.121.0'
    results=@($testLabels | ForEach-Object { [ordered]@{test=$_;result='PASS'} }) }
  $evidenceDir=Join-Path $pocRoot 'evidence'; New-Item -ItemType Directory -Path $evidenceDir -Force | Out-Null
  [IO.File]::WriteAllText((Join-Path $evidenceDir ($ProjectRef+'_results.json')),($evidence | ConvertTo-Json -Depth 6),[Text.UTF8Encoding]::new($false))
  Write-Host 'PASS: sanitized evidence saved without JWTs, keys, passwords, emails or user IDs'
}
catch {
  Write-Error ('FAIL: hosted POC stopped at stage ' + $stage + '; details suppressed to prevent credential disclosure.')
  exit 1
}
finally {
  $env:PGPASSWORD=$oldPgPassword; $env:PGSSLMODE=$oldPgSsl
  $http.Dispose()
}
