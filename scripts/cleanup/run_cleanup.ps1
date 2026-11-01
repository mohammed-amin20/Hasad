# =====================================================================
# Hasad ERP V2 - DEV CLEANUP MASTER ORCHESTRATOR (PowerShell) - FIXED
# =====================================================================
# Target: Supabase DEV project sxasnunzspkuwbxiddqd
# Status: NOT AUTHORIZED FOR EXECUTION
# Purpose: Orchestrate cleanup with strict guards and explicit authorization
# Windows-compatible
# =====================================================================

[CmdletBinding()]
param(
    [switch]$Execute = $false,
    [switch]$WhatIf = $true,
    [string]$AuthConfirmation = "",
    [string]$ProjectRef = "",
    [string]$ConnectionString = ""
)

function Write-SafeLog {
    param([string]$Message, [string]$Color = "White")
    Write-Host $Message -ForegroundColor $Color
}

function Test-ProjectConfirmation {
    param([string]$Ref, [string]$Confirm)
    if ($Ref -ne "sxasnunzspkuwbxiddqd") {
        throw "Project ref mismatch. Expected sxasnunzspkuwbxiddqd"
    }
    if ([string]::IsNullOrWhiteSpace($Confirm)) {
        throw "Project-specific confirmation missing"
    }
    # Require explicit confirmation token
    if ($Confirm -ne "CONFIRM_DELETE_V1_LEGACY_SXASNUNZSPKUWBXIDDQD") {
        throw "Project-specific confirmation missing. Required: CONFIRM_DELETE_V1_LEGACY_SXASNUNZSPKUWBXIDDQD"
    }
    return $true
}

function Invoke-CleanupSqlStage {
    param(
        [string]$StageName,
        [string]$SqlFile,
        [bool]$IsExecute,
        [string]$ConnStr
    )
    
    if (-not (Test-Path $SqlFile)) {
        throw "SQL file not found: $SqlFile"
    }
    
    $mode = if ($IsExecute) { "EXECUTE" } else { "DRY_RUN" }
    $authorized = if ($IsExecute) { "true" } else { "false" }
    
    Write-SafeLog "Running stage $StageName in mode $mode" "Cyan"
    
    # Build psql command with session variables for authorization
    # Using SET LOCAL via -v or via SQL
    $psqlArgs = @(
        "-v", "cleanup_authorized=$authorized",
        "-v", "cleanup_project=sxasnunzspkuwbxiddqd",
        "-v", "cleanup_mode=$mode",
        "-f", $SqlFile
    )
    
    if (-not [string]::IsNullOrWhiteSpace($ConnStr)) {
        $psqlArgs = @("-d", $ConnStr) + $psqlArgs
    }
    
    # For safety, we don't actually execute - just validate
    Write-SafeLog "  Command would be: psql $($psqlArgs -join ' ')" "Gray"
    Write-SafeLog "  Authorization: $authorized, Project: sxasnunzspkuwbxiddqd, Mode: $mode" "Gray"
    
    return @{Stage=$StageName; Mode=$mode; Authorized=$authorized; Status="VALIDATED"}
}

# Enforce authorization rules
if ($Execute -and -not $WhatIf) {
    Write-SafeLog "AUTHORIZATION GATE TRIGGERED" "Red"
    try {
        Test-ProjectConfirmation -Ref $ProjectRef -Confirm $AuthConfirmation | Out-Null
        Write-SafeLog "Project confirmation validated" "Green"
        Write-SafeLog "WARNING: Execution mode requires explicit authorization and will COMMIT only if all stages pass" "Red"
    } catch {
        Write-SafeLog $_.Exception.Message "Red"
        Write-SafeLog "ABORTING" "Red"
        exit 1
    }
} elseif (-not $WhatIf) {
    Write-SafeLog "FATAL: Must use -WhatIf:`$true for dry-run or proper authorization for execute" "Red"
    exit 1
}

Write-SafeLog "==================================================" "Cyan"
Write-SafeLog "HASAD V2 DEV CLEANUP ORCHESTRATOR (FIXED)" "Cyan"
Write-SafeLog "Target: sxasnunzspkuwbxiddqd" "Yellow"
Write-SafeLog "Status: $(if($Execute -and -not $WhatIf){'AUTHORIZED (EXECUTE)'}else{'NOT AUTHORIZED (DRY-RUN/WHATIF)'})" $(if($Execute -and -not $WhatIf){'Red'}else{'Green'})
Write-SafeLog "==================================================" "Cyan"
Write-SafeLog ""

Write-SafeLog "[ORDER]" "Yellow"
Write-SafeLog "0. Preflight: 00_preflight_check.sh + inventory verification" "White"
Write-SafeLog "0.5. Resolve auth.user IDs BEFORE dropping public.users (capture securely, never log)" "White"
Write-SafeLog "1. Cron: 01_remove_cron_job5.sql" "White"
Write-SafeLog "2. Triggers: 02_drop_triggers.sql" "White"
Write-SafeLog "3. RLS Policies: 03_drop_rls_policies.sql (53/53 exact reconciliation, public only)" "White"
Write-SafeLog "3b. Storage Policies: 03b_remove_legacy_storage_policies.sql (3 exact policies on storage.objects - SEPARATE AUTHORIZATION, own scope token; NOT wired into this orchestrator)" "White"
Write-SafeLog "4. Functions: 04_drop_functions.sql (only after 3b; fail-closed all-class dependency scan)" "White"
Write-SafeLog "5. Tables: 05_drop_tables.sql (FK leaf-first)" "White"
Write-SafeLog "6. Auth: 06_remove_auth_users.ps1 (Auth Admin API only, no direct SQL)" "White"
Write-SafeLog "7. Storage: 07_remove_storage_bucket.ps1 (empty check required)" "White"
Write-SafeLog "8. Verify: 08_post_cleanup_verify.sql" "White"
Write-SafeLog ""

Write-SafeLog "[GUARDS - FAIL-CLOSED]" "Yellow"
Write-SafeLog "- Project-bound authorization via orchestrator params" "White"
Write-SafeLog "- SQL stages check cleanup.authorized/project/mode session vars" "White"
Write-SafeLog "- BEGIN; all destructive ops; COMMIT only in EXECUTE mode after assertions pass" "White"
Write-SafeLog "- DRY_RUN/unauthorized → ROLLBACK (never commit)" "White"
Write-SafeLog "- Standalone SQL execution without auth vars → fails immediately" "White"
Write-SafeLog "- Exact policy reconciliation (53/53) with fail on mismatch" "White"
Write-SafeLog "- Auth IDs captured before table drops; no identifiers/credentials logged" "White"
Write-SafeLog "- Protected schemas/extensions/pgtap/pg_net preserved" "White"
Write-SafeLog "- No DROP SCHEMA" "White"
Write-SafeLog ""

# Validate stages (dry-run)
$isExec = $Execute -and -not $WhatIf
$stages = @(
    @{Name="03_policies"; File="scripts/cleanup/03_drop_rls_policies.sql"}
)
foreach ($s in $stages) {
    try {
        Invoke-CleanupSqlStage -StageName $s.Name -SqlFile $s.File -IsExecute $isExec -ConnStr $ConnectionString | Out-Null
        Write-SafeLog "✓ Stage $($s.Name) validated" "Green"
    } catch {
        Write-SafeLog "✗ Stage $($s.Name) failed: $($_.Exception.Message)" "Red"
        exit 1
    }
}

Write-SafeLog ""
Write-SafeLog "All local. NOT EXECUTED. No database connections made." "Red"
Write-SafeLog "==================================================" "Cyan"
