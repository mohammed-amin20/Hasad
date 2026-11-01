# Feature: المبيعات والفواتير / 06_sales_and_invoicing
**Status: DRAFT** | **Version:** 0.3 | **Owner approval:** PENDING | **Last reviewed:** 2026-10-21
**Source:** V2 clean-slate design (no Hasad V1 reuse). Bound by `15_DECISION_LOG.md` (D-005, D-006, D-013, D-016, D-017, D-018, D-019, D-023, R-07) and the 2026-10-20 sales & purchases planning report.
**Evidence labels:** `PROPOSED` unless marked `OWNER_APPROVED` (by decision ID), `RECOMMENDED_PENDING_VALIDATION`, or `REQUIRES_OWNER_DECISION`.
**Supersedes:** legacy skeleton OPEN "Is offline invoice posting permitted or draft-only?" — **resolved OWNER_APPROVED by D-006** (offline entry allowed, pending until server posts in transaction order). VAT mechanics (optional/configurable, inclusive/exclusive, group-by-rate rounding) **resolved OWNER_APPROVED by D-005**; the actual rate and legal tax-invoice form remain OPEN → **D-023**.

## A. Why this feature exists
Owns the sell side: quotations, sales orders, sales invoices, credit/debit notes, VAT calculation under the approved D-005 mechanics, discounts, cash/credit settlement, partial fulfillment, and the atomic posting contract that produces AR, revenue, VAT_OUTPUT, COGS and stock effects through the shared engine (`features/04`) and inventory ledger (`features/08`).

Exclusions: payments mechanics and allocations (`features/09`), party records (`features/05`), costing policy internals (`features/08`), report layouts (module 12). **Not assumed approved:** standalone goods-issue/goods-in-transit (O17), landed-cost allocation (O21).

## B. Roles and user stories
- **`sales.create` holder** → drafts quotations, orders, invoices, notes (online or offline).
- **`sales.post` holder** → posts invoices/notes; server assigns official numbers (D-018 OWNER_APPROVED).
- **`sales.reverse` holder** → linked reversals of posted documents (D-019); never edits/deletes posted rows.
- **All members** → read documents, fulfillment states, open-amount views (derived).
- Forbidden: client-issued numbers; editing posted rows; over-returning an invoice; posting across companies; cash lines written directly on invoice entries (I24).

## C. Business rules and state transitions
- C1 **Two document families:** *workflow* documents (quotation, sales_order) are **never financially posted** — states `draft → open → (cancelled | converted, derived)`, mutable while draft, cancellable while no posted children exist. *Financial* documents (sales_invoice, credit_note, debit_note) are `draft → posted` with **derived `reversed`** (D-019 OWNER_APPROVED). Quotations/orders produce **no GL lines and no stock movements** (RECOMMENDED, O16 covers numbering).
- C2 **One table family per module:** `sales_documents` + `sales_document_lines` with `doc_kind` CHECK (C1 families); posted financial rows immutable via three layers (pending PoC).
- C3 **VAT mechanics (OWNER_APPROVED D-005):** VAT optional and configurable per company; each document chooses `vat_mode ∈ {inclusive, exclusive}`; taxable amounts are **grouped by tax rate** and the **group tax total is rounded once** (HALF_UP, 2dp); final financial amounts `numeric(18,2)`. **Illustrative rates in this document are examples only — statutory rates remain OPEN (D-023).** **Effective-dated rate resolution (authoritative definition: `features/13` C5 — audit batch 3 alignment):** the server resolves each line's applicable rate from the company's effective-dated `tax_rates` catalogue **using the document date**, entirely server-side; client caches are UX-only; `RATE_NOT_FOUND_FOR_DATE` when no version covers the date; overlapping windows are impossible (`EFFECTIVE_DATE_OVERLAP` at configuration time, `features/13` C5). Every posted line preserves its resolved `tax_rate` **snapshot** forever (D-table) — later catalogue changes, closures or VAT-toggle changes never rewrite history. Optional VAT, invoice-level inclusive/exclusive, by-rate grouping and group-total HALF_UP rounding are **unchanged** by the effective dating; no statutory rate or mandatory form is assumed (D-023 OPEN).
- C4 **Calculation pipeline (RECOMMENDED_PENDING_VALIDATION — exact-decimal, R-07 parity-gated):**
  1. Line net (exclusive) = `round2(qty × unit_price)` with line discount applied first (`qty × price − discount`, rounded once).
  2. Group by tax rate: exclusive → `group_tax = round2(group_net × rate)`; inclusive → `group_net = round2(group_gross ÷ (1 + rate))`, `group_tax = group_gross − group_net` (gross conservation by construction — no residual bucket).
  3. Document totals = Σ group nets + Σ group taxes (+ zero-rate group). Invoice-level discount allocated **pro-rata to line nets, HALF_UP, largest-remainder fix on the largest line** (RECOMMENDED_PENDING_VALIDATION) **before** grouping.
  4. Header stores `net/tax/gross` as immutable posted facts; posting asserts `header = Σ lines = GL legs` (I22).
- C5 **Intermediates are not forced to 2dp:** quantities/unit prices `numeric(19,4)`, HALF_UP to 2dp only at line/document financial amounts — **R-07, RECOMMENDED_PENDING_VALIDATION, not owner-approved.**
- C6 **Cash vs credit settlement (O15, recommended default):** `settlement ∈ {credit, cash}`. A cash sale posts (a) the normal invoice entry and (b) a linked `payment_document` (receipt) with a 100% `payment_allocations` row — **both in one atomic transaction, two linked journal entries**. Invoice entries **never** contain cash-account lines (I24) — structurally prevents double-counted payments.
- C7 **Partial fulfillment (I23):** invoice lines may reference order lines (`order_line_id`); cumulative **invoiced qty per order line ≤ ordered qty**, derived from posted children — **no stored authoritative counters**. Ship-with-invoice is the v1 default: the invoice posts the stock issue in the same transaction. Orders do **not** reserve stock (recommended, O16).
- C8 **Returns and capacity:** credit notes (return or price reduction) and debit notes (additional charge) reference `original_document_id` + `original_line_id`. Cumulative returned qty per original line ≤ original line qty, enforced under `FOR UPDATE` on the original document — **over-returns and double returns are impossible** (I23). A reversed note restores capacity (append-only history). Debit notes adjust amounts, not quantities.
- C9 **Corrected posting matrix — every entry balances (see §G):** sales invoice posts `DR AR_CONTROL (gross) / CR SALES_REVENUE (net) / CR VAT_OUTPUT (group taxes)` plus, for stocked lines, `DR COGS / CR INVENTORY_CONTROL` — all in one journal entry, one transaction, together with movement writes and number issuance (I26).
- C10 **Sales return costing policy:** credit notes reverse revenue/VAT/AR **and** post the stock return + COGS reversal using an **explicitly documented costing policy** — recommended default **original issue cost (O11, pending owner validation — NOT approved)**; the alternative (current moving average) is documented, not silently chosen.
- C11 **Server authority:** totals, taxes, capacities, numbers and costs are computed server-side; client values are inputs only; posting atomically rechecks membership, permission and open period (04-I11); idempotency key required (D-006 context; mechanism pending PoC).
- C12 **Audit events (mandatory):** `sale.quotation_created`, `sale.order_opened`, `sale.order_cancelled`, `sale.invoice_posted`, `sale.note_posted`, `sale.reversed`, `sale.draft_deleted`, `number.issued`.
- C13 **Offline (D-006 OWNER_APPROVED):** all sales documents may be entered offline as pending outbox records; the server validates and posts **in transaction order** with server numbers (D-013/D-018); **typed `DEPENDENCY_PENDING`** when an invoice arrives before its order is accepted (preserved + retried, never reordered/discarded); `STOCK_INSUFFICIENT` at apply time ⇒ rejected and preserved locally; pending documents **never reserve stock** (D-025 OPEN, server-posted-only display recommended).

State chart: quotation/order `draft → open → cancelled|converted(derived)`; financial docs `draft → posted → (derived reversed)`.

## D. Data model (PostgreSQL — proposal until approved)
| Table | Purpose | Tenant scope | Key constraints | Status |
|---|---|---|---|---|
| `sales_documents` | Quotations, orders, invoices, notes | `company_id NOT NULL` | `doc_kind` CHECK (5); `party_id` same-company FK (required); `doc_date`; dual state CHECK (workflow vs financial); `vat_mode` CHECK (D-005); `doc_no` UNIQUE per (company, doc_type, fiscal_year) — server-issued **on posting** (financial) / **on creation** (quote & order, O16 recommended); `original_document_id` self-FK (notes); `idempotency_key` UNIQUE per company; header `net/tax/gross numeric(18,2)` immutable posted facts | PROPOSED |
| `sales_document_lines` | Document lines | `company_id NOT NULL` | `line_no` UNIQUE per doc; `product_id` nullable (service lines); `warehouse_id` required when `track_inventory`; `qty numeric(19,4) > 0`; `unit_price numeric(19,4) >= 0`; line discount fields; `tax_rate numeric(6,3)` **snapshot**; derived `net/tax/gross`; `order_line_id` / `original_line_id` composite same-company FKs; return capacity **derived**, never stored | PROPOSED |
| `tax_rates` | Per-company rate catalogue — **effective-dated versions (authoritative definition: `features/13` C5/D; the earlier flat `UNIQUE(company_id, code)` statement is superseded — audit batch 3)** | `company_id NOT NULL` | `UNIQUE(company_id, code, valid_from)`; `valid_from NOT NULL` / `valid_to NULL` (inclusive boundaries; successor `valid_from` = predecessor `valid_to + 1 day` — disjoint by construction, server rejects overlap `EFFECTIVE_DATE_OVERLAP`); `rate numeric(6,3) CHECK (rate >= 0)`; `is_active` — statutory values blocked by **D-023**; lines snapshot their resolved rate so history never recomputes | PROPOSED |

Cross-module proposal: `products.track_inventory` boolean (default true) so service lines skip stock issues — **now specified in `features/08` C1/D (audit batch 3)**: service lines emit no movements, require no warehouse (`WAREHOUSE_REQUIRED` typed rejection otherwise) and are GL-unaffected.
Indexes: `(company_id, doc_kind, doc_date)`; `(party_id, doc_date)`; `(company_id, doc_no)` unique; `(original_document_id)`; `(order_line_id)`; `(company_id, idempotency_key)` unique.
Deletion policy: posted financial rows never deleted/updated; workflow drafts deletable with audit; cancellation only with no posted children.

## E. RLS / grants / RPCs
- Private `hasad` schema; RPCs in `hasad_api` INVOKER; privilege model **DRAFT pending the isolated security PoC** (`07`).
- Grants: `SELECT` for `authenticated`; `INSERT/UPDATE` on drafts via RPCs with `sales.create`; no `UPDATE/DELETE` on posted rows (three layers); notes/credits only via posting RPCs with `sales.post`.
- Every RPC rederives company from verified membership (R-03); client-supplied party/product/warehouse/tax values are consistency inputs, never trusted.

## F. Offline SQLite and synchronization
- Party/product/tax-rate/stock caches support offline drafting (UX only; availability is server-posted only — D-025 recommendation).
- Outbox: durable UUID + idempotency key; upload in dependency order (order → invoice → note); server applies in transaction order (D-006); typed rejections preserved locally for correction and retry; official numbers appear only after server posting (D-018); local temporary references are never printed as official numbers.

## G. Accounting impact (if any)
Roles consumed (`features/03`): `AR_CONTROL`, `SALES_REVENUE`, `VAT_OUTPUT`, `COGS`, `INVENTORY_CONTROL`, plus `CASH`/`BANK` indirectly via the linked payment (features/09). **Corrected and balance-checked matrix (every row ΣDR = ΣCR):**

| Document | Journal lines | Stock movements | Subledger |
|---|---|---|---|
| Sales invoice (credit) | DR `AR_CONTROL` gross / CR `SALES_REVENUE` net / CR `VAT_OUTPUT` tax | `sales_issue` out @ avg (stocked lines) | AR ↑ |
| — stocked lines, same entry | + DR `COGS` / CR `INVENTORY_CONTROL` (movement values) | paired in entry | — |
| Cash sale | invoice entry **plus, same transaction,** payment entry: DR container / CR `AR_CONTROL` (gross) + 100% allocation row | same | AR ↑ then settled once |
| Sales credit note (return / price cut) | DR `SALES_REVENUE` net / DR `VAT_OUTPUT` tax / CR `AR_CONTROL` gross **+** DR `INVENTORY_CONTROL` / CR `COGS` (return costing policy — O11) | `sales_return` in @ documented policy | AR ↓ |
| Sales debit note (additional charge) | DR `AR_CONTROL` / CR `SALES_REVENUE` (+ CR `VAT_OUTPUT`) | none | AR ↑ |
| Reversal (D-019) | linked entry with swapped amounts | linked reversal movements | derived |

Balance proofs: invoice — `gross = net + Σ group taxes`; cash pair — payment gross offsets the invoice's AR leg exactly once (I24); credit note — mirror of the invoice plus the COGS/inventory pair (`movement value = COGS amount`, I18). VAT shown only via `VAT_OUTPUT` (output); **input VAT does not exist on the sales side.** Actual rate/statutory tax-invoice form: **OPEN D-023** — no statutory claim is made here.

## H. UI and Arabic RTL
Arabic RTL screens: quotation/order list + editor (fulfillment badges مكتمل/جزئي), invoice form with **inclusive/exclusive toggle**, per-rate tax group summary (ملخص الضريبة حسب النسبة), discount fields, party picker, warehouse picker per stocked line, credit/debit note forms with original-document link and remaining-return indicator, posting confirmation (number shown only after posting, D-018), pending/offline badges, print preview in Arabic. Domain-safe Arabic errors (`تجاوز الكمية المرتجعة من الفاتورة`). Number/date formats from tenant settings.

## I. API / RPC contract
| RPC | Input | Output | Auth | Audit |
|---|---|---|---|---|
| `sale_draft_create/update/delete` | document payload | id | `sales.create` | sale.draft_deleted |
| `sale_post(doc, idempotency_key, settlement)` | draft + key | posted doc + number (+payment ref if cash) | `sales.post` | sale.invoice_posted, number.issued |
| `sale_order_open` / `sale_order_cancel(id)` | order | status | `sales.create`/`sales.post` | sale.order_opened/cancelled |
| `credit_note_post(note, key)` / `debit_note_post(note, key)` | note vs original | posted note | `sales.post` | sale.note_posted |
| `sale_reverse(ref, reason)` | ref | reversal | `sales.reverse` | sale.reversed |
| `document_list/get`, `open_orders`, `document_open_state(ref)` | filters | derived rows | member / `reports.view` | — |

Typed errors: `PERIOD_CLOSED`, `ORDER_OVER_INVOICED`, `RETURN_EXCEEDS`, `ORIGINAL_NOT_POSTED`, `DEPENDENCY_PENDING`, `STOCK_INSUFFICIENT`, `WAREHOUSE_INACTIVE`, `PRODUCT_INACTIVE`, `VAT_NOT_CONFIGURED`, `RATE_NOT_FOUND_FOR_DATE` (effective-dated catalogue — `features/13` C5), `ALREADY_REVERSED`, `IDEMPOTENCY_MISMATCH`, `MAPPING_MISSING`, `PERMISSION_DENIED`. No RPC accepts a client-issued document number (D-018).

## J. Tests and acceptance criteria
**Positive:** VAT-exclusive example (nets 59.97/29.96/20.00 @ illustrative 18%/0%) → group tax **16.19** (not the per-line sum 16.18) and total **126.12**; VAT-inclusive example (gross 104.97 @18% + 60.00 @0%) → net 88.96 + tax 16.01 + 60.00, totals net **148.96** / tax **16.01** / gross **164.97** exactly; invoice-level discount 5.00 over the three nets allocates 2.73/1.36/0.91 = 5.00 exactly; cash sale = invoice + payment + allocation in one transaction with AR settled exactly once; partial invoicing lands invoiced = ordered at full conversion; credit note returns stock and reverses COGS under the documented policy; reversal pair linked; R-07 parity set (≥100 generated documents incl. 0.333×3).
**Negative:** over-return beyond line qty ⇒ `RETURN_EXCEEDS`; cumulative invoiced > ordered ⇒ `ORDER_OVER_INVOICED`; invoice against cancelled/draft order ⇒ `DEPENDENCY_PENDING`/typed rejection; credit note on reversed invoice; **document dated outside every effective rate window ⇒ `RATE_NOT_FOUND_FOR_DATE`; a catalogued rate version closed or added later never changes a posted line's snapshot (effective-dating proof)**; cash lines written directly on an invoice entry ⇒ rejected (I24); UPDATE/DELETE on posted rows ⇒ three-layer rejection; closed-period post; unmapped revenue/VAT/COGS role ⇒ `MAPPING_MISSING`; cross-company party/product/warehouse refs; non-stocked line issuing stock; reused idempotency key with different payload; `anon` everywhere.
**Concurrency:** two credit notes racing the last returnable qty ⇒ exactly one succeeds (row lock on original); invoice post racing numbering ⇒ unique server numbers (gap behavior observed, no gap-free claim); delayed-ack idempotent replay.
**Reconciliation:** header = Σ lines = GL legs (I22); AR movement of a document ≡ its gross (ties to I14); Σ COGS ≡ Σ `sales_issue` movement values; trial balance Σ = 0 after a month containing invoices, cash sales, partial payments, notes and reversals.
Test only disposable datasets (`13_TEST_STRATEGY.md`); database execution belongs to the isolated PoC.

## K. Rollout and migration
Depends on: identity/authorization (`features/01`/`02`, DRAFT pending security PoC), CoA + mappings (`features/03`, needs O1 — `SALES_REVENUE`/`VAT_OUTPUT` roles unmapped until then), GL engine (`features/04`, needs O2/O3/O5/O6), parties (`features/05`), inventory (`features/08`, needs O11/O12), cash (`features/09`, for cash settlement, needs O7/O15). Additive migrations; **no VAT-rate seed until D-023**; no V1 data migration (D-002).

## L. Open questions and decisions
- [ ] **D-023 (OPEN, owner):** actual VAT rate, exemptions, legal tax-invoice form and reporting — blocks finalization of this spec.
- [ ] **O15 (REQUIRES_OWNER_DECISION):** cash-sale settlement as linked payment document + allocation in one transaction (**recommended**) vs direct cash lines on the invoice entry.
- [ ] **O16 (REQUIRES_OWNER_DECISION):** server numbering for quotations/orders at creation (**recommended**) and confirmation that orders **do not reserve stock** (interacts with D-025).
- [ ] **O17 (REQUIRES_OWNER_DECISION):** standalone goods issue / goods-in-transit in v1 (**recommendation: defer**; ship-with-invoice is v1 default).
- [ ] **O11 (with `features/08`):** sales-return costing policy — original issue cost recommended, **not approved**.
- [ ] **D-025 (OPEN, owner):** availability display with pending documents — server-posted only recommended.
- [ ] Discount largest-remainder allocation; inclusive group-split formula; header-total assertions; capacity-lock behavior under pooling — RECOMMENDED_PENDING_VALIDATION (PoC + R-07 parity set).

## M. Source evidence
| Claim | Evidence source | Observed on | Confidence |
|---|---|---|---|
| VAT mechanics: optional/configurable, inclusive/exclusive, by-rate grouping, group-total rounding; ILS 2dp HALF_UP | `15_DECISION_LOG.md` D-005 | 2026-10-20 | OWNER_APPROVED (rate/form OPEN → D-023) |
| Offline pending → server order; conflicts rejected + preserved | `15_DECISION_LOG.md` D-006 | 2026-10-20 | OWNER_APPROVED |
| Numbering per company+type+FY; server-issued numbers | `15_DECISION_LOG.md` D-013, D-018 | 2026-10-20 | OWNER_APPROVED |
| Immutability + linked reversals / credit-debit notes | `15_DECISION_LOG.md` D-019 | 2026-10-20 | OWNER_APPROVED |
| Unified party; derived AR/AP | `15_DECISION_LOG.md` D-016, D-017 | 2026-10-20 | OWNER_APPROVED |
| Moving average; no negative stock | `15_DECISION_LOG.md` D-014 | 2026-10-20 | OWNER_APPROVED |
| Precision 19,4 / line HALF_UP | `15_DECISION_LOG.md` R-07 | 2026-10-20 | RECOMMENDED_PENDING_VALIDATION |
| Posting matrix, settlement/capacity design, worked VAT examples | 2026-10-20 sales & purchases planning report (corrected per review) + this spec | 2026-10-20 | PROPOSED / RECOMMENDED_PENDING_VALIDATION |
| Effective-dated VAT resolution (server-side by document date, `features/13` C5 authoritative); flat `tax_rates` uniqueness superseded by `UNIQUE(company_id, code, valid_from)`; line rate snapshots preserved forever; D-023 stays OPEN | 2026-10-21 audit corrections batch 3 — Task 1 alignment | 2026-10-21 | PROPOSED (mechanics RECOMMENDED_PENDING_VALIDATION; no statutory rate assumed) |

**Gate:** keep DRAFT until D-023, O15–O17 (and shared O11/O12/O15) are decided and the security PoC validates the RPC/RLS model.
