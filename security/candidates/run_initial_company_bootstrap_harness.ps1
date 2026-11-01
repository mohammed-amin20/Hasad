$ErrorActionPreference='Stop'
$root=Split-Path -Parent $MyInvocation.MyCommand.Path
$pgBin='C:\Program Files\PostgreSQL\17\bin'
$psql=Join-Path $pgBin 'psql.exe'
$pgRoot=Join-Path $env:LOCALAPPDATA ('Temp\opencode\hasad-initial-bootstrap-'+[guid]::NewGuid().ToString('N'))
$data=Join-Path $pgRoot 'data'; $log=Join-Path $pgRoot 'server.log'
$port=Get-Random -Minimum 56000 -Maximum 64000; $started=$false; $postgres=$null
$base=@('-X','-w','-h','127.0.0.1','-p',"$port",'-U','postgres','-d','postgres','-v','ON_ERROR_STOP=1')
$template=Join-Path $root '20261030000200_v2_initial_company_bootstrap_operator.sql'
$tokenValues=[ordered]@{
  '__OWNER_AUTH_USER_ID__'='00000000-0000-0000-0000-000000000001'
  '__COMPANY_ID__'='10000000-0000-0000-0000-000000000001'
  '__OWNER_ROLE_ID__'='20000000-0000-0000-0000-000000000001'
  '__MEMBERSHIP_ID__'='30000000-0000-0000-0000-000000000001'
  '__AUDIT_ID__'='40000000-0000-0000-0000-000000000001'
  '__COMPANY_NAME_AR__'='شركة الاختبار'
  '__OWNER_ROLE_CODE__'='initial_owner'
}
function New-CandidateFile([hashtable]$values){
  $text=Get-Content -Raw $template
  foreach($entry in $values.GetEnumerator()){
    $text=$text.Replace($entry.Key,([string]$entry.Value).Replace("'","''"))
  }
  $path=Join-Path $pgRoot ('candidate-'+[guid]::NewGuid().ToString('N')+'.sql')
  [IO.File]::WriteAllText($path,$text,[Text.UTF8Encoding]::new($false))
  return $path
}
function Assert-FailedCandidate([string]$path,[string]$expected){
  $previous=$ErrorActionPreference; $ErrorActionPreference='Continue'
  $output=& $psql @base -f $path 2>&1; $exit=$LASTEXITCODE
  $ErrorActionPreference=$previous
  if($exit -eq 0 -or ($output -join "`n") -notmatch $expected){throw 'EXPECTED_BOOTSTRAP_FAILURE_NOT_OBSERVED'}
}
New-Item -ItemType Directory -Path $pgRoot | Out-Null
try {
  & (Join-Path $pgBin 'initdb.exe') -D $data -U postgres -A trust --no-locale | Out-Null
  if($LASTEXITCODE -ne 0){throw 'DISPOSABLE_INITDB_FAILED'}
  $postgres=Start-Process -FilePath (Join-Path $pgBin 'postgres.exe') -ArgumentList @('-D',$data,'-p',"$port",'-h','127.0.0.1') -RedirectStandardError $log -PassThru
  foreach($attempt in 1..40){try{$probe=[Net.Sockets.TcpClient]::new('127.0.0.1',$port);$probe.Dispose();break}catch{Start-Sleep -Milliseconds 250}}
  if($null -eq $probe){throw 'DISPOSABLE_POSTGRES_START_FAILED'}
  $started=$true
  & $psql @base -f (Join-Path $root 'initial_company_bootstrap_harness_setup.sql') | Out-Null
  if($LASTEXITCODE -ne 0){throw 'HARNESS_SETUP_FAILED'}

  $wrong=[ordered]@{}+$tokenValues; $wrong['__OWNER_AUTH_USER_ID__']='00000000-0000-0000-0000-000000000099'
  Assert-FailedCandidate (New-CandidateFile $wrong) 'BOOTSTRAP_OWNER_AUTH_ID_NOT_FOUND'
  & $psql @base -c 'DO $$ BEGIN IF (SELECT count(*) FROM hasad.companies)<>0 OR (SELECT count(*) FROM hasad.user_profiles)<>0 THEN RAISE EXCEPTION ''ROLLBACK_LEFT_ROWS''; END IF; RAISE NOTICE ''PASS: nonexistent selected Auth user rolls back all rows''; END $$;' | Out-Null
  if($LASTEXITCODE -ne 0){throw 'NONEXISTENT_OWNER_ROLLBACK_ASSERTION_FAILED'}
  Write-Host 'PASS: nonexistent selected Auth user rolls back all rows'

  $candidate=New-CandidateFile $tokenValues
  & $psql @base -f $candidate | Out-Null
  if($LASTEXITCODE -ne 0){throw 'SUCCESSFUL_BOOTSTRAP_FAILED'}
  & $psql @base -f (Join-Path $root 'initial_company_bootstrap_assertions.sql')
  if($LASTEXITCODE -ne 0){throw 'SUCCESSFUL_BOOTSTRAP_ASSERTIONS_FAILED'}
  Write-Host 'PASS: atomic initial-company bootstrap created only approved minimum rows'

  Assert-FailedCandidate (New-CandidateFile $tokenValues) 'BOOTSTRAP_OWNER_PROFILE_ALREADY_EXISTS|BOOTSTRAP_TENANT_SURFACE_NOT_EMPTY'
  & $psql @base -c 'DO $$ BEGIN IF (SELECT count(*) FROM hasad.companies)<>1 OR (SELECT count(*) FROM hasad.company_memberships)<>1 THEN RAISE EXCEPTION ''DUPLICATE_BOOTSTRAP_LEFT_ROWS''; END IF; RAISE NOTICE ''PASS: duplicate bootstrap is rejected without additional rows''; END $$;' | Out-Null
  if($LASTEXITCODE -ne 0){throw 'DUPLICATE_BOOTSTRAP_ASSERTION_FAILED'}
  Write-Host 'PASS: duplicate bootstrap is rejected without additional rows'
}
finally {
  if($started -and $null -ne $postgres -and -not $postgres.HasExited){Stop-Process -Id $postgres.Id -Force -ErrorAction SilentlyContinue;$postgres.WaitForExit()}
  $tempRoot=[IO.Path]::GetFullPath((Join-Path $env:LOCALAPPDATA 'Temp\opencode')).TrimEnd('\')+'\'
  $target=[IO.Path]::GetFullPath($pgRoot)
  if($target.StartsWith($tempRoot+'hasad-initial-bootstrap-',[StringComparison]::OrdinalIgnoreCase)){Remove-Item -LiteralPath $target -Recurse -Force -ErrorAction SilentlyContinue}
}
