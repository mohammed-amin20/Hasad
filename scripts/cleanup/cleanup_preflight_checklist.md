# Cleanup Preflight Checklist (Read-Only)

**Project:** `sxasnunzspkuwbxiddqd` (Supabase DEV)  
**Status:** NOT AUTHORIZED FOR EXECUTION  
**Rule:** All checks must pass or be explicitly accepted with justification. Stop on any unexpected finding.

## 1. Project Identity & Environment
- [ ] Confirm repo root contains `supabase/.temp/project-ref` = `sxasnunzspkuwbxiddqd`
- [ ] Confirm `supabase/.temp/pooler-url` matches expected endpoint (non-secret verification only)
- [ ] psql is PostgreSQL 17
- [ ] Working in read-only mode; no destructive commands prepared for execution
- [ ] Owner has not provided credentials in chat/files

## 2. Inventories (Verify Fresh State)
- [ ] Review `local_audit/DEV_INVENTORY_20261021_192155.txt` (ended ROLLBACK)
- [ ] Review `local_audit/DEV_PLATFORM_INVENTORY_20261024_122126.txt` (ended ROLLBACK, latest)
- [ ] Confirm `hasad` and `hasad_api` schemas ABSENT
- [ ] Confirm no unexpected V2 objects in public

## 3. Legacy Object Counts (Match Manifest)
- [ ] Public tables: exactly 22 (accounts, commission_dues, customers, employee_movements, employees, expenses, invoice_counters, invoice_items, invoices, journal_entries, journal_entry_lines, payments, processed_requests, products, reminder_log, salaries, stock_moves, suppliers, tenant_settings, tenants, user_tenants, users)
- [ ] Legacy functions: exactly 33 (postgres-owned) with full signatures from manifest
- [ ] Triggers: exactly 6
- [ ] RLS policies: exactly 53 (all in `public`; the 3 `storage.objects` policies are a separate Stage 3b item and are **not** included in the 53)
- [ ] Indexes: 52, Constraints: 110
- [ ] Extension views in public: `pg_all_foreign_keys`, `tap_funky` present (pgtap)

## 4. Cron Job 5 (Strict Identity/Dependency)
- [ ] `cron.job` contains jobid 5, jobname `send-due-reminders-daily`, schedule `0 9 * * *`, active = true
- [ ] Run `scripts/inventory/cron_job5_dependency_readonly.sql` (owner-operated, read-only) and record sanitized result
- [ ] If dependency CONFIRMED -> must disable/remove jobid 5 BEFORE dependent functions/tables
- [ ] If dependency UNRESOLVED -> treat as dependency and still remove/disable before functions/tables, OR explicitly accept ordering with justification
- [ ] If dependency NOT_CONFIRMED -> still verify no indirect dependencies; prefer disabling before function removal

## 5. Auth Linkage (4 Users)
- [ ] `auth.users` count = 4
- [ ] All 4 linked via `public.users.auth_user_id` with FK `users_auth_user_id_fkey` ON DELETE CASCADE
- [ ] Exactly 4 rows in `public.users` linked (or reconcile)
- [ ] Removal method identified: **supported Supabase Auth Admin tooling only** (no direct SQL on auth tables)
- [ ] Prepare list of exact auth user identifiers at execution time (resolved securely, never printed in logs)

## 6. Storage (bucket pdfs)
- [ ] Bucket `pdfs` exists (private)
- [ ] Object count = 0 (verified)
- [ ] Ownership confirmed as legacy/app-specific (not used by V2)
- [ ] Removal via supported Storage tooling only if confirmed

## 7. Protected Objects (Must Remain)
- [ ] Managed schemas intact: auth, storage, realtime, cron, extensions, net, vault, graphql, graphql_public, pgbouncer, information_schema, pg_catalog
- [ ] Extensions intact: pg_cron, pg_net, pg_stat_statements, pgcrypto, pgtap, plpgsql, supabase_vault, uuid-ossp
- [ ] Extension-owned in public preserved: pgtap objects, pg_net objects
- [ ] Platform roles preserved
- [ ] Platform API keys preserved (no values collected)
- [ ] `hasad` and `hasad_api` absent

## 8. Webhooks/Integrations
- [ ] No triggers with `tgfoid` -> `http_request` found (section returned 0 rows)
- [ ] `net.http_request_queue` empty (0)
- [ ] No unexpected webhooks/integrations detected
- [ ] Recheck if anything changed

## 9. Authorization & Safety
- [ ] Explicit owner authorization obtained with exact scope/method (see authorization summary)
- [ ] D-026 understood: no-backup exception ONLY for this disposable V1 DEV cleanup; permanent data loss possible
- [ ] D-027 scope understood; no deletion authorized until explicit authorization
- [ ] All scripts reviewed, no automatic execution planned
- [ ] Stop conditions understood
- [ ] Post-cleanup verification plan ready
