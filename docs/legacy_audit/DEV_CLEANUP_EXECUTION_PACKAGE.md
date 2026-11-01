# Hasad ERP V2 — Cleanup Execution Package (Final Review)

**Status:** DRAFT — NOT AUTHORIZED FOR EXECUTION  
**Target:** Supabase DEV `sxasnunzspkuwbxiddqd`  
**Created:** Local files only. No connections, no SQL, no deletions.  

## Purpose
Convert approved-scope documentation into precise, reviewable execution artifacts for retiring Hasad V1.

## Files Created
- `scripts/cleanup/cleanup_preflight_checklist.md`
- `scripts/cleanup/cleanup_execution_checklist.md`
- `scripts/cleanup/cleanup_protected_objects.txt`
- `scripts/cleanup/v2_build_starting_plan.md`
- `scripts/inventory/cron_job5_dependency_readonly.sql` (prepared earlier)

## Scope Summary
See `docs/legacy_audit/DEV_CLEANUP_MANIFEST_DRAFT.md` for full details:
- 22 public tables, 33 functions (with full signatures), 6 triggers, 53 policies **in `public`**, 52 indexes, 110 constraints
- **3 application policies on `storage.objects`** (`tenant_isolated_pdf_select/_insert/_delete`) — **NEW, separate scope item (D-029)**; Stage 3b must run before Stage 4 (updated 2026-10-25)
- Cron jobid 5 (send-due-reminders-daily) - UNRESOLVED dependency, must handle first
- 4 auth.users linked to public.users - remove via Auth Admin tooling
- Bucket pdfs (0 objects) - remove via Storage tooling if confirmed
- Protected: managed schemas, roles, extensions (pgtap, pg_net), platform keys

## Safety
- No automatic execution
- Distinct stages (DB/Auth/Storage)
- No schema-wide CASCADE
- Fail-safe on unexpected findings
- D-026 waiver noted (permanent data loss possible)
- D-027 scope only
