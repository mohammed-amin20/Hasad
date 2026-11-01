# =====================================================================
# Hasad ERP V2 - Supabase DEV read-only metadata inventory runner
# =====================================================================
# Purpose:
#   Runs scripts/inventory/dev_inventory_readonly.sql against the linked
#   Supabase DEV project (sxasnunzspkuwbxiddqd) and writes sanitized
#   catalog metadata to a gitignored local_audit/ folder.
#
# Safety contract:
#   * Run ONLY after the owner separately authorizes database inspection.
#   * The PostgreSQL password is entered at psql's own native terminal
#     prompt (-W). It is never placed in arguments, source files, logs,
#     repository files, environment variables or chat.
#   * The SQL file runs inside one BEGIN TRANSACTION READ ONLY /
#     ROLLBACK pair with a server-side fail-closed guard and
#     ON_ERROR_STOP=1.
#   * No application row data, no auth records, no hashes, no storage
#     contents, no secrets are read.
#   * Nothing here touches Supabase CLI state, Auth, Storage, or
#     project settings; this is a read-only metadata query only.
# =====================================================================

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------
# Locate the repository root by walking up until the linked-project
# marker is found (works regardless of the caller's working directory).
# ---------------------------------------------------------------------
$repoRoot = $PSScriptRoot
$marker = $null
for ($i = 0; $i -lt 5; $i++) {
    $candidate = Join-Path $repoRoot 'supabase\.temp\project-ref'
    if (Test-Path -LiteralPath $candidate) {
        $marker = $candidate
        break
    }
    $parent = Split-Path -Parent $repoRoot
    if ($parent -eq $repoRoot -or [string]::IsNullOrEmpty($parent)) { break }
    $repoRoot = $parent
}
if (-not $marker) {
    throw 'Linked Supabase project marker not found (supabase/.temp/project-ref). Link the DEV project first. No connection attempted.'
}

# ---------------------------------------------------------------------
# Fail-closed project identity guard (docs/11 Part B gate: exact project).
# Project ref and pooler URL are non-secret values stored by the CLI.
# ---------------------------------------------------------------------
$expectedRef = 'sxasnunzspkuwbxiddqd'
$expectedUrl = 'postgresql://postgres.sxasnunzspkuwbxiddqd@aws-0-ap-southeast-1.pooler.supabase.com:5432/postgres'

$projectRef = (Get-Content -LiteralPath $marker -Raw).Trim()
if ($projectRef -cne $expectedRef) {
    throw "Linked project ref '$projectRef' does not match expected '$expectedRef'. Refusing to run. No connection attempted."
}

$poolerUrlPath = Join-Path $repoRoot 'supabase\.temp\pooler-url'
if (-not (Test-Path -LiteralPath $poolerUrlPath)) {
    throw "Pooler URL file not found ($poolerUrlPath). No connection attempted."
}
$poolerUrl = (Get-Content -LiteralPath $poolerUrlPath -Raw).Trim()
if ($poolerUrl -cne $expectedUrl) {
    throw 'Pooler connection string does not match the previously verified non-secret endpoint. Refusing to run. No connection attempted.'
}
# Supabase pooler requires sslmode=require; append as query parameter to the URI
$poolerUrl = $poolerUrl + '?sslmode=require'

# ---------------------------------------------------------------------
# Locate the installed PostgreSQL 17 psql.exe (fail-closed version check).
# ---------------------------------------------------------------------
$psqlPath = $null
$candidates = @(
    'C:\Program Files\PostgreSQL\17\bin\psql.exe',
    (Join-Path ${env:ProgramFiles} 'PostgreSQL\17\bin\psql.exe')
)
foreach ($cand in $candidates) {
    if ($cand -and (Test-Path -LiteralPath $cand)) { $psqlPath = $cand; break }
}
if (-not $psqlPath) {
    $cmd = Get-Command 'psql.exe' -ErrorAction SilentlyContinue
    if ($cmd) { $psqlPath = $cmd.Source }
}
if (-not $psqlPath) {
    throw 'psql.exe not found (PostgreSQL 17). No connection attempted.'
}
$psqlVersion = (& $psqlPath --version | Out-String).Trim()
if ($psqlVersion -notmatch '\(PostgreSQL\) 17\.') {
    throw "psql.exe is not PostgreSQL 17 (found: $psqlVersion). Refusing to run. No connection attempted."
}

# ---------------------------------------------------------------------
# Inventory output (gitignored local audit directory, never a tracked doc).
# ---------------------------------------------------------------------
$sqlFile = Join-Path $PSScriptRoot 'dev_inventory_readonly.sql'
if (-not (Test-Path -LiteralPath $sqlFile)) {
    throw "Inventory SQL file not found ($sqlFile). No connection attempted."
}
$auditDir = Join-Path $repoRoot 'local_audit'
New-Item -ItemType Directory -Force -Path $auditDir | Out-Null
$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$outFile = Join-Path $auditDir "DEV_INVENTORY_$stamp.txt"

Write-Host '---------------------------------------------------------------------'
Write-Host 'Hasad ERP V2 - DEV read-only metadata inventory'
Write-Host "  Project ref : $projectRef"
Write-Host '  Transaction : READ ONLY (server-side fail-closed guard)'
Write-Host "  psql        : $psqlVersion"
Write-Host "  SQL         : $sqlFile"
Write-Host "  Output      : $outFile"
Write-Host '---------------------------------------------------------------------'
Write-Host 'This inspects catalog metadata only. No application data is read.'
Write-Host 'Run this only when database inspection has been separately authorized.'
Write-Host ''
$confirm = Read-Host 'Type YES to continue (anything else cancels without connecting)'
if ($confirm -cne 'YES') {
    Write-Host 'Cancelled. No database connection was attempted.'
    exit 2
}

Write-Host ''
Write-Host 'psql will now prompt for the PostgreSQL password directly on the'
Write-Host 'terminal (the password is not echoed and is never stored anywhere).'
Write-Host 'Connecting...'
Write-Host ''

# -X: ignore psqlrc | -W: native interactive password prompt
# -v ON_ERROR_STOP=1: abort on the first error (fail-closed)
# sslmode=require is appended to the connection URI above
# No password or credential is passed in any argument.
& $psqlPath -X -W -v ON_ERROR_STOP=1 -f $sqlFile -o $outFile $poolerUrl
$exitCode = $LASTEXITCODE

Write-Host ''
if ($exitCode -ne 0) {
    Write-Host "FAILED - psql exited with code $exitCode (error shown above)."
    Write-Host 'Any error aborts the run; the transaction is rolled back.'
    if (Test-Path -LiteralPath $outFile) {
        Write-Host "Partial output (if any): $outFile"
    }
    exit $exitCode
}

Write-Host "Inventory complete. Output: $outFile"
if (Test-Path -LiteralPath $outFile) {
    Write-Host '----- tail -----'
    Get-Content -LiteralPath $outFile -Tail 15
    Write-Host '----------------'
}
exit 0
