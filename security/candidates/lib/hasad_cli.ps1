# Hasad ERP V2 — shared CLI transport and payload parsing for the bootstrap operator runner.
# This file must never handle, receive, or emit operator identity values.

function Invoke-HasadCliFile {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$CliPath,
    [Parameter(Mandatory)][string[]]$Arguments,
    [Parameter(Mandatory)][string]$StandardOutputPath,
    [Parameter(Mandatory)][string]$StandardErrorPath
  )

  foreach ($p in @($StandardOutputPath, $StandardErrorPath)) {
    if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue }
  }

  # Quote arguments that contain whitespace so paths with spaces survive.
  # Windows paths cannot contain a double quote, so no escaping is needed and
  # cmd.exe (unlike CRT-style parsers) must not receive backslash-escaped quotes.
  $quoted = foreach ($a in $Arguments) {
    if ($a -match '\s') { '"' + $a + '"' } else { $a }
  }

  # OS-level redirection: independent of PowerShell stream capture, so a chatty
  # .cmd shim can never abort the run or leak its payload to the console.
  $proc = Start-Process -FilePath $CliPath -ArgumentList $quoted `
    -RedirectStandardOutput $StandardOutputPath `
    -RedirectStandardError $StandardErrorPath `
    -Wait -PassThru -NoNewWindow

  $stdout = ''
  $stderr = ''
  if (Test-Path -LiteralPath $StandardOutputPath) { $stdout = Get-Content -Raw -LiteralPath $StandardOutputPath }
  if (Test-Path -LiteralPath $StandardErrorPath) { $stderr = Get-Content -Raw -LiteralPath $StandardErrorPath }
  if ($null -eq $stdout) { $stdout = '' }
  if ($null -eq $stderr) { $stderr = '' }

  [pscustomobject]@{
    ExitCode       = [int]$proc.ExitCode
    StandardOutput = [string]$stdout
    StandardError  = [string]$stderr
    OutputLength   = ([string]$stdout).Length
    ErrorLength    = ([string]$stderr).Length
  }
}

# Extracts a single-line base64 payload emitted as MARKER=<base64 utf8 json>.
# Base64 survives JSON string escaping and pretty-printing, so the payload can be
# found anywhere in the CLI output without parsing the CLI envelope.
function ConvertFrom-HasadBase64Payload {
  [CmdletBinding()]
  param(
    [AllowNull()][AllowEmptyString()][string]$Text,
    [Parameter(Mandatory)][string]$Marker
  )

  if ([string]::IsNullOrEmpty($Text)) { return $null }

  $match = [regex]::Match($Text, [regex]::Escape($Marker) + '([A-Za-z0-9+/=]+)')
  if (-not $match.Success) { return $null }

  $b64 = $match.Groups[1].Value
  if ([string]::IsNullOrEmpty($b64)) { return $null }

  try {
    $json = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($b64))
    return ($json | ConvertFrom-Json)
  } catch {
    return $null
  }
}

# Converts a required property of a parsed payload into a non-negative integer,
# refusing null rather than silently treating it as zero.
function Get-HasadPayloadInt {
  [CmdletBinding()]
  param(
    [AllowNull()]$Payload,
    [Parameter(Mandatory)][string]$Name
  )
  if ($null -eq $Payload) { throw "PAYLOAD_MISSING_FOR:$Name" }
  $prop = $Payload.PSObject.Properties[$Name]
  if ($null -eq $prop -or $null -eq $prop.Value) { throw "PAYLOAD_PROPERTY_MISSING:$Name" }
  return [int]$prop.Value
}

# Converts a required boolean property of a parsed payload, refusing null.
function Get-HasadPayloadBool {
  [CmdletBinding()]
  param(
    [AllowNull()]$Payload,
    [Parameter(Mandatory)][string]$Name
  )
  if ($null -eq $Payload) { throw "PAYLOAD_MISSING_FOR:$Name" }
  $prop = $Payload.PSObject.Properties[$Name]
  if ($null -eq $prop -or $null -eq $prop.Value) { throw "PAYLOAD_PROPERTY_MISSING:$Name" }
  return [bool]$prop.Value
}
