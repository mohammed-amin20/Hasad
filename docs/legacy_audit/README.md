# Legacy Audit â€” REFERENCE ONLY â€” NOT V2 DESIGN

Everything in this folder is a preserved observation about the **old** Hasad
environment: the previous Supabase DEV project (`sxasnunzspkuwbxiddqd`), prior
reports, and legacy backup findings.

## Rules
- **Never** derive V2 architecture, schema, roles, or business rules from these
  files. Hasad V1 source/migrations are not inspected or reused (approved D-008).
- These files exist for environment/reset planning and historical traceability only.
- Content is preserved **verbatim**; only the "REFERENCE ONLY" headers were added
  when the files were moved here (2026-10-20).
- The authoritative reset plan is `../11_MIGRATION_AND_RESET_PLAN.md` (Part B).
- The authoritative decision register is `../15_DECISION_LOG.md`.

## Contents
| File | What it preserves | Original location |
|---|---|---|
| `01_CURRENT_STATE_INVENTORY.md` | Evidence ledger of verified DEV catalog checks (2026-10-19) and unknowns | `docs/01_CURRENT_STATE_INVENTORY.md` |
| `DEV_RESET_SAFETY_GATE.md` | Historical safety/approval gate checklist for a DEV reset, plus prior findings to preserve | `docs/11_DEV_RESET_SAFETY_GATE.md` |
| `LEGACY_BACKUP_OBSERVATIONS.md` | Legacy backup findings extracted from `12_BACKUP_AND_RECOVERY.md` | bullets in `docs/12_BACKUP_AND_RECOVERY.md` |
| `DEV_CLEANUP_MANIFEST_DRAFT.md` | DRAFT object-scoped cleanup manifest derived from the verified 2026-10-21 inventory (no destructive SQL; not authorized) | new (2026-10-21) |
# legacy_audit — REFERENCE ONLY — NOT V2 DESIGN

This directory contains legacy DEV/V1 observations preserved for environment/reference purposes only.
They must **never** be used to derive V2 architecture, schema, or implementation.

Contents:
- 01_CURRENT_STATE_INVENTORY.md — Legacy evidence ledger (OBSERVED about old DEV project; not a V2 specification)
- DEV_RESET_SAFETY_GATE.md — Legacy safety-gate checklist/notes for the existing DEV project (REFERENCE ONLY)
- LEGACY_BACKUP_OBSERVATIONS.md — Extracted legacy backup observations from older docs (REFERENCE ONLY)
