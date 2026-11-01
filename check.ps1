# =====================================================================
# Hasad ERP V2 - LOCAL STATIC VALIDATION (NO DATABASE CONNECTION)
# =====================================================================
# Target: Supabase DEV project sxasnunzspkuwbxiddqd
# Status: LOCAL ONLY - text checks on prepared scripts; never connects,
#         never executes SQL, never changes any file.
#
# Usage (from the repository root):
#   powershell -NoProfile -ExecutionPolicy Bypass -File .\check.ps1
# Exit code 0 = every check passed; 1 = at least one check failed.
# =====================================================================

$script:failed = 0

function Fail {
    param([string]$Message)
    Write-Host "FAIL: $Message" -ForegroundColor Red
    $script:failed = 1
}

function Pass {
    param([string]$Message)
    Write-Host "OK  : $Message" -ForegroundColor Green
}

# ---------------------------------------------------------------------
# 1. Generic prepared-script checks (all cleanup stages)
# ---------------------------------------------------------------------
$files = @(
    'scripts/cleanup/01_remove_cron_job5.sql',
    'scripts/cleanup/02_drop_triggers.sql',
    'scripts/cleanup/03_drop_rls_policies.sql',
    'scripts/cleanup/03b_remove_legacy_storage_policies.sql',
    'scripts/cleanup/04_drop_functions.sql',
    'scripts/cleanup/05_drop_tables.sql'
)

foreach ($f in $files) {
    if (-not (Test-Path -LiteralPath $f)) {
        Fail "$f : file missing"
        continue
    }

    $content = Get-Content -LiteralPath $f -Raw
    $missing = @()
    foreach ($needle in @('AUTHORIZATION REQUIRED', 'BEGIN;', 'ROLLBACK;')) {
        if ($content -notmatch [regex]::Escape($needle)) { $missing += $needle }
    }

    if ($missing.Count -gt 0) {
        Fail "$f : missing marker(s): $($missing -join ', ')"
    } else {
        Pass "$f : authorization gate + explicit transaction markers"
    }
}

# ---------------------------------------------------------------------
# 2. Stage 3b specific checks (the new storage.objects scope)
# ---------------------------------------------------------------------
$f3b = 'scripts/cleanup/03b_remove_legacy_storage_policies.sql'
if (-not (Test-Path -LiteralPath $f3b)) {
    Fail "$f3b : file missing"
} else {
    $raw   = Get-Content -LiteralPath $f3b -Raw
    # Code lines only: drop full-line comments so prose such as "no CASCADE"
    # in the header cannot satisfy or trip a token check.
    $lines = Get-Content -LiteralPath $f3b
    $code  = @($lines | Where-Object { $_ -notmatch '^\s*--' })
    $codeText = ($code -join "`n")

    # 2.1 Exact authorization binding + separate scope token
    if ($raw -match 'sxasnunzspkuwbxiddqd') {
        Pass "03b: project ref literal present"
    } else {
        Fail "03b: project ref literal missing"
    }
    if ($raw -match 'CONFIRM_DROP_3_LEGACY_PDF_POLICIES_SXASNUNZSPKUWBXIDDQD') {
        Pass "03b: separate scope token present"
    } else {
        Fail "03b: separate scope token missing"
    }
    if ($raw -match 'cleanup_storage_policy_scope') {
        Pass "03b: separate scope GUC wired"
    } else {
        Fail "03b: separate scope GUC missing"
    }
    if ($raw -match "current_database\(\)\s+IS\s+DISTINCT\s+FROM\s+'postgres'") {
        Pass "03b: connected-database guard present"
    } else {
        Fail "03b: connected-database guard missing"
    }

    # 2.2 Exactly three DROP POLICY statements, exact identities + relation
    $dropPattern = '(?m)^[ \t]*DROP\s+POLICY\s+"(tenant_isolated_pdf_select|tenant_isolated_pdf_insert|tenant_isolated_pdf_delete)"\s+ON\s+storage\.objects;[ \t]*$'
    $dropMatches = [regex]::Matches($codeText, $dropPattern)
    if ($dropMatches.Count -ne 3) {
        Fail "03b: expected exactly 3 DROP POLICY ... ON storage.objects statements, found $($dropMatches.Count)"
    } else {
        $names = @($dropMatches | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
        if ($names.Count -eq 3) {
            Pass "03b: exactly 3 DROP POLICY statements, 3 unique authorized names"
        } else {
            Fail "03b: DROP POLICY names are not the 3 unique authorized policies"
        }
    }

    # 2.3 No DROP IF EXISTS (presence must be proven in the same transaction)
    if ($codeText -match 'DROP\s+POLICY\s+IF\s+EXISTS') {
        Fail "03b: DROP POLICY IF EXISTS is forbidden"
    } else {
        Pass "03b: no DROP POLICY IF EXISTS"
    }

    # 2.4 No forbidden DDL / data statements (code lines only)
    $forbidden = @(
        @{ Name = 'CASCADE';        Pattern = '\bCASCADE\b' },
        @{ Name = 'DROP SCHEMA';    Pattern = '\bDROP\s+SCHEMA\b' },
        @{ Name = 'DROP TABLE';     Pattern = '\bDROP\s+TABLE\b' },
        @{ Name = 'ALTER TABLE';    Pattern = '\bALTER\s+TABLE\b' },
        @{ Name = 'ALTER POLICY';   Pattern = '\bALTER\s+POLICY\b' },
        @{ Name = 'CREATE POLICY';  Pattern = '\bCREATE\s+POLICY\b' },
        @{ Name = 'GRANT';          Pattern = '(?m)^[ \t]*GRANT\b' },
        @{ Name = 'REVOKE';         Pattern = '(?m)^[ \t]*REVOKE\b' },
        @{ Name = 'TRUNCATE';       Pattern = '(?m)^[ \t]*TRUNCATE\b' },
        @{ Name = 'DELETE FROM';    Pattern = '\bDELETE\s+FROM\b' },
        @{ Name = 'INSERT INTO';    Pattern = '\bINSERT\s+INTO\b' },
        @{ Name = 'UPDATE ... SET'; Pattern = '\bUPDATE\s+[A-Za-z_][A-Za-z0-9_."]*\s+SET\b' }
    )
    $badTokens = @()
    foreach ($rule in $forbidden) {
        if ($codeText -match $rule.Pattern) { $badTokens += $rule.Name }
    }
    if ($badTokens.Count -gt 0) {
        Fail "03b: forbidden statement token(s) in executable code: $($badTokens -join ', ')"
    } else {
        Pass "03b: no CASCADE / schema-wide / ALTER / GRANT / DML statements"
    }

    # 2.5 Expected-state expectations match the captured diagnostic
    if ($raw -match "ARRAY\['r',\s*'a',\s*'d'\]") {
        Pass "03b: command expectations = SELECT/INSERT/DELETE (r,a,d)"
    } else {
        Fail "03b: command expectation array missing or changed"
    }
    if ($raw -match 'ARRAY\[true,\s*false,\s*true\]') {
        Pass "03b: USING-expression expectations = select/insert/delete"
    } else {
        Fail "03b: USING-expression expectation array missing or changed"
    }
    if ($raw -match 'ARRAY\[false,\s*true,\s*false\]') {
        Pass "03b: WITH CHECK-expression expectations = select/insert/delete"
    } else {
        Fail "03b: WITH CHECK-expression expectation array missing or changed"
    }
    if ($raw -match [regex]::Escape('public.get_my_tenant_id()|storage.foldername(name text)')) {
        Pass "03b: exact policy dependency set matches diagnostic"
    } else {
        Fail "03b: exact policy dependency set missing or changed"
    }

    # 2.6 DRY_RUN = checks + ROLLBACK; EXECUTE = drops + verify + COMMIT
    foreach ($needle in @('\gset', '\if :exec_flag_bool', '\else', '\endif')) {
        if (-not $raw.Contains($needle)) {
            Fail "03b: missing psql control marker '$needle'"
        }
    }
    $beginCount   = ([regex]::Matches($codeText, '(?m)^[ \t]*BEGIN;[ \t]*$')).Count
    $commitCount  = ([regex]::Matches($codeText, '(?m)^[ \t]*COMMIT;[ \t]*$')).Count
    $rollbackCount = ([regex]::Matches($codeText, '(?m)^[ \t]*ROLLBACK;[ \t]*$')).Count
    if ($beginCount -eq 1 -and $commitCount -eq 1 -and $rollbackCount -eq 1) {
        Pass "03b: exactly one BEGIN, one conditional COMMIT, one DRY_RUN ROLLBACK"
    } else {
        Fail "03b: transaction control counts are BEGIN=$beginCount COMMIT=$commitCount ROLLBACK=$rollbackCount (expected 1/1/1)"
    }

    # 2.7 Post-drop verification present before COMMIT
    foreach ($needle in @('VERIFIED REMOVED', 'fingerprint unchanged', 'still depend on public.get_my_tenant_id()')) {
        if ($raw -notmatch [regex]::Escape($needle)) {
            Fail "03b: post-drop verification marker missing: $needle"
        }
    }
    $commitPos = $codeText.IndexOf('COMMIT;')
    $verifyPos = $codeText.IndexOf('VERIFIED REMOVED')
    if ($commitPos -gt 0 -and $verifyPos -gt 0 -and $verifyPos -lt $commitPos) {
        Pass "03b: post-drop verification appears before COMMIT"
    } else {
        Fail "03b: post-drop verification is missing or appears after COMMIT"
    }

    # 2.8 Balanced dollar-quote blocks
    foreach ($tag in @('cleanup_authz', 'verify_storage_policies_exact', 'verify_after')) {
        $count = ([regex]::Matches($raw, '\$' + [regex]::Escape($tag) + '\$')).Count
        if ($count -ne 2) {
            Fail "03b: dollar-quote tag '$tag' appears $count time(s), expected 2"
        }
    }

    # 2.9 No shell escapes / file inclusion / COPY meta-commands
    #     (\if and \ir are distinguished by the required argument separator)
    if ($raw -match '(?m)^[ \t]*\\(!|i[ \t]|ir[ \t]|include[ \t]|copy[ \t])') {
        Fail "03b: psql shell-escape or file-include meta-command found"
    } else {
        Pass "03b: no psql shell escape or file inclusion"
    }
}

Write-Host ''
if ($script:failed -ne 0) {
    Write-Host 'STATIC VALIDATION: FAILED (no database was contacted)' -ForegroundColor Red
    exit 1
}

Write-Host 'STATIC VALIDATION: ALL CHECKS PASSED (no database was contacted)' -ForegroundColor Green
exit 0
