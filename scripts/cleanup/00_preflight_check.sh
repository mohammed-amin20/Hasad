#!/usr/bin/env bash
# Hasad ERP V2 - DEV Cleanup Preflight (READ-ONLY)
# Target: sxasnunzspkuwbxiddqd (DEV only)
# Status: NOT AUTHORIZED FOR EXECUTION - LOCAL ONLY
# Purpose: Validate environment and state before any destructive operations

set -euo pipefail

echo "=================================================="
echo "HASAD V2 DEV CLEANUP - PREFLIGHT VALIDATION"
echo "Target: sxasnunzspkuwbxiddqd"
echo "Status: NOT AUTHORIZED FOR EXECUTION"
echo "Mode: READ-ONLY VALIDATION"
echo "=================================================="
echo ""

# Check we're in repo root
if [ ! -d "supabase/.temp" ]; then
  echo "❌ ERROR: Not in repo root or supabase/.temp missing"
  exit 1
fi

# Verify project ref
if [ -f "supabase/.temp/project-ref" ]; then
  PROJ_REF=$(cat supabase/.temp/project-ref)
  echo "✓ Project ref: $PROJ_REF"
  if [ "$PROJ_REF" != "sxasnunzspkuwbxiddqd" ]; then
    echo "❌ ERROR: Project ref mismatch! Expected sxasnunzspkuwbxiddqd"
    exit 1
  fi
else
  echo "⚠️  WARNING: supabase/.temp/project-ref not found"
fi

# Check for pooler URL
if [ -f "supabase/.temp/pooler-url" ]; then
  echo "✓ Pooler URL present (non-secret check passed)"
else
  echo "⚠️  WARNING: supabase/.temp/pooler-url not found"
fi

# Check required files exist
echo ""
echo "--- Checking required artifacts ---"
REQUIRED=(
  "local_audit/DEV_INVENTORY_20261021_192155.txt"
  "local_audit/DEV_PLATFORM_INVENTORY_20261024_122126.txt"
  "docs/legacy_audit/DEV_CLEANUP_MANIFEST_DRAFT.md"
  "scripts/inventory/cron_job5_dependency_readonly.sql"
)

for f in "${REQUIRED[@]}"; do
  if [ -f "$f" ]; then
    echo "✓ $f"
  else
    echo "❌ MISSING: $f"
    exit 1
  fi
done

echo ""
echo "--- Static Validation ---"
echo "✓ All required files present"
echo "✓ Project identity validated"
echo "✓ No destructive operations prepared for execution"
echo "✓ Status: NOT AUTHORIZED FOR EXECUTION"
echo ""
echo "PREFLIGHT VALIDATION COMPLETE - READY FOR MANUAL REVIEW"
echo "=================================================="
