# Cleanup Execution Checklist (Supervised, Read-Only Preparation)

**Project:** `sxasnunzspkuwbxiddqd` (Supabase DEV)  
**Status:** NOT AUTHORIZED FOR EXECUTION  
**Rule:** Execute only after passing preflight and receiving explicit written authorization. Stop on any unexpected finding. No cross-service atomicity assumed.

## PHASE 0: Preflight (Complete First)
- [ ] All items in `cleanup_preflight_checklist.md` completed
- [ ] Fresh read-only inventory captured (if needed) and logged
- [ ] Cron dependency resolved/accepted with ordering
- [ ] Exact Auth identifiers prepared (securely, not logged)
- [ ] Bucket ownership confirmed
- [ ] Authorization summary reviewed and accepted
- [ ] Protected objects list verified

## PHASE 1: Database - Disable/Remove Cron (FIRST)
**Order:** 1  
**Method:** Supported tooling (pg_cron management)  
**Risk:** If dependent on functions, must do first.  
**State 2026-10-25:** jobid 5 is **owner-confirmed ABSENT** (Stage 1 applied; not visible in the saved diagnostic `.txt`, which captured result sets only). Recheck before execution; no removal is expected.

- [ ] Identify jobid 5 (`send-due-reminders-daily`) exists and is active
- [ ] If dependency confirmed OR unresolved but assumed -> **disable or unschedule** jobid 5
- [ ] Verify job no longer active/running
- [ ] Log action (timestamp, method, who)

## PHASE 2: Database - Triggers
**Order:** 2

- [ ] Drop `trg_set_tenant` on `customers`, `employees`, `expenses`, `products`, `suppliers`
- [ ] Drop `trg_seed_tenant_settings` on `tenants`
- [ ] Verify triggers removed

## PHASE 3: Database - RLS Policies
**Order:** 3

- [ ] Drop all 53 legacy RLS policies on the 22 tables (explicitly, avoid schema-wide operations; all 53 are in `public` - the 3 `storage.objects` policies are Phase 3b)
- [ ] Verify policies removed

## PHASE 3b: Database - Legacy Storage policies (NEW SCOPE, separate authorization)
**Order:** 3b (**must run before Phase 4**)
**Method:** `scripts/cleanup/03b_remove_legacy_storage_policies.sql` (exact-identity, DRY_RUN then EXECUTE)
**Why:** `public.get_my_tenant_id()` is blocked by 3 policies on `storage.objects`; the 53-policy set does not include them and their removal is not covered by the public-schema authorization.

- [ ] Separate written authorization obtained for exactly `tenant_isolated_pdf_select`, `tenant_isolated_pdf_insert`, `tenant_isolated_pdf_delete` on `storage.objects`
- [ ] DRY_RUN passes with `cleanup_storage_policy_scope` token; review output
- [ ] EXECUTE drops only those 3 and verifies `storage.objects` fingerprint unchanged
- [ ] Confirm no policy anywhere still depends on `public.get_my_tenant_id()`

## PHASE 4: Database - Functions
**Order:** 4 (after 1-3 **and 3b**)

Drop the 33 legacy functions in dependency-safe order. Use exact signatures from manifest:

- [ ] Drop triggers/functions with dependencies cleared first
- [ ] Drop all 33 functions: `_fire_reminder`, `add_employee_movement`, `adjust_inventory`, `create_account`, `create_journal_entry`, `create_purchase_invoice`, `create_sale_invoice`, `get_balance_sheet`, `get_chart_of_accounts`, `get_dashboard_summary`, `get_employee_entitlement`, `get_income_statement`, `get_journal_entries`, `get_ledger`, `get_my_role`, `get_my_tenant_id`, `get_my_user`, `get_party_statement`, `get_trial_balance`, `get_user_tenants`, `next_invoice_no`, `next_journal_no`, `pay_salary`, `record_payment`, `register_tenant`, `seed_chart_of_accounts`, `seed_tenant_settings`, `send_due_reminders`, `send_reminder_now`, `send_reminders_to_all`, `set_master_tenant`, `settle_supplier`, `switch_tenant`
- [ ] Verify none remain in public (postgres-owned legacy set)

## PHASE 5: Database - Tables (FK leaf-first)
**Order:** 5

Drop in order: `journal_entry_lines`, `invoice_items`, `payments`, `stock_moves`, `employee_movements`, `salaries`, `commission_dues`, `expenses`, `reminder_log`, `processed_requests`, `invoices`, `journal_entries`, `users`, `user_tenants`, `customers`, `suppliers`, `products`, `invoice_counters`, `accounts`, `tenant_settings`, `employees`, `tenants`

- [ ] Drop each table after confirming FKs handled
- [ ] Coordinate with Auth removal for `users` (FK to `auth.users`)
- [ ] Verify all 22 removed

## PHASE 6: Auth Users (Coordinated, separate service)
**Order:** 6 (after/with table coordination)  
**Method:** **Supported Supabase Auth Admin tooling only. NO direct SQL on auth tables.**

- [ ] Confirm 4 linked users identified securely
- [ ] Remove via Auth Admin API/tooling
- [ ] Verify users removed
- [ ] Log actions separately from DB

## PHASE 7: Storage Bucket (separate service)
**Order:** 7  
**Method:** **Supported Storage tooling only**

- [ ] Re-verify bucket `pdfs` empty and ownership confirmed
- [ ] Remove bucket if authorized
- [ ] Verify removal
- [ ] Log actions separately

## PHASE 8: Post-Cleanup Verification
- [ ] Public schema: no legacy tables/views/functions/triggers from lists remain
- [ ] Legacy views only if confirmed extension-related remain; `pg_all_foreign_keys`, `tap_funky` still present if pgtap kept
- [ ] Managed schemas/roles/extensions intact
- [ ] pgtap/pg_net untouched (if kept)
- [ ] Cron job removed/suspended
- [ ] Auth users removed as authorized
- [ ] Storage bucket handled as authorized
- [ ] No `hasad`/`hasad_api` created
- [ ] Cross-schema FKs from public to managed schemas only as before or removed appropriately
- [ ] `public` default privileges reviewed/documented
- [ ] All actions logged with timestamps and authorization reference
- [ ] Irreversible data loss acknowledged per D-026
