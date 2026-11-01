# HASAD V2 — Decision Register
**Status: OPEN (updated 2026-10-20 — owner decisions from the architecture review consolidated; 2026-10-21 — consolidated O1–O34 register added, R-02 clarified, R-04 wording superseded — audit batch 1; 2026-10-21 — D-010 and D-012 design/tooling decisions recorded as OWNER_APPROVED with explicit scope limits, see Approval record; 2026-10-21 — owner Decisions A/B recorded as D-026/D-027, D-011 partially resolved, D-028 inventory VERIFIED — second Approval record; 2026-10-28 — Phase 9A owner choices consolidated and P9A-04 assessed CONDITIONAL PASS; 2026-10-28 — D-030 products.read catalogue extension approved; unrelated readiness items remain OPEN)**

Every approval records date, reason, effects on DB/API/Flutter, and the tests it
implies. No invented approvals. When an answer changes, append a new row; never
silently rewrite history.

Status vocabulary: `OPEN` / `APPROVED` / `PARTIALLY APPROVED` / `REJECTED`.
Technical recommendations live in the "Recommendations pending validation"
section below; they are **not** decisions and never become approved by being listed.
No design may be marked `VERIFIED` without executable evidence.

## Standing gates (not decision rows)
- Any DEV reset execution requires a **separate explicit authorization** naming
  the exact project, objects, and method — see `11_MIGRATION_AND_RESET_PLAN.md`.
  No current decision authorizes any deletion.
- No SQL may be generated for financial or tenancy rules until the related rows
  below are `APPROVED`.

## Register — business decisions

| ID | Decision needed | Owner answer | Status | Scope / effects |
|---|---|---|---|---|
| D-001 | New DEV project or reset existing? | **Reuse existing DEV project** `sxasnunzspkuwbxiddqd` for V2; the old database must not determine V2 design | APPROVED (2026-10-20) | V2 schema isolation strategy inside the reused project remains OPEN → D-010 |
| D-002 | Move existing DEV financial data into V2? | **NO migration** of old DEV business data into V2; removal of old business data is part of the future reset scope | APPROVED (2026-10-20) | No data-migration task in the V2 roadmap; reset execution still requires separate authorization |
| D-003 | One user can join multiple tenants? | **NO** — each user account belongs to one company only | APPROVED (2026-10-20) | Single `company_id` per session; revocation of the membership locks that company's local data (D-020) |
| D-004 | Which modules in MVP? | **12 business modules, including full employees and payroll** (see `02_REQUIREMENTS_AND_SCOPE.md`) | APPROVED (2026-10-20) | Initial scope fixed; statutory payroll rules remain OPEN → D-024; later-phase candidates listed in `02_REQUIREMENTS_AND_SCOPE.md` |
| D-005 | Fiscal periods, tax/currency, rounding? | Base currency **ILS**; final amounts **2 decimals**, **HALF_UP**; VAT **optional and configurable** per company; invoice-level choice **inclusive/exclusive**; tax grouped **by rate** with **group-total rounding**; financial year **Jan 1 – Dec 31** with **monthly** periods; **strict** period closing, privileged reopening **audited** | APPROVED (2026-10-20) | Actual VAT rate and jurisdiction-specific requirements remain OPEN → D-023; intermediate precision is a recommendation → R-07 |
| D-006 | Can offline documents be posted or drafts only? | Offline **entry allowed but pending**; documents remain unposted until **accepted and posted by the server**, which processes valid synchronized operations **in transaction order**; **inventory conflicts are rejected and retained locally** for correction and retry | APPROVED (2026-10-20) | Official numbers are issued only by the server (D-018); display of available stock while offline documents are pending → D-025 |
| D-007 | Auth / Storage / integration retention? | Old Supabase **Auth users are removed** as part of the future reset scope | PARTIALLY APPROVED (2026-10-20) | Storage objects, external integrations, and migration history remain OPEN → D-011 |
| D-008 | Reuse V1 code vs replace each module? | **No reuse.** Clean-slate V2; V1 source/migrations are never inspected and never determine V2 architecture | APPROVED (2026-10-20) | All layers: Flutter, SQL, tests built from V2 specs only |
| D-009 | Flutter location: repository root or `app/`? | **Repository root** (`lib/`, `test/`, `pubspec.yaml`, `windows/`, `android/`) | APPROVED (2026-10-20) | Repo layout: do not move Flutter into `app/` |
| D-010 | V2 schema isolation inside the reused DEV project (schema naming, PostgREST exposure, coexistence with old objects until reset)? | **DESIGN APPROVED (2026-10-21): private data schema `hasad`; exposed RPC interface schema `hasad_api`** — architecture/tooling decision only | APPROVED (2026-10-21, design scope only — see Approval record) | Approved: schema-organization design (private `hasad` + interface `hasad_api`, per R-01's core idea). **Not authorized by this approval:** SQL creation or execution, database/schema/role creation, PostgREST/exposure configuration changes in DEV, or any other DEV modification — each such step requires its own explicit authorization. Legacy-object coexistence remains governed by D-001/D-002 standing rules (no deletion authorized) — not newly decided here. Implementation mechanisms (RLS, RPC grants, `SECURITY INVOKER`/`DEFINER` choice, privilege enforcement, Supabase transaction-pooling behavior) remain **RECOMMENDED_PENDING_VALIDATION / UNVERIFIED** until independently tested (R-01/R-02). Remaining doc/API gates: `05_DATABASE_SCHEMA.md` and `10_API_RPC_CONTRACTS.md` approval still follow the standing "no SQL before APPROVED specs" rule; security PoC remains **POSTPONED** |
| D-011 | Disposition of Storage objects, external integrations, and migration history at reset time? | **PARTIALLY RESOLVED (2026-10-21, Decision B):** Storage buckets/objects, Edge Functions, webhooks/cron/external integrations, and legacy app-specific secrets/config are now **in removal scope** (ownership confirmed per object). **Residual PENDING INVENTORY:** Auth users & hooks, Storage object-level inventory, Edge Function list, webhook/consumer list, cron job list, secret name list — see `11_MIGRATION_AND_RESET_PLAN.md` Part B §9. Migration history: **none exists** (no `schema_migrations` table in public/supabase/supabase_migrations — verified D-028) | PARTIALLY APPROVED (2026-10-21) | No deletion authorized by this row; execution still gated by Part B items 1–8 with D-026 exception |
| D-012 | Migration tooling and numbering convention? | **DESIGN/TOOLING APPROVED (2026-10-21): Supabase CLI with forward-only, timestamped migration files for future database changes** | APPROVED (2026-10-21, tooling scope only — see Approval record) | Approved: tooling and file convention (per R-09's core idea). **Not authorized by this approval:** creating migration files, installing or running the Supabase CLI, writing or executing SQL, or any database change — each such step requires its own explicit authorization. Validation evidence (clean install on a disposable target; catalog matches canonical schema) remains outstanding in R-09's required-validation column; deployment recording per file stays mandatory when execution is later authorized. First migration also remains gated by the standing "no SQL until related specs are APPROVED" rule |
| D-013 | Document numbering scope? | **Per company, document type and fiscal year, restarting annually** | APPROVED (2026-10-20) | Sequence table keyed `(company_id, doc_type, fiscal_year)`; server issues official numbers only (D-018) |
| D-014 | Inventory valuation and negative stock? | **Moving weighted average**; **negative inventory prohibited** | APPROVED (2026-10-20) | Cost columns and movement logic in `features/08`; rejected offline inventory conflicts implement the prohibition (D-006) |
| D-015 | Employees and payroll in initial scope? | **YES — full employees and payroll included** | APPROVED (2026-10-20, scope only) | Statutory payroll rules remain OPEN → D-024; spec `features/11` may not be finalized before D-024 |
| D-016 | One unified party record for customers and suppliers? | **YES — one unified party record**, with receivables and payables kept distinct | APPROVED (2026-10-20) | Single parties table; AR and AP remain separate subledger dimensions |
| D-017 | AR/AP balances derived or materialized? | **Derived from posted accounting entries**, with optional derived reporting summaries | APPROVED (2026-10-20) | No hand-entered balance columns; summaries are rebuildable projections |
| D-018 | Offline document numbering? | Offline documents carry **temporary local references**; the **server issues official sequential numbers** on final approval | APPROVED (2026-10-20) | Local references never printed as official numbers; UI must distinguish them |
| D-019 | Editing posted documents? | Posted financial documents **cannot be edited or deleted**; corrections require **linked reversals or credit/debit notes** | APPROVED (2026-10-20) | Immutability enforced server-side; triggers and grants must deny UPDATE/DELETE on posted rows |
| D-020 | Offline permissions, revocation, and expiry? | Offline uses **last-known permissions**, **rechecked at synchronization**; after revocation is detected the **local company data is locked** and pending operations are **preserved** for authorized review; offline access **expires 24 hours** after the last successful server-side permission verification | APPROVED (2026-10-20) | Enforced in the sync client and at the server apply step; UI must warn before expiry |
| D-021 | Local data protection? | Local SQLite databases **must be encrypted**, with encryption keys in **platform-appropriate secure storage**; app unlock requires a **local PIN** | APPROVED (2026-10-20) | Implementation approach is a recommendation → R-05 |
| D-022 | PIN / key recovery mechanism? | Forgotten-PIN recovery **requires verified Supabase authentication and a separately designed safe recovery mechanism**; recommend device-protected keys plus an independently secured recovery mechanism, subject to **security review and recovery testing** | PARTIALLY APPROVED (2026-10-20) | Requirement approved; the **exact mechanism remains OPEN within this row** and must be designed and reviewed before implementation |
| D-023 | Actual VAT rates and jurisdiction-specific tax requirements (rate, exemptions, legal invoice form, reporting)? | — | OPEN | Blocks: `features/06`, `features/07`, `features/10` finalization; mechanics already fixed by D-005, only legal parameters missing |
| D-024 | Payroll legislation and statutory deductions (social security, income-tax withholding, statutory benefits)? | — | OPEN | Blocks: finalization of `features/11` (scope approved by D-015) |
| D-025 | Inventory availability display while offline documents are pending? | — | OPEN | Affects `features/08` and `features/14`; recommendation pending: count only server-posted stock |
| D-026 | Backup/restore prerequisites for the Hasad V1 DEV legacy cleanup (owner Decision A)? | **Backup-policy exception approved for THIS cleanup only:** waive the mandatory fresh full backup and isolated restore drill for the disposal of Hasad V1 disposable test data in DEV `sxasnunzspkuwbxiddqd`. Owner accepts permanent unrecoverability of deleted legacy test data | APPROVED (2026-10-21, scoped exception — see Approval record) | Amends `11_MIGRATION_AND_RESET_PLAN.md` Part B items 4–5 and `12_BACKUP_AND_RECOVERY.md`. **Scope:** ONLY the identified Hasad V1 cleanup in DEV `sxasnunzspkuwbxiddqd`. **Does NOT waive** backup/recovery/verification for future V2 production, other projects, or unrelated destructive actions. **Does NOT authorize** any deletion — all other gates (inventory, manifest, authorization, post-cleanup verification) remain in force |
| D-027 | Legacy cleanup scope (owner Decision B)? | **All Hasad V1 application components are in removal scope:** legacy public business tables, views and RPC functions; legacy Auth users and app-specific Auth integrations; legacy Storage buckets and file objects; legacy Edge Functions; legacy webhooks, cron jobs and external integrations; legacy app-specific configuration and secrets **where ownership is confirmed** | APPROVED IN PRINCIPLE (2026-10-21, scope only — see Approval record) | Supabase-managed infrastructure, platform roles, extensions and shared services are **PRESERVED** unless separately reviewed and explicitly authorized. **Extension-owned objects in `public` (pgtap, pg_net) are NOT legacy application objects and are protected.** **Does NOT authorize** deletion or any DEV modification — execution requires separate explicit authorization (no such authorization exists yet) |
| D-028 | Complete read-only DEV metadata inventory recorded? | **VERIFIED 2026-10-21:** full metadata inventory executed successfully; output `local_audit/DEV_INVENTORY_20261021_192155.txt`; run ended `ROLLBACK COMPLETE - NO DATABASE STATE WAS CHANGED` | VERIFIED (2026-10-21, evidence — see Approval record) | Facts (OBSERVED): 24 relations in `public` (22 tables + 2 extension views); 1,112 public functions (33 legacy `postgres`-owned + 1,079 pgtap `supabase_admin`-owned); 6 triggers; 0 sequences; 52 indexes; 110 constraints; 53 RLS policies; 8 extensions; `hasad`/`hasad_api` ABSENT; **no `schema_migrations` table anywhere**. Zero cross-schema dependency from `public` outward. **CORRECTED 2026-10-25:** the original claim that no managed-schema object depends on `public` is wrong — 3 `storage.objects` policies depend on `public.get_my_tenant_id()` (see Defect record below). Findings feed the DRAFT manifest at `docs/legacy_audit/DEV_CLEANUP_MANIFEST_DRAFT.md` |
| D-029 | Are the three `storage.objects` policies (`tenant_isolated_pdf_select/_insert/_delete`) part of the legacy cleanup scope, and how are they authorized? | **They are a NEW, SEPARATE scope item and are NOT authorized.** Evidence (READ-ONLY, `local_audit/DEV_STAGE4_DEPENDENCY_20261025_123320.txt`, ended ROLLBACK): they are the only catalog-tracked blockers to Stage 4; each is permissive, applies to `{PUBLIC}`, is not extension-owned, and depends on exactly `{public.get_my_tenant_id(), storage.foldername(text)}`. Catalog provenance cannot prove authorship | OPEN — **authorization not granted** (2026-10-25) | Prepared only: `scripts/cleanup/03b_remove_legacy_storage_policies.sql` (exact 3-identity allowlist, object-fingerprint guard, DRY_RUN then EXECUTE, no CASCADE). Execution additionally requires the scope token `CONFIRM_DROP_3_LEGACY_PDF_POLICIES_SXASNUNZSPKUWBXIDDQD`; the approved `public`-schema cleanup authorization does **not** satisfy it. **Does NOT authorize** execution or any `storage` DDL |
| D-030 | Add a product read permission to the static catalogue? | **Approve `products.read` as one explicit, read-only permission code in module `products`. Preserve all original 37 codes and meanings. Do not assign it to any role or user automatically.** | APPROVED (2026-10-28; catalogue decision only) | The deployed DEV catalogue remains 37 until separately approved deployment; the proposed catalogue after the candidate changes are separately approved and deployed would be 38. Does not approve RPC/security implementation, role mappings, user overrides, or DEV deployment. See `16_DATABASE_DECISION_PACKAGE.md` §10.1/§11 and `features/02_roles_and_permissions.md` §C. |

## Approval record (appended 2026-10-21)
Design/tooling approvals only. This record supersedes the earlier `—`/OPEN answers of
D-010 and D-012 in place (the rows above are the register's current state); no other row
was touched by this approval.

| Date | ID | Decision approved (exact scope) | Effects (DB / API / Flutter) | Tests implied or still outstanding | Explicit limits |
|---|---|---|---|---|---|
| 2026-10-21 | D-010 | Private data schema **`hasad`**; exposed RPC interface schema **`hasad_api`** (architecture/tooling decision) | DB: future designs place private objects in `hasad` and exposed RPCs in `hasad_api` — **no schema has been created**. API: interface-schema separation becomes the design basis for `10_API_RPC_CONTRACTS.md`. Flutter: unaffected. | R-01 exposure/load validation still outstanding; R-02/R-03 real-JWT, RLS and grant tests still outstanding (UNVERIFIED — isolated security PoC **POSTPONED**) | **Does NOT authorize:** SQL creation/execution; database, schema or role creation; PostgREST exposure changes; any Supabase DEV change; the isolated security PoC. **Remains RECOMMENDED_PENDING_VALIDATION until independently tested:** RLS, RPC grants, `SECURITY INVOKER`/`DEFINER` choices, privilege enforcement, Supabase transaction-pooling behavior |
| 2026-10-21 | D-012 | **Supabase CLI** with **forward-only, timestamped migration files** for future database changes (tooling/convention decision) | DB: none performed. API/Flutter: none. Tooling choice is fixed for when migrations are later authorized | R-09 clean-install-on-disposable-target validation still outstanding; deployment recorded per file when execution is authorized | **Does NOT authorize:** creating migration files, installing/running Supabase CLI, writing/executing SQL, or any database change. The standing "no SQL until related specs are APPROVED" gate is unchanged |

Statuses of every other decision (D-001…D-009, D-011, D-013…D-025), all R-items'
recommendation status, and all O1–O34 items are **unchanged** by this record. Feature
specification approval states are **unchanged** (all remain DRAFT).

## Approval record — owner Decisions A and B (appended 2026-10-21)

Scope/policy decisions only. These rows record the owner's explicit instructions of
2026-10-21; they **do not authorize any deletion or any Supabase DEV modification**.

| Date | ID | Decision approved (exact scope) | Effects (DB / API / Flutter) | Tests implied or still outstanding | Explicit limits |
|---|---|---|---|---|---|
| 2026-10-21 | D-026 | **Backup-policy exception (Decision A):** waive the mandatory fresh full backup and isolated restore drill for the disposal of Hasad V1 disposable test data in DEV `sxasnunzspkuwbxiddqd`; owner accepts permanent unrecoverability | DB: none performed. Policy: amends `11_MIGRATION_AND_RESET_PLAN.md` Part B items 4–5 and `12_BACKUP_AND_RECOVERY.md` | Post-cleanup verification checklist still required (`DEV_CLEANUP_MANIFEST_DRAFT.md`) | **Applies ONLY** to the identified Hasad V1 DEV cleanup. **Does NOT waive** backup/recovery/verification for future V2 production, other projects, or unrelated destructive actions. **Does NOT authorize** deletion |
| 2026-10-21 | D-027 | **Legacy cleanup scope (Decision B):** remove all Hasad V1 application components — legacy public tables/views/RPCs, legacy Auth users + app-specific Auth integrations, Storage buckets/objects, Edge Functions, webhooks/cron/external integrations, and app-specific config/secrets where ownership is confirmed | DB/API/Platform: scope defined only; nothing performed | Platform inventory (Part B §9) outstanding; per-object ownership confirmation outstanding | Supabase-managed infrastructure, platform roles, extensions and shared services **preserved** unless separately authorized. **pgtap/pg_net and all extension-owned `public` objects are protected.** **Does NOT authorize** deletion or any DEV change — execution needs a separate explicit authorization |
| 2026-10-21 | D-028 | **Complete read-only metadata inventory VERIFIED:** `local_audit/DEV_INVENTORY_20261021_192155.txt` (run ended `ROLLBACK COMPLETE - NO DATABASE STATE WAS CHANGED`) | DB: evidence only; no state changed | — | Evidence/planning only; authorizes nothing |

**Residual OPEN after this record:** D-011 (Storage/Auth/Edge/webhook/cron/secret
**inventory** remains PENDING INVENTORY per Part B §9 — disposition is decided, the
item-level list is not yet captured); D-023, D-024, D-025; the isolated security PoC
remains **POSTPONED**.

Statuses of every other decision (D-001…D-010, D-012…D-025), all R-items'
recommendation status, and all O1–O34 items are **unchanged** by this second record.
Feature specification approval states are **unchanged** (all remain DRAFT).

## Recommendations pending validation (NOT approved architecture)
These are **RECOMMENDED_PENDING_VALIDATION** only. They must be validated by the
listed tests and then explicitly approved (or replaced) before any dependent
schema, API, or Flutter structure is treated as decided.

| ID | Topic | Recommendation | Required validation before adoption |
|---|---|---|---|
| R-01 | Supabase schema organization | V2 objects in a dedicated schema (e.g., `hasad`) with explicit PostgREST exposure; legacy objects untouched until the separately authorized reset. **Design core approved as D-010 (2026-10-21): `hasad` private / `hasad_api` exposed — the recommendation itself (exposure mechanics) stays RECOMMENDED_PENDING_VALIDATION** | Load test on the reused DEV project proving old RPCs keep working; exposure change reviewed |
| R-02 | RPC security model and grants | `SECURITY INVOKER` with pinned `search_path` as the default; **deliberate, reviewed table privileges** granted to the invoking role for exactly the tables its functions touch; **tenant data access only through appropriately authorized RPCs; no arbitrary direct financial-table reads from application roles; no direct writes to authoritative posting tables; RPC execution must not bypass domain-level permission checks; sensitive payroll data separately protected (`features/11` C13)**; nothing for `anon`. **Clarification (2026-10-21, audit batch 1):** the intended access boundary is RPC-controlled and least-privilege, but the exact INVOKER/DEFINER choice, the table-grant set and the RLS implementation are **UNVERIFIED** pending the isolated executable PoC. **The D-010/D-012 approvals of 2026-10-21 change nothing here:** RLS, RPC grants, `SECURITY INVOKER`/`DEFINER` choices, privilege enforcement, and Supabase transaction-pooling behavior all remain **RECOMMENDED_PENDING_VALIDATION** until independently tested (the security PoC is POSTPONED). Several feature specs currently record `SELECT` grants on financial tables to `authenticated` — these are recorded as explicit follow-up alignment items in `07_SECURITY_TENANCY_RLS.md`, not silently changed here | Real-JWT permission matrix test per role. Note: an INVOKER function **cannot** write tables after its role's privileges are revoked — the grant set is part of the design, never an afterthought |
| R-03 | Tenant isolation and session context | `company_id` derived **server-side from verified membership on every call**; an application-controlled session variable may be used only as a filter **after** membership validation, never as proof of membership; RLS remains the second line of defense | Cross-company negative tests with real JWTs; membership-revocation mid-session test |
| R-04 | Cross-device sync sequence and changelog ordering | **Superseded in wording / clarified 2026-10-21 (audit batch 1).** Original recommendation: downloads ordered by a per-company sequence created inside the posting transaction. **Clarification:** the authoritative sync design requires a safe **post-commit publication ordering** mechanism — an ordinary sequence allocated inside the posting transaction does not establish commit order (a rolled-back allocation leaves a gap; two committed transactions may commit in a different order than their sequences). The current design (`08_OFFLINE_SYNC.md`, `features/14` C9–C10, I33): provisional `sync_changes` rows are invisible to clients until publication; `public_seq` is assigned **at publication, for committed rows only**, under a per-company advisory lock, monotonic in publication order. Clients use commit watermarks and **must tolerate gaps**; `bigserial` must **not** be treated as gap-free or commit-ordered per company | Two-device ordering test; kill-and-resume download test; gap-injection test; publication-after-commit ordering proof |
| R-05 | SQLCipher implementation and key recovery | `drift` + SQLCipher where supported; PIN-derived key; recovery per D-022 | **Windows support spike**; key-loss and device-restore drills; security review |
| R-06 | Flutter libraries and state management | Riverpod + drift + feature-first layers (`presentation/application/domain/data`) | `flutter analyze` clean; first vertical slice builds on Windows **and** Android |
| R-07 | Monetary intermediate precision | `NUMERIC(19,4)` for unit price, quantity, unit cost; line-level **HALF_UP to 2dp**; document total = sum of rounded lines; Dart computes with `Decimal` | SQL↔Dart parity test set (≥100 generated invoices, incl. 0.333×3 and weight fractions) |
| R-08 | UUID version | **UUIDv7** for primary keys | Cross-language generation test; index-performance check at realistic volume |
| R-09 | Migration tooling | Supabase CLI; forward-only timestamped files in `supabase/migrations/`; disposable-target install before deployment; deployment recorded per file. **Core approved as D-012 (2026-10-21) — validation evidence below still outstanding; no files created and no CLI run** | Clean install on a disposable project; catalog matches canonical schema |

## Consolidated register of owner-pending O-items (O1–O34)
Consolidated 2026-10-21 (audit batch 1) from the feature specs' §L sections. **This is a
read-only consolidation: no O-item is answered, approved or resolved here; none may be
treated as decided by appearing in this register.** Each row preserves its original ID,
source and recommended default (where one is documented). `Status` reflects the feature
spec, not a new approval. Groups match the audit's G1–G5 question bundles. D-items
(D-010/D-011/D-012/D-023/D-024/D-025) remain in the main register above and are only
cross-referenced here.

### G1 — Migration and environment
**Status update (2026-10-21):** the G1 blockers **D-010** (schema naming/exposure design —
approved as `hasad` private / `hasad_api` exposed) and **D-012** (migration tooling —
approved as Supabase CLI, forward-only timestamped files) are now **OWNER_APPROVED within
the recorded design/tooling scope only** (see Approval record): neither approval authorizes
SQL, migration files, CLI execution, or any DEV change, and R-01/R-09 validation evidence
remains outstanding. Still OPEN in this group: **D-011** (Storage disposition). The
isolated security-PoC execution gate remains **POSTPONED** (owner approval pending;
database and roles do not yet exist).

### G2 — Accounting and permissions
| ID | Decision | Source | Status | Recommended default | Approval stage | Dependency / blocker |
|---|---|---|---|---|---|---|
| O1 | Israeli statutory/accountant CoA requirements (mandated structure or minimum accounts) and starter-chart template content | `features/03` §L | REQUIRES_OWNER_DECISION | none documented — no government-mandated CoA assumed either way | before CoA template seed; part of the D-023 legal bundle | feeds D-023; template seed |
| O2 | Automated year-end closing/opening entries vs manual accountant-prepared | `features/04` §L | REQUIRES_OWNER_DECISION | automated | before `features/04` release | year-end automation implementation |
| O3 | Who closes periods; audited reopening owner-only vs delegated; intermediate locked-not-closed state? | `features/04` §L | REQUIRES_OWNER_DECISION | owner-only audited reopening; **no** intermediate state | before `features/04` release | period-close role in the role catalogue |
| O4 | Account-code immutability after posting | `features/03` §L (C3) | REQUIRES_OWNER_DECISION | immutable after posting; names always editable | before `features/03` release | — |
| O5 | Accrual basis confirmation (interacts with cash-basis tax reporting?) | `features/04` §L | REQUIRES_OWNER_DECISION | accrual basis confirmed (implied by double-entry) | before 04/06/07/10 release | interacts with O14, O26 |
| O6 | Certification process for the first-year opening trial balance (who signs) | `features/04` §L | REQUIRES_OWNER_DECISION | owner-certified; signatory TBD | before first opening-balance load | opening-stock RPC (`features/08` K) |
| — | Predefined role catalogue content and permission-code enumeration (incl. `payroll_officer` scope, admin-manages-admin, `module_account_map` change tier, `inventory.adjust` tier, `reports.export` granularity) | `features/01` §L, `features/02` §L, `features/03` §L, `features/08` §L, `features/12` §L | Owner decision (unnumbered — not assigned an O-ID) | catalogue set documented in `features/02` §L, RECOMMENDED_PENDING_VALIDATION | before permission seed migration | security PoC (R-02) |

### G3 — Trade, cash, inventory, expenses and reports
| ID | Decision | Source | Status | Recommended default | Approval stage | Dependency / blocker |
|---|---|---|---|---|---|---|
| O7 | Tender methods enumeration and check handling | `features/09` §L (shared `features/05`) | REQUIRES_OWNER_DECISION | reference fields only in v1; no dedicated checks module | before `features/09` release | affects `features/05` party refund fields |
| O8 | Bank statement import format for v1 | `features/09` §L | REQUIRES_OWNER_DECISION | manual entry only in v1; import later | before `features/09` release | — |
| O9 | Cash-count variance posting policy (shrinkage/overage) | `features/09` §L | REQUIRES_OWNER_DECISION | reporting only; no automatic gain/loss posting | before `features/09` release | — |
| O10 | Overpayment / unapplied-credit policy | `features/09` §L (shared `features/05`) | REQUIRES_OWNER_DECISION | overpayments allowed as unapplied party credits | before `features/09` release | — |
| O11 | Sales-return cost policy | `features/08` §L (shared `features/06`) | REQUIRES_OWNER_DECISION | original issue cost | before `features/06/08` release | — |
| O12 | Costing pool scope | `features/08` §L | **APPROVED 2026-10-30** | per-warehouse moving weighted average | recorded below |
| O13 | `INVENTORY_ADJUSTMENT` gain/loss account treatment | `features/08` §L | REQUIRES_OWNER_DECISION | none recorded; feeds the CoA template under O1 | before `features/08` release | O1 |
| O14 | Clearing-account receipt model vs bill-only receipts | `features/07` §L | REQUIRES_OWNER_DECISION | clearing-account receipt model | before `features/07` release | interacts with O5 |
| O15 | Cash-bill settlement via linked payment document | `features/07` §L (shared 06/09) | REQUIRES_OWNER_DECISION | linked payment document + allocation in one transaction | before `features/06/07/09` release | — |
| O16 | Numbering for quotations/orders at creation | `features/06`/`07` §L (carried `features/13`) | REQUIRES_OWNER_DECISION | server numbering at creation; `issuance='creation'` rows stay dormant until answered | before quote/order release | `document_types` rows stay dormant |
| O17 | Standalone goods issue / goods-in-transit in v1 | `features/06` §L | REQUIRES_OWNER_DECISION | defer; ship-with-invoice is the v1 default | before `features/06` release | — |
| O18 | Invoice price vs goods-receipt valuation differences | `features/07` §L | REQUIRES_OWNER_DECISION (accountant validation) | `PURCHASE_PRICE_VARIANCE` at bill posting | before `features/07` release | — |
| O19 | Purchase-return cost divergence (current average vs document price) | `features/07` §L | REQUIRES_OWNER_DECISION (accountant validation) | route difference to `PURCHASE_PRICE_VARIANCE` | before `features/07` release | — |
| O20 | Non-recoverable VAT posting | `features/07` §L (carried `features/10`) | REQUIRES_OWNER_DECISION (accountant/legal) | dedicated `NONRECOVERABLE_VAT` expense role | before 06/07/10 release | D-023-adjacent |
| O21 | Freight, duties and landed-cost allocation | `features/07` §L (carried `features/08`) | REQUIRES_OWNER_DECISION (accountant/legal) | deferred; explicitly not v1 inventory cost | before any landed-cost implementation | — |
| O22 | Credit/debit notes against previously settled bills | `features/07` §L | REQUIRES_OWNER_DECISION | normal allocation flow producing an unapplied credit or refund request | before `features/07` release | — |
| O23 | Expense approval workflow | `features/10` §L | REQUIRES_OWNER_DECISION | none in v1 (posting permission suffices) | before `features/10` release | — |
| O24 | Receipt attachments — storage, retention, offline capture | `features/10` §L | REQUIRES_OWNER_DECISION | per-company Storage folder; online-only capture in v1 | before `features/10` release | D-011 (Storage disposition) |
| O25 | AR/AP aging bucket boundaries | `features/12` §L | REQUIRES_OWNER_DECISION | 0–30 / 31–60 / 61–90 / 90+ days from due date | before `features/12` release | — |
| O26 | Cash-flow classification/reporting | `features/12` §L | REQUIRES_OWNER_DECISION | no cash-flow statement in v1 (container statements only) | before `features/12` release | interacts with O5 |
| O28 | Reimbursement vehicle | `features/10` §L | REQUIRES_OWNER_DECISION | employee-as-party via `settlement='employee'` | before `features/10` release | boundary recorded in `features/11` C12 |
| O29 | Expenses↔Purchases ownership boundary and duplicate-guard scope | `features/10` §L | REQUIRES_OWNER_DECISION | goods/inventory costs with supplier invoices → Purchases; standalone operating costs → Expenses; guard on `(party, external_ref)` across both | before `features/10`/`07` release | — |

### G4 — Legal and statutory configuration
No additional O-numbered items in this group. The G4 blockers are registered rows
**D-023** (VAT rates, legal invoice form, tax-ID format) and **D-024** (statutory payroll
legislation) in the main register above. Cross-referenced O-items requiring
accountant/legal validation are **O18, O19, O20, O21** (listed under G3, flagged there);
tax-ID format validation for Israeli IDs is an unnumbered owner item in `features/05` §L
(recommended default: stored as text only, no compliance check).

### G5 — Payroll, UI and other policy choices
| ID | Decision | Source | Status | Recommended default | Approval stage | Dependency / blocker |
|---|---|---|---|---|---|---|
| O27 | Sync draft-conflict resolution | `features/14` §L (carried in `08_OFFLINE_SYNC.md`) | REQUIRES_OWNER_DECISION | reject stale versions, manual reconciliation, no silent auto-merge | before sync release | — |
| O30 | Official number format per document type | `features/13` §L | REQUIRES_OWNER_DECISION | `PREFIX-YYYY-NNNN` (RECOMMENDED_PENDING_VALIDATION) | before numbering seed | I8 gap-policy claim withheld until PoC tests |
| O31 | Historical legal-identity snapshots on posted documents | `features/13` §L (carried `docs/06`) | REQUIRES_OWNER_DECISION | snapshot legal name/tax ID/address at posting (mechanism RECOMMENDED_PENDING_VALIDATION) | before print-template finalization | D-023 (legal fields) |
| O32 | Leave/attendance module boundary | `features/11` §L | REQUIRES_OWNER_DECISION | no leave/attendance module in v1; manual quantity inputs only | before `features/11` release | entitlements deferred to D-024 |
| O33 | Employee self-service access to own data/payslips | `features/11` §L | REQUIRES_OWNER_DECISION | none in v1 (no employee logins) | before `features/11` release | — |
| O34 | Advance settlement flexibility (deduction caps) | `features/11` §L | REQUIRES_OWNER_DECISION | no deduction cap in v1 (capacity ≤ derived open advance) | before `features/11` release | statutory caps arrive with D-024 |

Unnumbered owner items in this group: offline payroll **posting finalization**
online-only (recommendation in `features/11` §L — RECOMMENDED_PENDING_VALIDATION,
consistent with D-006); role-catalogue mapping for `payroll.setup/run/reverse/view/
payslip` (`features/02` owner decision); the D-022 recovery-mechanism design (registered
row above, PARTIALLY APPROVED).

## How to close an OPEN decision
1. Owner answers in this table (or in the conversation, then recorded here).
2. Record date, reason, effects on DB/API/Flutter, and affected documents.
3. Update the affected documents' text and status; do not leave contradictions.

## Defect record — Stage 4 dependency scan (appended 2026-10-25)

Recorded under the "stop and record discrepancies" rule (working agreement §1).

- **OBSERVED — failure.** Stage 4 (`scripts/cleanup/04_drop_functions.sql`) in `EXECUTE` aborted with
  `cannot drop function get_my_tenant_id() because other objects depend on it`.
  15 `DROP FUNCTION` statements had already run in the same transaction; the transaction never reached
  `COMMIT`, so the script's own post-drop verification never ran. No state change was committed.
- **OBSERVED — root cause (fail-open scan).** The Stage 4 preflight resolved `pg_depend` dependents only for
  `classid IN (pg_class, pg_proc)`. For a `pg_policy` dependent both resolution joins produced NULL, and the
  row was then discarded by `WHERE COALESCE(dep.nspname,'') <> ''`. The same blind spot applied to
  `pg_attrdef`, `pg_constraint`, `pg_type`, `pg_operator`, `pg_cast`, `pg_statistic_ext`, `pg_ts_*` and
  `pg_extension`. A dependency the scan could not resolve therefore became a dependency it ignored.
- **OBSERVED — evidence gap.** `scripts/inventory/dev_inventory_readonly.sql` enumerated policies only for
  `nspname = 'public'`, so policies outside `public` were never inventoried. The "53 policies" figure in
  D-028 and in the manifest is a **`public`-only** count.
- **CORRECTED — D-028 factual claim.** D-028's "zero managed-schema object depending on `public`" is **wrong**.
  Three `storage.objects` policies depend on `public.get_my_tenant_id()`. D-028's counts and all other
  findings stand; only that dependency statement is corrected here.
- **CORRECTED — scanner.** The Stage 4 preflight now resolves dependents by `classid` across all catalog
  classes, tolerates only the 33 target functions and the 22 legacy tables (`relkind='r'`), names any other
  dependent in the exception, and treats an unmapped class as a blocker. No `CASCADE` was introduced.
- **OPEN — authorization.** Removing the three Storage policies is a separate scope item (**D-029**), not
  covered by any existing authorization.
- **Evidence:** `local_audit/DEV_STAGE4_DEPENDENCY_20261025_123320.txt` (read-only, ended `ROLLBACK`).
- **VERIFIED — subsequent Stage 4 execution.** Owner-confirmed actual `psql` output establishes that a later, corrected Stage 4 run dropped all 33 authorized legacy functions, completed its verification, and **COMMITTED**. This supersedes the earlier entry's “No state change was committed” conclusion as the current-state result; the documented failed attempt and its scanner defect remain historical facts.

## Build-blocker record — V2 database authorization (2026-10-26)

- **OWNER INSTRUCTION:** Begin and deploy the Hasad ERP V2 database foundation to DEV project `sxasnunzspkuwbxiddqd`.
- **DOCUMENTATION DISCREPANCY:** The authoritative V2 schema, ERD, security/RLS, RPC, migration, and feature specifications remain `DRAFT`; `05_DATABASE_SCHEMA.md` explicitly says “NOT SQL-READY”, and `15_DECISION_LOG.md` records their approval states as unchanged. D-010/D-012 approve only schema organization and migration tooling, explicitly not SQL creation/execution.
- **EFFECT:** No V2 table, RLS/privilege, trigger, function, RPC, or seed migration can be authored or applied without selecting proposed mechanics and unresolved business decisions as if they were approved. That would violate the clean-slate and no-invented-rules requirements.
- **OWNER-SCOPED EXCEPTION (2026-10-26):** The owner authorized the independently specified D-010 schema boundary. `supabase/migrations/20261026000000_v2_foundation_schemas.sql` created only the empty `hasad` and `hasad_api` schemas in DEV `sxasnunzspkuwbxiddqd` and **COMMITTED**. Owner-confirmed post-deployment verification found both schemas present. It neither approves nor implements table, security, RLS, grant, function, trigger, RPC, seed, or PostgREST-exposure behavior.
- **OWNER-SCOPED PREPARATION (2026-10-26):** Local SQL-contract preparation is authorized for only `hasad.user_profiles`, `hasad.companies`, `hasad.roles`, and `hasad.company_memberships`. The owner requires UUID keys; restrictive `user_profiles.id → auth.users.id`; roles scoped to one company with `UNIQUE(company_id, code)`; one company per user; cross-company role assignment prevented; and forced/default-deny RLS with no application grants, policies, RPCs, or PostgREST exposure. This authorizes no table deployment until the remaining exact definitions are approved.
- **IDENTITY BOOTSTRAP DETAIL (2026-10-26):** Owner specified `companies.created_by` as restrictive and non-null; `companies.status` as `active|suspended` defaulting to `active`; nullable profile display/check-time fields; membership UUID/company/user/optional-role/owner/status/inviter/revocation fields; membership status `active|suspended|revoked`; revocation timestamp consistency; no membership status default; and the rule that `role_id` can be null only for an owner. The owner also requires forced/default-deny RLS and no grants/policies/RPCs/triggers/seeds. **OPEN MATERIAL GAP:** `roles` still lacks approved exact column/null/default and FK-action definitions, and explicit delete actions remain unspecified for the non-Auth FKs. No four-table migration is created until those details are decided.
- **IDENTITY ROLE/FK CONTRACT APPROVED (2026-10-26):** `roles(id uuid PK, company_id uuid NOT NULL, code text NOT NULL, is_system boolean NOT NULL DEFAULT false)` with `UNIQUE(company_id, code)` and `UNIQUE(company_id, id)` is approved. Every remaining identity-foundation FK uses `ON DELETE RESTRICT`: role→company; membership→company/profile/(company,role)/inviter. This resolves the prior material gap and authorizes preparation (not deployment) of the exact four-table, forced/default-deny-RLS migration. No role catalogue, policy, grant, RPC, trigger, or seed is authorized.
- **DEPLOYMENT EVIDENCE (2026-10-26):** Owner-confirmed PostgreSQL output establishes that `20261026000100_v2_identity_tenancy_foundation.sql` created the four approved identity tables and **COMMITTED** after verification. The deployed objects are `hasad.user_profiles`, `hasad.companies`, `hasad.roles`, and `hasad.company_memberships`.
- **MIGRATION-HISTORY RECONCILIATION (2026-10-26):** Local Supabase CLI 2.121.0 authenticated to the linked DEV project and initially found no remote history rows for local migrations `20261026000000` and `20261026000100`, consistent with owner-confirmed prior `psql` deployment outside CLI history. A CLI read-only catalog query independently verified the foundation schemas, four tables, 18 expected columns, 7 restrictive FKs, composite role FK, 8 named constraints, partial index, forced RLS, and zero policies/functions/non-internal triggers/table ACLs. Under separate owner authorization, `supabase migration repair` recorded exactly `20261026000000` and `20261026000100` as `applied`; final `migration list --linked` showed both local/remote pairs matching. A post-repair read-only catalog query confirmed the same 4 tables, 7 restrictive FKs, forced RLS, and zero policies/functions/non-internal triggers/table ACLs. No migration SQL was re-executed.
- **STATUS:** Schema-only and four-table identity foundations are **DEPLOYED, VERIFIED, AND CLI-HISTORY RECONCILED**. Broader data/security foundation work remains blocked pending its own owner-approved, SQL-ready specifications. No other DEV object is recorded as deployed under this record; the later permission-foundation deployment is recorded separately below.

## Permission-foundation preparation record (2026-10-26)

- **STATUS AT PREPARATION TIME:** PREPARED, NOT DEPLOYED — superseded by the deployment-evidence record below. This preparation task opened no database connection, ran no SQL, changed no migration history, and did not touch the four deployed identity tables.
- **AUTHORITY:** Owner direction to finalize the C1/C2 contract; deployment remains gated on one explicit approval of `docs/16_DATABASE_DECISION_PACKAGE.md` §11.
- **PREPARED STRUCTURE:** `supabase/migrations/20261026000200_v2_permissions_foundation.sql` — exactly three tables (`hasad.permissions`, `hasad.role_permissions`, `hasad.user_permission_overrides`), four `ON DELETE RESTRICT` FKs, two non-unique FK indexes, and `ENABLE` + `FORCE` RLS. No rows, policies, grants, functions, triggers, RPCs, or exposure.
- **PREPARED CATALOGUE:** `supabase/migrations/20261026000210_v2_permission_catalogue_seed.sql` — exactly the 37 documented codes, with module prefixes matching the code namespace. No role rows or role mappings are inserted because roles are company-scoped.
- **PREPARED POC:** `scripts/security/poc_c1_c2_default_deny.sql` (read-only, target-guarded, refuses DEV) and `scripts/security/poc_c1_c2_real_jwt.md` (real-JWT matrix, blocked until approved policies/RPCs exist).
- **PREPARED DEPLOYMENT:** `scripts/deploy/deploy_v2_permissions_foundation.ps1` — static checks, read-only catalog/history preflight, `migration list`, dry-run, CLI push restricted to the two prepared versions, and post-deploy verification. Not run; requires `SUPABASE_DB_PASSWORD` in the operator environment, never as an argument.
- **CONTRADICTION AUDIT RESOLVED IN §11:** override escalation against `fiscal.close`, `inventory.adjust`, and `cash.post`; admin-manages-admin; coarse `parties.manage` scope; cashier expense-payment scope; absent read codes; auditor restriction.
- **DOCUMENTATION DEVIATION (recorded, not approved as a new rule):** `role_permissions.role_id` uses `ON DELETE RESTRICT`, whereas `docs/05_DATABASE_SCHEMA.md` illustrates “cascade with unassigned role”. No role-delete lifecycle is approved and the workspace forbids `CASCADE` shortcuts; revisit only when role deletion is separately decided.
- **STATIC VALIDATION:** PASS — exact table/FK/index/RLS counts, no DDL/DML beyond approved `CREATE`/`ALTER ... RLS`/`COMMIT`, exact 37-code set, module-prefix consistency, no role/mapping seed rows, PoC DEV refusal and read-only guard, and approval-block/seed equality. No remote verification is claimed.
- **STILL BLOCKED AT PREPARATION TIME:** explicit §11 approval; disposable-target PoC execution; verified-email source; invitation/audit migration; all application-facing policies, grants, and RPCs. The §11 approval and structural deployment were completed later the same day, as recorded below; the PoC, invitation/audit, and application-surface blockers remain.

## Permission-foundation deployment evidence (2026-10-26)

- **AUTHORITY:** Owner approved `docs/16_DATABASE_DECISION_PACKAGE.md` §11 for preparing and deploying the default-deny structural permissions foundation, with these conservative scope decisions: `parties.manage` remains a shared catalogue code but no customer/supplier RPC may be exposed; cashier receives only the five `cash.*` codes; `fiscal.close` remains owner-only; `sales` must never receive `cash.post`, including through overrides; `inventory.adjust` remains owner/admin-only with no allow-overrides; `auditor` receives `reports.view` only; no implicit read codes, role codes, or access grants; the C1/C2 PoC remains mandatory before application-facing policies, grants, or RPCs.
- **SCOPE:** Exactly `20261026000200_v2_permissions_foundation.sql` and `20261026000210_v2_permission_catalogue_seed.sql`. No other migration, role row, role mapping, policy, grant, function, trigger, RPC, or PostgREST exposure.
- **PREFLIGHT — linked project:** `supabase/.temp/linked-project.json` reported `sxasnunzspkuwbxiddqd` exactly.
- **PREFLIGHT — existing state.** Read-only CLI catalog query verified 4 identity tables, 4 forced-RLS identity tables, 0 permission tables, 0 policies, 0 `hasad`/`hasad_api` functions, 0 unexpected `hasad` tables, 2 prior history rows, 0 new history rows, and `auth.users` present.
- **PREFLIGHT — history and pending set.** `supabase migration list --linked` showed local/remote pairs for `20261026000000` and `20261026000100`, and empty remote for `20261026000200` and `20261026000210`. `supabase db push --linked --dry-run --skip-vault --yes` exited `0` and listed exactly those two migrations.
- **CREDENTIALS:** `SUPABASE_DB_PASSWORD` was **NOT_SET** in the process environment. No password or API key was requested, printed, stored, or passed as an argument. The authenticated CLI connection applied the push without an interactive password prompt; stdin was closed during execution.
- **EXECUTION:** `supabase db push --linked --skip-vault --yes` exited `0`. CLI output reported `Applying migration 20261026000200_v2_permissions_foundation.sql...`, then `Applying migration 20261026000210_v2_permission_catalogue_seed.sql...`, then `Finished supabase db push.` The reported migration list contained exactly the two approved versions; seeds and roles were empty.
- **POST-DEPLOY — tables and RLS.** Read-only CLI catalog query found 3 permission tables (`hasad.permissions`, `hasad.role_permissions`, `hasad.user_permission_overrides`), 7 forced-RLS tables total (the 4 identity tables plus the 3 permission tables), and 0 unexpected `hasad` tables. Each permission table individually reported `rls_enabled = true`, `rls_forced = true`, and `acl_is_null = true`.
- **POST-DEPLOY — foreign keys.** Exactly 4 permission FKs, all `ON DELETE RESTRICT` (`confdeltype = 'r'`):
  - `role_permissions_permission_code_fkey`: `hasad.role_permissions` → `hasad.permissions`
  - `role_permissions_role_id_fkey`: `hasad.role_permissions` → `hasad.roles`
  - `user_permission_overrides_membership_id_fkey`: `hasad.user_permission_overrides` → `hasad.company_memberships`
  - `user_permission_overrides_permission_code_fkey`: `hasad.user_permission_overrides` → `hasad.permissions`
- **POST-DEPLOY — indexes.** Exactly the two expected non-unique FK indexes: `role_permissions_permission_code_idx` on `hasad.role_permissions` and `user_permission_overrides_permission_code_idx` on `hasad.user_permission_overrides`.
- **POST-DEPLOY — catalogue.** Exactly 37 rows in `hasad.permissions`; 0 missing from the approved 37-code set; 0 module-prefix mismatches. No role rows or role mappings were seeded (roles are company-scoped).
- **POST-DEPLOY — default deny.** 0 rows in `hasad.role_permissions`; 0 rows in `hasad.user_permission_overrides`; 0 policies across all 7 tables; 0 tables with non-null ACLs across all 7 tables; 0 functions in `hasad`/`hasad_api`; 0 non-internal triggers on the 3 permission tables.
- **POST-DEPLOY — history.** `supabase migration list --linked` reported all four local/remote pairs matching: `20261026000000`, `20261026000100`, `20261026000200`, `20261026000210`.
- **STATUS:** `20261026000200_v2_permissions_foundation.sql` and `20261026000210_v2_permission_catalogue_seed.sql` are **DEPLOYED / VERIFIED** in DEV `sxasnunzspkuwbxiddqd`. Role rows, role mappings, application policies, grants, functions, triggers, RPCs, and PostgREST exposure remain absent. The C1/C2 PoC on a disposable target and all application-facing work remain **BLOCKED**.

## C1/C2 local disposable mechanics PoC evidence (2026-10-26)

- **SCOPE / ISOLATION:** A fresh local PostgreSQL 17 cluster ran on
  `127.0.0.1:55432` under the approved temporary directory. It never connected
  to DEV `sxasnunzspkuwbxiddqd`, production, Supabase Auth, or PostgREST. The
  runner stopped and removed the temporary cluster after completion.
- **REPRODUCIBLE ARTIFACTS:** `scripts/security/poc_c1_c2_local_pre.sql`,
  `scripts/security/poc_c1_c2_local_setup.sql`,
  `scripts/security/poc_c1_c2_local_assertions.sql`, and
  `scripts/security/poc_c1_c2_local_run.ps1`. These are test-only artifacts,
  not V2 migrations and not eligible for DEV deployment.
- **EXECUTION:** `powershell -ExecutionPolicy Bypass -File
  scripts/security/poc_c1_c2_local_run.ps1` exited `0`. It applied the four
  already-deployed migration files to the isolated cluster; the existing
  target-guarded default-deny baseline reported `PASS`; then the test-only
  surface/matrix completed with **36 pass / 0 fail**. Evidence:
  `local_audit/C1_C2_LOCAL_POC_20261026_223540.log`.
- **VERIFIED LOCALLY:** forced RLS/default-deny baseline; no direct table access
  for `anon` or `authenticated`; no `PUBLIC` execute on test RPCs; tenant
  isolation; suspended/revoked denial; owner/deny/allow/default-deny resolution;
  owner-only `fiscal.close`; owner/admin-only `inventory.adjust`; permanent
  `sales` denial for `cash.post`; pinned-search-path resistance; and a narrow,
  locked-non-superuser `SECURITY DEFINER` append-only audit helper with actor
  derivation and foreign-company denial.
- **LIMITATION / NO RELEASE CLAIM:** The harness supplied test
  `request.jwt.claims` values through a local auth stub. It did **not** validate
  a real Supabase-issued JWT or prove Supabase Auth, PostgREST, transaction
  pooling, or managed-role ownership behavior. Therefore it does **not** pass
  the required real-JWT disposable-Supabase release gate and does **not**
  authorize DEV application policies, grants, RPCs, functions, triggers, role
  mappings, invitations, audit tables, or ownership safeguards.
- **NEXT GATE:** Exact invitation/audit contracts and actual-Supabase helper
  ownership remain open. The consolidated decision package is
  `docs/16_DATABASE_DECISION_PACKAGE.md` §11.4.
- **DOCUMENTATION DISCREPANCY — OBSERVED:** The already-applied SQL files
  `20261026000200_v2_permissions_foundation.sql` and
  `20261026000210_v2_permission_catalogue_seed.sql` retain their historical
  header phrase “prepared only; not deployed”. Their verified SHA-256 hashes
  remain unchanged (`D815…35E0` and `A574…4257` respectively), so they were not
  edited after deployment. The authoritative current-state record is this log
  and `docs/16_DATABASE_DECISION_PACKAGE.md`; do not rewrite an applied
  migration merely to update a comment. A separate owner decision is required
  if a non-migration documentation index is desired to mirror those headers.

## Owner decision — invitation verified-email authority (2026-10-27)

- **APPROVED:** At invitation acceptance, the authoritative identity email is
  read server-side from `auth.users.email` for the current `auth.uid()`.
  `auth.users.email_confirmed_at` must be non-null.
- **APPROVED:** Compare the invitation email and Auth email as
  `LOWER(BTRIM(email))`; reject missing, empty, or unequal normalized values.
  Provider-specific transformations, including Gmail dot removal and plus-tag
  stripping, are forbidden.
- **APPROVED:** Never accept client-supplied email, `user_metadata`, or an
  unverified JWT email claim as acceptance authority. Recheck the Auth email at
  the acceptance transaction, not at invitation creation.
- **APPROVED SECURITY BOUNDARY:** Application roles receive no direct
  `auth.users` access. The narrow internal access mechanism is not deployable
  until its hosted disposable-Supabase PoC proves the boundary.
- **EFFECT:** This resolves §11.4 item 1's business/source decision. It does
  not approve the remaining invitation/audit row shapes, helper-role topology,
  ownership RPC contracts, test identities, application policies, grants,
  functions, or migrations.

## C2 structural migration preparation record (2026-10-27)

- **OWNER-SCOPED AUTHORITY:** The owner authorized preparation, local validation,
  and review of one migration containing only `hasad.company_invitations` and
  `hasad.audit_log`. The owner explicitly withheld deployment until approving the
  exact structural contract.
- **PREPARED ARTIFACT:**
  `supabase/migrations/20261027000300_v2_invitation_audit_structure.sql`.
  It contains only the two proposed private tables, 7 `ON DELETE RESTRICT` FKs,
  5 indexes, and `ENABLE` + `FORCE` RLS on both tables. It contains no rows,
  policies, grants, functions, triggers, RPCs, role changes, Auth changes,
  Storage changes, or PostgREST exposure.
- **LOCAL VALIDATION:** `scripts/security/validate_v2_c2_structure.ps1` passed
  its static contract scan and a fresh local PostgreSQL 17 catalog test. The
  test applied the four deployed V2 migrations plus the prepared C2 migration,
  verified the two tables, 7 restrictive FKs, 5 explicit indexes, forced RLS,
  zero policies, zero non-internal triggers, zero table ACLs, and zero rows, then
  stopped and removed the local cluster.
- **STATUS:** **PREPARED — NOT DEPLOYED.** No CLI push, migration-history change,
  or DEV database connection occurred for this artifact.
- **MATERIAL BLOCKERS:** §11.6 approval of the exact table contract; token
  delivery and expiry-transition semantics; audit payload/retention vocabulary;
  actual hosted-Supabase locked-role and `auth.users` access PoC; company-name
  and mutation-RPC contracts; last-active-owner trigger/lock design; and a named
  disposable Supabase target with authorized test identities. The structural
  migration does not and cannot enforce those deferred behaviors.

## C2 structural deployment attempt — blocked at dry-run (2026-10-27)

- **AUTHORITY:** The owner approved deployment only of
  `20261027000300_v2_invitation_audit_structure.sql` to DEV
  `sxasnunzspkuwbxiddqd`, subject to the listed preflight safeguards.
- **LOCAL SAFEGUARDS — PASS:** Linked ref matched exactly; the migration SHA-256
  matched `1E9B2F372A482447805327DEFFF15CD5524A8857D82246879D0D902DD31BCEB5`;
  the local static and fresh-PostgreSQL catalog validator passed.
- **READ-ONLY DEV PREFLIGHT — PASS:** `migration list --linked` showed the four
  prior versions matching local/remote and only `20261027000300` pending. A
  read-only catalog query found 7 existing V2 tables with forced RLS, 0 target
  tables, 0 policies, 0 `hasad`/`hasad_api` functions, 0 non-internal `hasad`
  triggers, 0 unexpected `hasad` tables, 4 prior history rows, and 0 target
  history rows.
- **BLOCKER — DRY-RUN FAILURE:** The required command
  `supabase db push --linked --dry-run --skip-vault --yes` exited `1` before it
  could list a pending migration. CLI returned `DbConnectError`: the connection
  to the Supabase PostgreSQL pooler was terminated unexpectedly. This was a
  dry-run; no migration SQL or history mutation was requested or attempted.
- **STATUS:** **NOT DEPLOYED.** Per the owner fail-stop instruction, no real
  `db push` was run and no further remote action was attempted. A new owner
  instruction is required before retrying the dry-run/deployment sequence.

## C2 deployment connectivity retry — blocked at read-only catalog preflight (2026-10-27)

- **SAFE NETWORK DIAGNOSTICS:** The linked ref and approved migration hash still
  matched. DNS resolved the configured Supabase session-pooler hostname and TCP
  port 5432 succeeded. No process-level proxy variables or WinHTTP proxy were
  configured. Proton/VPN-named processes were present, but no matching active
  VPN/proxy adapter was observed. TCP success was not treated as proof of
  PostgreSQL authentication or SSL negotiation.
- **AUTHENTICATED CLI CHECK — PASS:** `supabase migration list --linked`
  completed and showed the four prior versions matching local/remote and only
  `20261027000300` pending.
- **BLOCKER — READ-ONLY CLI FAILURE:** The required `supabase db query --linked`
  catalog preflight then failed before executing its query with
  `DbConfigLoginRoleNetworkError: failed to initialise login role: request timed out`.
  This followed the prior dry-run pooler termination and establishes an
  intermittent CLI login-role/network path failure.
- **STATUS:** **NOT DEPLOYED.** Per the owner instruction not to retry
  indefinitely, no dry-run or real push was attempted after this failure. No
  Auth, Storage, schema, migration-history, policy, grant, function, trigger,
  RPC, or data change was requested or made by this retry attempt.

## C2 structural deployment evidence — deployed and verified (2026-10-27)

- **AUTHORITY:** Owner authorized deployment only of
  `20261027000300_v2_invitation_audit_structure.sql` to DEV project
  `sxasnunzspkuwbxiddqd`.
- **PREFLIGHT — PASS:** Linked ref matched exactly; migration SHA-256 matched
  `1E9B2F372A482447805327DEFFF15CD5524A8857D82246879D0D902DD31BCEB5`.
  The local static/fresh-PostgreSQL C2 validator passed. A fresh read-only DEV
  query found 4 prior history rows, 0 target history rows, 0 target tables, 7
  pre-existing forced-RLS tables, 0 policies, 0 `hasad`/`hasad_api` functions,
  0 non-internal `hasad` triggers, and 0 unexpected `hasad` tables.
- **DRY RUN — PASS:** `supabase db push --linked --dry-run --skip-vault --yes`
  exited `0` and listed exactly
  `20261027000300_v2_invitation_audit_structure.sql`; seeds and roles were empty.
- **EXECUTION — PASS:** `supabase db push --linked --skip-vault --yes` exited
  `0` and reported applying exactly
  `20261027000300_v2_invitation_audit_structure.sql`. No other migration was
  listed; seeds and roles were empty.
- **POST-DEPLOY — PASS:** Read-only DEV catalog verification found both target
  tables; 14 invitation columns and 9 audit columns matching the migration; 7
  `ON DELETE RESTRICT` FKs; exactly 5 required indexes; RLS enabled and forced
  on both tables; 0 policies; 0 table ACLs; 0 functions in `hasad`/`hasad_api`;
  0 non-internal target triggers; and 0 rows in each new table.
- **HISTORY — PASS:** `supabase migration list --linked` shows all local/remote
  pairs matching: `20261026000000`, `20261026000100`, `20261026000200`,
  `20261026000210`, and `20261027000300`.
- **STATUS:** `company_invitations` and `audit_log` are **DEPLOYED / VERIFIED —
  STRUCTURE ONLY**. Invitation acceptance, token generation/delivery, expiry
  processing, audit writer/append-only trigger, ownership safeguards, application
  policies, grants, functions, RPCs, and PostgREST exposure remain absent and
  blocked pending their contracts and the hosted real-JWT PoC.

## Current DEV state verification and readiness review (2026-10-27)

- **VERIFIED — DEV catalog:** A read-only CLI query found 9 `hasad` tables and
  forced RLS on all 9; 37 permission rows; 0 policies; 0 functions in
  `hasad`/`hasad_api`; 0 non-internal `hasad` triggers; 0 table ACLs; and 0 rows
  in `company_invitations` and `audit_log`.
- **VERIFIED — migration history:** A read-only query found all five applied
  versions: `20261026000000`, `20261026000100`, `20261026000200`,
  `20261026000210`, and `20261027000300`.
- **OBSERVED — intermittent CLI issue:** During this review, `supabase migration
  list --linked` failed once while connecting as the temporary CLI role with
  `SQLSTATE 28P01` password authentication failure. The subsequent read-only
  history query succeeded. No remediation, credential change, or write action
  was attempted.
- **SECURITY IMPLEMENTATION STATUS:** C2 behavior remains design-only. The
  non-executable preparation outline is `docs/16_DATABASE_DECISION_PACKAGE.md`
  §11.7; no deployable C2 function, trigger, policy, grant, or RPC has been
  authored or deployed. The existing local PoC harness remains test-only.
- **ERP READINESS STATUS:** `docs/17_ERP_STRUCTURAL_READINESS_PACKAGE.md`
  consolidates the DRAFT module contracts and owner-decision bundles. No ERP
  structural migration is eligible under the current documentation state.

## Owner decision — Core-nine ERP structural foundation (2026-10-27)

- **APPROVED SCOPE:** Prepare and deploy only
  `hasad.company_settings`, `hasad.accounts`, `hasad.module_account_map`,
  `hasad.fiscal_years`, `hasad.fiscal_periods`, `hasad.document_types`,
  `hasad.tax_rates`, `hasad.doc_numbers`, and `hasad.parties`, as specified by
  the Core-nine contract in `docs/17_ERP_STRUCTURAL_READINESS_PACKAGE.md`.
- **APPROVED — legal/contact fields:** Use the exact proposed fields; optional
  legal/contact text remains nullable; no additional field, legal obligation,
  validation, tax rate, or statutory seed is implied.
- **APPROVED — fiscal lifecycle structure:** Include only the proposed
  close/reopen actor/timestamp fields and counters. This authorizes no fiscal
  close/reopen function, policy, grant, or operational behavior.
- **APPROVED — document numbering structure:** `format_prefix` is nullable,
  `pad_length` defaults to 4, and both issuance values are structurally allowed
  but dormant. No number seed, allocator, concurrency mechanism, official
  format, or quote/order numbering behavior is authorized.
- **APPROVED — initial data:** All nine tables start empty. No account, mapping,
  party, settings, document type, tax rate, fiscal calendar, or counter seed.
- **APPROVED — safety boundary:** Implement only row-local/declarative
  constraints and forced default-deny RLS. Cross-row lifecycle enforcement and
  all application access remain deferred to separately reviewed transaction
  logic and the hosted security PoC.
- **PREPARED ARTIFACTS:**
  `supabase/migrations/20261027000400_v2_erp_core_master_fiscal_settings.sql`
  and `scripts/security/validate_v2_erp_core_nine.ps1`. Deployment is authorized
  only if their static, local, linked-DEV, remote-history/catalog, dry-run, and
  post-deploy checks pass exactly; no other migration or object is authorized.

## Core-nine deployment attempt — blocked at dry-run (2026-10-27)

- **LOCAL VALIDATION — PASS:**
  `20261027000400_v2_erp_core_master_fiscal_settings.sql` SHA-256 is
  `4FF4D41B1F9A2111DF6B63CF749AB487046C67CAECC34AECC3BBEFC23E497260`.
  Static validation and a fresh local PostgreSQL 17 catalog test passed: exactly
  9 tables, 18 restrictive FKs, 8 explicit indexes, forced RLS on all 9, zero
  policies/triggers/ACLs/rows, then local-cluster cleanup.
- **READ-ONLY DEV PREFLIGHT — PASS:** Linked ref was exactly
  `sxasnunzspkuwbxiddqd`. DEV contained the 5 prior migration history rows, 9
  forced-RLS V2 tables, 0 Core-nine target tables, 0 policies, 0 functions, 0
  non-internal triggers, 0 table ACLs, and 0 unexpected `hasad` tables. CLI
  migration list showed only `20261027000400` pending.
- **BLOCKER — DRY-RUN FAILURE:** The required command
  `supabase db push --linked --dry-run --skip-vault --yes` exited `1` before it
  could list or apply a migration. CLI returned `DbConnectError`: the connection
  to the Supabase PostgreSQL pooler was terminated unexpectedly.
- **STATUS:** **NOT DEPLOYED.** No real `db push`, migration-history repair,
  schema write, Auth/Storage change, policy, grant, function, trigger, RPC, or
  seed action was attempted after the failure. Per fail-closed instruction, no
  automatic retry was made.

## Core-nine deployment evidence — deployed and verified (2026-10-27)

- **AUTHORITY:** The owner approved the Core-nine structural contract and
  authorized deployment only of
  `20261027000400_v2_erp_core_master_fiscal_settings.sql` to DEV
  `sxasnunzspkuwbxiddqd`.
- **PREFLIGHT — PASS:** Linked ref matched exactly; migration SHA-256 matched
  `4FF4D41B1F9A2111DF6B63CF749AB487046C67CAECC34AECC3BBEFC23E497260`.
  Static and fresh-local-PostgreSQL validation passed. A read-only DEV query
  found 5 prior history rows, 9 existing forced-RLS V2 tables, 0 Core-nine target
  tables, 0 policies/functions/non-internal triggers/table ACLs, and 0 unexpected
  `hasad` tables. `migration list --linked` showed only `20261027000400` pending.
- **DRY RUN — PASS:** `supabase db push --linked --dry-run --skip-vault --yes`
  exited `0` and listed exactly
  `20261027000400_v2_erp_core_master_fiscal_settings.sql`; seeds and roles were
  empty.
- **EXECUTION — PASS:** `supabase db push --linked --skip-vault --yes` exited
  `0` and reported applying exactly that migration. No other migration, seed, or
  role was listed.
- **POST-DEPLOY — PASS:** Read-only DEV catalog verification found 9 Core-nine
  tables with 88 columns, exactly 18 `ON DELETE RESTRICT` FKs, and exactly 8
  explicit indexes. RLS is enabled and forced on all 9. All 9 are empty and have
  0 policies, 0 table ACLs, 0 functions in `hasad`/`hasad_api`, and 0 non-internal
  triggers. Total V2 state is 18 `hasad` tables, all with forced RLS.
- **HISTORY — PASS:** `supabase migration list --linked` shows all six
  local/remote pairs matching through `20261027000400`.
- **STATUS:** Core-nine is **DEPLOYED / VERIFIED — STRUCTURE ONLY**. No account
  mapping, settings, fiscal, tax, numbering, party, journal, policy, grant,
  function, trigger, RPC, seed, Auth/Storage, or application-facing behavior was
  added beyond the approved empty default-deny table structures.

## Phase 7A � Accounting journals deployed (2026-10-27)

- **Linked DEV:** sxasnunzspkuwbxiddqd
- **Migration applied:** 20261028000500_v2_accounting_journals_structure.sql (SHA-256: E8FBEAF706A3B7F082DEC1CF90109B257C6470E7D54A6B9A3858938771E290E0)
- **Tables:** hasad.journal_entries, hasad.journal_lines (2 tables, 22 columns total)
- **Constraints/indexes:** 9 ON DELETE RESTRICT FKs on the new tables; 8 indexes (partial uniques for idempotency_key/entry_no and supporting indexes)
- **Security:** ENABLE and FORCE RLS on both; 0 policies, 0 table ACLs, 0 non-internal triggers
- **Data:** 0 rows
- **History:** supabase_migrations.schema_migrations now includes up to 20261028000500 (7 total). 00600/00700 not in history.
- **Safety:** 00600 (7FC5E9...) and 00700 (B12B33...) were moved out during deployment, dry-run listed only 00500, and restored after deployment with identical SHA-256.
- **Status:** DEPLOYED / VERIFIED � STRUCTURE ONLY. No grants/policies/functions/triggers/RPCs/seeds/application access added.

## Phase 7B � Inventory deployed (2026-10-27)

- **Linked DEV:** sxasnunzspkuwbxiddqd
- **Migration applied:** 20261028000600_v2_inventory_structure.sql (SHA-256: 7FC5E927E1BCC86F1D2232CDA44C723DB1796B460B96B2A026724A7DBF1D1573)
- **Tables:** hasad.warehouses, hasad.product_categories, hasad.units_of_measure, hasad.products, hasad.product_uom_conversions, hasad.stock_levels, hasad.stock_movements, hasad.stock_counts, hasad.stock_count_lines (9 tables, 60 columns)
- **Constraints/indexes:** 20 ON DELETE RESTRICT FKs; composite tenant references; unique constraints; supporting indexes (including movement/source and count/product)
- **Security:** ENABLE and FORCE RLS on all 9; 0 policies, 0 table ACLs, 0 non-internal triggers
- **Data:** 0 rows
- **History:** up to 20261028000600 (8 total). 00700 not in history.
- **Safety:** 00700 moved out, dry-run listed only 00600, restored with identical SHA-256 (B12B33785108814AC4D7EDE1534729140B473124670D9CE8257692695E4BADC5) and remains unapplied.
- **Total hasad tables:** 29 (20 + 9)
- **Status:** DEPLOYED / VERIFIED � STRUCTURE ONLY. No grants/policies/functions/triggers/RPCs/seeds/application access added.

## Phase 7C � Sales & Purchases deployed (2026-10-27)

- **Linked DEV:** sxasnunzspkuwbxiddqd
- **Migration applied:** 20261028000700_v2_sales_purchases_structure.sql (SHA-256: B12B33785108814AC4D7EDE1534729140B473124670D9CE8257692695E4BADC5)
- **Tables:** hasad.sales_documents, hasad.sales_document_lines, hasad.purchase_documents, hasad.purchase_document_lines (4 tables, 66 columns)
- **Constraints/indexes:** 20 ON DELETE RESTRICT FKs; tenant-safe composites; partial uniques for idempotency_key/doc_no/supplier_ref; row-local money/qty/status/VAT checks
- **Security:** ENABLE and FORCE RLS on all 4; 0 policies, 0 table ACLs, 0 non-internal triggers
- **Data:** 0 rows
- **History:** up to 20261028000700 (9 total)
- **Total hasad tables:** 33 (29 + 4)
- **Status:** DEPLOYED / VERIFIED � STRUCTURE ONLY. No grants/policies/functions/triggers/RPCs/seeds/application access added.

## Phase 8 FK correction - local candidate validation (2026-10-27)

- OWNER APPROVAL - LOCAL EDIT ONLY: The owner authorized one structural correction in local candidate 00900: add a tenant-safe FK from `hasad.payment_allocations(company_id, expense_document_id)` to `hasad.expense_documents(company_id, id) ON DELETE RESTRICT`, after the referenced table is created. No DEV deployment was authorized.
- OBSERVED - prerequisite shape: 00800 declares `payment_allocations.expense_document_id uuid NULL`; its exactly-one-target check requires it when `target_kind='expense'`. 00900 declares `UNIQUE(company_id, id)` on `expense_documents`, and neither candidate had this FK before correction. No duplicate FK or conflicting constraint was present.
- OBSERVED - correction: Added named constraint `payment_allocations_company_expense_fkey` in 00900 immediately after the `expense_documents` definition. 00800 was not modified.
- VERIFIED - hashes: 00800 remains `EF076C57F723113A1689405EFFD6B047A3ED5675EC5613D1E00388C1332207BE`. Corrected 00900 is `49AA093E04A5C2F113E6051BFD45DB5B02C04A92F340DF3B5DBBEFC9349F94CA`.
- VERIFIED - static review: Both candidates retain restrictive tenant-safe composite FKs and ENABLE+FORCE RLS on every candidate table. Static scan found no grants, policies, functions, RPCs, or explicit triggers. 00900 alters RLS on six tables created by 00800 plus its five own tables; neither candidate alters a baseline table. The documented baseline accounts key `UNIQUE(company_id,id)` is present in migration 00400 and was recorded as verified in the prior DEV catalog report.
- BLOCKED - PostgreSQL 17 local migration execution: `initdb` emitted restricted-token errors 87 and 3, but completed cluster initialization. `pg_ctl` startup failed with those errors; direct foreground `postgres.exe` startup succeeded and logged that the server was ready. Baseline migration 00100 then failed because this plain local cluster has no Supabase-managed `auth.users`. To honor the no Auth/Storage changes boundary, no local Auth/Storage stubs were created. The nine-migration baseline plus 00800 alone and plus corrected 00900 were not executed; PostgreSQL catalog counts remain unverified. Static checks passed: 00800 has 6 tables, 19 restrictive FKs, and ENABLE+FORCE RLS on all 6; corrected 00900 has 5 tables, 18 restrictive FKs including the correction, and ENABLE+FORCE RLS on all 11 candidate tables. All 19 and 18 candidate references respectively explicitly specify ON DELETE RESTRICT; no grants, policies, functions, triggers, or RPCs were found.
- STATUS: Both Phase 8 candidates remain NOT DEPLOYED. No DEV connection, push, migration repair, reset, Auth/Storage change, or production access was performed. Fresh local PostgreSQL execution remains a prerequisite.
## Phase 8 local PostgreSQL validation recovery (2026-10-27)

- OBSERVED - baseline dependency scan: Of the nine baseline migrations, only `20261026000100_v2_identity_tenancy_foundation.sql` references a Supabase-managed object: `auth.users(id)`. No other managed schema, function, role, extension, Storage or Auth object dependency was found in the nine files.
- VERIFIED - test fixture: `scripts/testing/phase8_local_supabase_compat.sql` supplies only local `auth.users(id uuid PRIMARY KEY)`. No actual Supabase Auth/Storage service, identity, credential, password or token was accessed or changed. The fixture is not in `supabase/migrations`.
- VERIFIED - CASE A execution: Fresh disposable database `phase8_case_a` applied baseline migrations `20261026000000` through `20261028000700` in original order and 00800 only. Catalog: 6 target tables, 60 columns, 19 FKs, 8 CHECK, 8 UNIQUE, 6 PK, 24 indexes, 6/6 forced RLS, zero policies, non-internal triggers, ACLs and candidate rows. Exact column names/order and FK definitions were inspected from catalogs.
- VERIFIED - CASE B execution: Separate fresh disposable database `phase8_case_b` applied the same nine baseline migrations, then 00800 and corrected 00900. Catalog: 11 target tables, 110 columns, 37 FKs, 17 CHECK, 16 UNIQUE, 11 PK, 40 indexes, 11/11 forced RLS, zero policies, non-internal triggers, ACLs and candidate rows after test rollback. Composite tenant FKs included `company_id` on source and referenced columns and all used `ON DELETE RESTRICT`.
- VERIFIED - FK positive catalog shape and negative tests: `payment_allocations_company_expense_fkey` references `hasad.expense_documents(company_id, id)`, with `ON DELETE RESTRICT`; its target key is `expense_documents_company_id_id_key UNIQUE(company_id,id)`. Synthetic test inserts were rejected for both a nonexistent expense document and a real expense document in a different company. The test transaction rolled back; post-test candidate row counts were zero.
- VERIFIED - SHA-256: 00800 unchanged at `EF076C57F723113A1689405EFFD6B047A3ED5675EC5613D1E00388C1332207BE`; corrected 00900 remains `49AA093E04A5C2F113E6051BFD45DB5B02C04A92F340DF3B5DBBEFC9349F94CA`.
- NOT DEPLOYED: No DEV or production connection, push, migration repair, Auth/Storage change or deployed schema change occurred.
- CLEANUP BLOCKED: The local server was stopped. Attempts to drop `phase8_case_a`, `phase8_case_b` and remove `%TEMP%\hasad-phase8-validation-20261027` were rejected by automatic sandbox review because `sandbox_approval` is disabled. The local test files remain inert in the stopped temporary cluster and require permitted cleanup.
- OBSERVED - runner: `scripts/testing/validate_phase8_local.ps1` passed PowerShell parser validation, but direct `.ps1` invocation is blocked by the current execution policy. No execution policy change was made; equivalent migration, catalog and negative-test commands were run directly.


## Phase 8 controlled DEV deployment authorization - preflight blocked (2026-10-27)

- OWNER AUTHORIZATION OBSERVED: Exact local link metadata in `supabase/.temp/project-ref` is `sxasnunzspkuwbxiddqd`. Candidate SHA-256 values match the approved hashes: 00800 `EF076C57F723113A1689405EFFD6B047A3ED5675EC5613D1E00388C1332207BE`; corrected 00900 `49AA093E04A5C2F113E6051BFD45DB5B02C04A92F340DF3B5DBBEFC9349F94CA`.
- OBSERVED - candidate static scope: 00800 still defines the six approved tables; corrected 00900 defines the five approved expense tables and `payment_allocations_company_expense_fkey` after the `expense_documents` composite unique key. No candidate file was changed in this deployment attempt.
- BLOCKED - linked preflight: The local Supabase CLI wrapper exits before CLI commands initialize because it receives `EPERM` writing `%USERPROFILE%\.supabase\telemetry.json.tmp`, which is outside the writable workspace. No workaround, credential relocation, execution-policy change, or privilege elevation was attempted. Therefore remote linked-ref verification, migration history, DEV catalog, pending migrations, and dry-run results were not obtained.
- NOT STARTED: No candidate was isolated from `supabase/migrations`; no dry-run or `db push` was run; Stage A and Stage B were not started. No DEV or production connection/change occurred. Previously verified DEV state remains unconfirmed for this attempt.
- LOCAL CLEANUP: The prior disposable test cluster exists at `%TEMP%\hasad-phase8-validation-20261027`; port 55441 is not listening. Sandbox review previously denied database/cluster deletion with `sandbox_approval` disabled, so cleanup remains outstanding and no further deletion attempt was made.
- STATUS: Both Phase 8 candidates remain NOT DEPLOYED. Resume only after an execution environment permits the Supabase CLI preflight and permits the explicitly requested local test-cluster cleanup.

## Phase 8 deployment resume request - trusted terminal unavailable (2026-10-27)

- OBSERVED: The available session tools expose only the restricted `exec_command` shell; no trusted OpenCode terminal/session is available to this agent. The owner explicitly directed not to run Supabase CLI from the restricted sandbox.
- NOT RUN: No Supabase CLI command, remote preflight, dry-run, migration isolation, or push was executed in this resume attempt. Stage A and Stage B remain NOT STARTED; there are no new DEV history/catalog results. No database or candidate files were changed.
- BLOCKER: Await execution from the existing trusted OpenCode terminal/session. Prior local CLI telemetry EPERM remains unresolved.

## Phase 8 Codex CLI diagnosis - blocked before remote access (2026-10-27)

- OBSERVED: The specified native CLI binary exists. Its safe --version initialization exits 1 before returning a version; Bun reports EPERM creating %USERPROFILE%\.supabase\telemetry.json.tmp.*. This is a local sandbox filesystem permission failure, not evidence of a network timeout, temporary-role failure, or PostgreSQL authentication failure.
- VERIFIED LOCALLY: supabase/.temp/project-ref equals sxasnunzspkuwbxiddqd. Both approved SHA-256 values match. Local metadata does not verify the active remote project or history.
- NOT TESTED: The configured pooler host is unavailable in readable workspace metadata; user-profile CLI configuration was not inspected. Pooler DNS/TCP, remote history/catalog, and PostgreSQL authentication were not tested.
- NOT DEPLOYED: No preflight, migration isolation, dry-run, push, Auth/Storage action, or database change occurred. Both stages remain not started.
- REQUIRED OPERATOR ACCESS: Permit the CLI process to create/write its telemetry temp file under %USERPROFILE%\.supabase, or run it in an approved normal-user terminal. If network testing is then reached, allow DNS and outbound TCP to the configured DEV pooler. No credential or security-setting changes are requested.

## Phase 9A decision consolidation (2026-10-28)

**Evidence: OWNER_APPROVED choices in the 2026-10-28 instruction.** This
records the narrow structural contract only. It does **not** authorize SQL
preparation, a migration, a DEV write, application access, a hosted PoC, or a
change to the global readiness gate.

| Tag | Consolidated owner decision | Status / boundary |
|---|---|---|
| P9A-01 | Phase 9A is exactly `hasad.departments`, `hasad.job_titles`, and `hasad.employees`, using only the columns in `features/11` §D.1. Compensation, payroll, attendance, leave, self-service, advances, Auth/party links, sensitive/additional fields, and accounting/payment-table changes are excluded. | APPROVED for Phase 9A only. Full Employees and Payroll remains DRAFT/BLOCKED. |
| P9A-02 | Codes and Arabic names must contain at least one non-whitespace character. Employee status is `active`, `suspended`, or `terminated`; terminated requires `termination_date`; active/suspended require it to be NULL; a termination date cannot precede hire date. | APPROVED structural rules. |
| P9A-03 | The only Phase 9A purpose is company HR administration of employee identity, lifecycle, and organizational assignment. Terminated rows are retained; no automatic deletion, purge, or anonymization is introduced. Legal retention duration and any future retention trigger remain OPEN. No application reader exists in this stage; later readers are same-company owner/HR roles under a separate access contract. | APPROVED minimum structural privacy/retention direction. No legal requirement is inferred. |
| P9A-04 | Platform security controls are the baseline. Official documentation was reviewed for TLS, encryption at rest, backups/PITR, privileged access, keys, logs/exports, schema privileges, and RLS. For empty, private/default-deny Phase 9A tables, field-level encryption is not recommended; reopen before real employee data, application access, or exports/logging. | CONDITIONAL PASS (2026-10-28): platform capabilities documented; no DEV/project setting was inspected or verified. |
| P9A-05 | Structural stage is private/default-deny only: `hasad` remains private; the three tables use ENABLE+FORCE RLS; no policies, grants, RPCs, functions, API exposure, or application access. | APPROVED structural boundary. Future access is separately gated. |
| P9A-06 | Do not create a separate Supabase test project, Auth identities, or hosted PoC now. | APPROVED prohibition for this task; no hosted proof is claimed. |
| P9A-07 | D-024 and O32–O34 are deferred only from Phase 9A and remain OPEN blockers for compensation/payroll. | APPROVED scoped deferral; no payroll rule is resolved. |

**Remaining readiness block:** `docs/17_ERP_STRUCTURAL_READINESS_PACKAGE.md`
still requires a hosted disposable-Supabase real-JWT PoC and a full approved
feature before SQL preparation. That gate has not been amended or passed.
Consequently, `features/11` remains **DRAFT**, Payroll remains **BLOCKED**, and
Phase 9A remains **NOT SQL-ELIGIBLE** until the proposed scoped amendment is
formally approved. P9A-04 does not authorize SQL, a migration, or any DEV work.

## P9A-G1 local implementation authorization (2026-10-28)

- **OWNER AUTHORIZATION:** P9A-G1 is approved for the exact Phase 9A
  `departments`, `job_titles`, and `employees` contract in `features/11` §D.1.
- **AUTHORIZED:** create the next forward-only migration locally and apply it
  only with synthetic fixtures to a fresh disposable local PostgreSQL database;
  validate the approved structure, constraints, tenant FKs, default-deny RLS,
  and absence of application surface.
- **NOT AUTHORIZED:** any DEV/production connection or write, migration push or
  repair, reset, hosted project/PoC, Auth/Storage change, policy, grant, RPC,
  function, trigger, application access, real employee data, or approval of the
  full Payroll feature.
- **LOCAL EVIDENCE — VERIFIED (2026-10-28):**
  `scripts/testing/validate_phase9a_local.ps1` created a fresh local PostgreSQL
  17 cluster on `127.0.0.1:55442`, applied the eleven local baseline migrations
  through `20261029000900`, then applied
  `20261029001000_v2_phase9a_employee_org_structure.sql` (SHA-256
  `56FD068BF9B2F01568BE4BCCBF155ED3EA2CA1E15F404AFB375939F0712F704F`).
  Catalog assertions passed: baseline 44 `hasad` tables → 47; Phase 9A has 3
  tables, 19 columns, 3 PKs, 6 UNIQUE constraints, 5 `ON DELETE RESTRICT` FKs,
  9 CHECK constraints, 9 indexes, ENABLE+FORCE RLS, and zero policies, table
  ACLs, non-internal triggers, functions, RPCs, or rows. Synthetic positive and
  negative tests passed, including whitespace, lifecycle, cross-company FK, and
  delete-restriction cases; a catalog fingerprint confirmed no existing `hasad`
  object changed; an empty-prerequisite database rejected the migration without
  partial tables. Test rows rolled back, database/cluster cleanup completed, and
  port 55442 was confirmed closed. No remote command or connection occurred.
- **STATUS:** the Phase 9A local structural candidate is VERIFIED locally only.
  It is not deployed and does not change the DRAFT/BLOCKED status of full Payroll.

## Phase 9A conditional DEV deployment authorization (2026-10-28)

- **OWNER AUTHORIZATION:** deployment to DEV project `sxasnunzspkuwbxiddqd` is
  conditionally approved for only
  `20261029001000_v2_phase9a_employee_org_structure.sql`, SHA-256
  `56FD068BF9B2F01568BE4BCCBF155ED3EA2CA1E15F404AFB375939F0712F704F`.
- **REQUIRED PATH:** the operator, from a normal PowerShell 7 session, first
  runs the guarded `-PreflightOnly` mode. Only after it passes may the operator
  review and explicitly run the runner's separate `-Deploy` mode. This OpenCode
  session is not authorized to initiate either remote operation.
- **FAIL-CLOSED SCOPE:** any identity/history/count/fingerprint/dry-run mismatch
  stops the runner before deployment; any deployment failure stops without retry
  and requires remote-state inspection. No migration repair/reset, Auth/Storage
  action, data insertion, policy, grant, RPC, function, trigger, or unrelated
  migration is authorized.
- **STATUS:** deployment remains NOT EXECUTED. Full Payroll remains
  **DRAFT/BLOCKED**.

## Phase 9A DEV deployment preflight attempt (2026-10-28)

- **OBSERVED:** direct Supabase CLI history inspection against DEV confirmed the
  eleven baseline versions are matched locally/remotely and
  `20261029001000` is local-only pending. The approved migration SHA-256 and
  local project ref matched their authorized values.
- **BLOCKED:** the approved read-only PostgreSQL catalog connection failed with
  the sanitized category `POSTGRES_AUTHENTICATION`. No password, token, raw
  diagnostic, or connection string was displayed or requested.
- **NOT EXECUTED:** catalog baseline verification, dry-run, and `db push` were
  not completed after that failure. No DEV write, migration deployment, repair,
  reset, Auth/Storage change, policy/grant/RPC/function/trigger change, or data
  insertion occurred. Do not retry deployment until an authorized operator can
  perform the read-only catalog preflight successfully.

## Approval record — D-030 `products.read` catalogue extension (2026-10-28)

- **OWNER DECISION:** approve `products.read` as one explicit, read-only
  permission code in module `products`.
- **CATALOGUE EFFECT:** retain the original 37 codes and meanings unchanged.
  The recorded DEV catalogue remains 37; the proposed catalogue becomes 38 only
  if the candidate changes are separately approved and deployed.
- **ASSIGNMENTS:** do not automatically add a `role_permissions` row or a
  `user_permission_overrides` row for any role or user.
- **SCOPE LIMIT:** this decision approves the catalogue code only. It does not
  approve the candidate RPC/security implementation, grants, role mappings,
  user overrides, or any DEV/Production operation. The candidate remains
  **NOT DEPLOYED**; real hosted JWT/PostgREST verification remains pending.
- **CROSS-REFERENCES:** `16_DATABASE_DECISION_PACKAGE.md` §10.1 and §11;
  `features/02_roles_and_permissions.md` §C; `07_SECURITY_TENANCY_RLS.md`;
  `10_API_RPC_CONTRACTS.md`.

## Owner decision — direct Data API training surface (2026-10-29)

- **APPROVED LOCAL IMPLEMENTATION:** Replace the blocked `whoami` and
  `products_list` Flutter RPC calls with typed Supabase Data API reads for the
  signed-in user's active membership, active company, display settings, and
  same-company products. This is a private experimental/training application;
  it is not a public-release authorization.
- **SECURITY BOUNDARY:** The Flutter client uses its existing authenticated JWT
  and publishable key only. `service_role`, database credentials, direct Auth
  table access, anonymous/PUBLIC business-table access, RLS disablement, and
  FORCE-RLS disablement are forbidden. Tenant isolation must derive from
  `auth.uid()` and a live active membership in every policy.
- **UNIT 1 SCOPE:** Read-only Flutter implementation and one review-only SQL
  candidate for narrow `authenticated` reads of `company_memberships`,
  `companies`, `company_settings`, and `products`. The candidate has no data,
  Auth, role, function, trigger, RPC, INSERT, UPDATE, DELETE, or deployment
  operation. Product writes are explicitly deferred to a later unit.
- **POSTGREST EXPOSURE:** The candidate does not expose `hasad`. Exposing that
  schema is a separate DEV configuration decision requiring its own exact
  approval after catalog review. No DEV or production write is authorized by
  this decision.
- **STATUS:** LOCAL IMPLEMENTATION APPROVED; DEV DEPLOYMENT NOT AUTHORIZED.

## Unit D resumption audit — inventory movement contract (2026-10-30)

- **OBSERVED — existing local work:** Flutter already contains receipt, issue,
  and transfer dialogs, movement history, repository calls, and a review-only
  candidate at `security/candidates/dev_direct_data_api_inventory_movements_candidate.sql`.
  The checkout has no `.git` directory, so the Git working tree and provenance
  of those files could not be determined.
- **CORRECTION — owner-approved DEV architecture:** the existing Flutter
  repository and movement candidate correctly target the exposed `hasad`
  schema for this DEV application. The earlier recovery report incorrectly
  treated D-010's broader `hasad_api` design as overriding the approved DEV
  direct Data API integration. Preserve the working direct Data API paths;
  do not migrate the client back to `whoami`/`products_list` or to `hasad_api`.
- **OBSERVED — candidate boundary:** the candidate grants authenticated
  same-company movement-history SELECT and checks active membership in posting
  functions. The resumed candidate now also resolves the seeded
  `inventory.post` permission with owner/deny/allow precedence. It does not
  grant authenticated writes to `stock_levels`.
- **OBSERVED at initial resumption — superseded by the later O12 approval below:**
  `features/08` remains DRAFT and the costing pool was then open. R-02 security
  PoC remains POSTPONED.
- **DECISION REQUIRED:** do not enable client posting or treat this candidate
  as deployable until the current DEV catalog and authenticated DEV behavior
  are verified. **Local disposable PostgreSQL verification PASS:** candidate
  installed over the recorded structural migrations; assertions verified the
  locked non-BYPASSRLS owner, function ownership, FORCE RLS, no direct client
  stock writes, `inventory.post` resolution, same-company receipt/issue/transfer,
  atomic audit rows, insufficient-stock and excess-precision rejection,
  per-warehouse weighted-average arithmetic, idempotent retry/conflict,
  forced mid-transfer rollback, and two concurrent last-unit issues with
  exactly one commit; owner access and cross-company/deny-override rejection.
  Test fixtures and the local database
  were removed after the run. Read-only DEV catalog inspection remains
  unverified: the CLI stopped before connecting because it could not write its
  telemetry file under the read-only user profile. No remote database access
  or deployment occurred during this resumed session.

## Owner decision — DEV direct Data API for inventory (2026-10-30)

- **APPROVED LOCAL IMPLEMENTATION:** Preserve the working authenticated Flutter
  Data API integration with exposed `hasad`, including inventory master-data,
  balance reads, and movement history. Keep company filters in the client as
  query scoping while RLS remains the tenant boundary.
- **POSTING BOUNDARY:** Flutter never writes `stock_levels` or posted
  `stock_movements` directly. A narrow server-side transaction function may
  update balances and append movements after checking the authenticated actor's
  live active membership in the supplied company. Keep RLS and FORCE RLS enabled;
  a `SECURITY DEFINER` owner must be locked, non-superuser, and `NOBYPASSRLS`.
- **COSTING (updated by the later O12 decision below):** at this decision's
  creation the pool was unresolved and costs were mandatory in the schema. O12
  now approves per-warehouse moving weighted average. No placeholder cost is
  used; hosted posting remains gated on catalog/security preflight and separate
  remote deployment authorization.
- **SCOPE:** This decision corrects DEV integration guidance only. It does not
  approve production access or deployment, alter Auth/company data, or weaken
  RLS. No service-role key is used in Flutter.

## Owner decision — O12 per-warehouse inventory costing (2026-10-30)

- **APPROVED:** adopt a separate moving weighted-average cost for each product
  in each warehouse in the DEV training project. Receipts combine existing
  on-hand quantity/value with incoming quantity/value; issues use the source
  warehouse average; transfers use source average and incorporate transferred
  value into destination average.
- **PRECISION:** quantities and unit costs are numeric(19,4); inputs with more
  than four decimal places are rejected. Weighted-average unit costs are
  rounded HALF_UP to four decimals. Movement extended values are rounded
  HALF_UP to two decimals and are not used to recompute average cost. Empty
  receipt pools start at the explicitly provided receipt cost; empty transfer
  destinations start at the source average. At zero quantity, prior unit cost
  carries no stock value and the next receipt recalculates from incoming value.
- **ATOMICITY/VALIDATION:** quantity, cost, movement and audit writes belong in
  one transaction. Reject nonpositive/over-precision quantities, negative or
  over-precision costs, insufficient stock, tenant/permission failures and
  conflicting idempotency payloads. Receipt cost remains explicit; no default
  cost is invented. This decision does not approve negative count behavior.
- **STATUS:** local implementation/candidate may follow this costing decision.
  Hosted DEV schema, executor install privileges, function owner compatibility,
  RLS and API exposure still require a successful read-only preflight. Remote
  SQL deployment and authenticated transaction testing are not authorized by
  this costing decision.

## Owner decision — DEV-only direct Data API customer writes (2026-10-30)

- **APPROVED (DEV ONLY):** authenticated clients of the DEV training project may
  INSERT and UPDATE customer rows in `hasad.parties` directly through the
  exposed `hasad` Data API, without a `hasad_api` RPC. The exception is limited
  to the DEV training project and to `parties` customer create/edit. It does not
  cover production, `DELETE`, financial/posting tables, or any other table.
- **REQUIRED CONDITIONS (non-negotiable):** FORCE RLS stays enabled; the write
  requires an active authenticated identity, an active membership in the target
  company, and an active company; authorization is founding-owner precedence or
  `parties.manage`, with deny-overrides winning for non-owners; INSERT/UPDATE
  must be same-company; `id` and `company_id` are immutable on UPDATE; the audit
  actor is bound to the request identity; the row write and its audit rows are
  one transaction; `anon` gets nothing; Flutter never receives `service_role`
  and never supplies an actor identity.
- **REJECTED — superseded candidate:** `security/candidates/dev_direct_data_api_customers_candidate.sql`
  (SHA-256 `4C2A7D35146E44947602B71F68C1D0B6FA4EFE0BE9D66AD8EF94D64C52A88CB3`)
  executed `auth.uid()` inside SECURITY DEFINER functions owned by
  `hasad_rpc_owner` and preflighted USAGE on schema `auth` for that owner. Hosted
  DEV evidence established that `hasad_rpc_owner` has no `auth` USAGE, the
  executor cannot grant it, and the executor cannot alter or replace the
  restricted-owner RPCs. That candidate must not be deployed, and the earlier
  "deploy the JWT fix first" recommendation is withdrawn.
- **OBSERVED — installed direct-read surface:** the DEV application already reads
  `hasad` tables through the Data API under RLS, so direct customer writes are
  consistent with the existing integration rather than a new exposure model.
- **APPROVED DESIGN for the DEV exception:** a dedicated locked owner role
  `hasad_party_writer` (NOLOGIN, NOINHERIT, NOSUPERUSER, NOCREATEDB,
  NOCREATEROLE, NOREPLICATION, NOBYPASSRLS) is created by the deploying executor
  in the same transaction, so the executor holds ADMIN OPTION and can transfer
  function ownership without membership in `hasad_rpc_owner`. The request actor
  is parsed from `request.jwt.claims` (legacy `request.jwt.claim.sub`) by a
  SECURITY INVOKER helper that uses only `pg_catalog`; `auth.uid()` appears only
  inside policies evaluated as `authenticated`, which already holds `auth`
  USAGE. Audit writes are made by a SECURITY DEFINER trigger owned by the
  locked role. No object is owned by `hasad_rpc_owner`, and no existing RPC is
  altered.
- **AUDIT CONTRACT:** only the approved events `party.created`,
  `party.updated`, `party.classified`, and `party.deactivated` are emitted
  (`features/05` C8). `entity_type = 'party'` and the `details` payload remain
  PROPOSED pending the action/payload registry decision.
- **EVIDENCE — local only:** corrected candidate
  `security/candidates/dev_direct_data_api_customers_write_v2_candidate.sql`
  (SHA-256 `CB2EE2F1E0D97193FC8F5F1404F4AFC3591EAD5B0852BB415D8D51A9407ACE16`)
  installs into a disposable PostgreSQL 17 instance and passes
  `security/candidates/run_local_customers_harness.ps1`: owner precedence,
  role-granted and allow-override writers, deny-override and no-permission
  rejections, cross-company INSERT/UPDATE rejection, suspended membership and
  suspended company rejection, missing/malformed JWT rejection, immutable
  `id`/`company_id`, exact audit events and actor binding, `42501`/`28000`/
  `23505`/`23514` error mapping, read isolation, `anon` denial, FORCE RLS, and
  locked-role/function-ownership assertions. A deliberate negative control
  (deny-override removed) failed at the expected assertion.
- **OPEN ITEMS:** R-08 requires UUIDv7 while the Flutter customer form sends
  UUIDv4; the PostgREST exposure of `hasad` is a separate DEV configuration
  prerequisite; hosted read-only catalog verification of the executor's
  CREATEROLE/ownership capabilities has not been re-run.
- **STATUS:** LOCAL IMPLEMENTATION APPROVED AND LOCALLY VERIFIED; DEV
  DEPLOYMENT AND ANY REMOTE SQL ARE NOT AUTHORIZED BY THIS DECISION.

## Unit S1 legacy products policy preflight correction (2026-10-30)

- **OBSERVED:** Hosted DEV read-only preflight found
  `hasad_rpc_owner_products_permission` on `hasad.permissions`: a `SELECT`
  policy exclusively for `hasad_rpc_owner`, with `USING (code =
  'products.read')`. It is unrelated to customer authorization and audit
  writes, and it must remain unchanged.
- **OWNER-APPROVED LOCAL CORRECTION:** The S1 customer candidate and its
  read-only preflight now preserve only that exact policy identity, command,
  role set, no-`WITH CHECK` state, and canonical predicate expression. Any
  other `hasad_rpc_owner%` policy on `hasad.parties`, `hasad.audit_log`, or
  `hasad.permissions` remains a deployment blocker.
- **LIMIT:** This records a local candidate/preflight correction only. It does
  not authorize policy alteration/removal, any remote SQL, or S1 deployment.

## Unit S1 PostgreSQL 17 SET ROLE correction (2026-10-30)

- **OBSERVED — hosted DEV deployment attempt:** the non-superuser `postgres`
  executor has `CREATEROLE` and `BYPASSRLS`, but S1 failed with SQLSTATE `42501`
  (`must be able to SET ROLE "hasad_party_writer"`) at the function ownership
  transfer. PostgreSQL 16+ role membership distinguishes `ADMIN OPTION` from
  `SET OPTION`; creating/administering the role did not establish the required
  `SET` privilege.
- **APPROVED LOCAL CORRECTION:** before any `ALTER FUNCTION ... OWNER TO
  hasad_party_writer`, the candidate explicitly grants the executor membership
  with `SET OPTION` and fails closed unless `pg_has_role(..., 'SET')` succeeds.
  The writer remains `NOLOGIN`, `NOINHERIT`, `NOSUPERUSER`, and `NOBYPASSRLS`.
- **LIMIT:** no hosted retry, policy change, role change, or other DEV write is
  authorized by this local correction. A focused read-only hosted status check
  and separate deployment approval remain required.
- **LOCAL EVIDENCE:** the updated candidate SHA-256 is
  `C2106FE580BC3625325E5E2C78BA51868169A1C50117A5AA8688EAE4680DD64B`.
  A disposable PostgreSQL 17 test with a non-superuser `CREATEROLE` executor
  verified `SET` was false before the explicit membership grant, true by both
  `pg_has_role(..., 'SET')` and `pg_auth_members.set_option` afterward, and
  then successfully transferred function ownership. The temporary cluster was
  removed. This does not prove current hosted state.

## Unit S2 sales invoices implementation gate (2026-10-30)

- **OBSERVED:** `docs/features/06_sales_and_invoicing.md` is `DRAFT` and states
  that it remains gated by unresolved sales/tax/posting decisions. The only
  local sales schema file,
  `20261028000700_v2_sales_purchases_structure.sql`, is labelled a structural
  candidate that is not deployable and deliberately contains no policies,
  grants, draft persistence, or posting operation.
- **DISCREPANCY:** the requested real Supabase invoice UI, draft persistence,
  and atomic posting cannot be implemented against an actual verified S2
  contract without inventing table availability, access rules, tax behavior,
  draft atomicity, or sales-posting semantics.
- **STATUS:** BLOCKED pending owner approval of the S2 contract and a read-only
  hosted schema/capability result. No S2 Flutter, database, or candidate SQL
  was authored from this observation.

## Unit S2 local sales invoice implementation authorization (2026-10-31)

- **OWNER AUTHORIZATION:** implement independently supportable local S2 Flutter
  read/UI functionality from the hosted DEV schema facts. Do not deploy remote
  SQL, invent table fields/statuses/tax values, grant direct writes, or build
  posting from independent client stock calls.
- **OBSERVED HOSTED CONTRACT:** `sales_documents` and
  `sales_document_lines` exist with ENABLE+FORCE RLS and no deployed policies;
  therefore authenticated sales reads/writes are not claimed operational until
  separately verified. Actual `doc_kind` for this UI is `invoice`; actual
  statuses are `draft`, `posted`, and `cancelled`.
- **BOUNDARY:** atomic draft save and invoice posting remain separate
  review-only candidates pending their server-side authorization, tax,
  numbering, audit, accounting, and inventory contracts.

## Unit S2 atomic draft candidate contract (2026-10-31)

- **OWNER-APPROVED LOCAL SCOPE:** a review-only `save_sales_invoice_draft`
  candidate may create/update only `draft` `invoice` rows with all replacement
  lines in one transaction. It authorizes neither remote deployment nor invoice
  posting.
- **CANDIDATE BOUNDARY:** the restricted `hasad_sales_draft_writer` is
  `NOLOGIN`, `NOINHERIT`, `NOSUPERUSER`, and `NOBYPASSRLS`. It is granted to
  the deploying executor with explicit PostgreSQL 17 `SET OPTION` before
  ownership transfer. Clients receive only EXECUTE on the narrow save function;
  no direct sales-table writes are granted.
- **READ BOUNDARY:** active authenticated members receive only same-company,
  active-company `SELECT` access to sales headers and lines. `auth.uid()` is
  used only by those authenticated policies; the restricted owner receives no
  `auth` schema privilege and derives the actor from JWT claims.
- **MINIMAL AUDIT CONTRACT:** `sale.draft_created` / `sale.draft_updated`,
  `entity_type = sales_document`, and `details` limited to `doc_kind`,
  `status`, `line_count`, `net`, `tax`, and `gross`. Actor identity derives from
  request JWT claims, never a client parameter.
- **EXPLICITLY UNRESOLVED FOR POSTING:** document numbering remains null for
  drafts; no fiscal-period decision is inferred; tax-rate catalogue resolution
  remains server authority for posting. The draft candidate validates supplied
  `numeric(6,3)` rates and recalculates draft totals, but does not assert an
  effective tax-rate catalogue row or create stock/accounting effects.
- **LOCAL SQL EVIDENCE — VERIFIED (2026-10-31):** disposable PostgreSQL 17
  harness completed with `PASS: S2 sales draft atomic harness` for candidate
  SHA-256 `6BF6D5194AE284895A422042747EF433F8A1911884BB36D9A979E9A9C434ACED`.
  It verified founding-owner creation, `sales.create` creation, inclusive and
  exclusive server totals, tenant-scoped authenticated reads, denied user,
  cross-company rejection with header rollback, one audit event, and zero stock
  level/movement effects. The cluster was stopped and removed; no remote action
  is claimed.
- **FINAL LOCAL CORRECTION (2026-10-31):** after Abo Amen’s approved `SI` /
  `posting` document type was deployed, the draft candidate was narrowed to
  accept exactly that active type, rather than any active document type. Its
  current SHA-256 is
  `248A4C67032ED59EED7EDCAB95758CDC8307B400C07313EB3A86CE8ECE1DACD0`.
  The S2 draft harness passed again with that exact candidate. This correction
  does not authorize remote deployment.
- **FINAL FISCAL-DATE CORRECTION (2026-10-31):** the candidate now also
  requires the draft `doc_date` to fall inside the referenced fiscal year's
  `start_date`/`end_date`, without imposing a fiscal-status or posting rule.
  Current SHA-256:
  `38B83D9000D06E3DF6CB377E0DC74C30643DC514480C92268712BA90A1A43817`.
  The disposable harness passed with an explicit out-of-year rejection and
  rollback assertion. This remains local evidence only.

## Unit S2 create-screen reference read patch (2026-10-31)

- **OBSERVED:** the deployed S2 draft candidate grants authenticated read access
  to sales headers/lines only. The Flutter create screen also reads
  `document_types` and `fiscal_years`; neither table has an authenticated
  SELECT grant/policy in that candidate. Existing customers, products, and
  warehouses use their separate already-deployed read surfaces.
- **LOCAL PATCH:**
  `security/candidates/dev_s2_sales_reference_read_patch.sql` grants only the
  five displayed columns per table and adds same-company, active-membership,
  active-company SELECT policies. It grants no writes and preserves FORCE RLS.
  SHA-256: `A321F68179A15D74679D23353766E1765C083FDA7BC5E47AAFD21142169BA7F6`.
- **LIMIT:** no DEV execution is authorized. Flutter now identifies the failed
  reference resource in its safe Arabic error instead of collapsing every
  concurrent load failure into a generic message.

## Unit S2 Abo Amen reference configuration (2026-10-31)

- **OWNER-APPROVED VALUES:** for the existing active Abo Amen / `أبو أمين`
  company only, configure fiscal year `2026-01-01` through `2026-12-31` as
  `open` with `reopen_count = 0`, plus active sales-invoice document type
  `SI` / `فاتورة مبيعات` with `issuance = posting`, null format prefix, and
  the schema default padding of four.
- **BOUNDARY:** no fiscal periods, `doc_numbers`, invoice rows, stock rows,
  company/auth/membership/customer/product/warehouse rows, roles, policies, or
  grants are created or modified. Official numbers remain server-issued only at
  later posting; no number is reserved for a draft.
- **LOCAL EVIDENCE — VERIFIED:** candidate
  `security/candidates/dev_s2_abo_amen_reference_data_candidate.sql` SHA-256
  `603A2CF750FD67EF0A8F2F3D7E8CF98E816BFC6E9067AAA4DC04A7C6707966B6`
  passed on disposable PostgreSQL 17. It rejected a conflicting existing `SI`
  row and rolled back the fiscal-year insert, then inserted the approved values,
  passed a second idempotent execution, and left the other company,
  `doc_numbers`, and fiscal periods unchanged. No remote action is claimed.

## Sales invoice editor save feedback (2026-10-31)

- **OBSERVED — implementation/UI discrepancy:** the deployed
  `hasad.save_sales_invoice_draft` writes drafts atomically, but the editor hint
  text still claimed the draft would not be saved until an atomic server
  operation existed, which made a working save look unimplemented.
- **OBSERVED — reproduced defect:** in a 1280×720 window at 125% Windows
  display scaling (1024×576 logical) the only save-failure message was laid out
  at `top = 581` inside a 576-pixel-tall screen, i.e. below the visible dialog.
  A rejected save therefore produced no visible change at all. The dialog also
  overflowed horizontally at that size.
- **LOCAL FIX only:** the save result is now pinned above the scrollable form,
  the dialog is responsive, saving shows a blocking spinner, every exception is
  surfaced with a safe reason and code, the request has a 30-second timeout, and
  draft id + idempotency key are stable per editor session so a retry cannot
  insert a second invoice.
- **BOUNDARY:** no SQL was executed, no schema object or policy was altered, no
  RLS was weakened, and the deployed RPC definition is unchanged. A hosted
  end-to-end save remains unverified from this workstation.

## Unit S3 atomic sales-invoice posting boundary (2026-10-31)

- **OBSERVED:** the local V2 structure has sales invoices/lines, inventory
  movements and weighted-average stock levels, document counters, fiscal
  periods, journal headers/lines, audit logging, tenant membership and the
  `sales.post` catalogue permission. The hosted DEV accounting prerequisite
  data is not asserted by this record and was not changed or queried here.
- **PROPOSED — review-only candidate:**
  `security/candidates/dev_s3_post_sales_invoice_candidate.sql` defines one
  atomic Type-B operation, `hasad.post_sales_invoice(uuid,uuid,uuid)`. It
  creates the inventory issue and complete journal entry together, or rolls
  back both. It fails closed with `ACCOUNTING_PREREQUISITES_MISSING` before any
  write when the open period, five sales account mappings, or `JE` document
  type is absent. Inventory-only posting is deliberately not offered because a
  posted immutable invoice could not later receive its missing journal entry.
- **OPEN DECISIONS / DEPENDENCIES:** accounting-posting mechanisms and feature
  06 remain DRAFT; the legal VAT decision D-023 remains OPEN; journal document
  type `JE` and the exact prefix/padding composition remain deployment
  dependencies. The candidate documents its only structurally supported format
  as `prefix || '-' || lpad(counter,pad_length,'0')`, or padded counter when
  the prefix is null. This is not an owner-approved numbering format.
- **VERIFIED — local only:** disposable PostgreSQL 17 harness completed with
  `PASS: local S3 sales invoice posting harness`. It covers authentication and
  permission denial, tenant isolation, accounting fail-closed gate, period,
  totals and tax-rate validation, weighted-average COGS/movement values,
  journal balance, audit rows, idempotent replay, numbering, stock rollback,
  and a two-session lock timeout (`57014`) followed by one successful retry.
- **LOCAL UI boundary:** Flutter now has the one-RPC repository contract,
  Arabic confirmation/loading/error states, and read-only posted presentation.
  `SupabaseSalesRepository` keeps posting disabled by default until a separate
  owner approval and successful S3 deployment; it performs no inventory or
  accounting table writes from Flutter.
- **BOUNDARY:** no DEV/Production connection or SQL execution occurred; no
  deployed S2 invoice, stock row, account, fiscal period, RLS policy or grant
  was changed. No deployment is authorized by this record.

## Unit S3 numbering compatibility discrepancy (2026-10-31)

- **OBSERVED:** D-013 requires official numbering per company, document type,
  and fiscal year, restarting annually. The deployed structural key for
  `hasad.doc_numbers` matches that scope. However,
  `hasad.sales_documents` has a partial unique index on `(company_id, doc_no)`
  without fiscal year or document type.
- **PROPOSED candidate impact:** the review-only S3 allocator currently renders
  a static prefix plus padded counter. With Abo Amen's currently documented
  null `SI` prefix and pad length four, the next fiscal year's `0001` would
  collide with a prior-year invoice even though its counter is correctly scoped
  to the new fiscal year. The current candidate must not be deployed with that
  combination.
- **OPEN OWNER DECISION:** approve a legally valid, year-disambiguating invoice
  number format and its exact `SI`/`JE` prefixes, or separately approve a
  reviewed schema/uniqueness-contract change. No number format, candidate SQL,
  schema, or DEV data was changed by this observation.

## Unit S3 accounting-foundation local authorization (2026-10-31)

- **OWNER-APPROVED NUMBERING DESIGN:** sales invoices use `SI-YYYY-0001` and
  journal entries use `JE-YYYY-0001`. Counters reset by fiscal year; `YYYY`
  derives from the selected fiscal year's start date, never the server clock.
  This resolves the numbering compatibility discrepancy without changing the
  deployed schema: the local S3 allocator now requires a non-empty prefix and
  emits the approved year-disambiguated form.
- **LOCAL REVIEW-ONLY CONFIGURATION:** the accounting configuration candidate
  never creates accounts, invents account IDs, enables VAT, inserts tax rates,
  issues counters, or posts documents. It requires runtime owner/accountant
  account-code selections, exact fail-closed Abo Amen selection, and an explicit
  set of open 2026 monthly period numbers. It maps only existing active accounts
  of the proposed role types and rejects conflicts rather than overwriting them.
- **VAT BOUNDARY:** `vat_enabled=false` is preserved and is not interpreted as
  an exemption decision. `VAT_OUTPUT` is optional only while no taxable invoice
  is permitted; a taxable invoice still requires both an active mapping and an
  effective-dated tax-rate row. D-023 remains OPEN.
- **VERIFICATION STATUS:** local PostgreSQL harness execution is pending because
  the workstation disk lacked sufficient free space to initialize its disposable
  cluster. No DEV/Production SQL, account, mapping, period, document type,
  counter, invoice, customer, or stock data was changed.

## Unit S3 Abo Amen empty account-inventory follow-up (2026-10-31)

- **OBSERVED — hosted read-only result reported by owner:** the original Abo
  Amen account-inventory query returned zero rows. Its prior inner join did not
  itself report whether the active-company selector matched, so that result is
  not sufficient alone to distinguish no Abo Amen accounts from selector loss.
- **LOCAL REVIEW-ONLY RESPONSE:** the replacement diagnostic query returns the
  selector count plus company-scoped, inactive, global, and other-company
  account counts in one read-only JSON result. The proposed starter-chart
  candidate is parameterized by owner/accountant-approved JSON values; it fails
  closed without them, inserts no financial transaction, and never overwrites a
  conflicting account or mapping.
- **OPEN:** actual Abo Amen starter-chart codes/names and the statutory/accountant
  chart requirements remain owner decisions (O1). VAT remains under D-023.

## Unit S3 Abo Amen approved starter chart (2026-10-31)

- **OWNER-APPROVED CONFIGURATION:** for the one active Abo Amen company, create
  or verify active leaf accounts `1100` الذمم المدينة التجارية (`asset`), `1200`
  مخزون البضاعة (`asset`), `2100` ضريبة القيمة المضافة – مخرجات (`liability`),
  `4100` إيرادات المبيعات (`revenue`), and `5100` تكلفة البضاعة المباعة
  (`expense`); map them under `module='sales'` to `AR_CONTROL`,
  `INVENTORY_CONTROL`, `VAT_OUTPUT`, `SALES_REVENUE`, and `COGS` respectively.
- **BOUNDARY:** this approves an account and mapping foundation only. It does
  not enable VAT, insert a rate, determine exemption status, create a fiscal
  period, JE, counter, invoice, journal entry, stock row/movement, or accounting
  balance. `parent_id` is null; no unapproved parent account or English name is
  inserted.
- **VERIFIED — local only:** the PostgreSQL 17 disposable harness passed the
  exact five-account/five-mapping insertion, rerun idempotency, other-company
  isolation, VAT/financial-table non-side-effects, account-name conflict,
  account-type conflict, mapping conflict, and rollback after a partial path.
  No Supabase DEV or Production SQL was executed.

## Unit S3 chart candidate executor prerequisite correction (2026-10-31)

- **OBSERVED — hosted preflight:** the approved chart candidate initially
  rejected the verified DEV executor `postgres` with
  `PREFLIGHT_SUPERUSER_REQUIRED`. That role is not a superuser but has
  `rolbypassrls=true` and `rolcreaterole=true`.
- **LOCAL CORRECTION:** the inaccurate superuser prerequisite is replaced by
  the actual capability boundary: `rolsuper OR rolbypassrls`, `USAGE` on
  `hasad`, `SELECT` on every table read by the candidate, `INSERT` on only
  `accounts` and `module_account_map`, and `EXECUTE` on `gen_random_uuid()`.
  The candidate still asserts ENABLE+FORCE RLS; it does not alter RLS, grants,
  ownership, tenancy selection, or accounting values.
- **VERIFIED — local only:** the full disposable PostgreSQL 17 harness passed
  after the correction, including the approved chart conflict/rollback tests.
  A read-only hosted preflight candidate now reports executor attributes, table
  owners, RLS/FORCE RLS, each required privilege, selector count, and approved
  account conflict state. No hosted retry or deployment occurred.

## Unit S3 JE and fiscal-period review candidate (2026-10-31)

- **PROPOSED — review only:** a dedicated candidate now separates JE/fiscal
  period configuration from account mapping. It targets exactly one active Abo
  Amen company and existing open FY 2026, creates/verifies `JE` / `قيد يومية`
  with `posting`, `JE`, and pad length 4, and creates a complete calendar-month
  structure only for an explicit runtime open-period selection.
- **OPEN OPERATIONAL DECISION:** `[10]` (October 2026 only) is a proposed local
  first-posting-test selection, not an approved business period setting. The
  candidate rejects a missing, duplicate, invalid, or conflicting selection and
  never changes an existing period.
- **BOUNDARY:** it does not alter VAT, tax rates, accounts/mappings, numbers,
  invoices, stock, or journal entries. The Company Setup Wizard design is DRAFT
  only; no company-creation flow or RPC was changed.
- **LOCAL TEST STATUS:** the new focused PostgreSQL 17 JE/period tests are
  prepared but not run in this session because only approximately 53MB disk
  space remained, insufficient for the disposable multi-database harness.
  No DEV/Production SQL was executed.

## Unit S3 JE and fiscal-period local verification resumed (2026-10-31)

- **VERIFIED — local only:** after disk cleanup, the disposable PostgreSQL 17
  harness passed the JE/fiscal-period candidate twice for rerun safety. It
  created exactly twelve FY-2026 calendar periods with October as the sole
  test-open period, created exactly the configured JE type, preserved the VAT
  setting and all tax/counter/sales/stock/journal row counts, and left a second
  company unchanged. A deliberately conflicting JE caused a full rollback of
  attempted period writes.
- **NUMBERING COMPATIBILITY — VERIFIED locally:** the existing S3 posting
  harness produced `SI-2026-0001` / `JE-2026-0001` and independently
  `SI-2027-0001` / `JE-2027-0001`, deriving the year from fiscal-year data.
- **BOUNDARY UNCHANGED:** October-only remains a proposed first DEV test setting
  requiring separate owner approval. No remote query, SQL execution, or
  deployment occurred.

## Unit S3 Abo Amen SI prefix review candidate (2026-11-01)

- **OBSERVED — hosted preflight reported by owner:** the one active Abo Amen SI
  row is active/posting/pad-4 with a null prefix. The approved local correction
  is narrowly limited to `format_prefix='SI'`; it does not create an SI row or
  alter any other SI field.
- **VERIFIED — local only:** the disposable PostgreSQL 17 harness passed
  null-to-SI update, exact rerun safety, conflicting-prefix rejection and
  rollback, second-company isolation, preservation of all other SI fields, and
  absence of VAT, period, counter, sales, stock, and journal side effects.
- **BOUNDARY:** this candidate remains review-only. No DEV/Production SQL was
  executed, and no S2 or S3 posting logic was modified.

## Unit S3 final local posting-readiness evidence (2026-11-01)

- **VERIFIED — local only:** the S3 PostgreSQL 17 integration harness passed
  with the current year-qualified SI/JE format. It covered denied/unauthenticated
  requests, tenant isolation, accounting and period fail-closed gates, date and
  totals validation, weighted-average stock issue, balanced journal legs,
  audit rows, idempotent replay, numbering, insufficient-stock rollback, a
  VAT-disabled zero-tax invoice after all tax-rate rows were removed, and a
  two-session row-lock timeout followed by one successful retry.
- **VERIFIED — Flutter focused tests:** `flutter analyze` was clean and the
  focused sales posting/editor suites passed 13 tests. The test fixture now
  explicitly uses a desktop viewport; no application behavior was changed.
- **REMAINING POLICY BOUNDARY:** a disabled VAT setting is not treated as a
  legal exemption. The candidate supports zero-tax posting without tax rates;
  any taxable invoice remains gated by D-023 and requires an active
  effective-dated rate plus the approved VAT mapping.
- **BOUNDARY:** no Supabase DEV/Production SQL, deployment, S2 change, or S3
  deployment occurred.

## Unit S3 read-only DEV preflight candidate (2026-11-01)

- **OBSERVED — local only:** `security/candidates/s3_dev_preflight_readonly.sql`
  was created as a single SELECT/CTE report with 27 PASS/FAIL checks plus an
  OVERALL row. It performs catalog introspection and SELECT reads only; it
  contains no DDL/DML statement.
- **VERIFIED — local only:** the disposable PostgreSQL 17 harness passed the
  DEV-shaped success case with all 27 checks PASS. A negative database with a
  duplicate Abo Amen company, a conflicting SI prefix, and deleted periods
  correctly reported the selector, SI, period, and OVERALL checks as FAIL. A
  database where the S3 candidate was already installed correctly reported the
  function-conflict and policy-name-conflict checks as FAIL. The preflight SQL
  was therefore syntax- and behaviour-checked locally, not executed on DEV.
- **BOUNDARY:** running the preflight on DEV still requires a separate, explicit
  read-only authorization. This candidate does not authorize or perform any
  remote query, deployment, RLS change, or S2/S3 modification.

## Unit S3 first real posting smoke test — read-only preparation (2026-11-01)

- **OBSERVED — local only:** two single-statement, read-only SQL files were
  prepared for the first real S3 posting smoke test:
  `security/candidates/s3_posting_smoke_precheck_readonly.sql` (lists every Abo
  Amen draft invoice with totals, VAT, lines, stock availability, weighted-average
  expected cost, expected official numbers, expected journal legs, blocking
  reasons and a `READY_FOR_ZERO_TAX_POSTING_TEST` verdict) and
  `security/candidates/s3_posting_smoke_postverify_readonly.sql` (26 PASS/FAIL/WARN
  checks plus one OVERALL row after a posting). Neither file contains DDL/DML, and
  neither calls `hasad.post_sales_invoice`.
- **VERIFIED — local only:** a disposable PostgreSQL 17 cluster was built from
  the nine migrations, the S2 draft candidate, the S3 posting candidate and
  DEV-shaped fixtures with four drafts (zero-tax ready, taxable, stock-short,
  date outside the open period). The precheck returned exactly 1 READY, 1
  `NOT_SUITABLE_TAXABLE_INVOICE`, and 2 BLOCKED (`STOCK_INSUFFICIENT`,
  `DOC_DATE_OUTSIDE_OPEN_PERIOD`). The posted state was then hand-built from the
  documented contract (never by calling the RPC) and the post-verification
  returned 26 PASS and OVERALL PASS. Tampering with the AR leg, the invoice
  counter, and a `stock.posted` audit row was detected as FAIL in each case.
  Evidence logs: `local_audit/S3_SMOKE_*_LOCAL_VALIDATION.log` and
  `local_audit/S3_SMOKE_QUERY_VALIDATION_SUMMARY.log`.
- **DISCREPANCY — deployment evidence vs. owner statement:** the header of the
  local `dev_s3_post_sales_invoice_candidate.sql` still says "REVIEW ONLY, NOT
  DEPLOYED, NOT DEPLOYABLE YET", while the owner states that the four S3
  functions are installed on DEV and owned by `hasad_sales_poster`. The DEV
  function body cannot be read from this workstation, so the installed body is
  **owner-reported only** and the local candidate remains the contract reference.
  The post-verification query is therefore defensive: it locates the journal
  entry by `idempotency_key` (preferring the documented reason) because
  `journal_entries` has no source-document column, and it reports a numbering
  mismatch as FAIL rather than assuming the approved `SI-YYYY-0001` format.
- **BOUNDARY:** no DEV query was executed, no invoice was posted, the Flutter
  posting button was not enabled, and VAT/RLS/Production were not touched. The
  next step requires a separate, explicit read-only authorization to run the
  precheck on DEV; a real posting requires a second, separate authorization.

## Unit S3 one-time authenticated Flutter posting diagnostic (2026-11-01)

- **PREPARED — not executed on DEV:** a DEV-only Flutter screen can invoke
  `hasad.post_sales_invoice(uuid,uuid,uuid)` exactly once for the owner-authorized
  Abo Amen invoice `86e7a408-479f-4d41-b699-6940cd6b50c8` (company
  `aed949e1-9561-4ae6-a44f-31c25e7e3658`, idempotency key
  `9c225844-e45b-48ef-b7a1-a2cc0572036e`, date `2026-10-31`, gross `10.00`,
  tax `0.00`). It uses the real signed-in session; it never manufactures JWT
  claims or impersonates a user.
- **GATES:** the screen exists only with
  `--dart-define=ENABLE_S3_POSTING_SMOKE=true` and only when the configured
  Supabase project is `sxasnunzspkuwbxiddqd`. The runtime precheck derives the
  project ref from the live PostgREST client URL (`client.rest.url`), verifies
  the active session, the current-user membership in the authorized company,
  the Abo Amen settings name, the exact invoice identity/status/amounts/date/
  key/official-number state, line totals, tracked-stock sufficiency and
  `hasad.sales_posting_allowed(company_id)`. The RPC rechecks permission,
  period, mapping and stock on the server.
- **HUMAN SEQUENCE:** the operator must first run
  `security/candidates/s3_posting_smoke_precheck_readonly.sql` on DEV and see
  `READY_FOR_ZERO_TAX_POSTING_TEST`, then tick an explicit attestation, then
  pass a final confirmation dialog that lists the exact ids and expected
  accounting/inventory effects. The single attempt is consumed before the HTTP
  request leaves the client; timeouts and unknown responses are treated as
  uncertain and the only permitted next step is
  `security/candidates/s3_posting_smoke_postverify_readonly.sql`, never a retry.
- **FILES:** `lib/sales/dev/s3_posting_smoke_contract.dart`,
  `s3_posting_smoke_service.dart`, `s3_posting_smoke_screen.dart`,
  `lib/shell/hasad_app_shell.dart`, `test/sales/s3_posting_smoke_test.dart`.
  The general `SupabaseSalesRepository(postingEnabled: false)` posting button is
  unchanged.
- **VERIFIED — local only:** `flutter analyze` reports no issues and all 87
  tests pass, including 27 focused smoke-diagnostic tests. Tests use an injected
  fake gateway; no test reaches Supabase, reads a secret, or invokes the RPC.
- **BOUNDARY:** no DEV query, no database connection, no posting and no
  deployment occurred. Removing the diagnostic requires deleting the four new
  files/import wiring or simply omitting the dart-define; without the flag the
  navigation entry and route are absent. No commit or push was performed.

## Unit S3 smoke precheck 403 on company_settings — root cause (2026-11-01)

- **OBSERVED — local evidence:** the compiled DEV bundle the operator ran
  (`build/flutter_assets/kernel_blob.bin`, written 2026-11-01 15:26) still asks
  PostgREST for
  `company_settings.company_id,name_ar,name_en,display_name,vat_enabled,currency`.
  The direct-read contract grants `authenticated` column-level SELECT on
  `company_id, display_name, name_ar` only, so the three extra columns are a
  column-privilege denial (SQLSTATE 42501 → HTTP 403), not RLS row filtering.
- **OBSERVED — source state:** `s3_posting_smoke_contract.dart` pins
  `companySettingsReadColumns` to the same three columns the app's own
  `company_context_repository.dart` reads. `HasadAppShell` only renders after
  `CompanyContextState.ready`, which requires that identical read to succeed, so
  the current source cannot produce this 403 for the authorized member.
- **UNCONFIRMED:** why the screen printed `رمز الخادم: 403` rather than the
  mapped `42501` denial. With the locked postgrest 2.9.1, a PostgREST body
  carrying `"code":"42501"` maps to `DENIED`; a bare `403` means the response
  carried no string database code (gateway/proxy 403) or the running bundle
  predates that mapping. This does not change the correction.
- **CORRECTION — Flutter only, no SQL:** read-failure mapping moved to
  `mapS3ReadFailure`. HTTP 401/403 without a database code now reports
  `HTTP_401`/`HTTP_403` and states explicitly that it is not evidence of a
  missing RLS policy; the default branch appends the PostgREST message but
  refuses HTML/proxy bodies and long payloads.
- **VERIFIED — local only:** disposable PostgreSQL 17 harness (nine migrations +
  DEV-shaped column grants and policies). The diagnostic returned 16 rows with
  `normal_app_columns_granted=PASS`, `old_smoke_screen_columns_granted=FAIL`
  (missing `name_en`, `vat_enabled`, `currency`) and
  `fixed_smoke_select_would_succeed_now=PASS`. As `authenticated`, the
  three-column read returned 1 row, the six-column read raised
  `permission denied for table company_settings`, a non-member read and a
  missing SELECT policy both returned 0 rows with no error, and ENABLE/FORCE RLS
  stayed on with no `anon` access. `flutter analyze` is clean and all 30 focused
  smoke tests pass.
- **SQL CANDIDATE:**
  `security/candidates/diagnose_dev_company_settings_403_readonly.sql`
  (read-only), SHA-256
  `2FCEA66628B5C28762DD5BD677090127C91FCB2558A5C87820CB9E4752C5977B`.
- **BOUNDARY:** no DEV/Production query, no GRANT/REVOKE/CREATE POLICY/ALTER, no
  RPC call, no posting, no retry, no commit and no push. Running the diagnostic
  on DEV requires a separate explicit read-only authorization.

## Unit S3 real DEV posting and postverify evidence (2026-11-01)

- **VERIFIED — operator-observed on DEV:** the DEV S3 smoke flow executed
  `hasad.post_sales_invoice` once for invoice
  `86e7a408-479f-4d41-b699-6940cd6b50c8` and reported success. The official
  invoice number is `SI-2026-0001` and the journal entry number is
  `JE-2026-0001`. The posting button was pressed once only; there was no retry
  and no second press.
- **VERIFIED — owner-reported postverify result:** the post-posting verification
  reported 26 PASS, 0 FAIL and 0 WARN. It covered the posted invoice state,
  zero-tax outcome, unique official numbering, balanced journal, inventory
  movement, audit rows and idempotency single use. VAT remains disabled.
- **BOUNDARY:** the operator reports no manual DEV SQL execution and no
  diagnostic-file execution by them, no additional invoice posting, and no
  Production operation. This evidence supersedes the earlier *not executed on
  DEV* state for this single authorized smoke target only; it does not enable
  the normal sales-posting UI or authorize any new posting, database change,
  rollback, commit or push.
