# HASAD V2 — Canonical PostgreSQL Schema
**Status: DRAFT SCHEMA BLUEPRINT, NOT SQL-READY**

## Conceptual domains, not final identifiers
1. Identity: tenant/company, tenant memberships, roles/permissions, settings.
2. Accounting: accounts, fiscal periods, journal headers/lines, posting references.
3. Parties: customers, suppliers and related balances derived from postings.
4. Trade: documents (sales/purchases), items, numbering, receipts and allocations.
5. Inventory: products, warehouses, movements, reconciliations.
6. Expenses: categories/account mapping, payments, expense source and journals.
7. Sync/audit: request idempotency, event/outbox metadata, audit trail.

## Every approved table MUST document
PK UUID or domain key; tenant_id + tenant-safe FK; types/nullability/defaults; UNIQUE and CHECK; indexes; archival/deletion policy; creator/updater; RLS and grants; migrations; server API; test cases.

## Security and accounting invariants
- Tenant boundary at DB level; explicit ownership and same-tenant FK validation.
- No caller direct write bypass to finalized money tables.
- Balanced debit/credit within single atomic posting; appropriate precision, positive validated amounts.
- Reversal/void rules preserve original posted financial history; locked periods enforced server-side.
- Idempotent request replay returns original result; concurrency and sequence collisions tested.

**WARNING** Names and relationships are illustrative until signed off. Generate SQL only after the related feature spec and cross-domain ERD are approved.

## Identity & authorization foundation (PROPOSED 2026-10-20 — not SQL-ready)
Design sources: `features/01_tenants_and_users.md`, `features/02_roles_and_permissions.md`,
`07_SECURITY_TENANCY_RLS.md`. All rows below are `PROPOSED`; business rules behind
them trace to approved decisions D-003/D-006/D-018/D-020 in `15_DECISION_LOG.md`.

### Table inventory, relationships and constraints
| Table | Purpose | Key constraints | Deletion policy |
|---|---|---|---|
| `companies` | Tenant root | `created_by → user_profiles`; `status` active/suspended | No hard delete; suspension only (pending owner decision) |
| `user_profiles` | 1:1 `auth.users` identity | `id = auth.users.id ON DELETE RESTRICT`; `display_name`; `last_permission_check_at` | Identity removal only via approved reset/auth tooling (D-011) |
| `company_memberships` | Active membership (company, user, role, `is_owner`, `status`) | FKs companies/users/roles; **UNIQUE(user_id)** (one company per user, D-003); UNIQUE(company_id, user_id) | No hard delete; `revoked` rows retained for audit |
| `company_invitations` | Pending invitations — **not memberships** | FK company/role/inviter; `token_hash` **UNIQUE**; `expires_at NOT NULL`; partial UNIQUE `(lower(email)) WHERE status='pending'` (global scope, recommended) | No hard delete; states pending/accepted/revoked/expired; one-time acceptance (pending→accepted under row lock) |
| `roles` | Predefined (`is_system`) and custom roles per company | UNIQUE(company_id, code) | Delete custom role only when unassigned (RESTRICT) |
| `permissions` | Static catalogue (`code` PK, `module`, `description`) | Global seed; migration-only changes | No delete |
| `role_permissions` | Role → permission grants | PK(role_id, permission_code) | Cascade with unassigned role |
| `user_permission_overrides` | Per-membership allow/deny | UNIQUE(membership_id, permission_code); `effect` CHECK | Delete allowed (audit kept) |
| `audit_log` | Append-only trail (actor, action, entity, details) | Trigger rejects UPDATE/DELETE; **no direct write grants** — written only via the narrow audit helper (see `07`) | Never deleted |

Relationships: `companies 1—* memberships *—1 roles *—* permissions`; `memberships 1—* overrides`; `companies 1—* invitations`; `user_profiles 1—1 memberships` (via UNIQUE).
Cross-table integrity: every tenant-scoped row carries `company_id NOT NULL`; membership-derived checks happen in RLS/RPCs, not client logic.

### Corrected integrity requirements (PROPOSED 2026-10-20 — RECOMMENDED_PENDING_VALIDATION until PoC-tested)
Full reasoning and test cases live in `07_SECURITY_TENANCY_RLS.md` ("Corrected design flaws"). Summary of what the first migration must satisfy:
1. **Audit write path:** `audit_log` gets **no direct INSERT grant** for `authenticated`; rows are written through a narrow `SECURITY DEFINER` audit helper owned by a locked non-superuser role (actor derived from `auth.uid()`, live-membership verified, fixed table/column set, pinned `search_path`). Fallback if locked roles prove infeasible in Supabase: `INSERT`-only grant on `audit_log` (append-only via missing `UPDATE`/`DELETE` grants + rejection triggers), with spoofing residual risk documented. Both options pending validation. **DEV implementation note (2026-10-30):** for Unit S1 customer writes the actor is derived from `request.jwt.claims` instead of `auth.uid()` because the dedicated locked owner role has no USAGE on schema `auth` on DEV; the helper remains a SECURITY DEFINER trigger owned by that locked role, and `auth.uid()` is used only inside policies evaluated as `authenticated`. See `15_DECISION_LOG.md`.
2. **Ownership integrity — layered, deferred trigger alone rejected:** (a) `company_create` inserts company + owner membership atomically with an immediate pre-commit assertion; (b) deferred constraint trigger re-verifies `≥1 active owner` at COMMIT across INSERT/UPDATE/DELETE **and status changes** (suspending the sole owner must fail); (c) an advisory per-company lock (or ordered row locks) precedes every mutation of owner `is_owner`/`status` — closing the concurrent double-revoke race where each transaction's deferred check sees the other co-owner uncommitted; (d) no `DELETE` grants on `companies`/`company_memberships` plus rejecting triggers; company deletion out of scope (suspension-only, pending owner decision).
3. **Invitation security:** `UNIQUE(token_hash)` (regenerate on collision); `expires_at NOT NULL` with rejection at acceptance (recommended TTL 7 days — open item); one-time acceptance `pending→accepted` inside `SELECT ... FOR UPDATE` with `UNIQUE(user_id)` as final arbiter; raw token stored never — only its hash, delivered once, kept out of URLs/logs; global pending-uniqueness on `lower(email)` recommended over per-company scope (consistent with D-003), trade-off documented.

### Open implementation choices (RECOMMENDED_PENDING_VALIDATION — not approved)
- UUIDv7 primary keys (R-08); `text + CHECK` state columns instead of PostgreSQL enums.
- Two-schema exposure: private `hasad` + exposed `hasad_api` (R-01 extension) — requires PostgREST config validation on the reused DEV project (D-010).
- `SECURITY INVOKER`-only RPCs; any future `SECURITY DEFINER` requires a locked non-superuser owner role (never `postgres`) — availability untested.
- Deferred (`DEFERRABLE INITIALLY DEFERRED`) constraint trigger for the ≥1-active-owner invariant — **necessary but not sufficient alone**; must be paired with the per-company advisory lock (see "Corrected integrity requirements").
- Advisory per-company lock for ownership/membership mutations.
- Throttled updates of `last_permission_check_at`; UUIDv7 generation site (SQL vs Dart).
- `ON DELETE RESTRICT` from `auth.users` to profiles (must align with the future reset plan, D-011).

## Accounting foundation (PROPOSED 2026-10-20 — not SQL-ready)
Design sources: `features/03_chart_of_accounts.md`, `features/04_journals_and_fiscal_periods.md`,
and `09_ACCOUNTING_INVARIANTS.md`. All rows are `PROPOSED`; business rules behind them trace to
OWNER_APPROVED decisions D-005/D-006/D-013/D-017/D-018/D-019 in `15_DECISION_LOG.md`.
The accounting tables reuse the identity/tenancy model above: `company_id NOT NULL` on every
tenant-scoped row, composite same-tenant FKs, RLS + RPC authorization per `07_SECURITY_TENANCY_RLS.md`.

### Table inventory, relationships and constraints
| Table | Purpose | Key constraints | Deletion policy |
|---|---|---|---|
| `accounts` | Per-company CoA tree | `UNIQUE(company_id, code)`; `account_type` CHECK (asset/liability/equity/revenue/expense); `parent_id` self-FK with same-company composite FK; `is_active` | Never deleted; deactivate only |
| `module_account_map` | (company, module, account_role) → account | `UNIQUE(company_id, module, account_role)`; same-company FK to accounts | Delete allowed; audit kept |
| `fiscal_years` | FY header (Jan 1–Dec 31, D-005) | `UNIQUE(company_id, start_date)`; `status open/closed` | Never deleted; close only |
| `fiscal_periods` | 12 monthly periods (D-005) | `UNIQUE(fiscal_year_id, period_no)`; `period_no CHECK 1..12`; contiguous dates; `status open/closed`; `reopen_count` + stamps | Never deleted |
| `journal_entries` | Headers: draft/posted; kinds standard/opening/closing/reversal/adjustment | `entry_no` server-issued on posting — **issued number UNIQUE per (`company_id`, `entry_no`)** (counter scope per D-013: company + document type + fiscal year; counter mechanics owned by `features/04`/`doc_numbers`); `reversal_of_id` self-FK; `idempotency_key` UNIQUE per company; `posted_at/by` | Posted rows never deleted; drafts deletable with audit |
| `journal_lines` | Debit/credit lines | Composite same-company FKs (entry, account, party); one-sided positive amount CHECK; `numeric(18,2)`; `line_no` UNIQUE per entry; nullable `party_id` (D-017) | Posted rows never deleted |
| `doc_numbers` | Server-issued numbers — **counter scope per (company, doc_type, fiscal year) (D-013); the issued formatted number is UNIQUE per (company_id, doc_no); official numbers issued on successful posting only and a failed/rolled-back transaction consumes none (D-018)** | PK triple; `next_value`; advisory-locked increments | Never deleted |

Relationships: `companies 1—* accounts (self-tree)`; `companies 1—* fiscal_years 1—* fiscal_periods`;
`companies 1—* journal_entries 1—* journal_lines *—1 accounts`; `journal_entries *—1 journal_entries (reversal_of)`;
`module_account_map *—1 accounts`; lines optionally `*—1 parties`.

### Open implementation choices (RECOMMENDED_PENDING_VALIDATION — not approved)
- Deferred constraint trigger for Σdebits = Σcredits at COMMIT; advisory lock per (company, doc_type, fiscal_year) for numbering — both untested under Supabase transaction pooling.
- Leaf-rule posting eligibility (postable iff no active children), evaluated live — no stored flag (avoid drift).
- Number-gap semantics under crash scenarios: no gap-free claim without PoC proof.
- Server-side draft storage (vs client-only drafts); UUIDv7 generation site (R-08); `numeric(18,2)` final amounts (D-005 OWNER_APPROVED) with **intermediate precision still R-07 pending** — unit prices, quantities and costing must not be silently forced to 2dp.
- Single-currency (ILS) v1; accrual basis (O5 pending); year-end automation OFF until O2 decided.
- Starter chart-of-accounts template and any statutory account structure: BLOCKED on O1/D-023 — no seed authored.

## Parties, cash & banking foundation (PROPOSED 2026-10-20 — not SQL-ready)
Design sources: `features/05_customers_and_suppliers.md`, `features/09_cash_and_bank.md`,
invariants I12–I17 in `09_ACCOUNTING_INVARIANTS.md`. Business rules behind these tables trace to
OWNER_APPROVED decisions D-005/D-006/D-013/D-016/D-017/D-018/D-019. Same tenancy model as above:
`company_id NOT NULL` everywhere, composite same-tenant FKs, RLS + RPC authorization per
`07_SECURITY_TENANCY_RLS.md` (itself DRAFT pending the security PoC).

### Table inventory, relationships and constraints
| Table | Purpose | Key constraints | Deletion policy |
|---|---|---|---|
| `parties` | Unified counterparty (customer and/or supplier) | `UNIQUE(company_id, code)`; `party_type` CHECK; stored classification flags `is_customer`/`is_supplier` (explicit, usable before first transaction); `tax_id` nullable; `is_active` | Never deleted; deactivate (RESTRICT while referenced) |
| `cashboxes` | Cash containers | `UNIQUE(company_id, code)`; `account_id` same-company FK to an active postable leaf account | Never deleted; deactivate (zero derived balance, recommended) |
| `bank_accounts` | Bank containers | as cashboxes + `bank_name`, `branch_no`, `account_no`, `iban` nullable | same |
| `payment_documents` | Receipts / payments / transfers / refunds | `doc_kind` CHECK; `status draft/posted`; `amount numeric(18,2) CHECK > 0`; `party_id` + nullable `employee_id` (same-company composite FK → `employees`) under an **exactly-one counterparty CHECK per `doc_kind` (features/09 C2): transfers — neither; receipts/refunds — `party_id` required; payments — exactly one of `party_id` (supplier) or `employee_id` (net wages, features/09 C12); simultaneous party + employee structurally impossible**; `from_account_id`/`to_account_id` (transfer CHECK `<> from`); `doc_no` server-issued on posting (counter per company+doc_type+FY, D-013; issued number UNIQUE per (`company_id`, `doc_no`)); `reversal_of_id` self-FK; `idempotency_key` UNIQUE per company; `tender_method`/`tender_reference` (enumeration = O7) | Drafts deletable with audit; posted never deleted |
| `payment_allocations` | Append-only application of money documents to posted invoices/notes/**expense documents** | `target_kind` CHECK registry (AR-direction — sales invoice, debit note; AP-credit direction — purchase bill, supplier credit note, **`expense_document` for credit/employee-settlement expenses only — audit batch 2**); **one nullable same-company FK column per target kind (`sales_document_id`, `purchase_document_id`, `expense_document_id`) with a CHECK matching `target_kind` exactly once** (proposed — real tenant-safe FKs; RECOMMENDED_PENDING_VALIDATION); same-company FK to the payment; `amount CHECK > 0`; `status ('active','superseded','reversed')`; `supersedes_id` self-FK (corrections append rows, never mutate) | Never deleted |
| `reconciliation_statements` | Statements per container GL account | `status ('open','closed')`; closing balance; close audit stamps | Never deleted |
| `reconciliation_items` | Statement lines and matches | FK statement; optional `journal_line_id` match on the same container account; unmatched external lines flagged, never auto-posted | Never deleted |

Relationships: `companies 1—* parties`; `companies 1—* cashboxes/bank_accounts *—1 accounts`;
`companies 1—* payment_documents *—1 parties (nullable)` and `*—1 employees (nullable — employee-kind
net-wage payments, features/09 C12; exactly one counterparty per `doc_kind`)`;
`payment_documents 1—* payment_allocations *—1 posted business documents` (**per-kind target edges:
sales_documents / purchase_documents / expense_documents — same-company composite FKs**);
`cashboxes/bank_accounts 1—* reconciliation_statements 1—* reconciliation_items`.
**No stored balance columns** on any table (D-017): container balances, party AR/AP, unapplied credits, open document amounts and statement variances are all derived.

### Open implementation choices (RECOMMENDED_PENDING_VALIDATION — not approved)
- Append-only allocation supersession mechanics (row shape + status transitions) — consistency with the D-019 immutability philosophy to be proven in the PoC.
- Per-(company, party) advisory lock serializing `allocation_set` (capacity can never be exceeded — proof required).
- Auto-classification of parties on posting (vs strict per-module rejection); auto-matching heuristics for reconciliation (amount + value date).
- Offline-entered **pending allocations** accepted by the server only after both documents are posted, in outbox order (D-006); pending-entry vs server-acceptance states are explicitly distinct.
- Manual bank statement entry for v1 (O8); cash-count reporting only, no variance posting (O9); overpayments allowed as unapplied credits (O10) — all three pending owner confirmation.
- Single-currency ILS containers; tender enumeration (O7) blocks final `tender_method` CHECK authoring.

## Inventory foundation (PROPOSED 2026-10-20 — not SQL-ready)
Design sources: `features/08_inventory_and_warehouses.md`, invariants I18–I21 in
`09_ACCOUNTING_INVARIANTS.md`. Business rules trace to OWNER_APPROVED D-005/D-006/D-013/D-014/D-018/D-019.
Same tenancy model: `company_id NOT NULL` everywhere, composite same-tenant FKs, RLS + RPC
authorization per `07_SECURITY_TENANCY_RLS.md` (DRAFT pending the security PoC).

### Table inventory, relationships and constraints
| Table | Purpose | Key constraints | Deletion policy |
|---|---|---|---|
| `warehouses` | Quantity locations (quantity sub-pools only) | `UNIQUE(company_id, code)`; `is_active` | Never deleted; deactivate |
| `product_categories` | Flat classification | `UNIQUE(company_id, code)` | same |
| `units_of_measure` | Per-company base + secondary units | `UNIQUE(company_id, code)`; exactly one base per company (RPC-enforced) | same |
| `products` | Items | `UNIQUE(company_id, code)`; `barcode` nullable `UNIQUE(company_id, barcode)`; `name_ar NOT NULL`; same-company FKs (category, base UOM); `is_active` (deactivate blocks new documents) | same |
| `product_uom_conversions` | UOM → base factors | `UNIQUE(product_id, uom_id)`; `factor numeric(19,6) > 0`; immutable once used by a posted movement (recommended) | Not deleted; immutable after use |
| `stock_levels` | **Rebuildable cache** of (product, warehouse) quantity — never authoritative | PK (product, warehouse); `qty numeric(19,4) CHECK (>= 0)`; `last_unit_cost numeric(19,4)` | Cache row; rebuilt by replay |
| `stock_movements` | **Authoritative append-only ledger** (single source of truth) | `direction in/out`; `qty numeric(19,4) > 0`; `unit_cost numeric(19,4) >= 0` (snapshot); `value numeric(18,2)` HALF_UP line rule; `movement_type` CHECK (`purchase_receipt`,`sales_issue`,`sales_return`,`purchase_return`,`transfer_out`,`transfer_in`,`count_adjustment`,`opening`); per-product `seq` UNIQUE (deterministic replay); same-company composite FKs (product, warehouse, source document); optional `journal_line_id`; **no UPDATE/DELETE** | Never deleted; immutability = three layers (pending PoC) |
| `stock_counts` / `stock_count_lines` | Physical counts → adjustments | `status open/posted`; `counted_qty numeric(19,4) >= 0` (negative count rejected for investigation, not clamped); one posted count per warehouse/date (recommended) | Posted rows never deleted |

Relationships: `companies 1—* warehouses / product_categories / units_of_measure / products`;
`products 1—* product_uom_conversions *—1 units_of_measure`;
`companies 1—* stock_movements *—1 products *—1 warehouses` (+ same-company source-document FK);
`warehouses 1—* stock_levels *—1 products`;
`warehouses 1—* stock_counts 1—* stock_count_lines *—1 products`.

### Indexing requirements
- `stock_movements (product_id, seq)` UNIQUE — replay order and determinism gate.
- `stock_movements (company_id, source_document_type, source_document_id)` — document→movements.
- `stock_movements (warehouse_id, posted_at)` — warehouse ledger views.
- `stock_levels (warehouse_id)`, `stock_levels (product_id)` — balance lookups.
- `products (company_id, lower(name_ar))` search; partial index on barcode when present.

### Valuation and cost-input rules (PROPOSED — approvals pending)
- **Costing pools:** recommended **company-wide moving weighted average per product** with warehouses
  as quantity sub-pools — **O12 (REQUIRES_OWNER_DECISION)**, not approved. Every movement stores its
  own `unit_cost` snapshot; warehouse value reports sum stored movement values, never qty × a
  re-derived average.
- **Rounding/reconciliation policy:** the GL amount of each movement **is its rounded 2dp `value`**,
  so Σ rounded movement values ≡ `INVENTORY_CONTROL` GL balance **by construction**; residuals versus
  unrounded qty × average are disclosed by a residual-report test — **no claim that independently
  rounded values reproduce an unrounded valuation total**.
- **Cost inputs:** v1 cost = net purchase price **excluding recoverable VAT** (VAT is a separate GL
  line); **nonrecoverable VAT, freight and duties are not silently inventory cost** — landed-cost
  allocation is deferred and remains OPEN.
- **Transfers:** paired movements at identical snapshot cost — quantity and total value preserved,
  no GL entry under company-wide pools.

### Open implementation choices (RECOMMENDED_PENDING_VALIDATION — not approved)
- Company-wide vs per-warehouse costing pools (O12); sales-return cost policy (O11: original issue
  cost recommended); `INVENTORY_ADJUSTMENT` gain/loss treatment (O13); pending-stock display (D-025).
- R-07 precision (`numeric(19,4)` intermediates, line HALF_UP 2dp) pending parity test.
- Rounding residual bound, per-product `seq` assignment mechanics, row-lock vs advisory-lock under
  pooling, UOM-conversion immutability-after-use — PoC validation items.

## Trade (sales & purchases) foundation (PROPOSED 2026-10-20 — not SQL-ready)
Design sources: `features/06_sales_and_invoicing.md`, `features/07_purchases.md`, invariants
I22–I26 in `09_ACCOUNTING_INVARIANTS.md`, and the tenant-safe relationship rules in
`06_ENTITY_RELATIONSHIPS.md`. Business rules trace to OWNER_APPROVED D-005/D-006/D-013/D-016/
D-017/D-018/D-019. Same tenancy model: `company_id NOT NULL`, composite same-tenant FKs,
RLS + RPC authorization per `07_SECURITY_TENANCY_RLS.md` (DRAFT pending the security PoC).

### Table inventory, relationships and constraints
| Table | Purpose | Key constraints | Deletion policy |
|---|---|---|---|
| `sales_documents` | Quotations, orders, invoices, credit/debit notes | `company_id NOT NULL`; `doc_kind` CHECK (`quotation`,`order`,`sales_invoice`,`credit_note`,`debit_note`); `party_id` same-company FK; dual state CHECK (workflow `draft/open/cancelled` vs financial `draft/posted` + derived reversed); `vat_mode CHECK ('inclusive','exclusive')` (D-005); `doc_no` server-issued on posting (financial) / on creation (quote & order, O16 rec.) — **counter scope (company, doc_type, fiscal year) per D-013; issued formatted number UNIQUE per (`company_id`, `doc_no`)**; `original_document_id` self-FK (notes, same company); `idempotency_key` UNIQUE per company; header `net/tax/gross numeric(18,2)` immutable posted facts asserted = Σ lines | Posted financial rows never deleted/updated; workflow drafts deletable with audit; cancellation only with no posted children |
| `sales_document_lines` | Sales lines | `line_no` UNIQUE per doc; `product_id` nullable (service lines); `warehouse_id` required for stocked lines; `qty numeric(19,4) > 0`; `unit_price numeric(19,4) >= 0`; discount fields; `tax_rate numeric(6,3)` snapshot; derived `net/tax/gross`; `order_line_id` / `original_line_id` composite same-company FKs; **return/invoice capacities derived from posted children, never stored** | Never deleted once posted (with document) |
| `purchase_documents` | Quotations, orders, goods receipts, bills, notes | as sales_documents with `doc_kind` CHECK (6: add `goods_receipt`, `purchase_bill`); `supplier_ref` with `UNIQUE(company_id, party_id, supplier_ref)` when present (duplicate-bill guard, recommended); receipt/bill links via lines | same |
| `purchase_document_lines` | Purchase lines | as sales lines + `receipt_line_id` composite same-company FK (clearing consumption); bill/receipt capacities derived | same |
| `tax_rates` | Per-company VAT rate catalogue — **effective-dated versions (authoritative definition in the settings foundation below and `features/13` C5; the earlier flat `UNIQUE(company_id, code)` statement is superseded — audit batch 3)** | `company_id NOT NULL`; `UNIQUE(company_id, code, valid_from)`; `valid_from NOT NULL` / `valid_to NULL` (inclusive boundaries, successor = predecessor `valid_to + 1 day`); `rate numeric(6,3) CHECK (>= 0)`; `is_active` — **statutory values blocked by D-023**; document lines snapshot their resolved rate (history never recomputes) | Never deleted; versions closed, never removed |

Cross-module: `products.track_inventory` boolean default true — **now specified in `features/08`
C1/D (audit batch 3):** service lines emit no stock movements, require no warehouse
(`WAREHOUSE_REQUIRED` typed rejection otherwise), are GL-unaffected, and the class is frozen
once movements exist (recommended rule); no-negative-stock and server-authoritative valuation
untouched.

### Indexing requirements
- `sales_documents / purchase_documents (company_id, doc_kind, doc_date)`; `(party_id, doc_date)`;
  `(company_id, doc_no)` UNIQUE; `(original_document_id)`; `(company_id, idempotency_key)` UNIQUE.
- `sales_document_lines (order_line_id)`; `purchase_document_lines (receipt_line_id)`; `(order_line_id)`
  — fulfillment/return capacity lookups.
- `tax_rates (company_id, code, valid_from)` UNIQUE + partial active lookup (effective-dated —
  matches the settings foundation; the earlier flat `(company_id, code)` index is superseded).

### Posting and cost-input rules (PROPOSED — approvals pending)
- **Corrected matrix (balance-proven in the specs' §G):** input VAT is **DR `VAT_INPUT`** on bills and
  supplier debit notes and **CR `VAT_INPUT`** on supplier credit notes; goods receipt posts
  `DR INVENTORY_CONTROL / CR PURCHASE_CLEARING`; bills against receipts consume clearing at receipt
  valuation with price differences to `PURCHASE_PRICE_VARIANCE` (O18 pending); direct purchases post
  `DR inventory/expense + DR VAT_INPUT / CR AP_CONTROL`; sales invoice posts `DR AR / CR revenue +
  CR VAT_OUTPUT` plus `DR COGS / CR INVENTORY_CONTROL` for stocked lines; every posted entry balances.
- **Cost inputs remain distinct (no silent equivalence):** recoverable VAT never enters inventory
  cost or expense nets; non-recoverable VAT → `NONRECOVERABLE_VAT` expense role (O20 pending);
  freight/duties/landed costs excluded in v1 (O21 OPEN); return-cost policies O11/O19 pending.
- **Capacities are derived, not stored:** ordered ≥ received ≥ billed (per line), returned ≤ original
  line qty — enforced at posting under row locks on the source document (I23/I25).

### Open implementation choices (RECOMMENDED_PENDING_VALIDATION — not approved)
- O14 clearing receipt model; O15 cash settlement via linked payment document; O16 quote/order
  numbering; O17 standalone goods issue deferral — all recommended defaults, owner answers pending.
- O18 price-variance treatment; O19 purchase-return cost divergence; O20 non-recoverable VAT;
  O21 landed costs; O22 notes against settled bills — accountant/legal validation required.
- Discount largest-remainder allocation; inclusive group-split formula; header-total assertions;
  capacity-lock behavior under Supabase pooling; R-07 precision — PoC + parity test pending.

## Sync foundation (PROPOSED 2026-10-20 — not SQL-ready)
Design sources: `08_OFFLINE_SYNC.md` (authoritative contract), `features/14_sync_and_conflicts.md`,
invariants I31–I33 in `09_ACCOUNTING_INVARIANTS.md`. Business rules trace to OWNER_APPROVED
D-006/D-013/D-018/D-020/D-021; R-04 (publication semantics) and R-05 remain pending validation.
Same tenancy model: `company_id NOT NULL`, RPC authorization per `07_SECURITY_TENANCY_RLS.md`
(DRAFT pending the security PoC).

### Table inventory, relationships and constraints
| Table | Purpose | Key constraints | Deletion policy |
|---|---|---|---|
| `sync_operations` | Committed outcome ledger per client operation (applied/rejected evidence, replay source) | `company_id NOT NULL`; `UNIQUE(company_id, client_op_id)`; `payload_hash` canonical; `status ('inflight','applied','rejected')`; `outcome jsonb` (server id, official number, public seq); `supersedes_op_id` self-FK (corrections = new identifiers); `attempts`, `device_id`, `applied_at`; **rejection rows written after savepoint rollback and committed by the outer transaction** (never inside the failed business block); **no UPDATE on `applied` rows** (outcome immutable) | Retained as audit evidence; purge only under a documented retention policy with backups (12) — never hard-deleted in normal operation |
| `sync_changes` | Download publication feed | `company_id NOT NULL`; **provisional rows invisible to clients until published**; `public_seq` assigned at publication **only for committed rows**, under a per-company advisory lock, monotonic in publication order; `UNIQUE(company_id, public_seq)` when published; `entity_type`, `entity_id`, `op`, minimal payload; append-only | Retention-bounded (recommended ≥ 90 days or row floor — RECOMMENDED_PENDING_VALIDATION); truncation forces client `FEED_TRUNCATED` → snapshot resync, never silent loss; covered by backup policy (12) |

Relationships: `companies 1—* sync_operations` (self-FK `supersedes_op_id`); `companies 1—* sync_changes`;
applied outcomes reference (soft, via `outcome` payload, not FK) posted documents/entries/movements
produced by the target feature's RPC — the ledger is transport evidence, not a business table.

### Indexing requirements
- `UNIQUE (company_id, client_op_id)` — idempotency arbiter (I31).
- `sync_changes (company_id, public_seq)` UNIQUE — watermark pull ranges.
- Partial index `sync_changes (company_id, provisional_order) WHERE NOT published` — publication step.
- `sync_operations (company_id, created_at)`; `sync_operations (supersedes_op_id)`.

### Ownership, security and retention requirements
- **No client grants** on either table: written only by the sync/posting path; reads only through
  `sync_pull`/`sync_snapshot`/`sync_status` with server-derived membership (R-03); `anon` denied.
  Table owner: the locked non-superuser migration role (never `postgres`) — consistent with the
  audit-helper ownership decision in `07` (mechanism pending PoC).
- Duplicate-ack resends pass the same membership/permission gate before any stored outcome is
  disclosed (protocol risk E).
- Retention: feed bounded with explicit `FEED_TRUNCATED` resync path; `sync_operations` retained with
  backups; both subject to the future backup/retention policy — no silent history loss (protocol risk F).
- Rebuildability: feed regeneration from business tables is **conditional** (verified source data +
  documented deterministic ordering; state-at-a-point only, not historical op order).

### Open implementation choices (RECOMMENDED_PENDING_VALIDATION — not approved)
- Publication piggyback-on-`sync_pull` vs background publisher; per-company apply/publication advisory
  lock contention under pooling; canonical payload-hash serialization (SQL↔Dart parity).
- Feed retention window; snapshot granularity; rejection re-evaluation semantics for resends;
  one-op-per-call upload throughput.

## Expenses foundation (PROPOSED 2026-10-20 — not SQL-ready)
Design sources: `features/10_expenses.md`, invariants I27–I30 in `09_ACCOUNTING_INVARIANTS.md`,
the tenant-safe relationship rules in `06_ENTITY_RELATIONSHIPS.md`, and the 2026-10-20 expenses &
financial reports planning report. Business rules trace to OWNER_APPROVED D-005/D-006/D-013/D-017/
D-018/D-019; VAT rates/legal forms remain D-023-OPEN; Storage disposition remains D-011-OPEN.
Same tenancy model: `company_id NOT NULL` everywhere, composite same-tenant FKs, RLS + RPC
authorization per `07_SECURITY_TENANCY_RLS.md` (DRAFT pending the security PoC).

### Table inventory, relationships and constraints
| Table | Purpose | Key constraints | Deletion policy |
|---|---|---|---|
| `expense_categories` | Category master data with **direct GL account binding** (proposed mechanism; shared roles still via `module_account_map` — see open choices) | `UNIQUE(company_id, code)`; `name_ar NOT NULL`; `account_id` same-company FK to an active postable expense-type leaf (validated at create **and** at posting); `is_active` | Never deleted; deactivate only |
| `expense_documents` | Cash / credit / employee-settled expense receipts | `settlement CHECK ('cash','credit','employee')` (`employee` = unapproved proposal, O28); `party_id` nullable (RPC-enforced NOT NULL for credit/employee); `container_account_id` same-company container account (cash mode only); `vat_mode CHECK` (D-005); `doc_no` server-issued on posting — **counter scope (company, doc_type, fiscal year) per D-013; issued number UNIQUE per (`company_id`, `doc_no`)**; `external_ref` (supplier receipt reference); `reversal_of_id` self-FK (one level, D-019); `idempotency_key` UNIQUE per company; header `net/tax/gross numeric(18,2)` immutable posted facts | Posted rows never deleted/updated; drafts deletable with audit |
| `expense_document_lines` | Lines (mixed categories per receipt allowed) | `line_no` UNIQUE per doc; `category_id` same-company FK; `amount numeric(19,4)` (R-07); `tax_rate numeric(6,3)` snapshot; derived `net/tax/gross`; `account_id` **resolved and stored at posting** (binding snapshot for auditability) | Never deleted once posted (with document) |
| `expense_attachments` | Receipt evidence references | FK `expense_document_id` same company; `storage_path` under a per-company folder; `content_hash`; `byte_size`; `mime CHECK`; uploader stamps | Retained with posted document; removed only with draft deletion, audited (O24/D-011 pending) |
| `expense_receipt_dedup` | **Duplicate-reference guard** (I27 layer 2) | `UNIQUE(company_id, party_id, external_ref)`; FK to the expense document; append-only — **release mechanism on reversal is documented but unvalidated** | Rows retained; released only via the documented reversal mechanism |

Relationships: `companies 1—* expense_categories *—1 accounts`; `companies 1—* expense_documents
*—1 parties (nullable) *—* lines`; `expense_documents 1—* expense_document_lines *—1 expense_categories`;
`expense_documents 1—* expense_attachments`; `expense_documents 1—* expense_receipt_dedup`.
**Cross-module (additive):** credit/employee expense documents join `payment_allocations` as
AP-direction **targets** (`target_kind` gains `expense_document` — **now specified in
`features/09` C6/D, audit batch 2**: per-kind same-company FK column, derived capacity =
gross − Σ active allocations, over-allocation forbidden, reversals restore capacity per I15;
cash-mode expenses structurally cannot be targets) — capacities stay derived, direction rules
(I13) and AR/AP authority (D-017/I14) unchanged.

### Indexing requirements
- `expense_documents (company_id, doc_date)`; `(party_id, doc_date)`; `(company_id, doc_no)` UNIQUE;
  `(company_id, idempotency_key)` UNIQUE.
- `expense_document_lines (category_id)`; `(account_id)`.
- `expense_receipt_dedup (company_id, party_id, external_ref)` UNIQUE — duplicate-bill/receipt guard
  interoperable with `purchase_documents.supplier_ref`.

### Ownership, security and retention requirements
- Written only through expense RPCs (`expenses.create/post/reverse/manage`); no client `UPDATE/DELETE`
  on posted rows (three-layer immutability, D-019); `anon` denied; company derived server-side (R-03).
- Cash-mode expenses post **one entry with a direct container credit and create no
  `payment_documents` row** (C3 model — RECOMMENDED_PENDING_VALIDATION); container balances and
  statements derive from GL lines, so no stored balance exists here either (D-017).
- Attachments subject to the future Storage/retention policy (D-011, O24); dedup guard rows retained
  as evidence.

### Report read-model and indexing requirements (features/12 — **no report tables**)
Reports introduce **zero tables and no authoritative report balances** (D-017; I29/I30). Required
read-model indexes on existing tables:
- `journal_lines (company_id, account_id)` covering, joined to `journal_entries (company_id,
  entry_date, status)` — trial balance / GL / P&L / balance sheet.
- `journal_lines (company_id, party_id)` — statements and aging (O25 buckets derived at query time).
- Document indexes of features/06/07/09/10 — sales/purchases/expense summaries.
- `stock_movements (warehouse_id, posted_at)` (+ existing product/warehouse lookups) — inventory
  quantity and valuation (residual disclosure per I18).
- Any **future** summary/projection structure must be rebuildable, versioned and explicitly
  non-authoritative (D-017 permits derived reporting summaries only).

### Open implementation choices (RECOMMENDED_PENDING_VALIDATION — not approved)
- C3 direct cash-expense posting vs I24-style linked payment document for cash expenses (test proof
  required; owner/accountant may overturn).
- Category **direct account binding** vs dynamic `module_account_map` role per category (both
  documented in `features/10` C1; `features/03` C7 wording alignment is a recorded follow-up).
- Duplicate-guard release mechanism on reversal; server-side report aggregation vs pagination;
  report export engine (Arabic PDF/CSV, R-06); `STABLE` report snapshot semantics under pooling.

## Settings & numbering foundation (`features/13`; configuration — PROPOSED)

**`company_settings` — one row per company** (PK `company_id`, 1:1 `companies`; typed single-row
core is RECOMMENDED_PENDING_VALIDATION over a key-value store because CHECK constraints hard-lock
owner-approved constants): legal `name_ar`/`name_en`, business `display_name`, address columns
(line/city/region/postal), contact (phone/email/website), optional `tax_id`/`registry_no`
(**nullable text, no assumed legal-format validation** — D-023), `currency` **CHECK-locked to
`'ILS'`** (D-005 OWNER_APPROVED, immutable via RPCs), `vat_enabled boolean` (D-005 optional),
`logo_storage_path` (nullable — Storage blocked by **D-011**), `preferences jsonb` (non-critical
UI only), `updated_by/at`. **Rounding (2dp HALF_UP, D-005) and the fiscal calendar
(`features/04` tables) are not columns here — they are immutable constants / delegated ownership.**

**`tax_rates` — effective-dated extension of the `features/06/07` catalogue (additive; no
duplicate):** add `valid_from date NOT NULL` and `valid_to date NULL` and change uniqueness to
`UNIQUE(company_id, code, valid_from)`; boundaries are **inclusive on both ends** with a
successor's `valid_from` = predecessor's `valid_to + 1 day` (disjoint by construction; server
additionally rejects overlap — `EFFECTIVE_DATE_OVERLAP`). Version rows are appended/closed, never
mutated once used, never deleted. Posting resolves the rate in effect **on the document date,
server-side**; posted lines keep their `tax_rate` snapshot forever (I22-class immutability). **No
rate seeds until D-023.**

**`document_types` — per-company numbering/format registry:** `UNIQUE(company_id, code)`;
Arabic display name; `issuance CHECK ('posting','creation')` (financial docs post-only per D-018;
`'creation'` rows dormant until **O16** is answered); `format_prefix`; `pad_length CHECK (1..10)`;
`is_active`. **Cross-reference — not owned here:** the `doc_numbers (company_id, doc_type,
fiscal_year)` counter and its advisory-locked atomic allocation belong to the **accounting
foundation above / `features/04` (I8)**; feature 13 configures only how numbers look and when
they are issued. Recommended format `PREFIX-YYYY-NNNN` is **O30 (owner-pending)**, not approved.

**`document_templates` — print/PDF layouts + branding:** `UNIQUE(company_id, template_code)`;
same-company FK `doc_type → document_types`; `layout_version`; paper size/orientation;
`header_fields jsonb`; `is_active`. Templates affect **presentation only** — every rendered value
comes from immutable posted rows; date/number formats follow tenant settings, never device
locale; **no statutory format assumed (D-023)**.

### Indexing requirements (settings)
- `tax_rates (company_id, code, valid_from)` UNIQUE + partial-active lookup; `document_types
  (company_id, code)` UNIQUE; `document_templates (company_id, doc_type)`; `doc_numbers` PK triple
  (accounting foundation, D-013).

### Ownership, security and retention requirements (settings)
- Settings rows are **updated with in-transaction audit events (old → new), never deleted; no
  `DELETE` anywhere in this feature**; writes are online-only RPCs gated by
  `company.settings/tax/numbering` (mapping into the owner-pending role catalogue);
  **no client write grants on `doc_numbers`**; company derived server-side (R-03); **no settings
  RPC accepts or issues an official number**; `anon` denied. The INVOKER/RLS privilege model
  remains **DRAFT — not verified** (`07`).
- **Historical integrity:** posted documents are never rewritten by configuration changes — tax
  snapshots are structural; the **legal-identity snapshot (`company_snapshot` at posting) is
  RECOMMENDED_PENDING_VALIDATION under O31**; format changes apply only to numbers issued
  afterward (posted `doc_no` strings immutable; committed numbers never reassigned — I8; no
  gap-free claim until transaction/crash tests pass).

## Payroll foundation (`features/11`; PROPOSED 2026-10-21 — statutory content blocked by D-024)

**Phase 9A exception (OWNER_APPROVED 2026-10-28):** for the three-table
employee-master structural subset, `features/11_employees_and_payroll.md` §D.1
is the controlling contract. The broader `employees` links/fields and every
other payroll table below are future-payroll proposals, excluded from Phase 9A;
they remain DRAFT/BLOCKED with D-024 and O32–O34 OPEN.

Same tenancy model as above: `company_id NOT NULL` everywhere, composite same-tenant FKs, RLS +
RPC authorization per `07_SECURITY_TENANCY_RLS.md` (DRAFT pending the security PoC). **No
statutory rate, bracket, contribution, minimum wage, entitlement or deduction limit is seeded or
invented** — D-024 OPEN; the statutory tables exist empty and the posting gate (below) blocks
every run until the owner answers.

### Table inventory, relationships and constraints
| Table | Purpose | Key constraints | Deletion policy |
|---|---|---|---|
| `departments`, `job_titles` | Org master data | `UNIQUE(company_id, code)`; `name_ar NOT NULL` | Status toggle only; never deleted |
| `employees` | HR master — **not** an Auth identity and **not** a party | `UNIQUE(company_id, employee_code)`; `status CHECK(active,suspended,terminated)`; department/job-title same-company FKs; **nullable sensitive columns (national ID, bank details) masked on every read**; nullable `user_id` (composite same-company FK + UNIQUE guard — D-003 one-company rule preserved; grants nothing); nullable `party_id` (O28 reimbursement interop only — never used by payroll logic) | Status change only; never deleted |
| `payroll_components` | Earning/allowance/deduction/statutory/employer-cost catalogue | `UNIQUE(company_id, code)`; `kind CHECK(...)`; `method CHECK(fixed,percent_of_base,quantity_rate,manual)`; `is_statutory`; direct `account_id` binding (validated at create and re-resolved at post); `is_active` | Deactivate only |
| `employee_contracts` | Effective-dated compensation | `UNIQUE(employee_id, effective_from)`; non-overlapping windows per employee (`EFFECTIVE_DATE_OVERLAP`); `base_amount numeric(18,2)` (R-07 intermediates pending) | Append-only; never mutated/deleted |
| `employee_component_assignments` | Per-employee component parameters | `UNIQUE(employee_id, component_id, effective_from)`; typed parameters; append-only | Append-only |
| `payroll_statutory_config` | Effective-dated statutory parameters | `UNIQUE(company_id, param_code, effective_from)`; inclusive-boundary discipline (features/13 C5); **empty until D-024** | Append-only; versions closed, never removed |
| `payroll_runs` | Monthly run header | `company_id NOT NULL` | **`status CHECK(draft,posted)` — `reversed` is DERIVED, never stored** (a posted linked reversal run points at the original via `reversal_of_id`; the original posted row is never updated — three-layer immutability, I3/I34); **active-run uniqueness (at most one active run per (company, period); active = posted without a posted linked reversal) enforced by a layered guard — per-(company, period) advisory lock + RPC `RUN_EXISTS` under the lock evaluating the derived reversal + optional deferred constraint trigger; mechanics RECOMMENDED_PENDING_VALIDATION** (a partial unique index cannot express derived reversal state); `period_id` same-company FK → `fiscal_periods`; `doc_no` server-issued at posting; `reversal_of_id` (derived reversal link) + `supersedes_run_id` self-FKs (replacement chain, fresh number); `idempotency_key` UNIQUE per company; frozen totals + `config_snapshot jsonb` | Posted rows immutable (no UPDATE at all — status included); drafts deletable with audit; settlement workflow flips audited |
| `payroll_run_lines` | Per-employee results | `UNIQUE(run_id, employee_id)`; frozen `gross/net/withholding/settled numeric(18,2)` posted facts | Immutable with the run |
| `payroll_run_components` | Per-component detail | frozen `qty/rate/amount` + `account_id` binding snapshot + component code snapshot | Immutable with the run |
| `employee_advances` | Salary advances (**assets** until validly settled) | `amount numeric(18,2) CHECK > 0`; own doc_type with server-issued number; `reversal_of_id`; `idempotency_key` UNIQUE per company; **open amount always derived** (amount − Σ active settlements) | Posted rows immutable; drafts deletable with audit |
| `payroll_settlements` | Append-only advance-settlement records | `UNIQUE(run_id, advance_id)`; `amount CHECK > 0 ≤` derived open (RPC-enforced); `status CHECK(active,reversed)` | Never deleted; status flips audit-logged |

### Follow-up extensions (owned by other features — additive, recorded not applied here)
`payment_documents` += nullable `employee_id` with an "exactly one of party/employee per
`doc_kind`" CHECK — **specified in `features/09` C2/C12/D (audit batch 2; PROPOSED)**: the
vehicle debits `PAYROLL_CLEARING` (employee dimension) and credits the container, never
`AP_CONTROL`; capacity = derived unpaid clearing, never negative (`PAYROLL_CLEARING_EXCEEDED`);
per-employee advisory-lock serialization; `journal_lines` += nullable `employee_id` dimension
(composite same-company FK, mirrors `party_id`) enabling per-employee clearing/payable
derivation (**still a follow-up**); `doc_numbers` consumes `PAYROLL_RUN`/`EMPLOYEE_ADVANCE` types (features/04/13);
`module_account_map` gains module `payroll` roles — `PAYROLL_CLEARING`, `EMPLOYEE_ADVANCES`,
`SALARY_EXPENSE`, statutory payable role **names** (`INCOME_TAX_WITHHOLDING_PAYABLE`,
`SOCIAL_INSURANCE_EMPLOYEE_PAYABLE`, `SOCIAL_INSURANCE_EMPLOYER_PAYABLE`) — **never seeded until
D-024**.

### Indexing requirements (payroll)
- `employees (company_id, employee_code)` unique; `(company_id, department_id)`; `(company_id,
  status)` partial for run selection; `payroll_runs (company_id, period_id)` **non-unique
  supporting index for the layered active-run guard (derived reversal — a partial unique index
  cannot express it)**; `payroll_run_lines (run_id)`; `payroll_run_components (line_id)`;
  `employee_advances (company_id, employee_id, doc_date)`; `payroll_settlements (advance_id)`
  partial active.

### Ownership, security and privacy requirements (payroll)
- **No direct client `SELECT` grants** on `employees`, payroll run/line/component tables,
  advances, settlements or statutory config — every read is a masking RPC that rederives
  membership (R-03), checks the specific `payroll.*` permission code, and redacts national
  ID/bank/salary fields without `payroll.payslip`/`payroll.setup`; unmasked reads and payslip
  generation are **audited** (`payroll.employee_viewed`, `payroll.payslip_generated`) — privacy
  design RECOMMENDED_PENDING_VALIDATION. Generic reports never expose per-employee figures
  without `payroll.view` (features/12 #13). `anon` denied; no UPDATE/DELETE on posted rows.
- **Employee-kind `payment_documents` rows (audit batch 2) are payroll-adjacent:** generic cash
  list/read RPCs mask the employee reference (no name, national ID or bank detail) unless the
  caller holds `payroll.view` (`features/09` §E/C12.5 — the single privacy definition stays
  `features/11` C13); posting writes the ordinary `payment.posted` audit event; no new grant on
  any payroll table is created by the vehicle.
- **Posting gate (safeguard):** `payroll_run_post` refuses to post unless complete
  effective-dated statutory configuration exists for the run's period
  (`STATUTORY_CONFIG_INCOMPLETE`) — until D-024 is answered, no run can post anywhere.
- **No stored balances** (D-017): advance open amounts, per-employee `PAYROLL_CLEARING`
  balances and run-open figures derive solely from posted rows and append-only settlement
  records. **Payroll liabilities never touch `AP_CONTROL`** (I12 untouched — the net-payment
  template debits `PAYROLL_CLEARING` only); posted runs are balanced, atomic, immutable and
  idempotently replayable (I34–I37 in `09_ACCOUNTING_INVARIANTS.md`).
