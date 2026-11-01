# HASAD V2 — Evidence Ledger and Current-State Audit

> **MOVED TO `docs/legacy_audit/` — REFERENCE ONLY — NOT V2 DESIGN.**
> Preserved verbatim as a legacy evidence ledger about the OLD DEV project.
> V2 architecture and schema must not be derived from this file. The authoritative
> sources are `docs/README.md`, `docs/00_MASTER_PLAN.md`, and `docs/15_DECISION_LOG.md`.

**Status: DRAFT** | Prepared 2026-10-20 | Owner approval: PENDING

## Verified from the operator's DEV SQL Editor output (OBSERVED, not a new live connection)
- DEV ref: `sxasnunzspkuwbxiddqd`. At 2026-10-19 18:08 UTC, PostgreSQL `current_database=postgres`, `current_user=postgres`.
- `public.expenses` table existed; `public.expense_category_accounts`, `public.expense_category` enum, `public.create_expense` RPC and `public.expenses.payment_method` column were absent. This supports **0035 core objects NOT deployed**; does not prove every possible 0035 side-effect absent.
- `get_my_role()` body MD5 `3b12e8cbc2a1f29de7dcc5c31b744183`, SECURITY INVOKER, `search_path=pg_catalog`, anon denied, authenticated allowed: expected 0031 function matches.
- `get_party_statement(text,uuid,date,date)` body MD5 `08c8c564f3b0c0c25b905b996a1ca7e6`, SECURITY INVOKER, `search_path=pg_catalog`, zero default args, anon denied, authenticated allowed: expected 0032 function matches.
- 0033 sampled 17/17 named RPC signatures: 0 missing, 0 anon, 0 PUBLIC; all 17 matched the checked expected EXECUTE matrix. This is not a complete proof of all 0033 changes.
- Default ACL query flagged 1 grant: `postgres` / schema `storage` / `anon` / `EXECUTE` / not grantable. This is outside `public`; do not change managed `storage`. The query is not sufficient to certify implicit PostgreSQL default grants for future functions.
- Local backup archive named `full_20261016_110832_8117893_e738f231ad84439491908f5d5fb404e4.sql.gz` passed local `verify_backup.ps1` integrity verification. **No backup artifact dated Oct 19 was found**, and **restore has never been proven** by these results.

## Prior historical report (2026-10-14; NOT verified against current repo or DEV)
`PROJECT_COMPLETION_REPORT.pdf` describes a substantial existing Flutter/Riverpod/SQLite/Supabase app, major accounting and authorization review items, and 969/969 Flutter tests at its audit time. It predates the later verified DEV functions above; do not override newer evidence with its deployment assumptions. Findings remain candidates for re-audit, not automatic current-state facts.

## Unknown; must not be invented
- Current complete list of PostgreSQL objects, FKs, row counts, RLS policies, table grants, triggers, partitions, indexes, owners, extensions, and deploy history.
- Actual SQLite drift schema; its parity with PostgreSQL and offline write / conflict semantics.
- Presence or importance of customer financial data in DEV, Auth users, Storage objects, Edge Functions, background jobs and external integrations.
- Verified full recovery procedure and tested isolated restore.
- Whether existing app needs a clean new DEV project or a controlled reset of this one.

## Independent evidence sequence
1. OpenCode PLAN-only repository audit, collect actual source paths and git status; do not edit.
2. Operator manually executes **one** SELECT-only DEV catalog query at a time from `audit_sql/DEV_READ_ONLY`, saves output without confidential values.
3. Compare repo-declared schema against DEV catalog and SQLite schema; annotate DIFFERENCE, NOT DEPLOYED, IMPLEMENTED, UNKNOWN.
4. Decide old DEV retention versus separate new DEV project. Protect Production.
5. Report evidence in `01_CURRENT_STATE_INVENTORY.md`, append date and source to every claim; never declare installed objects based on migration filenames.
