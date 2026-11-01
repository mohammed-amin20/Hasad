$ErrorActionPreference='Stop'
$root=Split-Path -Parent $MyInvocation.MyCommand.Path
$pgBin='C:\Program Files\PostgreSQL\17\bin'
$psql=Join-Path $pgBin 'psql.exe'
$pgRoot=Join-Path $env:LOCALAPPDATA ('Temp\opencode\hasad-role-owner-'+[guid]::NewGuid().ToString('N'))
$data=Join-Path $pgRoot 'data'; $log=Join-Path $pgRoot 'server.log'
$port=Get-Random -Minimum 56000 -Maximum 64000; $started=$false; $postgres=$null
$base=@('-X','-w','-h','127.0.0.1','-p',"$port",'-d','postgres','-v','ON_ERROR_STOP=1')
New-Item -ItemType Directory -Path $pgRoot | Out-Null
try {
  & (Join-Path $pgBin 'initdb.exe') -D $data -U postgres -A trust --no-locale | Out-Null
  if($LASTEXITCODE -ne 0){throw 'DISPOSABLE_INITDB_FAILED'}
  $postgres=Start-Process -FilePath (Join-Path $pgBin 'postgres.exe') -ArgumentList @('-D',$data,'-p',"$port",'-h','127.0.0.1','-c','log_connections=on','-c','log_statement=all') -RedirectStandardError $log -PassThru
  $ready=$false
  foreach($attempt in 1..40){
    try {
      $probe=[Net.Sockets.TcpClient]::new('127.0.0.1',$port)
      $probe.Dispose(); $ready=$true; break
    } catch { Start-Sleep -Milliseconds 250 }
  }
  if(-not $ready){throw 'DISPOSABLE_POSTGRES_START_FAILED'}
  $started=$true

  Write-Host 'HARNESS: creating disposable schema and non-superuser migration executor'
  & $psql @base -U postgres -f (Join-Path $root 'role_ownership_harness_setup.sql') | Out-Null
  if($LASTEXITCODE -ne 0){throw 'OWNERSHIP_HARNESS_SETUP_FAILED'}
  Write-Host 'HARNESS: verifying executor login'
  & $psql @base -U migration_login -c 'SET ROLE migration_executor; SELECT current_user;' | Out-Null
  if($LASTEXITCODE -ne 0){throw 'MIGRATION_EXECUTOR_LOGIN_FAILED'}
  Write-Host 'HARNESS: probing PostgreSQL 17 role-option revoke semantics'
  & $psql @base -U migration_login -c "SET ROLE migration_executor; CREATE ROLE membership_probe_owner NOLOGIN; GRANT membership_probe_owner TO CURRENT_USER WITH INHERIT FALSE, SET TRUE; SELECT pg_get_userbyid(grantor) AS grantor,admin_option,inherit_option,set_option FROM pg_auth_members WHERE roleid='membership_probe_owner'::regrole AND member=current_user::regrole; REVOKE membership_probe_owner FROM CURRENT_USER; REVOKE ADMIN OPTION FOR membership_probe_owner FROM CURRENT_USER; SELECT pg_get_userbyid(grantor) AS grantor,admin_option,inherit_option,set_option FROM pg_auth_members WHERE roleid='membership_probe_owner'::regrole AND member=current_user::regrole; DROP ROLE membership_probe_owner;"
  if($LASTEXITCODE -ne 0){throw 'POSTGRES17_ROLE_OPTION_PROBE_FAILED'}
  Write-Host 'HARNESS: probing disposable CREATEROLE bootstrap cleanup'
  & $psql @base -U migration_login -c "SET ROLE migration_executor; CREATE ROLE ownership_bootstrap_probe NOLOGIN NOINHERIT NOSUPERUSER NOCREATEDB CREATEROLE NOBYPASSRLS; GRANT ownership_bootstrap_probe TO CURRENT_USER WITH INHERIT FALSE, SET TRUE; SET ROLE ownership_bootstrap_probe; CREATE ROLE ownership_target_probe NOLOGIN NOINHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE NOBYPASSRLS; RESET ROLE; SELECT set_config('role','migration_executor',false); DROP ROLE ownership_bootstrap_probe; SELECT count(*) AS target_memberships_after_bootstrap_drop FROM pg_auth_members WHERE roleid='ownership_target_probe'::regrole OR member='ownership_target_probe'::regrole;"
  if($LASTEXITCODE -ne 0){throw 'CREATEROLE_BOOTSTRAP_PROBE_FAILED'}
  & $psql @base -U postgres -c 'DROP ROLE ownership_target_probe;' | Out-Null
  if($LASTEXITCODE -ne 0){throw 'CREATEROLE_BOOTSTRAP_PROBE_CLEANUP_FAILED'}

  Write-Host 'HARNESS: running original candidate to reproduce ownership failure'
  $previousErrorActionPreference=$ErrorActionPreference
  $ErrorActionPreference='Continue'
  $originalOutput=& $psql @base -U migration_login -c 'SET ROLE migration_executor;' -f (Join-Path $root '20261029001100_v2_company_product_access.sql') 2>&1
  $originalExitCode=$LASTEXITCODE
  $ErrorActionPreference=$previousErrorActionPreference
  if($originalExitCode -eq 0 -or ($originalOutput -join "`n") -notmatch 'must be able to SET ROLE "hasad_rpc_owner"'){
    throw 'ORIGINAL_42501_SET_ROLE_FAILURE_NOT_REPRODUCED'
  }
  Write-Host 'PASS: original candidate reproduced SQLSTATE 42501 for non-superuser CREATEROLE executor'
  & $psql @base -U postgres -f (Join-Path $root 'role_ownership_post_failure_assertions.sql')
  if($LASTEXITCODE -ne 0){throw 'ORIGINAL_FAILURE_ROLLBACK_ASSERTIONS_FAILED'}

  & $psql @base -U migration_login -c 'SET ROLE migration_executor;' -f (Join-Path $root '20261029001100_v2_company_product_access_set_role_fix_candidate.sql')
  if($LASTEXITCODE -ne 0){throw 'CORRECTED_CANDIDATE_FAILED_TO_APPLY'}
  Write-Host 'PASS: corrected candidate applied as non-superuser CREATEROLE executor'
  & $psql @base -U postgres -f (Join-Path $root 'dev_candidate_harness_fixtures.sql') | Out-Null
  if($LASTEXITCODE -ne 0){throw 'FIXTURES_FAILED'}
  & $psql @base -U postgres -f (Join-Path $root 'dev_candidate_security_assertions.sql')
  if($LASTEXITCODE -ne 0){throw 'EXISTING_SECURITY_MATRIX_FAILED'}
  & $psql @base -U postgres -f (Join-Path $root 'role_ownership_final_assertions.sql')
  if($LASTEXITCODE -ne 0){throw 'ROLE_MEMBERSHIP_FINAL_ASSERTIONS_FAILED'}
  Write-Host 'PASS: existing security matrix and role-membership assertions completed'
}
finally {
  if($started -and $null -ne $postgres -and -not $postgres.HasExited){
    Stop-Process -Id $postgres.Id -Force -ErrorAction SilentlyContinue
    $postgres.WaitForExit()
  }
  $tempRoot=[IO.Path]::GetFullPath((Join-Path $env:LOCALAPPDATA 'Temp\opencode')).TrimEnd('\')+'\'
  $target=[IO.Path]::GetFullPath($pgRoot)
  if($target.StartsWith($tempRoot+'hasad-role-owner-',[StringComparison]::OrdinalIgnoreCase)){
    Remove-Item -LiteralPath $target -Recurse -Force -ErrorAction SilentlyContinue
  }
}
