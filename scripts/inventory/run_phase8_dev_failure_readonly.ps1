# Hasad ERP V2 - read-only Phase 8 failed-deployment catalog check.
# Uses the repository's existing DEV pooler + native psql -W authentication.
# No password is read, stored, logged, or passed by this script.
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$expectedRef = 'sxasnunzspkuwbxiddqd'
$expectedUrl = 'postgresql://postgres.sxasnunzspkuwbxiddqd@aws-0-ap-southeast-1.pooler.supabase.com:5432/postgres'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$projectRefFile = Join-Path $repoRoot 'supabase\.temp\project-ref'
$poolerUrlFile = Join-Path $repoRoot 'supabase\.temp\pooler-url'
$sqlFile = Join-Path $PSScriptRoot 'phase8_dev_failure_readonly.sql'

if (-not (Test-Path -LiteralPath $projectRefFile -PathType Leaf)) { throw 'DEV project-ref marker is missing; no connection attempted.' }
$projectRef = (Get-Content -LiteralPath $projectRefFile -Raw).Trim()
if ($projectRef -cne $expectedRef) { throw 'Local linked project ref does not match authorized DEV; no connection attempted.' }
if (-not (Test-Path -LiteralPath $poolerUrlFile -PathType Leaf)) { throw 'Existing verified pooler endpoint is missing; no connection attempted.' }
$poolerUrl = (Get-Content -LiteralPath $poolerUrlFile -Raw).Trim()
if ($poolerUrl -cne $expectedUrl) { throw 'Pooler endpoint does not match verified DEV endpoint; no connection attempted.' }
$poolerUrl += '?sslmode=require'
if (-not (Test-Path -LiteralPath $sqlFile -PathType Leaf)) { throw 'Read-only catalog SQL file is missing; no connection attempted.' }

$psql = $null
$psqlCandidates = @('C:\Program Files\PostgreSQL\17\bin\psql.exe', (Join-Path ${env:ProgramFiles} 'PostgreSQL\17\bin\psql.exe'))
foreach ($candidate in $psqlCandidates) {
    if ($candidate -and (Test-Path -LiteralPath $candidate -PathType Leaf)) { $psql = $candidate; break }
}
if (-not $psql) { $psqlCommand = Get-Command 'psql.exe' -ErrorAction SilentlyContinue; if ($psqlCommand) { $psql = $psqlCommand.Source } }
if (-not $psql) { throw 'psql.exe not found; no connection attempted.' }
$versionOutput = (& $psql --version | Out-String).Trim()
if ($versionOutput -notmatch '\(PostgreSQL\) 17\.') { throw 'psql is not PostgreSQL 17; no connection attempted.' }

$auditDir = Join-Path $repoRoot 'local_audit'
New-Item -ItemType Directory -Force -Path $auditDir | Out-Null
$outputFile = Join-Path $auditDir ('PHASE8_FAILURE_CATALOG_{0}.txt' -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
Write-Host "Read-only catalog check for DEV ref $projectRef using $versionOutput."
Write-Host 'The SQL reads PostgreSQL catalog metadata only and ends with ROLLBACK.'
Write-Host "Output file: $outputFile"
$confirmation = Read-Host 'Type YES to connect (anything else cancels)'
if ($confirmation -cne 'YES') { Write-Host 'Cancelled; no connection attempted.'; exit 2 }
Write-Host 'psql will prompt directly for its database password. Do not paste it into PowerShell or chat.'
& $psql -X -W -v ON_ERROR_STOP=1 -f $sqlFile -o $outputFile $poolerUrl
$exitCode = $LASTEXITCODE
if ($exitCode -ne 0) { Write-Host "Read-only psql check failed with exit code $exitCode. Review the local psql diagnostic privately."; exit $exitCode }
Write-Host "Read-only catalog check complete: $outputFile"
exit 0
