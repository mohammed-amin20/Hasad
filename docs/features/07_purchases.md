# Feature: المشتريات / 07_purchases
**Status: DRAFT** | **Version:** 0.3 | **Owner approval:** PENDING | **Last reviewed:** 2026-10-21
**Source:** V2 clean-slate design (no Hasad V1 reuse). Bound by `15_DECISION_LOG.md` (D-005, D-006, D-013, D-016, D-017, D-018, D-019, D-023, R-07) and the 2026-10-20 sales & purchases planning report.
**Evidence labels:** `PROPOSED` unless marked `OWNER_APPROVED` (by decision ID), `RECOMMENDED_PENDING_VALIDATION`, or `REQUIRES_OWNER_DECISION`.
**Supersedes:** legacy skeleton OPEN "How is purchase cost allocated?" — **answered for v1:** inventory cost = net purchase price **excluding recoverable VAT**; **freight/duties/landed-cost allocation remain OPEN → O21**, non-recoverable VAT → **O20**. Offline posting semantics **resolved OWNER_APPROVED by D-006**; VAT mechanics **resolved OWNER_APPROVED by D-005** (rate/form → D-023).

## A. Why this feature exists
Owns the buy side: purchase quotations/orders, goods receipts (partial receiving), supplier bills (partial invoicing), purchase clearing, supplier credit/debit notes, purchase returns, input-VAT handling and atomic posting of inventory/expense/VAT/AP through the shared engine (`features/04`) and inventory ledger (`features/08`), with payments flowing only through `features/09`.

Exclusions: payment mechanics (`features/09`), landed-cost allocation (deferred, O21), tax-law determination (D-023), report layouts (module 12).

## B. Roles and user stories
- **`purchases.create` holder** → drafts quotations, orders, receipts, bills, notes (online or offline).
- **`purchases.post` holder** → posts receipts/bills/notes; server assigns official numbers (D-018 OWNER_APPROVED).
- **`purchases.reverse` holder** → linked reversals (D-019); never edits posted rows.
- **All members** → read purchase documents, receipt/bill capacities, clearing views (derived).
- Forbidden: client-issued numbers; editing posted rows; billing more than received; returning more than billed; writing input-VAT credits on debit-side documents incorrectly (I25/matrix).

## C. Business rules and state transitions
- C1 **Two document families:** *workflow* (purchase_quotation, purchase_order) never post — `draft → open → (cancelled | converted, derived)`. *Financial* (goods_receipt, purchase_bill, credit_note, debit_note) post — `draft → posted` + derived `reversed` (D-019). One table family (`purchase_documents` + lines) with `doc_kind` CHECK (6 kinds).
- C2 **Goods receipt (clearing design — O14 recommended):** posts stock **and** GL: `DR INVENTORY_CONTROL (net) / CR PURCHASE_CLEARING (net)` with `purchase_receipt` movements at the receipt's valuation (order price or direct price) — preserving invariant I18 (every movement has its GL leg). Receipts consume ordered qty; multiple partial receipts allowed.
- C3 **Supplier bill:** stock lines may consume posted receipts (`receipt_line_id`) — posting then debits `PURCHASE_CLEARING` at **receipt valuation**, debits recoverable **`VAT_INPUT` (debit side — input VAT is an asset)**, posts any **price difference** to `PURCHASE_PRICE_VARIANCE` (**O18, recommended default, accountant validation required**), and credits `AP_CONTROL` at gross. Service/expense lines debit their expense roles directly. **Direct purchase** (no order/receipt): one transaction posts bill + receipt movements together: `DR INVENTORY/expense + DR VAT_INPUT / CR AP_CONTROL` (corrected matrix — see §G).
- C4 **Partial receiving and partial invoicing (I25):** cumulative received ≤ ordered; cumulative billed ≤ received **per line** when receipts exist (derived from posted children — **no stored authoritative counters**); enforced under `FOR UPDATE` on the order/receipt. At full match `PURCHASE_CLEARING` derived balance → 0 for those receipts.
- C5 **Supplier notes:** **credit note** (return or price reduction) *reduces* AP: `DR AP_CONTROL (gross) / CR inventory-or-expense (net) / CR VAT_INPUT (tax reversal — **a credit to input VAT**) / ± PURCHASE_PRICE_VARIANCE`. **Debit note** (additional charge) *increases* AP: mirror image (`DR inventory-or-expense + DR VAT_INPUT / CR AP_CONTROL`). Notes reference `original_document_id` + `original_line_id`; cumulative returned/billed-adjment capacity ≤ original line qty (I23). Purchase returns also emit `purchase_return` movements at the **current moving average** (`features/08` C7).
- C6 **Settlement:** bills never contain cash lines. Supplier payments are `payment_documents` from `features/09` with allocations (direction: payment-side money against AP-credit documents) — cash purchase = bill entry + linked payment entry + 100% allocation, **one atomic transaction** (I24 symmetric with sales).
- C7 **VAT treatment (D-005 mechanics; D-023 rate OPEN):** recoverable input VAT is a **debit** accumulating on `VAT_INPUT`; **non-recoverable VAT is not silently an inventory cost** — recommended default: debit a dedicated expense role `NONRECOVERABLE_VAT` (**O20, accountant/legal validation required**); VAT-inclusive purchase documents use the same group-by-rate, group-rounding pipeline as sales (§4 examples are symmetric). Input VAT **never** enters inventory cost or expense line nets (consistent with `features/08` C10). **Effective-dated rate resolution (audit batch 3 — authoritative definition: `features/13` C5):** rates resolve server-side from the company's effective-dated catalogue **using the document date** (`RATE_NOT_FOUND_FOR_DATE` when none; overlap rejected at configuration, `EFFECTIVE_DATE_OVERLAP`); every posted line keeps its resolved `tax_rate` **snapshot** forever — later catalogue changes never rewrite bill or note history; client caches are UX-only; no statutory rate is assumed (D-023 OPEN).
- C8 **Cost inputs (O21 OPEN):** v1 inventory cost = net price excluding recoverable VAT; **freight, duties and landed-cost allocation are explicitly not treated as inventory cost** and are deferred pending an owner/accountant decision. No silent equivalence between recoverable VAT, non-recoverable VAT, freight and duties.
- C9 **Server authority & atomicity:** totals/taxes/capacities/costs computed server-side; posting rechecks membership, permission, open period (04-I11); idempotency keys; stock + GL + number in one transaction (I26); official numbers server-issued (D-013/D-018).
- C10 **Audit events (mandatory):** `purchase.quotation_created`, `purchase.order_opened`, `purchase.order_cancelled`, `purchase.receipt_posted`, `purchase.bill_posted`, `purchase.note_posted`, `purchase.reversed`, `purchase.draft_deleted`, `number.issued`.
- C11 **Offline (D-006 OWNER_APPROVED):** all purchase documents enter the outbox as pending; server applies in transaction order; `DEPENDENCY_PENDING` when a receipt/bill precedes its order (preserved + retried); `STOCK_INSUFFICIENT` impossible on receipts but **capacity overruns** (`ORDER_OVER_RECEIVED`, `RECEIPT_EXCEEDS_BILLED`) are typed rejections preserved locally; pending receipts **never increase authoritative stock** (D-025 OPEN).

State chart: quotation/order `draft → open → cancelled|converted(derived)`; financial docs `draft → posted → (derived reversed)`; receipts open→consumed (derived via bills).

## D. Data model (PostgreSQL — proposal until approved)
| Table | Purpose | Tenant scope | Key constraints | Status |
|---|---|---|---|---|
| `purchase_documents` | Quotations, orders, receipts, bills, notes | `company_id NOT NULL` | `doc_kind` CHECK (6); `party_id` same-company FK; dual state CHECK; `vat_mode`; `doc_no` UNIQUE per (company, doc_type, fiscal_year) server-issued (on posting for financial kinds; on creation for quote/order — O16 symmetrical); `original_document_id` (notes); `supplier_ref` with `UNIQUE(company_id, party_id, supplier_ref)` when present (duplicate-bill guard, recommended); `idempotency_key` UNIQUE per company; header `net/tax/gross` immutable facts | PROPOSED |
| `purchase_document_lines` | Document lines | `company_id NOT NULL` | `line_no` UNIQUE per doc; `product_id` nullable; `warehouse_id` for stocked lines; `qty numeric(19,4) > 0`; `unit_price numeric(19,4) >= 0`; discount fields; `tax_rate` snapshot; derived `net/tax/gross`; `order_line_id`, `receipt_line_id`, `original_line_id` composite same-company FKs; capacities derived, never stored | PROPOSED |

Indexes: `(company_id, doc_kind, doc_date)`; `(party_id, doc_date)`; `(company_id, doc_no)` unique; `(receipt_line_id)`; `(original_document_id)`; `(company_id, idempotency_key)` unique. Deletion policy: posted rows immutable, never deleted; workflow drafts deletable with audit.

## E. RLS / grants / RPCs
- Private `hasad` schema; RPCs in `hasad_api` INVOKER; privilege model **DRAFT pending the isolated security PoC** (`07`).
- Grants: `SELECT` for `authenticated`; draft writes via RPCs with `purchases.create`; no `UPDATE/DELETE` on posted rows (three layers); receipts/bills/notes only through posting RPCs with `purchases.post`.
- Server rederives company from membership (R-03); client party/product/tax/price values are inputs, never trusted.

## F. Offline SQLite and synchronization
- Product/party/tax caches support offline drafting; cached quantities are UX only.
- Outbox dependency order: order → receipts → bills; typed `DEPENDENCY_PENDING` preserved and retried; capacity rejections (`ORDER_OVER_RECEIVED`, `RECEIPT_EXCEEDS_BILLED`) preserved locally with current authoritative quantities for correction (D-006); official numbers only after server posting (D-018); local temporary refs never printed officially.

## G. Accounting impact (if any)
Roles consumed: `AP_CONTROL`, `VAT_INPUT`, `PURCHASE_CLEARING`, `PURCHASE_PRICE_VARIANCE` (O18), `INVENTORY_CONTROL`, `COGS` (indirect, sales side), expense roles, `NONRECOVERABLE_VAT` (O20), `CASH`/`BANK` via linked payments. **Corrected and balance-checked matrix (every row ΣDR = ΣCR):**

| Document | Journal lines | Stock movements | Subledger |
|---|---|---|---|
| Goods receipt (order-based) | DR `INVENTORY_CONTROL` (net) / CR `PURCHASE_CLEARING` (net) | `purchase_receipt` in @ receipt valuation | — |
| Purchase bill — against receipts | DR `PURCHASE_CLEARING` (receipt-valued net) + DR `PURCHASE_PRICE_VARIANCE` (± bill−receipt diff) + DR `VAT_INPUT` (recoverable tax, **debit**) / CR `AP_CONTROL` (gross) | none (already received) | AP ↑ |
| Purchase bill — direct (no order) | DR `INVENTORY_CONTROL` (stock net) + DR expense roles (service net) + DR `VAT_INPUT` (tax) / CR `AP_CONTROL` (gross) | `purchase_receipt` in @ net (same tx) | AP ↑ |
| Cash purchase | bill entry **plus, same transaction,** payment entry: DR `AP_CONTROL` (gross) / CR container + 100% allocation row | as bill | AP ↑ then settled once |
| Supplier credit note (return / price cut) | DR `AP_CONTROL` (gross) / CR inventory-or-expense (net @ current average) + CR `VAT_INPUT` (**input-VAT reversal = credit**) ± `PURCHASE_PRICE_VARIANCE` | `purchase_return` out @ current avg | AP ↓ |
| Supplier debit note (additional charge) | DR inventory-or-expense (net) + DR `VAT_INPUT` (tax) / CR `AP_CONTROL` (gross) | none | AP ↑ |
| Reversal (D-019) | linked swapped entry | linked reversal movements | derived |

Balance proofs: bill gross = receipt/expense net ± variance + VAT; receipt row is self-balanced (equal nets); credit note mirrors the bill with input VAT on the **credit** side. **Correction applied:** input VAT is **DR** on bills/debit notes and **CR** on credit notes — never the reverse. Recoverable VAT always sits on `VAT_INPUT` (debit-normal); it **never** enters inventory cost or expense nets (C7/C8). Actual statutory rates/forms: **OPEN D-023**.

## H. UI and Arabic RTL
Arabic RTL screens: purchase order editor with received/billed progress bars (مستلم/مفوتر), receipt form (per-line remaining qty), bill form with receipt picker + price-difference highlight, inclusive/exclusive toggle, per-rate tax group summary, credit/debit note forms with original link and remaining capacity, clearing balance view (حساب التسوية), posting confirmation with post-posting number display, offline pending badges. Domain-safe Arabic errors (`الكمية المفوترة تتجاوز المستلم`). Tenant settings govern number/date formats.

## I. API / RPC contract
| RPC | Input | Output | Auth | Audit |
|---|---|---|---|---|
| `purchase_draft_create/update/delete` | payload | id | `purchases.create` | purchase.draft_deleted |
| `purchase_order_open/cancel(id)` | order | status | `purchases.create`/`purchases.post` | purchase.order_opened/cancelled |
| `purchase_receipt_post(order_ref, lines, key)` | receipt lines | posted receipt + movements + GL | `purchases.post` | purchase.receipt_posted, number.issued |
| `purchase_bill_post(doc, key)` | bill (receipt refs or direct) | posted bill + GL (+movements if direct) | `purchases.post` | purchase.bill_posted, number.issued |
| `purchase_note_post(note, key)` | credit/debit note | posted note (+movements if return) | `purchases.post` | purchase.note_posted |
| `purchase_reverse(ref, reason)` | ref | reversal | `purchases.reverse` | purchase.reversed |
| `document_list/get`, `open_orders`, `document_open_state(ref)`, `clearing_state(as_of)` | filters | derived rows | member / `reports.view` | — |

Typed errors: `PERIOD_CLOSED`, `ORDER_OVER_RECEIVED`, `RECEIPT_EXCEEDS_BILLED`, `RETURN_EXCEEDS`, `ORIGINAL_NOT_POSTED`, `DEPENDENCY_PENDING`, `WAREHOUSE_INACTIVE`, `PRODUCT_INACTIVE`, `VAT_NOT_CONFIGURED`, `RATE_NOT_FOUND_FOR_DATE` (effective-dated catalogue — `features/13` C5), `ALREADY_REVERSED`, `IDEMPOTENCY_MISMATCH`, `MAPPING_MISSING`, `PERMISSION_DENIED`. No RPC accepts a client-issued number (D-018).

## J. Tests and acceptance criteria
**Positive:** receipt posts `DR INV / CR CLEARING` and moves stock; bill against receipts debits clearing at receipt valuation, **debits** `VAT_INPUT`, credits AP at gross, variance line posted when prices differ (O18 default); direct purchase posts bill + receipt atomically; partial receipt ×2 + partial bill ×2 lands clearing → 0 at full match; VAT-inclusive purchase group split conserves gross exactly (mirror of sales Example B); supplier credit note credits `VAT_INPUT` and reduces AP; supplier debit note debits `VAT_INPUT` and increases AP; cash purchase = bill + payment + allocation in one transaction; purchase return emits movement @ current average with variance handling (O19 default); R-07 parity set.
**Negative:** billed > received ⇒ `RECEIPT_EXCEEDS_BILLED`; received > ordered ⇒ `ORDER_OVER_RECEIVED`; over-return ⇒ `RETURN_EXCEEDS`; bill referencing draft/cancelled receipt ⇒ `DEPENDENCY_PENDING`/typed rejection; input VAT posted as a credit on a bill or debit on a credit note ⇒ matrix/consistency test failure; recoverable VAT inside inventory cost ⇒ reconciliation failure (I22/I25); **bill/note dated outside every effective rate window ⇒ `RATE_NOT_FOUND_FOR_DATE`; a later catalogue change never rewrites a posted line's `tax_rate` snapshot (effective-dating proof)**; UPDATE/DELETE on posted rows ⇒ three-layer rejection; closed period; unmapped `AP_CONTROL`/`VAT_INPUT`/`PURCHASE_CLEARING` role ⇒ `MAPPING_MISSING`; cross-company references; reused idempotency key with different payload; `anon`.
**Concurrency:** two bills racing one receipt's capacity ⇒ Σ billed ≤ received always (row lock); two partial receipts racing order capacity; bill racing its reversal; parallel numbering ⇒ unique numbers; delayed-ack idempotent replay.
**Reconciliation:** clearing derived balance ≡ received-not-billed value and → 0 at full match (I25); AP movement per document ≡ gross; Σ receipt movement values ≡ inventory-GL leg (I18); trial balance Σ = 0 after a month with orders, receipts, bills, notes, payments.
Test only disposable datasets (`13_TEST_STRATEGY.md`).

## K. Rollout and migration
Depends on: identity/authorization (`features/01`/`02`, DRAFT pending PoC), CoA + mappings (`features/03`, needs O1 — `AP_CONTROL`/`VAT_INPUT`/`PURCHASE_CLEARING`/variance roles must be mapped), GL engine (`features/04`), parties (`features/05`), inventory (`features/08`, needs O11/O12), cash (`features/09`, needs O7/O15). Additive migrations; **no VAT-rate seed until D-023**; no landed-cost tables until O21; no V1 data migration (D-002).

## L. Open questions and decisions
- [ ] **D-023 (OPEN, owner):** actual VAT rates, deductibility rules, legal purchase-tax-invoice form — blocks finalization.
- [ ] **O14 (REQUIRES_OWNER_DECISION):** clearing-account receipt model (**recommended**) vs bill-only receipts (interacts with O5 accrual basis).
- [ ] **O15 (REQUIRES_OWNER_DECISION):** cash-bill settlement via linked payment document (**recommended**) — shared with `features/06`/`09`.
- [ ] **O16 (REQUIRES_OWNER_DECISION):** numbering for quotations/orders at creation (**recommended**) — shared with `features/06`.
- [ ] **O18 (REQUIRES_OWNER_DECISION — accountant validation):** invoice price vs goods-receipt valuation differences → `PURCHASE_PRICE_VARIANCE` at bill posting (**recommended default**) vs retroactive inventory-cost adjustment.
- [ ] **O19 (REQUIRES_OWNER_DECISION — accountant validation):** purchase return valued at **current moving average** (`features/08` rule) while AP is credited at document price → difference routed to `PURCHASE_PRICE_VARIANCE` (**recommended default**) vs other treatment.
- [ ] **O20 (REQUIRES_OWNER_DECISION — accountant/legal):** non-recoverable VAT posting — dedicated expense role (**recommended**) vs alternative treatment (D-023-adjacent).
- [ ] **O21 (REQUIRES_OWNER_DECISION — accountant/legal):** freight, duties and landed-cost allocation — **deferred; explicitly not inventory cost in v1**.
- [ ] **O22 (REQUIRES_OWNER_DECISION):** credit/debit notes against **previously settled bills** — recommended default: notes follow the normal allocation flow producing an unapplied credit or refund request (`features/09`); confirmation required.
- [ ] Variance threshold/rounding; capacity-lock behavior under pooling; receipt-valuation snapshot mechanics — RECOMMENDED_PENDING_VALIDATION (PoC).

## M. Source evidence
| Claim | Evidence source | Observed on | Confidence |
|---|---|---|---|
| VAT mechanics; ILS 2dp HALF_UP; strict periods | `15_DECISION_LOG.md` D-005 | 2026-10-20 | OWNER_APPROVED (rate/form OPEN → D-023) |
| Offline pending → server order; conflicts rejected + preserved | `15_DECISION_LOG.md` D-006 | 2026-10-20 | OWNER_APPROVED |
| Server-issued numbering per company+type+FY | `15_DECISION_LOG.md` D-013, D-018 | 2026-10-20 | OWNER_APPROVED |
| Immutability + linked reversals / credit-debit notes | `15_DECISION_LOG.md` D-019 | 2026-10-20 | OWNER_APPROVED |
| Unified party; derived AP | `15_DECISION_LOG.md` D-016, D-017 | 2026-10-20 | OWNER_APPROVED |
| Moving average; no negative stock; net-of-recoverable-VAT cost | `15_DECISION_LOG.md` D-014 + `features/08` C10 | 2026-10-20 | OWNER_APPROVED / PROPOSED |
| Corrected input-VAT directions and clearing matrix | 2026-10-20 planning report **corrected at review** (task 3 checks) | 2026-10-20 | PROPOSED (balance-proven by test J) |
| Effective-dated VAT resolution referenced to `features/13` C5 (server-side by document date; line `tax_rate` snapshots preserved; `RATE_NOT_FOUND_FOR_DATE`); D-023 stays OPEN | 2026-10-21 audit corrections batch 3 — Task 1 alignment | 2026-10-21 | PROPOSED (no statutory rate assumed) |

**Gate:** keep DRAFT until D-023, O14–O22 (shared with 06/09) are decided and the security PoC validates the RPC/RLS model.
