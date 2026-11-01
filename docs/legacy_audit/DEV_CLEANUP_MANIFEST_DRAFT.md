# HASAD V2 — DEV Legacy Cleanup Manifest (FINAL DRAFT)

> **REFERENCE / PLANNING ONLY — NOT V2 DESIGN.**
> This file lives under `docs/legacy_audit/` and preserves V2 *cleanup planning*
> derived from the verified DEV metadata inventory. It must never be used to
> derive V2 architecture or schema.

**Status: DRAFT — NOT AUTHORIZED FOR EXECUTION.**  
**Updated: 2026-10-25 (Stage 4 dependency blocker diagnosed; Stage 3b prepared, not executed).**  
**Target project: `sxasnunzspkuwbxiddqd` (Hasad ERP DEV).**  
**Evidence sources:**  
- `local_audit/DEV_INVENTORY_20261021_192155.txt` (VERIFIED, D-028, captured 2026-10-21 16:22:19 UTC, ended ROLLBACK)  
- `local_audit/DEV_PLATFORM_INVENTORY_20261024_122126.txt` (VERIFIED, captured 2026-10-24 09:21:43 UTC, ended ROLLBACK)  
- `local_audit/DEV_STAGE4_DEPENDENCY_20261025_123320.txt` (READ-ONLY, captured 2026-10-25 09:33:32 UTC, ended ROLLBACK; the only source for `storage.objects` policy metadata)

This manifest contains **no destructive SQL** and authorizes nothing. Execution requires the separate explicit authorization defined in `docs/11_MIGRATION_AND_RESET_PLAN.md` Part B item 7.

---

## Evidence labels

- **APPROVED POLICY DECISIONS** — owner decisions recorded in `docs/15_DECISION_LOG.md`.
- **VERIFIED INVENTORY FACTS** — measured from the read-only inventory artifacts.
- **PROPOSED CLEANUP OBJECTS** — identified for removal; not yet authorized.
- **UNRESOLVED OWNERSHIP** — requires further owner review.
- **NOT AUTHORIZED FOR EXECUTION** — everything in this document.

---

## 1. APPROVED POLICY DECISIONS (docs/15)

| ID | Decision | Status |
|---|---|---|
| D-026 | Backup/restore prerequisites **waived** for the Hasad V1 DEV cleanup only (Decision A) | APPROVED (2026-10-21, scoped exception) |
| D-027 | Legacy cleanup scope: all Hasad V1 app components (Decision B) | APPROVED IN PRINCIPLE (2026-10-21, scope only) |
| D-028 | Complete read-only DEV metadata inventory recorded | VERIFIED (2026-10-21) |
| D-007 | Old Supabase Auth users removed in reset scope | PARTIALLY APPROVED (2026-10-20) |
| D-011 | Storage/Edge/webhooks/cron/secrets **disposition decided**, item-level list PENDING INVENTORY (now reconciled below) | PARTIALLY APPROVED (2026-10-21) |

---

## 2. VERIFIED INVENTORY FACTS (reconciled)

### Database (from DEV_INVENTORY_20261021_192155.txt)
- Schemas present: `auth, cron, extensions, graphql, graphql_public, information_schema, net, pg_catalog, pgbouncer, public, realtime, storage, vault` (13 schemas). **VERIFIED**
- `public` owner: `pg_database_owner`. **`hasad` and `hasad_api` ABSENT.** **VERIFIED**
- `public` relations: **24** = 22 tables + 2 extension views (`pg_all_foreign_keys`, `tap_funky`). **VERIFIED**
- `public` functions: **1,112** = **33 legacy** (`postgres`-owned) + **1,079 pgtap** (`supabase_admin`-owned; 1,081 extension-member dependency rows). **VERIFIED**
- Triggers: **6**. Sequences: **0**. Indexes: **52**. Constraints: **110**. **VERIFIED**
- RLS policies: **53 across 22 tables** (all RLS-enabled + forced). **`public`-only count** — see §3.4b for 3 further application policies in `storage`, which are **not** part of the 53. **VERIFIED**
- Extensions installed (8): `pg_cron, pg_net, pg_stat_statements, pgcrypto, pgtap, plpgsql, supabase_vault, uuid-ossp`. **VERIFIED**
- Migration history: **none** (`schema_migrations` absent in public, supabase, supabase_migrations). **VERIFIED**
- Dependency direction: **zero** cross-schema dependency from `public` outward (no `public` object depends on a managed-schema object) — but **NOT** the reverse: **3 `storage.objects` policies depend on `public.get_my_tenant_id()`** (corrected 2026-10-25). **VERIFIED**
- Run ended `ROLLBACK COMPLETE - NO DATABASE STATE WAS CHANGED`. **VERIFIED**

### Platform (from DEV_PLATFORM_INVENTORY_20261024_122126.txt)
- Schemas: `auth, cron, extensions, graphql, graphql_public, net, pgbouncer, realtime, storage, vault` present. **VERIFIED**
- Auth: `auth.users` exists (t). `auth.hooks` **absent** (f). Other auth tables present (audit_log_entries, flow_state, identities, instances, mfa_factors, one_time_tokens, refresh_tokens, sessions). **VERIFIED**
- **Auth users:** 4 auth.users exist; **all 4 linked to `public.users` via `public.users.auth_user_id`** (FK `users_auth_user_id_fkey` confirmed, ON DELETE CASCADE). No personal identifiers collected. **VERIFIED**
- Cron: `cron.job` exists (t), `cron.job_run_details` exists (t). **Active cron job:** jobid **5**, jobname **send-due-reminders-daily**, schedule **`0 9 * * *`** (active). Command/payload **redacted by inventory** (not exposed). **VERIFIED**
- Net/pg_net: `net._http_response` present (t), `net.http_request_queue` present (t) with **0 queued requests**. **pg_net owned by net schema (3 objects).** **VERIFIED**
- Storage: `storage.buckets`, `storage.objects`, `storage.s3_multipart_uploads` present (t). **Private bucket `pdfs` with 0 objects.** Ownership to be confirmed (legacy/app-specific). **VERIFIED**
- Edge Functions: `supabase_functions.functions` absent (f), `supabase_functions.hooks` absent (f). **No deployed Edge Functions.** **VERIFIED**
- Vault: `vault.secrets` table exists (t). **vault_secret_count=0** (no secrets). **VERIFIED**
- Database webhooks/triggers: **0 triggers** found across schemas (section returned no rows). `net.http_request_queue` exists but is empty (0 queued). **Webhook/triggers: NOT FOUND by trigger scan; pg_net queue empty. Status: ABSENT OR UNCONFIGURED (no explicit webhook configuration enumerated).** Evidence insufficient to claim platform webhooks exist; marked **ABSENT/UNCONFIGURED** based on current metadata scan (still subject to recheck).
- Cross-schema FK: `users_auth_user_id_fkey` (public.users.auth_user_id → auth.users.id) ON DELETE CASCADE. **VERIFIED**

### Extension ownership (platform inventory)
| Extension | Schema | Owned objects | Notes |
|---|---|---|---|
| pg_cron | cron | 4 | Preserve (managed). |
| pg_net | net | 3 | Preserve unless separately reviewed (extension-owned). |
| pg_stat_statements | extensions | 2 | Preserve (managed). |
| pgtap | public | 2 | **Protected** (testing). Do not classify as legacy app object. |
| supabase_vault | vault | 2 | Preserve (managed). |

**Apparent difference resolution:** Database shows 8 extensions total installed; platform inventory lists 5 extensions with owned objects. The remaining 3 (`pgcrypto`, `plpgsql`, `uuid-ossp`) are present in DB inventory but may not appear as "owned objects" in this platform summary — they are still **protected Supabase-managed/standard extensions** and must not be dropped. **Do not infer extension objects are safe to delete.**

---

## 3. PROPOSED CLEANUP OBJECTS — exact legacy objects

### 3.1 Legacy tables (22) — PROPOSED FOR REMOVAL
accounts, commission_dues, customers, employee_movements, employees, expenses, invoice_counters, invoice_items, invoices, journal_entries, journal_entry_lines, payments, processed_requests, products, reminder_log, salaries, stock_moves, suppliers, tenant_settings, tenants, user_tenants, users.

### 3.2 Legacy functions (33) — full signatures (PROPOSED FOR REMOVAL)
From DB inventory (public, postgres-owned):

| Function | Arguments | Returns | Volatility | SecDef |
|---|---|---|---|---|
| `_fire_reminder` | p_tenant_id uuid, p_customer_id uuid, p_customer_name text, p_phone text, p_amount numeric, p_webhook text, p_template text, p_company_name text | uuid | v | t |
| `add_employee_movement` | p_request_id uuid, p_employee_id uuid, p_month date, p_direction text, p_category text, p_amount bigint, p_description text, p_product_id uuid, p_qty numeric, p_date date | jsonb | v | f |
| `adjust_inventory` | p_product_id uuid, p_counted_qty numeric, p_reason text, p_date date, p_request_id uuid | jsonb | v | f |
| `create_account` | p_code text, p_name text, p_type text, p_parent_code text, p_request_id uuid | jsonb | v | f |
| `create_journal_entry` | p_request_id uuid, p_date date, p_memo text, p_lines jsonb | jsonb | v | f |
| `create_purchase_invoice` | p_request_id uuid, p_supplier_id uuid, p_items jsonb, p_invoice_date date, p_paid bigint, p_payment_method text, p_memo text | jsonb | v | f |
| `create_sale_invoice` | p_request_id uuid, p_customer_id uuid, p_items jsonb, p_invoice_date date, p_paid bigint, p_payment_method text, p_memo text | jsonb | v | f |
| `get_balance_sheet` | p_as_of_date date | jsonb | v | f |
| `get_chart_of_accounts` | — | jsonb | v | f |
| `get_dashboard_summary` | — | jsonb | v | f |
| `get_employee_entitlement` | p_employee_id uuid, p_month date | jsonb | v | f |
| `get_income_statement` | p_from date, p_to date | jsonb | v | f |
| `get_journal_entries` | p_from date, p_to date | jsonb | v | f |
| `get_ledger` | p_account_id uuid, p_from date, p_to date | jsonb | v | f |
| `get_my_role` | — | text | s | f |
| `get_my_tenant_id` | — | uuid | s | t |
| `get_my_user` | — | users | s | f |
| `get_party_statement` | p_party_type text, p_party_id uuid, p_from date, p_to date | jsonb | v | f |
| `get_trial_balance` | p_as_of_date date | jsonb | v | f |
| `get_user_tenants` | — | TABLE(tenant_id uuid, tenant_name text, role text) | s | t |
| `next_invoice_no` | p_type text | text | v | f |
| `next_journal_no` | — | bigint | v | f |
| `pay_salary` | p_request_id uuid, p_employee_id uuid, p_month date, p_paid bigint, p_method text, p_date date, p_note text | jsonb | v | f |
| `record_payment` | p_request_id uuid, p_invoice_id uuid, p_amount bigint, p_method text, p_date date, p_note text | jsonb | v | f |
| `register_tenant` | p_name text, p_owner_name text | uuid | v | t |
| `seed_chart_of_accounts` | p_tenant_id uuid | void | v | t |
| `seed_tenant_settings` | — | trigger | v | t |
| `send_due_reminders` | — | integer | v | t |
| `send_reminder_now` | p_customer_id uuid | jsonb | v | f |
| `send_reminders_to_all` | — | jsonb | v | f |
| `set_master_tenant` | — | trigger | v | f |
| `settle_supplier` | p_request_id uuid, p_supplier_id uuid, p_amount bigint, p_method text, p_date date, p_note text | jsonb | v | f |
| `switch_tenant` | p_tenant_id uuid | void | v | t |

### 3.3 Legacy triggers (6) — PROPOSED FOR REMOVAL
- `trg_set_tenant` on `customers`, `employees`, `expenses`, `products`, `suppliers` (BEFORE INSERT → `set_master_tenant()`).
- `trg_seed_tenant_settings` on `tenants` (AFTER INSERT → `seed_tenant_settings()`).

### 3.4 Legacy RLS policies (53) — PROPOSED FOR REMOVAL
All RLS policies on the 22 legacy tables in `public` (tenant_isolation*, user policies, own_or_same_tenant patterns). Removed with tables or explicitly in Stage 3.

### 3.4b Legacy Storage policies (3) — **NEW SCOPE ITEM — NOT AUTHORIZED**
**Classification: application-specific with high confidence; authorship NOT proven.**

These three policies live on `storage.objects` (Supabase-managed schema) and are the **only** catalog-tracked blockers to Stage 4 (`DROP FUNCTION public.get_my_tenant_id()`). They are **not** part of the 53 `public` policies and were never covered by any approved cleanup scope.

| Policy | Command | Permissive | Roles | USING expr | WITH CHECK expr | Extension-owned | Table owner |
|---|---|---|---|---|---|---|---|
| `tenant_isolated_pdf_select` | SELECT | yes | `{PUBLIC}` | yes | no | no | `supabase_storage_admin` |
| `tenant_isolated_pdf_insert` | INSERT | yes | `{PUBLIC}` | no | yes | no | `supabase_storage_admin` |
| `tenant_isolated_pdf_delete` | DELETE | yes | `{PUBLIC}` | yes | no | no | `supabase_storage_admin` |

**Supporting evidence (OBSERVED, `DEV_STAGE4_DEPENDENCY_20261025_123320.txt`):**
- Each policy has `pg_depend` rows (deptype `n`) to **exactly** two functions: `public.get_my_tenant_id()` and `storage.foldername(text)`. `get_my_tenant_id()` is one of the 33 legacy app functions (postgres-owned, `SECURITY DEFINER`, not extension-owned). *Inference (platform knowledge, not local evidence): a stock Supabase project does not ship this project-specific function.*
- All three are `permissive`, apply to `PUBLIC`, and are **not** extension-owned. *Inference (platform knowledge, not local evidence): a stock Supabase project ships no policies on `storage.objects`; these were therefore added after provisioning, and they are not default policies of the storage extension.*
- The `pdfs` bucket is private with 0 objects (§3.8), consistent with the same app feature.
- No other object in any catalog class depends on `get_my_tenant_id()`.

**Limits of that evidence:**
- `pg_policy` has **no owner and no `created_at`**; `pg_depend` records structure, not authorship. The DDL that created these policies was never recorded in any local artifact (no matching `CREATE POLICY` exists in the saved inventories or docs).
- A dashboard/SQL-editor operator could have authored them by hand against the V1 helper function. They are therefore **application-specific** (they target a V1 application function and an app bucket) but **cannot be attributed to V1 source code**.
- Names (`tenant_isolated_pdf_*`) are suggestive only and are **not** used as proof.

**Prepared script checks (`scripts/cleanup/03b_remove_legacy_storage_policies.sql`, static review only — never executed):**
1. **Authorization** — `cleanup.authorized=true`; project ref literal `sxasnunzspkuwbxiddqd`; `cleanup.mode` ∈ {`DRY_RUN`, `EXECUTE`}; the separate scope token below. A connection whose database name is not `postgres` is rejected. The project ref is **not catalog-visible**, so project binding remains operator-asserted (documented in the script header).
2. **Target relation** — `storage.objects` exists, `relkind='r'`, RLS enabled, owner recorded; the executing role must be superuser or a member of the table owner, otherwise the run aborts.
3. **Exact identity set** — exactly 3 policies on the relation; each authorized name present; command `SELECT`/`INSERT`/`DELETE` in the recorded order; permissive; roles exactly `{PUBLIC}`; `USING` / `WITH CHECK` presence exactly as observed; `extension_owned=false`.
4. **Dependency set** — each policy's `pg_depend` function set is exactly `{public.get_my_tenant_id(), storage.foldername(text)}`; no other function.
5. **Stage-4 anchor** — exactly one `public.get_my_tenant_id()`, `postgres`-owned, not extension-owned, still present (this script must not drop functions).
6. **No collateral change** — owner, table ACL, RLS flags, reloptions, and per-column name/type/NOT NULL/column ACL/default fingerprint captured before; must be bit-identical afterwards; 0 policies remain; no `pg_policy` anywhere still depends on the function.
7. **Execution shape** — only 3 `DROP POLICY` statements (no `IF EXISTS`, no `CASCADE`, no `ALTER`/`GRANT`/`REVOKE`/DML); `DRY_RUN` runs every check then `ROLLBACK`; `EXECUTE` drops, re-verifies absence + fingerprint, then `COMMIT`. A policy created concurrently before the DROPs makes the post-drop "0 policies remain" check fail and rolls the whole transaction back.

**Status: requires its own explicit owner authorization (D-029).** Prepared script: `scripts/cleanup/03b_remove_legacy_storage_policies.sql` (DRY_RUN/EXECUTE, exact-identity, no CASCADE, own authorization token). Dropping them is a **removal of an access-control control** on the managed schema and must precede Stage 4.

### 3.5 Legacy indexes (52) and constraints (110) — PROPOSED FOR REMOVAL
All defined on the 22 legacy tables; removed automatically with tables.

### 3.6 Cron job (jobid 5) — ABSENT (owner-confirmed 2026-10-25; Stage 1 applied)
- **Current state (owner-confirmed, 2026-10-25):** cron job **5** (`send-due-reminders-daily`) is **ABSENT**; Stage 1 is already applied. This fact comes from the owner's Stage 4 dependency diagnostic result, **not** from the saved `.txt` (the file contains query result sets only — psql `NOTICE` lines were not captured), so it is **owner-reported, not file-observable**.
- **Historical state (2026-10-24 inventory):** jobid 5 existed, active, schedule `0 9 * * *`, command/payload redacted by the sanitized inventory. Because the job is now absent, the former cron→`send_due_reminders()` dependency question is **moot**.
- **Recheck:** `cron.job` must still be rechecked immediately before any authorized cleanup in case the job was recreated; no removal step is currently expected.

### 3.7 Auth accounts (4 linked) — PROPOSED FOR REMOVAL (with ordering constraints)
- **4 auth.users**, all matched by `public.users.auth_user_id` via FK `users_auth_user_id_fkey` (ON DELETE CASCADE).  
- **Non-sensitive verification criteria:** count = 4, all have matching `public.users` rows, FK exists with ON DELETE CASCADE. No emails/hashes/tokens collected. Removal must respect FK coupling (legacy `public.users` and Auth users coupled; ordering must account for this).

### 3.8 Storage bucket (1) — PROPOSED FOR REMOVAL (with review)
- **Bucket:** `pdfs` (private), **0 objects** at inspection time (verified).  
- **Ownership review:** bucket appears unused (empty). Requires ownership confirmation — remove only if confirmed legacy/app-specific and not used by V2. Count may change between inventories.

### 3.9 Other platform items
- **Edge Functions:** None deployed (verified).  
- **Vault secrets:** `vault.secrets` exists but **vault_secret_count=0** (verified).  
- **Database webhooks/triggers:** **0 triggers** found; `net.http_request_queue` has **0 queued requests**. **Webhook status: ABSENT/UNCONFIGURED** based on current metadata scan (no explicit webhook/triggers enumerated). If new evidence appears, recheck required.  
- **App secrets/config/API keys:** Platform-managed keys exist (anon, service_role legacy JWT, default publishable/secret) — **PRESERVED as platform-managed**; no secret values collected.

---

## 4. CONFIRMED PROTECTED OBJECTS

### 4.1 Extension-owned objects in `public` (NOT legacy)
- **pgtap:** 1,079 functions + views `pg_all_foreign_keys`, `tap_funky` (owner `supabase_admin`, extension-member). **Protected.** Removal only via separate explicit `DROP EXTENSION pgtap` decision.
- **pg_net:** extension in `public` (3 owned objects). **Protected** unless separately reviewed and explicitly authorized.

### 4.2 Supabase-managed infrastructure
Schemas: `auth, storage, realtime, cron, extensions, net, vault, graphql, graphql_public, pgbouncer, information_schema, pg_catalog`.  
Roles/platform: `supabase_admin, supabase_auth_admin, dashboard_user, pgbouncer, service_role, anon, authenticated`.  
Extensions: `pg_cron, pg_stat_statements, pgcrypto, plpgsql, supabase_vault, uuid-ossp` (and others present) — **preserved** unless separately reviewed and explicitly authorized.  
`public` default privileges owned by `postgres`/`supabase_admin` — require deliberate review, not automatic removal.

---

## 5. CLEANUP ORDERING AND DEPENDENCY RISKS

### Dependency-safe proposed order (NO SQL)
1. **Cron job (jobid 5, send-due-reminders-daily)** — **ABSENT** (owner-confirmed 2026-10-25; Stage 1 applied). Recheck `cron.job` at execution in case it was recreated; no removal step expected.
2. **Legacy triggers (6)** — drop to stop side effects (trg_set_tenant on 5 tables, trg_seed_tenant_settings on tenants).
3. **Legacy RLS policies in `public` (53)** — remove with tables or explicitly; avoid leaving policies orphaned.
4. **Stage 3b — legacy Storage policies (3) on `storage.objects`** — **NEW, separately authorized scope (D-029)**. Must run **before** Stage 4: `public.get_my_tenant_id()` cannot be dropped while they exist. Script `03b_remove_legacy_storage_policies.sql`; DRY_RUN then EXECUTE with its own scope token.
5. **Legacy functions (33)** — drop after dependents (triggers/policies/cron **and the Stage 3b storage policies**) are cleared. Pay special attention to SECURITY DEFINER functions used by cron/integrations.
6. **Legacy tables (22)** — drop in FK-dependency order (leaf-first). Suggested order (respecting FK deps): `journal_entry_lines`, `invoice_items`, `payments`, `stock_moves`, `employee_movements`, `salaries`, `commission_dues`, `expenses`, `reminder_log`, `processed_requests`, `invoices`, `journal_entries`, `users`, `user_tenants`, `customers`, `suppliers`, `products`, `invoice_counters`, `accounts`, `tenant_settings`, `employees`, `tenants`. **Note:** `users.auth_user_id` FK to `auth.users` means Auth user removal/handling must be coordinated with `public.users` removal per approved plan.
7. **Auth users (4 linked)** — remove via supported Supabase tooling per approved plan, coordinated with `public.users` and after confirming no other dependencies.
8. **Storage bucket `pdfs` (0 objects)** — remove if confirmed legacy/app-specific; empty now but verify ownership again at recheck.
9. **Legacy views (2 in public)** — only if not needed; `pg_all_foreign_keys` and `tap_funky` appear extension-related in DB inventory context — do **not** drop as legacy without confirming.
10. **Extension decision (pgtap/pg_net)** — **separate explicit authorization** required. Do not drop via table cleanup.
11. **`public` default privileges review** — deliberate owner review.

**Key risks:**
- **Cross-schema dependency (discovered 2026-10-25):** three `storage.objects` policies depend on `public.get_my_tenant_id()`. Stage 4 failed on this. Handled only by Stage 3b with its own authorization; **never** by `DROP FUNCTION ... CASCADE`.
- **Cron/function coupling (RESOLVED):** `send-due-reminders-daily` (jobid 5) was active in the 2026-10-24 inventory with a redacted command/payload. The owner's 2026-10-25 diagnostic reports jobid 5 **ABSENT**, so the linkage question is moot; recheck `cron.job` at execution in case it was recreated.
- **Auth coupling:** `public.users.auth_user_id` FK to `auth.users` with ON DELETE CASCADE creates tight coupling between legacy app tables and Auth identities (4 users linked).
- **Extension boundary:** pgtap/pg_net in `public` must not be misclassified as legacy.
- **Webhook status:** No triggers found; `net.http_request_queue` empty (0). **ABSENT/UNCONFIGURED** from current scan; recheck required if state changes.
- **State drift:** Auth users/cron/jobs/storage counts can change between inventory and execution.

---

## 6. PRE-FLIGHT AND POST-FLIGHT CHECKLISTS

### Pre-flight (before any authorized cleanup)
- [ ] **Recheck immediately before cleanup** (see §7). Capture fresh metadata for Auth users, cron jobs, Storage buckets/objects, Edge Functions, webhooks, Vault secrets.
- [ ] **Verify inventories still match** project `sxasnunzspkuwbxiddqd` and timestamps recorded.
- [ ] **Confirm authorization** exists naming exact project, objects, destructive method, recovery plan (Part B item 7). D-026 waiver only applies to backup/restore prerequisites for this specific cleanup.
- [ ] **Stage 3b precondition:** a **separate** authorization covers the 3 `storage.objects` policies (`tenant_isolated_pdf_select/_insert/_delete`); the public-schema authorization does not. Run `03b` DRY_RUN first and confirm the exact-identity and fingerprint checks pass.
- [ ] **Review manifest** against fresh recheck; update if counts changed.
- [ ] **Document dependency confirmation** for cron job (what it invokes) before removing dependent functions.
- [ ] **Confirm Auth removal method** uses supported Supabase tooling (not direct SQL on auth tables).
- [ ] **Confirm no V2 objects created** in `hasad`/`hasad_api` (must remain absent).
- [ ] **Record execution plan** with ordering and rollback considerations (even if backup waived, document risk acceptance).

### Post-flight (after authorized cleanup)
- [ ] **Public schema:** no legacy tables/views/functions/triggers remain. Verify against §3 lists.
- [ ] **Storage policies (Stage 3b):** the 3 `tenant_isolated_pdf_*` policies are absent; `storage.objects` owner/ACL/columns/RLS flags unchanged; **no** policy anywhere depends on `public.get_my_tenant_id()`.
- [ ] **Schemas preserved:** `auth, storage, realtime, cron, extensions, net, vault, graphql, graphql_public, pgbouncer` intact and functional.
- [ ] **Extensions:** pgtap/pg_net state matches authorization decision; no accidental extension drops.
- [ ] **Roles:** all platform roles intact.
- [ ] **Auth/Storage/Edge:** APIs respond normally; Auth users removed only as authorized.
- [ ] **Cron:** jobid 5 removed/suspended as authorized.
- [ ] **Storage:** `pdfs` bucket handled per authorization.
- [ ] **FKs/cross-schema:** no broken dependencies introduced; verify `public` has no outward deps to managed schemas.
- [ ] **Default privileges:** `public` default privileges reviewed and documented.
- [ ] **Verification recorded:** timestamp, authorization reference, results of checks.

---

## 7. RECHECK REQUIREMENT (immediately before authorized cleanup)

Because inventories are point-in-time:
- **Auth users/hooks:** Recheck count and linkage to `public.users` (may have changed). Auth tables present; hooks absent now.
- **Cron jobs:** Recheck `cron.job` for jobid 5 and any new jobs (jobid 5 is **owner-confirmed ABSENT** as of 2026-10-25; the saved diagnostic `.txt` does not contain the `NOTICE` lines).
- **Storage:** Recheck `storage.buckets`/`storage.objects` for `pdfs` and others (currently 0; count may change).
- **Edge Functions:** Recheck (currently none).
- **Webhooks/integrations:** Recheck `net.http_request_queue` and triggers (`pg_trigger` where `tgfoid` is http_request); currently **ABSENT/UNCONFIGURED** with 0 queued.
- **Vault secrets:** Recheck names/count (currently 0).
- **Extensions:** Confirm no unexpected changes.

**Use prepared runner:** `scripts/inventory/run_dev_platform_inventory.ps1` (read-only) or equivalent metadata queries. Record results in `local_audit/` with timestamp.

---

## 8. RESIDUAL RISKS & IRREVERSIBLE-LOSS WARNING

**Risks:**
- **Irreversible loss:** D-026 waives backup/restore prerequisites for this specific cleanup only. Deleted legacy test data may be **permanently unrecoverable**.
- **State drift:** Platform state may change between inventories and execution.
- **Coupling complexity:** Auth/users/cron/functions tightly coupled.
- **Classification errors:** Extension objects in `public` must not be misclassified as legacy.
- **Webhook status:** No triggers found; `net.http_request_queue` empty → **ABSENT/UNCONFIGURED** from current scan; recheck required.
- **Scope creep:** Only Hasad V1 DEV cleanup covered by waiver; V2 prod/other projects not covered.

**Warning:** This is a **DRAFT — NOT AUTHORIZED FOR EXECUTION**. No deletion has been authorized. All destructive actions require separate explicit authorization naming exact project, objects, method, and recovery plan.

---

## 9. EXACT FILES UPDATED

**Updated (local documentation only):**
1. `docs/legacy_audit/DEV_CLEANUP_MANIFEST_DRAFT.md` — updated with fresh platform inventory `DEV_PLATFORM_INVENTORY_20261024_122126.txt` (captured 2026-10-24 09:21:43 UTC): confirms 4 linked Auth users, private bucket `pdfs` (0 objects), cron jobid 5 `send-due-reminders-daily` (`0 9 * * *`) active but **command/payload redacted** → **cron→function dependency UNRESOLVED**, webhook/triggers **0** and `net.http_request_queue` empty → **ABSENT/UNCONFIGURED**, `vault_secret_count=0`, no Edge Functions, no auth.hooks. Preserves protected objects, exact legacy scope (22 tables, 33 functions), ordering with dependency constraints, preflight/postflight, recheck requirements, risks/irreversible-loss warning. *(Cron item superseded 2026-10-25: jobid 5 owner-confirmed ABSENT — see §3.6.)*
2. **2026-10-25 (Stage 3b preparation):** added `local_audit/DEV_STAGE4_DEPENDENCY_20261025_123320.txt` as evidence; corrected the `public`-outward dependency claim (added the reverse direction: 3 `storage.objects` → `public.get_my_tenant_id()`); clarified that the 53-policy count is `public`-only; added §3.4b (3 Storage policies, **new scope, not authorized**); inserted Stage 3b before Stage 4 in §5 and in the preflight/postflight lists; added Stage 3b to §10 authorization requirements.
3. `scripts/cleanup/03b_remove_legacy_storage_policies.sql` — **NEW**, prepared only: DRY_RUN/EXECUTE, exact 3-policy allowlist, no CASCADE, own scope token.
4. `docs/15_DECISION_LOG.md` — D-029 (Storage-policy scope item, OPEN) and a defect record for the Stage 4 dependency scan.
5. `scripts/cleanup/04_drop_functions.sql` — dependency preflight corrected to inspect **all** `pg_depend` catalog classes and fail closed.
6. `scripts/cleanup/README.md`, `scripts/cleanup/cleanup_execution_checklist.md`, `scripts/cleanup/run_cleanup.ps1`, `check.ps1` — Stage 3b added to the index, order and validators.
7. **2026-10-25 (Stage 3b hardening, static only):** `03b_remove_legacy_storage_policies.sql` now also rejects a connection whose database is not `postgres`, requires RLS to be **enabled** on `storage.objects`, includes column **defaults** in the object fingerprint, and documents the concurrency (TOCTOU) bound. `08_post_cleanup_verify.sql` gained Stage 3b absence / dependency / object-state checks, and its pre-existing duplicate function query (which referenced an undefined alias) was removed. `check.ps1` is now a real static validator for 03b (exact 3 `DROP POLICY` identities, no `CASCADE`/DDL/DML, scope token, dollar-quote balance, verification before `COMMIT`).
8. **2026-10-25 (state reconciliation):** cron jobid 5 is **owner-confirmed ABSENT** (Stage 1 applied). §3.6, §5, §7 and §8 reconciled; `scripts/cleanup/README.md` and Phase 1 of `cleanup_execution_checklist.md` updated. The saved diagnostic `.txt` contains result sets only, so the cron `NOTICE` line is not file-observable — evidence label: owner-reported.

**No remote connections. No SQL executed. No Storage policy modified. No git operations.**

---

## 10. WHAT EXPLICIT AUTHORIZATION WILL BE REQUIRED LATER

A separate explicit owner authorization (per `docs/11_MIGRATION_AND_RESET_PLAN.md` Part B item 7) must name:
- **Exact project:** `sxasnunzspkuwbxiddqd` (DEV only; production out of scope)
- **Exact objects to remove:** The 22 tables, 33 functions, 6 triggers, 53 policies **in `public`**, indexes/constraints as listed; **separately and explicitly:** the 3 Storage policies `tenant_isolated_pdf_select`, `tenant_isolated_pdf_insert`, `tenant_isolated_pdf_delete` on `storage.objects` (own scope token `CONFIRM_DROP_3_LEGACY_PDF_POLICIES_SXASNUNZSPKUWBXIDDQD`); cron jobid 5 (send-due-reminders-daily); 4 auth.users (with method); storage bucket `pdfs` (if confirmed); any other confirmed legacy objects
- **Destructive method:** Specific commands/tooling (respecting Auth removal via supported tooling, not direct auth table SQL)
- **Recovery plan:** Even though D-026 waives backup/restore prerequisites for this specific cleanup, the plan must still document risk acceptance and verification approach
- **Ownership confirmations:** For any items marked UNRESOLVED/INCONCLUSIVE (webhooks, cron command details, bucket ownership) resolved at recheck time
- **Extension decisions:** Explicit keep/drop for pgtap/pg_net if different from current protection

---

## 11. ONE RECOMMENDED NEXT ACTION

**Run the platform recheck immediately before considering authorization** using the prepared read-only runner `scripts/inventory/run_dev_platform_inventory.ps1` (owner types DB password at psql prompt). Capture fresh metadata for Auth users/hooks, cron job details (command/schedule/active), Storage bucket attributes/object counts (pdfs), webhooks/integrations (`net.http_request_queue`, any webhook configs), and Vault secret names. Update this manifest with any changes, resolve the **INCONCLUSIVE** webhook item, confirm cron→function dependency, and only then request separate explicit authorization naming exact objects/methods if the owner still wants to proceed. No destructive actions in this step.
