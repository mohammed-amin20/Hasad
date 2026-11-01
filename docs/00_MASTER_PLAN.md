# Hasad ERP V2 — Master Design & OpenCode Working Agreement

> **Status: DRAFT (sections updated 2026-10-20 to record approved decisions; architecture and requirements remain unapproved).**
> This file is a planning contract, **not proof** of the current database or implemented features.
> No destructive database action is authorized by this document.
> Approved decisions are recorded in `15_DECISION_LOG.md`; where this file and the
> decision log disagree, the decision log wins.

## 1. Objective
Rebuild Hasad ERP V2 as a completely new, clean-slate application with a documented, auditable, consistent database and application architecture. Hasad V1 source code and migrations must not be inspected, imported, or reused and must not determine V2 architecture; they exist only as legacy audit evidence in `docs/legacy_audit/`. Primary application context: Arabic Flutter (Windows + Android) ERP initialized at the repository root (`lib/`, `test/`, `pubspec.yaml`, `windows/`, `android/` — approved; do not move it into `app/`), offline-first SQLite client, Supabase/PostgreSQL backend. The existing Supabase DEV project (`sxasnunzspkuwbxiddqd`) is reused for V2, but its old database does not determine the V2 design.

## 2. Non-negotiable safety boundaries
- Hasad V1 source code and migrations must not be inspected, imported, quoted, or reused to determine V2 architecture (clean-slate rule).
- Never drop/truncate/delete existing Supabase tables or records during discovery, design, or ordinary code generation.
- **Production is out of scope.** Never connect to, modify, or reset production.
- Supabase DEV project reference (reused for V2): `sxasnunzspkuwbxiddqd`. The old database is legacy; it does not determine the V2 design.
- Do not assume the DEV environment is disposable. Assume every row matters until the operator says otherwise.
- A future DEV reset is a **separate operation** requiring its own explicit authorization; see `11_MIGRATION_AND_RESET_PLAN.md`.
- Do not touch Supabase-managed schemas/services (`auth`, `storage`, `realtime`, `extensions`, etc.) through arbitrary SQL; dropping the `public` schema alone is not a complete Supabase reset.
- Inventory and classify data, tables, views, RPCs, triggers, extensions, policies, grants, users, and storage before planning any reset.
- Verify a **recent full backup**, checksums, and where possible an isolated restore drill before any irreversible reset. Old checksum-only backups are insufficient proof of a working restore.
- Require a separate explicit approval naming the **exact DEV project**, objects, destructive method, and recovery plan before executing deletion.
- Never pass secrets in OpenCode prompts, transcripts, tracked files, or command arguments when avoidable.
- Never stage, commit, push, or modify tracked files without separate approval. Preserve pre-existing uncommitted work.
- During discovery, use SELECT-only SQL and read-only OpenCode Plan mode. The agent must not execute migration scripts or tests that write accounting records.

## 3. Single source of truth and decision labels
Every doc must include: status (`DRAFT`, `APPROVED`, `IMPLEMENTED`, `VERIFIED`), owner/reviewer, update date, open questions, dependencies, DB tables/RPCs, security rules, offline-sync rules, acceptance tests, and references to actual code or verified SQL catalog evidence.

**Evidence labels:**
- `OBSERVED`: verified in source code or live DEV catalog, with exact path/query and date.
- `PROPOSED`: a future design decision; must not be described as existing.
- `APPROVED`: explicitly accepted by the owner.
- `VERIFIED`: backed by tests or reproducible checks.

When code and docs disagree, stop and record the discrepancy; don't silently choose one.

## 4. Work stages / gates
1. **Legacy/environment inventory (reference only)** — Read-only, operator-driven inventory of the existing DEV project (objects, Auth users, Storage, integrations) to support the **future reset plan** only. Record it in `docs/legacy_audit/`. This inventory must not drive V2 design, and Hasad V1 code/migrations are not inspected.
2. **Requirements** — Define supported business flows, user roles, tenancy, numbering, currencies, posting/voiding, reporting, error cases and acceptance criteria. Mark decisions needing owner approval.
3. **Domain and accounting model** — Define immutable posted journal, balanced debits/credits, account chart, fiscal periods, and links from business documents to journals. No screens before domain invariants.
4. **Canonical schema** — One authoritative entity/relationship model, normalized table definitions, constraints, indexes, triggers, functions, tenancy, RLS and roles.
5. **Offline-first sync** — Define SQLite ownership, IDs (UUIDs), mutation queue, idempotency keys, conflict resolution, deletes/tombstones, retries, pagination, and reconciliation.
6. **Build plan** — Migrations in reviewable increments, seed/reference data, API contracts, Flutter layers/screens, test matrix, backup/restore and deployment runbooks.
7. **Implementation** — Implement one vertical feature end-to-end, run focused tests, review permissions, then continue. Never re-run historic migrations based on filenames alone.

**Release gates:** requirements approved → schema approved → security reviewed → backup/recovery verified → migration approved → focused tests green → next feature.

## 5. Documentation tree (actual, as of 2026-10-20)
The authoritative index, naming convention, and approval workflow live in `docs/README.md`.
```text
docs/
  README.md
  00_MASTER_PLAN.md
  02_REQUIREMENTS_AND_SCOPE.md
  03_DOMAIN_GLOSSARY.md
  04_ARCHITECTURE.md
  05_DATABASE_SCHEMA.md
  06_ENTITY_RELATIONSHIPS.md
  07_SECURITY_TENANCY_RLS.md
  08_OFFLINE_SYNC.md
  09_ACCOUNTING_INVARIANTS.md
  10_API_RPC_CONTRACTS.md
  11_MIGRATION_AND_RESET_PLAN.md
  12_BACKUP_AND_RECOVERY.md
  13_TEST_STRATEGY.md
  14_UI_ARABIC_RTL_STANDARDS.md
  15_DECISION_LOG.md
  FEATURE_SPEC_TEMPLATE.md
  features/
    01_tenants_and_users.md
    02_roles_and_permissions.md
    03_chart_of_accounts.md
    04_journals_and_fiscal_periods.md
    05_customers_and_suppliers.md
    06_sales_and_invoicing.md
    07_purchases.md
    08_inventory_and_warehouses.md
    09_cash_and_bank.md
    10_expenses.md
    11_employees_and_payroll.md
    12_reports.md
    13_settings_and_sequences.md
    14_sync_and_conflicts.md
  legacy_audit/
    README.md
    01_CURRENT_STATE_INVENTORY.md
    DEV_RESET_SAFETY_GATE.md
    LEGACY_BACKUP_OBSERVATIONS.md
```
Notes: prefix `01` is retired (legacy evidence ledger moved to `legacy_audit/`); the former duplicate `11_` file was moved to `legacy_audit/DEV_RESET_SAFETY_GATE.md` with content preserved. This tree is **a coverage checklist, not confirmed implemented functionality**. Add/remove feature files only after scope review.

## 6. Cross-cutting technical principles (proposed)
- Tenant isolation enforced at the database boundary, not only in Flutter.
- Deny privileges by default; grant minimum RPC/table access required per role.
- Financial transactions must be atomic, tenant-scoped, balanced, validated, and idempotent; never edit posted entries in place without an approved reversal/adjustment strategy.
- Use explicit constraints and foreign keys in PostgreSQL; SQLite must use corresponding local integrity rules.
- Reference data, customer-owned records, immutable records, and sync metadata have distinct lifecycle policies.
- Database migrations are forward-only, numbered, reviewed, recorded as actually deployed, and tested on disposable data.
- Changes to auth/storage/public API exposure require separate security review.
- Arabic RTL and keyboard usability are tested; presentation must not alter accounting semantics.

## 7. Per-feature design contract
Use `FEATURE_SPEC_TEMPLATE.md` for every module. Nothing moves to implementation until the feature has business scenarios, entities/relations, posting rules (if applicable), security, local sync behavior, validations, tests and unresolved questions documented and accepted.

## 8. DEV reset decision — NOT AUTHORIZED
**Approved (2026-10-20): V2 reuses the existing DEV project** (`sxasnunzspkuwbxiddqd`). The future reset must include removal of old Hasad business data, application-owned database objects, and old Supabase Auth users. The reset is a **separate operation** governed by `11_MIGRATION_AND_RESET_PLAN.md`; nothing here authorizes it.

A reset may be planned only when all are true:
1. A complete read-only inventory of affected database objects, Auth users, Storage data, and dependencies exists.
2. Scope includes exact schemas/tables/functions/storage/users to retain or remove, with an explicit decision on Storage objects, identities, external integrations, and migration history.
3. Dependencies and external integrations are inventoried.
4. Fresh full backup exists, checksum verified and isolated restoration tested where feasible.
5. New schema and migration plan are approved; rollback/recovery approach is documented.
6. Written approval expressly authorizes the exact destructive operation and environment.

Do not provide/run `DROP SCHEMA`, `TRUNCATE`, bulk `DELETE`, or dashboard reset actions as part of planning.

## 9. OpenCode operating agreement
- Start in **Plan mode**: read-only repo audit, list actual paths, findings and unknowns.
- Avoid sweeping rewrites; one small unit of work per task.
- Before Build, show files to create/edit and tests to run; wait for approval.
- Record changed files, tests performed, and anything not verified.
- No connection to DEV/PROD, destructive SQL, migrations, seed scripts, or backups unless the user separately permits that exact step.

## 10. Working task pattern for OpenCode
```text
Hasad ERP V2 — DOCUMENTATION OR DESIGN TASK (respect AGENTS.md)
Goal: advance the approved V2 specifications. Do not implement features whose
specs are not APPROVED. Never inspect Hasad V1 code or migrations; legacy DEV
observations live in docs/legacy_audit/ and are REFERENCE ONLY.
Read docs/README.md and docs/15_DECISION_LOG.md first.
Label every claim OBSERVED or PROPOSED and list unanswered questions.
No file edits outside the task scope; no database actions, commits, staging, or secret access.
Stop after the report or after the approved documentation change.
```

## 11. Decisions to ask the owner (not assumptions)
Resolved and recorded in `15_DECISION_LOG.md`: clean-slate V2 with no V1 reuse; Flutter stays at the repository root; reuse the existing DEV project; future reset includes old business data, application-owned objects, and old Auth users.
Still OPEN — must be answered, never invented:
- Which business modules are required for first release versus future scope?
- What are the roles, supported currencies, tax rules, document flows, and offline expectations?
- How is V2 schema isolation achieved inside the reused DEV project (naming, PostgREST exposure)?
- What happens to Storage objects, external integrations, and migration history at reset time?
