# Feature: المخزون والمستودعات / 08_inventory_and_warehouses
**Status: DRAFT** | **Version:** 0.3 | **Owner approval:** PENDING | **Last reviewed:** 2026-10-21
**Source:** V2 clean-slate design (no Hasad V1 reuse). Bound by `15_DECISION_LOG.md` (D-005, D-006, D-013, D-014, D-018, D-019, D-025, R-07) and the 2026-10-20 inventory planning report.
**Evidence labels:** `PROPOSED` unless marked `OWNER_APPROVED` (by decision ID), `RECOMMENDED_PENDING_VALIDATION`, or `REQUIRES_OWNER_DECISION`.
**Supersedes:** the legacy skeleton OPEN "FIFO/average cost? Negative stock?" — **resolved OWNER_APPROVED by D-014** (moving weighted average; negative inventory prohibited). Offline posting semantics resolved by **D-006** (entry allowed, pending until server posts in transaction order). **Not assumed approved:** FIFO, batch/lot tracking, serial numbers — out of scope for v1.

## A. Why this feature exists
Owns the stock ledger: warehouses, products, units of measure, the append-only movement record, moving weighted-average valuation (D-014 OWNER_APPROVED), stock counts/adjustments, and the receipt/issue contracts that sales and purchases consume. The **stock ledger is the authoritative historical record**; every quantity or value shown elsewhere is a rebuildable projection verified by replay. Inventory GL effects post through the shared accounting engine (`features/04`) with account-role mappings (`features/03`) in the **same atomic transaction** as the business document (approved shared requirement 6).

Exclusions: invoice/bill semantics (modules 06/07), pricing rules, landed-cost allocation (deferred — §L), FIFO/lot/serial tracking (not approved).

## B. Roles and user stories
- **`inventory.manage` holder** → warehouses, products, categories, UOMs, conversions.
- **`inventory.post` holder** → receipts, issues, returns, transfers (usually invoked inside sales/purchase posting).
- **`inventory.adjust` holder** → stock counts and adjustment posting (recommended owner/admin tier — feeds role catalogue; REQUIRES_OWNER_DECISION on final tier).
- **All members** → read stock levels, valuation reports, movement history.
- Forbidden: editing/deleting posted movements; client-computed authoritative costs; negative on-hand; new documents against deactivated products/warehouses.

## C. Business rules and state transitions
- C1 **Master data:** per-company warehouses and products (`UNIQUE(company_id, code)`; optional `barcode` `UNIQUE(company_id, barcode)` when present); flat category list; per-company UOMs with exactly one base unit (RPC-enforced). Deactivation-only lifecycle — deactivated products/warehouses keep history and block **new** documents. **Stocked vs service products (proposed — cross-module alignment with `features/06` D, audit batch 3):** `products.track_inventory boolean NOT NULL DEFAULT true`.
  - `true` (**stocked**): every document line referencing the product must carry a warehouse; the product participates fully in the movement ledger, moving-average valuation (C2/C3) and the no-negative-stock checks (C6).
  - `false` (**service / non-stock**): lines referencing it **never emit stock movements**, never require a warehouse, and are excluded from availability and negative-stock checks — while their GL recognition (revenue/expense/VAT) is completely unaffected. A service line attempting a stock movement or carrying a warehouse reference is a typed rejection (`WAREHOUSE_REQUIRED`) at posting.
  - The flag is editable only while the product has **no posted movements** (RECOMMENDED — after first movement the stocked/service class is frozen; PoC-validated) and is validated server-side at posting, never trusted from cache. `track_inventory=false` never weakens any valuation rule for stocked products; the no-negative-stock invariant (D-014) and server-authoritative movement valuation (C11) are untouched.
- C2 **Valuation pools (O12 — OWNER_APPROVED 2026-10-30):** **per-warehouse moving weighted average per product**. `stock_levels` tracks quantity and average cost for each `(company, product, warehouse)` pool. Receipt updates that warehouse's average from its existing quantity/value and the explicitly supplied receipt quantity/cost. Issue uses that warehouse's current average. A transfer issues at the source average and adds that transferred value to the destination pool's weighted average. No cost is invented or entered implicitly.
- C3 **Costing arithmetic (OWNER_APPROVED for Unit D implementation 2026-10-30; schema-aligned precision):** quantities and unit costs are `numeric(19,4)`; reject inputs with more than four fractional digits (do not round submitted quantities/costs). Compute weighted averages at four decimals using PostgreSQL `round(numeric, 4)` (HALF_UP for nonnegative inventory values). Store each movement's extended value at two decimals using `round(qty * unit_cost, 2)` (HALF_UP); the rounded movement value is not used to recompute average cost. Receipt into an empty/zero-quantity warehouse starts its pool at the explicitly supplied receipt unit cost. Transfer into an empty/zero-quantity destination starts at the source warehouse's current average. A zero-quantity balance carries no stock value; the next receipt recalculates from incoming value only. Receipt cost is required, may be zero only when explicitly supplied, and is never defaulted by the client.
- C4 **Rounding & reconciliation policy (corrected design — explicitly tested, not assumed):** the GL inventory amount of every movement **is the movement's rounded 2dp `value`**; consequently **Σ rounded movement values ≡ `INVENTORY_CONTROL` GL balance by construction**. Any residual between (unrounded qty × current average) and Σ stored values is **disclosed by a residual-report test**, never silently absorbed; the test must prove the residual stays within the documented bound (≤ half a cent per movement compounded — exact bound to be measured in the PoC, RECOMMENDED_PENDING_VALIDATION). **No claim is made that independently rounded movement values reproduce an unrounded valuation total.**
- C5 **Deterministic replay (corrected design):** movements carry a per-product monotonic `seq` assigned at posting under the product's lock; replay order = `seq`. Replaying all movements from zero must reproduce identical quantities, averages and stock-level values — the acceptance gate for the whole design.
- C6 **Negative stock prohibited (D-014 OWNER_APPROVED), enforced in layers:** application check inside the posting transaction; stock-row lock serializing concurrent issues; `CHECK (qty >= 0)` on `stock_levels`. Reversals and adjustments respect the prohibition too.
- C7 **Movement types are distinct (corrected design):** `purchase_receipt` (in at net purchase cost), `sales_issue` (out at current average), `sales_return` (in — recommended at **original issue cost** from the originating sale movement's snapshot, **O11 pending owner validation**), `purchase_return` (out at current average), `transfer_out`/`transfer_in` (paired, identical snapshot cost), `count_adjustment` (± at current average), `opening` (initial quantities at certified cost, O6-adjacent). Reversals are linked reversal documents (`inventory_reverse`), not negative edits of history.
- C8 **Transfers preserve quantity and total value (OWNER_APPROVED context, D-014 consistent):** paired movements carry the same `unit_cost`; total inventory value is unchanged; **no GL entry** under company-wide pools (RECOMMENDED under O12; per-warehouse pools would still require value-neutral transfer postings).
- C9 **Stock counts & adjustments:** count document per warehouse; `counted_qty >= 0`; treatment of a count that implies negative on-hand remains an open decision and is never clamped silently; adjustment = counted − system; posting emits adjustment movements + one balanced GL entry (`INVENTORY_CONTROL` ↔ `INVENTORY_ADJUSTMENT`); `inventory.adjust` permission + mandatory audit.
- C10 **Cost inputs are not silently equivalent (corrected design):** v1 inventory cost = **net purchase price excluding recoverable VAT** (VAT-input is a separate GL line). **Nonrecoverable VAT, freight and duties are NOT silently treated as inventory cost** — landed-cost allocation is explicitly deferred and remains an open scope item inherited from the purchases module (carried in §L). Sales prices never affect valuation.
- C11 **Atomicity & authority:** every business posting's GL **and** inventory effects occur in one server transaction that rechecks membership, permission and open fiscal period (04-I11); the server is authoritative for quantities and costs (OWNER_APPROVED rules 3–4 of this task); official numbers are assigned server-side only after successful posting (D-018 OWNER_APPROVED).
- C12 **Immutability & audit (D-019 OWNER_APPROVED):** posted movements are never updated/deleted (three layers: triggers, absent grants, RLS — pending PoC). Mandatory audit events: `warehouse.*`, `product.*`, `stock.posted` (per document), `stock.reversed`, `count.posted`, `adjustment.posted`.
- C13 **Offline (D-006 OWNER_APPROVED):** receipts/issues/transfers/counts may be entered offline as **pending** outbox records; the server validates and posts in transaction order; conflicts (insufficient stock at apply time) are **rejected and preserved locally** for correction and retry. **Pending movements never reserve or alter authoritative server stock** — offline availability is UX-only (see D-025, §L).

State chart: documents `draft → posted → (derived reversed)`; movements append-only; counts `open → posted`.

## D. Data model (PostgreSQL — proposal until approved)
| Table | Purpose | Tenant scope | Key constraints | Status |
|---|---|---|---|---|
| `warehouses` | Quantity locations | `company_id NOT NULL` | `UNIQUE(company_id, code)`; `is_active` | PROPOSED |
| `product_categories` | Flat classification | `company_id NOT NULL` | `UNIQUE(company_id, code)` | PROPOSED |
| `units_of_measure` | Base + secondary units | `company_id NOT NULL` | `UNIQUE(company_id, code)`; one base per company (RPC) | PROPOSED |
| `products` | Items | `company_id NOT NULL` | `UNIQUE(company_id, code)`; `barcode` nullable `UNIQUE(company_id, barcode)`; `name_ar NOT NULL`; `track_inventory boolean NOT NULL DEFAULT true` (stocked vs service — C1; frozen once movements exist, recommended); FKs category/base UOM (same company); `is_active` | PROPOSED |
| `product_uom_conversions` | UOM → base factors | `company_id NOT NULL` | `UNIQUE(product_id, uom_id)`; `factor numeric(19,6) > 0`; immutable once used by a posted movement (recommended) | PROPOSED |
| `stock_levels` | **Rebuildable cache** of (product, warehouse) quantity | `company_id NOT NULL` | PK (product, warehouse); `qty numeric(19,4) CHECK (>= 0)`; `last_unit_cost numeric(19,4)`; never authoritative | PROPOSED |
| `stock_movements` | **Authoritative append-only ledger** | `company_id NOT NULL` | `direction in/out`; `qty numeric(19,4) > 0`; `unit_cost numeric(19,4) >= 0` (snapshot); `value numeric(18,2)` (HALF_UP line rule); `movement_type` CHECK (8 types, C7); per-product `seq` (deterministic replay, C5); same-company composite FKs (product, warehouse, source document); optional `journal_line_id` link; no UPDATE/DELETE | PROPOSED |
| `stock_counts` / `stock_count_lines` | Physical counts | `company_id NOT NULL` | `status open/posted`; `counted_qty numeric(19,4) >= 0`; one posted count per warehouse/date (recommended) | PROPOSED |

Indexing requirements: `stock_movements (product_id, seq)` UNIQUE (replay order); `(company_id, source_document_type, source_document_id)` (document→movements); `(warehouse_id, posted_at)` (warehouse ledger views); `stock_levels (warehouse_id)`, `(product_id)`; `products (company_id, lower(name_ar))` search; partial barcode index. Deletion policy: masters deactivate-only; movements/counts posted rows immutable, never deleted.

## E. RLS / grants / RPCs
- **DEV application architecture (OWNER_APPROVED 2026-10-30):** Flutter uses the authenticated Supabase Data API against the exposed `hasad` schema for company-scoped reads and approved master-data writes. Preserve this working DEV integration; do not route it through `whoami`/`products_list` or move it to `hasad_api`.
- Inventory posting is a narrow server-side transaction function callable with the authenticated client. The client never receives `INSERT`, `UPDATE`, or `DELETE` access to `stock_levels`; the function owner must be locked, non-superuser, and `NOBYPASSRLS`, with forced RLS retained and live active-membership validation inside the transaction. The exact function owner/ACL/policy behavior and installability are **UNVERIFIED** until local disposable-database validation and read-only DEV catalog verification.
- Authenticated movement-history reads are company-scoped by RLS. Posted movements remain append-only; no client `INSERT`/`UPDATE`/`DELETE` grants.
- The server validates quantities and computes movement fields required by the deployed schema. It rejects quantities/costs with more than four decimal places and does not invent cost values. Receipt cost must be explicit. O12 is approved for per-warehouse moving weighted average; implementation and DEV deployment remain separately gated on security and hosted compatibility verification.

## F. Offline SQLite and synchronization
- Products, warehouses, UOMs and cached levels sync down for offline entry (UX only — never the availability authority).
- Offline receipts/issues/transfers/counts → pending outbox (D-006), posted in transaction order with server numbers (D-013/D-018).
- **Conflict example (two devices, last unit):** both pending issues arrive; the first posts; the second fails `STOCK_INSUFFICIENT` at apply time, is **rejected and preserved locally** (D-006/D-014) — never silently discarded, never pre-reserving stock.
- Typed rejections carry reason + current authoritative quantity so the user can correct offline data.

## G. Accounting impact (if any)
Account roles consumed (via `module_account_map`, `features/03`): `INVENTORY_CONTROL` (asset), `COGS` (expense), `INVENTORY_ADJUSTMENT` (gain/loss treatment = **O13**, not assumed).
| Event | Movements | GL (one atomic transaction with the business document) |
|---|---|---|
| Purchase receipt — **order-based** (`features/07` C2/C3; I25) | `purchase_receipt` in @ net cost | DR INVENTORY_CONTROL (rounded value) / CR **PURCHASE_CLEARING** (equal net amount). The supplier bill later debits `PURCHASE_CLEARING` **at receipt valuation**, debits recoverable `VAT_INPUT` (bill time, not receipt time) and credits `AP_CONTROL` at gross; price differences go to `PURCHASE_PRICE_VARIANCE` (O18). VAT never enters cost |
| Direct purchase — bill + receipt post atomically (`features/07` C3; I25) | `purchase_receipt` in @ net cost | DR INVENTORY_CONTROL (stock net) + DR VAT_INPUT (recoverable tax) / CR **AP_CONTROL** (gross) — one transaction, **no clearing leg** |
| Sales issue | `sales_issue` out @ current avg | DR COGS / CR INVENTORY_CONTROL |
| Sales return | `sales_return` in @ original issue cost (O11 rec.) | reverse COGS leg |
| Purchase return | `purchase_return` out @ current avg | reverse inventory vs AP (module 07) |
| Transfer | paired out/in @ same snapshot cost | **none** (value-neutral, C8) |
| Count adjustment | `count_adjustment` ± @ current avg | DR/CR INVENTORY_CONTROL ↔ INVENTORY_ADJUSTMENT |
| Reversal | linked reversal movements | linked swapped journal entry (D-019) |

Reconciliation (invariants I18–I21, `09`): Σ rounded movement values ≡ `INVENTORY_CONTROL` GL balance (by construction, C4); replay reproduces levels (C5); GL+inventory legs of one document post atomically or not at all. Recoverable VAT, nonrecoverable VAT, freight and duties are **distinct** concepts — only net price enters v1 cost (C10).

## H. UI and Arabic RTL
Arabic RTL screens: product list/search (code, barcode scan field, Arabic name), product form (UOM + conversions), warehouse list with derived quantities + freshness label, transfer form (from/to, per-line availability warning), stock count worksheet (system vs counted with variance highlighting), movement ledger view with type badges, valuation report. Offline/pending movements carry a pending badge and are excluded from authoritative availability (D-025 recommendation, pending owner). Domain-safe Arabic errors (`الكمية المتاحة لا تكفي`). Official numbers appear only after posting (D-018).

## I. API / RPC contract
| RPC | Input | Output | Auth | Audit |
|---|---|---|---|---|
| `warehouse_create/update/deactivate`, `product_create/update/deactivate`, `category_*`, `uom_*`, `conversion_set` | fields | ids | `inventory.manage` | warehouse.*/product.* |
| `inventory_receipt_post(doc, key)` | lines | movements + GL | `inventory.post` | stock.posted |
| `inventory_issue_post(doc, key)` | lines | movements + GL | `inventory.post` | stock.posted |
| `stock_transfer_post(doc, key)` | from/to + lines | paired movements | `inventory.post` | stock.posted |
| `stock_return_post` (sales/purchase variants) | lines | movements + GL | `inventory.post` | stock.posted |
| `stock_count_open/submit`, `count_adjustment_post(count_id, key)` | count | adjustment movements + GL | `inventory.adjust` | count.posted, adjustment.posted |
| `inventory_reverse(doc, reason)` | ref | reversal movements + GL | `inventory.post` (+adjust tier recommended) | stock.reversed |
| `stock_level(product?, warehouse?)`, `stock_ledger(product, range)`, `valuation_report(as_of)` | filters | derived rows | `reports.view` | — |

Typed errors: `STOCK_INSUFFICIENT`, `PRODUCT_INACTIVE`, `WAREHOUSE_INACTIVE`, `WAREHOUSE_REQUIRED` (service/non-stock line carrying a warehouse or attempting a stock movement — C1), `CONVERSION_LOCKED`, `COUNT_NOT_OPEN`, `PERIOD_CLOSED`, `MAPPING_MISSING`, `ALREADY_REVERSED`, `IDEMPOTENCY_MISMATCH`, `PERMISSION_DENIED`. All postings idempotency-keyed via the shared engine (04-C9).

## J. Tests and acceptance criteria
**Positive:** receipt→issue→receipt sequence reproduces exact averages including 0.333×3 and weight fractions (R-07 parity set, ≥100 generated cases); sales return lands at original issue cost; transfer leaves quantity per warehouse and total value unchanged with **zero** GL lines; count adjustment posts one balanced entry and lands on counted qty; **full replay from zero reproduces identical levels, averages and values** (C5 acceptance gate); offline receipt posts in order with server number; one sales invoice's AR/VAT/COGS/inventory legs are atomic.
**Negative:** issue exceeding stock (equal-to-available boundary passes, one-more fails); **concurrent double-issue of the last unit ⇒ exactly one succeeds**; transfer out exceeding stock; count implying negative on-hand ⇒ rejected (O12 policy); reversal driving stock negative; closed-period posting; deactivated product/warehouse on new documents; **service (`track_inventory=false`) line attempting a stock movement or carrying a warehouse reference ⇒ `WAREHOUSE_REQUIRED`; toggling `track_inventory` after posted movements exist ⇒ rejected (recommended freeze rule); a service line posting GL legs with zero stock movements (documented behavior, positive-proven)**; conversion change after use; UPDATE/DELETE on posted movements ⇒ three-layer rejection; unmapped INVENTORY/COGS role; cross-company references; `anon` everywhere.
**Reconciliation proofs:** Σ rounded movement values ≡ `INVENTORY_CONTROL` GL balance; residual report bounded and disclosed (C4 — no unrounded-total claim); stock never negative at **any** ledger prefix (property-style assertion); determinism replay (C5); atomicity of combined business+inventory posting.
Test only disposable datasets (`13_TEST_STRATEGY.md`); execution belongs to the isolated PoC.

## K. Rollout and migration
Depends on: identity/authorization (`features/01`/`02`, DRAFT pending security PoC), CoA + mappings (`features/03`, needs O1/O13), GL engine (`features/04`, needs O2/O3/O5/O6). Opening stock quantities: `opening` movements at certified costs via a dedicated RPC (owner-certified process, O6-adjacent). Additive migrations; no V1 data migration (D-002); no product/warehouse seed.

## L. Open questions and decisions
- [ ] **O11 (REQUIRES_OWNER_DECISION):** sales-return cost policy — **original issue cost (recommended)** vs current moving average.
- [x] **O12 (OWNER_APPROVED 2026-10-30):** use per-warehouse moving weighted average. Negative-count handling remains reject-for-investigation pending separate decision; O12's prior negative-count sub-item is not treated as approved by the costing-pool decision.
- [ ] **O13 (REQUIRES_OWNER_DECISION):** `INVENTORY_ADJUSTMENT` gain/loss account treatment (expense vs revenue contra; feeds the CoA template under O1).
- [ ] **D-025 (OPEN, owner):** availability display with pending offline documents — **server-posted stock only recommended**; pending items shown separately as "pending, not reserved".
- [ ] **Landed-cost allocation (carried OPEN from purchases):** nonrecoverable VAT, freight, duties are **not** v1 inventory cost inputs (C10); allocation rules need a future owner decision before any implementation.
- [ ] R-07 intermediate precision (19,4 / line HALF_UP) — RECOMMENDED_PENDING_VALIDATION pending its parity test; **not** owner-approved.
- [ ] Rounding residual bound (C4), `seq` assignment mechanics, row-lock vs advisory-lock under pooling, UOM-conversion immutability-after-use — RECOMMENDED_PENDING_VALIDATION (PoC).
- [ ] `inventory.adjust` permission tier in the role catalogue — REQUIRES_OWNER_DECISION (with `features/02`).

## M. Source evidence
| Claim | Evidence source | Observed on | Confidence |
|---|---|---|---|
| Moving weighted average; negative stock prohibited | `15_DECISION_LOG.md` D-014 | 2026-10-20 | OWNER_APPROVED |
| Offline pending → server order; conflicts rejected + preserved | `15_DECISION_LOG.md` D-006 | 2026-10-20 | OWNER_APPROVED |
| Server-issued numbers per company+type+FY | `15_DECISION_LOG.md` D-013, D-018 | 2026-10-20 | OWNER_APPROVED |
| Immutability + linked reversals | `15_DECISION_LOG.md` D-019 | 2026-10-20 | OWNER_APPROVED |
| ILS / 2dp HALF_UP / strict periods | `15_DECISION_LOG.md` D-005 | 2026-10-20 | OWNER_APPROVED |
| Precision 19,4 / line HALF_UP | `15_DECISION_LOG.md` R-07 | 2026-10-20 | RECOMMENDED_PENDING_VALIDATION |
| Receipt GL matrix (order-based = DR INV/CR PURCHASE_CLEARING; direct = DR INV + DR VAT_INPUT/CR AP_CONTROL) matches features/07 C2/C3 and I25 | 2026-10-21 audit corrections batch 1 — receipt contradiction fix | 2026-10-21 | PROPOSED (balance-proven by §G/§J) |
| `products.track_inventory` stocked-vs-service behavior (default `true`; service lines emit no movements, require no warehouse, GL unaffected; class frozen once movements exist) | 2026-10-21 audit corrections batch 3 — implementing the cross-module addition recorded in `features/06` D | 2026-10-21 | PROPOSED (freeze-after-movement rule RECOMMENDED_PENDING_VALIDATION; D-014 invariants untouched) |
| Availability display while pending | `15_DECISION_LOG.md` D-025 | 2026-10-20 | OPEN (owner) |
| Pooling, replay, rounding policy, return policies | 2026-10-20 inventory planning report + this spec | 2026-10-20 | PROPOSED / RECOMMENDED_PENDING_VALIDATION |

**Gate:** keep DRAFT until O11, O13, D-025 and remaining R-07 parity validation are resolved and the security PoC completes. O12's costing-pool choice is approved; hosted implementation remains unverified.
