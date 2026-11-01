# Offline regression tests for lib/hasad_cli.ps1.
# No network, no database, no operator identity. Exit code 0 = all pass.

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
. (Join-Path $root 'lib/hasad_cli.ps1')

$script:failures = New-Object System.Collections.Generic.List[string]
$script:passes = 0

function Assert-True([bool]$Condition, [string]$Label) {
  if ($Condition) { $script:passes++; Write-Host "PASS: $Label" }
  else { $script:failures.Add($Label); Write-Host "FAIL: $Label" }
}
function Assert-Null($Value, [string]$Label) { Assert-True ($null -eq $Value) $Label }
function Assert-NotNull($Value, [string]$Label) { Assert-True ($null -ne $Value) $Label }

$b64 = { param($s) [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($s)) }
$marker = 'HASAD_PREFLIGHT_B64='

# --- payload parser: hostile and empty inputs must never throw, only return null ---
Assert-Null (ConvertFrom-HasadBase64Payload -Text $null -Marker $marker) 'null CLI output yields null payload'
Assert-Null (ConvertFrom-HasadBase64Payload -Text '' -Marker $marker) 'empty CLI output yields null payload'
Assert-Null (ConvertFrom-HasadBase64Payload -Text "   `r`n  " -Marker $marker) 'whitespace-only CLI output yields null payload'
Assert-Null (ConvertFrom-HasadBase64Payload -Text 'Initialising login role...' -Marker $marker) 'stderr-only noise yields null payload'
Assert-Null (ConvertFrom-HasadBase64Payload -Text 'Ready.' -Marker $marker) 'unrelated text yields null payload'
Assert-Null (ConvertFrom-HasadBase64Payload -Text ($marker + 'not_base64!!!') -Marker $marker) 'invalid base64 yields null payload'
Assert-Null (ConvertFrom-HasadBase64Payload -Text ($marker + (& $b64 'plain text, not json')) -Marker $marker) 'non-JSON payload yields null payload'

$valid = & $b64 '{"companies":0,"owner_auth_exists":true,"owner_banned":false}'
$parsed = ConvertFrom-HasadBase64Payload -Text ("noise`r`n" + $marker + $valid + "`r`nmore noise") -Marker $marker
Assert-NotNull $parsed 'valid payload surrounded by noise is parsed'
Assert-True ($parsed.companies -eq 0) 'parsed integer property is preserved'
Assert-True ($parsed.owner_auth_exists -eq $true) 'parsed boolean true property is preserved'
Assert-True ($parsed.owner_banned -eq $false) 'parsed boolean false property is preserved'

$envelope = '{"rows":[{"payload":"' + $marker + $valid + '"}],"message":""}'
$fromEnvelope = ConvertFrom-HasadBase64Payload -Text $envelope -Marker $marker
Assert-NotNull $fromEnvelope 'payload inside a JSON-escaped CLI envelope is parsed'

$wrapped = $marker + $valid + "`r`ntrailing prose that must not be captured"
$fromWrapped = ConvertFrom-HasadBase64Payload -Text $wrapped -Marker $marker
Assert-NotNull $fromWrapped 'payload followed by trailing prose is parsed'
Assert-True ($fromWrapped.companies -eq 0) 'trailing prose is not swallowed into the payload'

# --- typed accessors must fail loudly on missing data instead of defaulting to zero/false ---
$threw = $false
try { [void](Get-HasadPayloadInt -Payload $parsed -Name 'missing_property') } catch { $threw = $true }
Assert-True $threw 'missing integer property raises instead of defaulting to 0'

$threw = $false
try { [void](Get-HasadPayloadBool -Payload $parsed -Name 'missing_property') } catch { $threw = $true }
Assert-True $threw 'missing boolean property raises instead of defaulting to false'

$threw = $false
try { [void](Get-HasadPayloadInt -Payload $null -Name 'companies') } catch { $threw = $true }
Assert-True $threw 'null payload raises instead of indexing a null array'

# --- native command exit handling: stderr chatter must never abort a successful run ---
$tmp = Join-Path $env:LOCALAPPDATA ('Temp\opencode\hasad-cli-tests-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmp -Force | Out-Null
try {
  $outFile = Join-Path $tmp 'out.txt'
  $errFile = Join-Path $tmp 'err.txt'

  $ok = Invoke-HasadCliFile -CliPath $env:ComSpec `
    -Arguments @('/c', 'echo payload & echo warning 1>&2 & exit 0') `
    -StandardOutputPath $outFile -StandardErrorPath $errFile
  Assert-True ($ok.ExitCode -eq 0) 'exit 0 is reported as 0 despite stderr output'
  Assert-True ($ok.StandardOutput -match 'payload') 'stdout is captured'
  Assert-True ($ok.StandardError -match 'warning') 'stderr is captured separately'
  Assert-True ($ok.ExitCode -eq 0) 'stderr chatter does not raise or turn into failure'

  $bad = Invoke-HasadCliFile -CliPath $env:ComSpec `
    -Arguments @('/c', 'echo boom 1>&2 & exit 3') `
    -StandardOutputPath $outFile -StandardErrorPath $errFile
  Assert-True ($bad.ExitCode -eq 3) 'non-zero native exit code is propagated exactly'
  Assert-True ($bad.StandardOutput -eq '') 'empty stdout is reported as an empty string, not null'

  $empty = Invoke-HasadCliFile -CliPath $env:ComSpec `
    -Arguments @('/c', 'exit 0') `
    -StandardOutputPath $outFile -StandardErrorPath $errFile
  Assert-True ($empty.OutputLength -eq 0) 'silent success reports zero output length'
  Assert-True ($null -ne $empty.StandardOutput) 'silent success never returns null output'
  Assert-Null (ConvertFrom-HasadBase64Payload -Text $empty.StandardOutput -Marker $marker) 'silent success yields null payload, not an exception'

  # path quoting: a file path containing spaces must survive argument passing
  $spacedDir = Join-Path $tmp 'dir with spaces'
  New-Item -ItemType Directory -Path $spacedDir -Force | Out-Null
  $spacedFile = Join-Path $spacedDir 'payload file.txt'
  [IO.File]::WriteAllText($spacedFile, 'quoted-ok', [Text.UTF8Encoding]::new($false))
  $quoted = Invoke-HasadCliFile -CliPath $env:ComSpec `
    -Arguments @('/c', 'type', $spacedFile) `
    -StandardOutputPath $outFile -StandardErrorPath $errFile
  Assert-True ($quoted.ExitCode -eq 0 -and $quoted.StandardOutput -match 'quoted-ok') 'arguments containing spaces are quoted correctly'
}
finally {
  Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host ("RESULT: {0} passed, {1} failed" -f $script:passes, $script:failures.Count)
if ($script:failures.Count -gt 0) {
  $script:failures | ForEach-Object { Write-Host ("FAILED: {0}" -f $_) }
  exit 1
}
exit 0
