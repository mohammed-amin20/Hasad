# =====================================================================
# Hasad ERP V2 - Supabase DEV read-only PLATFORM metadata inventory runner
# =====================================================================
# Purpose:
#   Runs scripts/inventory/dev_platform_inventory_readonly.sql against the
#   linked Supabase DEV project (sxasnunzspkuwbxiddqd) and writes sanitized
#   platform metadata (Auth counts, Storage/Gateway/Edge/cron/webhook/vault
#   names) to a gitignored local_audit/ folder.
#
# Safety contract (identical guarantees to run_dev_inventory.ps1):
#   * Run ONLY after the owner separately authorizes database inspection.
#   * The PostgreSQL password is entered at psql's own native terminal
#     prompt (-W). It is never placed in arguments, source files, logs,
#     repository files, environment variables or chat.
#   * The SQL file runs inside one BEGIN TRANSACTION READ ONLY /
#     ROLLBACK pair with a server-side fail-closed guard and
#     ON_ERROR_STOP=1.
#   * Metadata only: no user emails, phones, password hashes, tokens,
#     session payloads, storage paths/contents, function source, cron
#     payloads or secret VALUES are read.
# * Nothing here touches Supabase CLI state, Auth, Storage, Edge
#   Functions or project settings; this is a read-only metadata query.
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
$sqlFile = Join-Path $PSScriptRoot 'dev_platform_inventory_readonly.sql'
if (-not (Test-Path -LiteralPath $sqlFile)) {
    throw "Platform inventory SQL file not found ($sqlFile). No connection attempted."
}
$auditDir = Join-Path $repoRoot 'local_audit'
New-Item -ItemType Directory -Force -Path $auditDir | Out-Null
$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$outFile = Join-Path $auditDir "DEV_PLATFORM_INVENTORY_$stamp.txt"

Write-Host '---------------------------------------------------------------------'
Write-Host 'Hasad ERP V2 - DEV read-only PLATFORM metadata inventory'
Write-Host "  Project ref : $projectRef"
Write-Host '  Transaction : READ ONLY (server-side fail-closed guard)'
Write-Host "  psql        : $psqlVersion"
Write-Host "  SQL         : $sqlFile"
Write-Host "  Output      : $outFile"
Write-Host '---------------------------------------------------------------------'
Write-Host 'This inspects Auth/Storage/Functions/cron/webhook/vault metadata only.'
Write-Host 'No emails, tokens, hashes, file contents, code or secret values.'
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

    # Evidence-based failure classification (no rollback claim unless a
    # transaction actually started). psql only writes its statement
    # acknowledgements (SET / BEGIN / ROLLBACK) to the -o file AFTER a
    # successful connection. A 0-byte output therefore proves the failure
    # happened during connection establishment - before any transaction,
    # so nothing was rolled back and no SQL was executed.
    $outBytes = 0
    if (Test-Path -LiteralPath $outFile) {
        $outBytes = (Get-Item -LiteralPath $outFile).Length
    }
    if ($outBytes -eq 0) {
        Write-Host 'Diagnosis: FAILURE AT CONNECTION PHASE.'
        Write-Host '  The output file is empty, so psql never connected and no'
        Write-Host '  transaction was started. Nothing was executed and nothing'
        Write-Host '  was rolled back. The remote database was not modified.'
        Write-Host '  This is typically a transient/pooler-side rejection or a'
        Write-Host '  password-entry/terminal issue, not a SQL error.'
    }
    else {
        Write-Host 'Diagnosis: FAILURE AFTER CONNECT (SQL or guard error).'
        Write-Host "  Partial output (with rollback marker if reached): $outFile"
        if (Select-String -LiteralPath $outFile -Pattern '^ROLLBACK' -Quiet) {
            Write-Host '  A ROLLBACK line is present: the read-only transaction was rolled back.'
        }
        else {
            Write-Host '  No ROLLBACK line found: the transaction may not have reached ROLLBACK;'
            Write-Host '  treat the session as aborted by ON_ERROR_STOP (no committed change).'
        }
    }
    exit $exitCode
}

Write-Host "Platform inventory complete. Output: $outFile"
if (Test-Path -LiteralPath $outFile) {
    Write-Host '----- tail -----'
    Get-Content -LiteralPath $outFile -Tail 20
    Write-Host '----------------'
}
exit 0
