# Hasad ERP V2 — OpenCode Working Agreement

This file defines the permanent rules OpenCode must follow in this repository.
Precedence: explicit owner instructions in the current conversation > this file > `docs/`. The authoritative documentation index is `docs/README.md`.

## 1. Status and single source of truth
- `docs/` is the single source of truth for every design decision. One topic, one document.
- Document status flow: `DRAFT` → `APPROVED` → `IMPLEMENTED` → `VERIFIED`. No code or SQL may be written for a feature whose specification is not `APPROVED`.
- Evidence labels for every claim: `OBSERVED` / `PROPOSED` / `APPROVED` / `VERIFIED`.
- When code, docs, or the operator disagree: stop, record the discrepancy in `docs/15_DECISION_LOG.md`, and ask the owner. Never silently choose one side.
- `docs/legacy_audit/` is **REFERENCE ONLY — NOT V2 DESIGN**. It preserves legacy DEV/V1 observations and must never be used to derive V2 architecture or schema.

## 2. Clean-slate rule (Hasad V1)
- Hasad V2 is a completely clean-slate design.
- Do **NOT** inspect, import, quote, or reuse Hasad V1 source code, migrations, or database objects to determine V2 architecture. V1 exists only as legacy audit evidence.

## 3. Fixed safety boundaries
- No connection to Supabase or any database. No SQL execution, migrations, resets, seeds, backups, or restores — unless the owner separately and explicitly authorizes that exact step by name.
- No creation, modification, or deletion of database objects. The existing DEV project (`sxasnunzspkuwbxiddqd`) is reused for V2, but its old database must not determine the V2 design.
- Any future DEV reset is a separate operation requiring its own explicit authorization (see `docs/11_MIGRATION_AND_RESET_PLAN.md`). Dropping the `public` schema does not reset Supabase completely. Supabase-managed schemas (`auth`, `storage`, `realtime`, `extensions`, `cron`, etc.) must never be altered through arbitrary SQL, and Auth tables must not be edited directly.
- Production is out of scope: never connect to, modify, or reset production.
- Never read, request, display, or store secrets (service_role keys, passwords, API tokens). Never pass secrets through prompts, tracked files, or command arguments.
- No `git` staging, committing, or pushing without separate approval.
- Do not modify Hasad V1 files or anything outside the current task's scope.

## 4. Execution method
- Start in Plan mode for read-only analysis. Before any build, list the exact files to create/edit and the tests to run, then wait for approval.
- One small unit of work per task. No sweeping rewrites.
- Flutter lives at the repository root (`lib/`, `test/`, `pubspec.yaml`, `windows/`, `android/`) — approved. Do not move it into `app/`.
- Documentation and architecture must be approved before implementation begins.
- Database migrations are forward-only, numbered, reviewed, and recorded as actually deployed. Never infer deployment from a migration filename.

## 5. Domain rules (until the owner decides otherwise)
- Never invent business rules. If a business decision is missing, label it `OPEN DECISION`, record it in `docs/15_DECISION_LOG.md`, and ask the owner.
- Tenant isolation is enforced at the database boundary (RLS), not only in Flutter.
- Financial posting RPCs are atomic, tenant-scoped, role-gated, and idempotent.
- Posted journal entries are immutable; corrections use linked reversal entries only.
- Arabic RTL is the default UI. Number and date formats come from tenant settings, not the device locale. Presentation must never alter accounting semantics.

## 6. Definition of done for a task
- Tests for the change pass; permissions/RLS behavior is checked where relevant.
- Changed files, tests performed, and anything not verified are reported.
- The report ends after the task. Do not enter a broader build without instruction.
