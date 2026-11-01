# Feature: المصروفات / 10_expenses
**Status: DRAFT** | **Version:** 0.3 | **Owner approval:** PENDING | **Last reviewed:** 2026-10-21
**Source:** V2 clean-slate design (no Hasad V1 reuse). Bound by `15_DECISION_LOG.md` (D-005, D-006, D-013, D-017, D-018, D-019, D-023, D-011, R-07) and the 2026-10-20 expenses & financial reports planning report.
**Evidence labels:** `PROPOSED` unless marked `OWNER_APPROVED` (by decision ID), `RECOMMENDED_PENDING_VALIDATION`, or `REQUIRES_OWNER_DECISION`.
**Supersedes:** legacy skeleton OPEN "Cash/bank and category mapping; approvals?" — the mapping and settlement design is specified below (§C/§G); **approvals remain an open owner decision → O23**. Skeleton OPEN "Is payroll in MVP?" belongs to `features/11` (scope approved by D-015; legislation D-024).

## A. Why this feature exists
Owns the recognition of **non-inventory operating costs**: expense categories with GL account binding, cash-settled expenses, unpaid supplier expenses, employee reimbursements (proposal), VAT handling under the approved D-005 mechanics, receipt attachments, partial payment through `features/09`, linked reversals, and atomic posting through the shared engine (`features/04`). Payments themselves are owned by `features/09`; inventory/goods costs with supplier invoices are owned by `features/07`.

Exclusions: purchase-side costs (features/07, O29 boundary); payment mechanics and allocations (features/09); payroll and statutory payroll liabilities (features/11, D-024); report layouts (features/12); tax-law determination (D-023).

**Concept separation (binding — consistency item B):** four distinct concepts never conflated:
1. **Expense recognition** — this feature's journal entry (DR expense lines + DR VAT / CR settlement leg).
2. **Cash/bank movement** — the container leg (cash mode: the CR line above; credit mode: a separate `payment_documents` entry from `features/09`).
3. **Supplier payable** — the CR `AP_CONTROL` (party) line created only by credit/employee mode.
4. **Payment allocation** — a subledger application record (`payment_allocations`, features/09) that settles payable capacity; it is never itself an expense or a cash movement.

## B. Roles and user stories
- **`expenses.create` holder** → drafts expense documents online or offline (receipt entry, category, settlement mode).
- **`expenses.post` holder** → posts them (server assigns the official number, D-018 OWNER_APPROVED) and manages categories (`expenses.manage`, or `company.settings` — open with the role catalogue).
- **`expenses.reverse` holder** → linked reversals of posted expenses (D-019 correction model); never edits/deleted posted rows.
- **All members** → read expense documents and categories (expense reports need `reports.view`, features/12).
- Forbidden: client-issued numbers; editing/deleting posted rows; posting an expense whose cost may already be recognized via a purchase bill (duplicate guard, C11); creating expenses directly against `INVENTORY`/`COGS` accounts; recognizing expense from a payment document (structurally impossible — C3).

## C. Business rules and state transitions
- C1 **Categories and GL binding (proposed mechanism — consistency item D):** `expense_categories` are per-company (`UNIQUE(company_id, code)`, Arabic name mandatory, `active ⇄ inactive`). Each category binds **directly** to a same-company **active, postable, expense-type leaf account** via `account_id` — validated at category creation **and re-resolved at posting** (never trusted from cache). This direct binding is the **proposed** mechanism; shared roles (`VAT_INPUT`, `NONRECOVERABLE_VAT`, default `CASH`/`BANK`) still flow through `module_account_map` (`features/03` C7). *Relationship to `module_account_map`: the map resolves per-company **shared module roles**, the category binding resolves **per-category accounts**; the alternative design (one dynamic map role per category code) is documented and rejected for v1 as indirection without benefit. Both are `RECOMMENDED_PENDING_VALIDATION`; the `features/03` C7 wording alignment ("expense-category roles") is **completed in audit batch 3** — C7 now states the direct-binding mechanism as specified here (no silent change in either direction).*
- C2 **Settlement modes:** `settlement ∈ {'cash','credit','employee'}`:
  - **cash** — one balanced entry, CR the container account (no AP, no party required; party optional for reference).
  - **credit** — CR `AP_CONTROL` with **party required** (accrual-consistent unpaid expense); settled only via `features/09` payment + allocation.
  - **employee** — CR `AP_CONTROL` with employee-as-party (**unapproved proposal, REQUIRES_OWNER_DECISION O28**; see C13).
- C3 **Consistency with the payment architecture (consistency item C — RECOMMENDED_PENDING_VALIDATION):** a **cash-mode expense posts exactly one entry with a direct CR container line and does NOT create a `payment_documents` row**. Rationale: no payable is ever created, so there is nothing to allocate; synthesizing an AP + payment pair would fabricate a supplier payable for petty cash costs, require a party for every cash receipt, and duplicate the cash movement across two tables. The `features/09` payment-document architecture remains the **sole** path for (a) settling credit/employee expenses and (b) standalone receipts/payments/transfers. Container balances and cash statements derive from posted GL lines either way (D-017), so reconciliation is unaffected. *Alternative (expense entry + linked payment + 100% allocation in one transaction, I24-style) is documented, not chosen — owner/accountant may overturn at review; validation = the C3 test in §J.*
- C4 **States:** `draft → posted`, **derived `reversed`** (a linked reversal points at the original; the row is never mutated — D-019 OWNER_APPROVED). Drafts deletable with audit; posted rows immutable (three-layer rule, mechanisms pending PoC). **No approval workflow in v1 — O23 (REQUIRES_OWNER_DECISION, recommended default: none).**
- C5 **Money and VAT (D-005 OWNER_APPROVED):** ILS; header `net/tax/gross numeric(18,2)` HALF_UP; document chooses `vat_mode ∈ {inclusive, exclusive}`; taxable amounts **grouped by rate**, **group tax rounded once**; line intermediates `numeric(19,4)` (R-07 pending). Calculation pipeline identical to `features/06` C4 (line round2 → group by rate → group rounding → header = Σ lines, asserted at posting, I28). **Illustrative rates in this document are examples only — statutory rates remain OPEN (D-023).** **Effective-dated rate resolution (audit batch 3 — authoritative definition: `features/13` C5):** rates resolve server-side from the company's effective-dated catalogue **using the document date** (`RATE_NOT_FOUND_FOR_DATE` when none; overlaps rejected at configuration); posted lines keep their resolved `tax_rate` **snapshot** forever — later catalogue changes never rewrite expense history; client caches are UX-only.
- C6 **VAT treatment:** recoverable input VAT posts **DR `VAT_INPUT`** (never inside an expense net — I28); `vat_treatment` per line resolves at posting: recoverable → `VAT_INPUT`; non-recoverable → dedicated expense role **`NONRECOVERABLE_VAT` (same recommended default as O20 in purchases — accountant/legal validation required)**; deductible determination itself is D-023-adjacent and never assumed. Reversal swaps the input-VAT direction (CR `VAT_INPUT`), symmetric with supplier credit notes (`features/07`).
- C7 **Posting (atomic, idempotent):** through `je_post` inside one server transaction; rechecks membership, permission and open period (04-I11); resolves category accounts and container **server-side**; idempotency key UNIQUE per company — replay returns the original document and number; `IDEMPOTENCY_MISMATCH` on key reuse with different content (I31 via the sync contract). Server issues the official number per company+doc_type+FY at posting (D-013/D-018).
- C8 **Partial payment & allocation:** a credit/employee expense becomes a **valid `payment_allocations` target** the moment it is posted. **Consistency item E:** the allocation registry is direction-based — AP-credit documents receive payment-side money (I13). A credit/employee expense produces exactly a CR `AP_CONTROL` movement with the party dimension, so it qualifies **without changing any authoritative AR/AP rule**: capacity stays derived (document amount − Σ active allocations), direction checks stay identical, GL balances remain sums of posted lines (D-017/I14 untouched). The only change is additive: `payment_allocations.target_kind` gains `expense_document` (a follow-up alignment item for `features/09` — not modified in this task).
- C9 **Reimbursement (unapproved proposal — consistency item F):** `settlement='employee'` recognizes an ordinary expense with a payable to an individual modeled as a party (O28). This is **plain expense-plus-payable accounting, entirely separate from payroll**: no salary, no statutory deductions, no `PAYROLL_CLEARING`, no employment calculation. Payroll-specific liabilities, advances and net-pay settlement belong exclusively to `features/11`, blocked by **D-024**; if payroll later wants to net employee advances, that requires an explicit linked design between the two specs — never assumed here.
- C10 **Attachments:** `expense_attachments` rows reference a per-company Storage folder path with `content_hash`, `byte_size`, `mime`; upload online-only in v1 (**O24, REQUIRES_OWNER_DECISION** — recommended default: online-only capture; offline expenses post without a receipt, UI warns `يمكن إرفاق الإيصال لاحقًا`, attachable after sync). Storage disposition remains blocked by **D-011**; retention follows the future backup/retention policy — posted attachments retained with the document.
- C11 **Duplicate recognition prevention (consistency item A — I27):** three layers:
  1. **Ownership rule:** inventory/goods costs arriving with a supplier invoice belong to **Purchases** (bills, `features/07`); standalone operating costs belong to **Expenses** — business confirmation **REQUIRES_OWNER_DECISION (O29)**.
  2. **Duplicate-receipt guard:** posting an expense with `(company_id, party_id, external_ref)` already present on a posted expense **or** a posted purchase bill is rejected `DUPLICATE_RECEIPT` (guard table append-only; a documented release mechanism on reversal — `RECOMMENDED_PENDING_VALIDATION`; mirrors the `supplier_ref` guard of `features/07`).
  3. **Structural:** reports (features/12) read GL only, and payment documents can never create expense lines (C3) — double counting can only enter through two postings, which layers 1–2 block.
- C12 **Audit events (mandatory):** `expense.posted`, `expense.reversed`, `expense.draft_deleted`, `expense.attachment_added`, `expense.category_created/updated/deactivated`, `number.issued`, plus `report.exported`-class events owned by `features/12`.
- C13 **Offline (D-006 OWNER_APPROVED):** expense drafts enter the outbox as pending; server posts in transaction order with server numbers (D-018); typed rejections (`PERIOD_CLOSED`, `CATEGORY_INACTIVE`, `ACCOUNT_NOT_EXPENSE`, `DUPLICATE_RECEIPT`, `PARTY_INACTIVE`, `CONTAINER_INACTIVE`, `VAT_NOT_CONFIGURED`, `PERMISSION_DENIED`/revocation per D-020) are preserved locally with correct/retry/supersede actions per `08_OFFLINE_SYNC.md`; pending expenses never appear in authoritative totals (I29; D-025 governs stock display only and remains OPEN).

State chart: `draft → posted → (derived reversed)`; categories `active ⇄ inactive`; attachments follow the document (removed only with draft deletion, audited).

## D. Data model (PostgreSQL — proposal until approved)
| Table | Purpose | Tenant scope | Key constraints | Status |
|---|---|---|---|---|
| `expense_categories` | Category master data + direct GL binding | `company_id NOT NULL` | `UNIQUE(company_id, code)`; `name_ar NOT NULL`; `account_id` same-company FK (active expense leaf, validated at create **and** post); `is_active` | PROPOSED |
| `expense_documents` | Expense receipts (cash/credit/employee) | `company_id NOT NULL` | `settlement CHECK ('cash','credit','employee')`; `party_id` nullable (NOT NULL for credit/employee — RPC-enforced); `container_account_id` (cash mode, same-company container account); `vat_mode CHECK` (D-005); `doc_no` UNIQUE per (company, doc_type, fiscal_year), server-issued on posting; `external_ref` (supplier receipt number); `reversal_of_id` self-FK (one level); `idempotency_key` UNIQUE per company; header `net/tax/gross numeric(18,2)` immutable posted facts | PROPOSED |
| `expense_document_lines` | Document lines (mixed categories allowed) | `company_id NOT NULL` | `line_no` UNIQUE per doc; `category_id` same-company FK; `amount numeric(19,4)` (R-07); `tax_rate numeric(6,3)` snapshot; derived `net/tax/gross`; `account_id` **resolved and stored at posting** (binding snapshot for auditability) | PROPOSED |
| `expense_attachments` | Receipt evidence | `company_id NOT NULL` | FK `expense_document_id` (same company); `storage_path` under per-company folder; `content_hash`; `byte_size`; `mime CHECK`; uploader stamps | PROPOSED |
| `expense_receipt_dedup` | Duplicate-reference guard | `company_id NOT NULL` | `UNIQUE(company_id, party_id, external_ref)`; FK to expense doc; append-only; **release mechanism on reversal documented but unvalidated** | PROPOSED |

Indexes: `expense_documents (company_id, doc_date)`, `(party_id, doc_date)`, `(company_id, doc_no)` unique, `(company_id, idempotency_key)` unique; `expense_document_lines (category_id)`, `(account_id)`; `expense_receipt_dedup (company_id, party_id, external_ref)` unique.
Deletion policy: posted rows immutable, never deleted; drafts deletable with audit (attachments cascade with audit); categories deactivated, never deleted; guard rows retained (released only via the documented reversal mechanism).

## E. RLS / grants / RPCs
- Private `hasad` schema; RPCs in `hasad_api` INVOKER; privilege model **DRAFT pending the isolated security PoC** (`07`).
- Grants: `SELECT` for `authenticated`; draft writes via RPCs with `expenses.create`; no `UPDATE/DELETE` on posted rows (three layers); posting/reversal only through RPCs with `expenses.post`/`expenses.reverse`; category management with `expenses.manage`; `expense_attachments` written only through the attach RPC (no direct client Storage writes without company-folder scoping).
- Every RPC rederives company from verified membership server-side (R-03) — including read paths; client-supplied party/category/container/tax values are inputs, never trusted; account resolution happens server-side (`ACCOUNT_NOT_EXPENSE`, `MAPPING_MISSING`).

## F. Offline SQLite and synchronization
- Category/container/party caches support offline drafting (UX only; the server re-resolves everything at posting).
- Outbox: durable `client_op_id` + idempotency key; posted in transaction order (D-006); typed rejections preserved locally (never discarded); official numbers appear only after server posting (D-018); local temporary references never printed officially.
- Reversal and attachment upload are online-only operations in v1 (RECOMMENDED — authorization freshness matters for destructive/evidence actions); credit-mode expenses sync like any document, and their later payment/allocation follows the `features/09` pending-allocation rules.
- Pending expense rows are displayed in the sync queue and counted **separately** in reports (features/12; I29).

## G. Accounting impact (if any)
Roles consumed (`features/03`): expense-category accounts (direct binding), `VAT_INPUT`, `NONRECOVERABLE_VAT` (O20 default), `AP_CONTROL` (credit/employee mode), `CASH`/`BANK` via container accounts (cash mode). **Balance-checked matrix (every row ΣDR = ΣCR):**

| Document | Journal lines | Cash movement | Subledger |
|---|---|---|---|
| Cash expense (C3 model) | DR expense lines (net) + DR `VAT_INPUT` (tax) / CR **container account** (gross) — one entry | container ↓ directly on the entry | — |
| Credit expense | DR expense lines + DR `VAT_INPUT` / CR `AP_CONTROL` (party, gross) | none at recognition | AP ↑ |
| Employee expense (O28 proposal) | DR expense lines + DR `VAT_INPUT` / CR `AP_CONTROL` (employee-party, gross) | none at recognition | AP ↑ (individual) |
| Settlement payment (credit/employee) | `features/09` payment entry: DR `AP_CONTROL` / CR container + allocation ≤ open amount | container ↓ via payment doc | AP ↓ once |
| Reversal (D-019) | linked swapped entry (cash reversal: DR container / CR expense + CR `VAT_INPUT`); active allocations reversed in the same transaction (I15 symmetry) | reversed | capacity restored |

Worked examples (exact integer cents; illustrative rates only — D-023): exclusive 120.00@18% + 50.00@0% → tax 21.60, gross 191.60 (DR 120+50+21.60 / CR 191.60); inclusive 150.00@18% → net 127.12 + tax 22.88 = 150.00; credit rent 2,000.00@18% → AP 2,360.00, partial payment 1,000.00 leaves derived open 1,360.00; reimbursement 46.80 gross → 39.66 + 7.14 to AP, settled 46.80 once. Invariants **I27–I30** in `09_ACCOUNTING_INVARIANTS.md` bind this feature. Payment movements never create expense (C3); no stored balances anywhere (D-017).

## H. UI and Arabic RTL
Arabic RTL screens: expense list with settlement badges (نقدًا/آجل/استرداد موظف); expense form (category picker with account preview, inclusive/exclusive toggle, per-rate tax group summary, party picker for credit/employee, container picker for cash, `external_ref` field with duplicate warning); attachment capture/upload with type+size validation and pending-upload state; posting confirmation (number shown only after posting, D-018); reversal confirmation with mandatory reason; offline pending badges with typed Arabic rejections (`الإيصال مسجل مسبقًا` for `DUPLICATE_RECEIPT`, `الفترة مغلقة`). Number/date formats from tenant settings. Empty/loading/error/failed-sync states mirror `features/06/07`.

## I. API / RPC contract
| RPC | Input | Output | Auth | Audit |
|---|---|---|---|---|
| `expense_draft_create/update/delete` | document payload | id | `expenses.create` | expense.draft_deleted |
| `expense_post(doc, idempotency_key)` | draft + key | posted doc + number | `expenses.post` | expense.posted, number.issued |
| `expense_reverse(ref, reason)` | ref, reason | reversal doc id | `expenses.reverse` | expense.reversed |
| `expense_attach(doc_ref, file_meta)` | storage ref | attachment id | `expenses.create` (online) | expense.attachment_added |
| `expense_category_create/update/deactivate` | category fields | id | `expenses.manage` (open vs `company.settings`) | expense.category_* |
| `expense_list/get(ref)` | filters | rows | any active member | — |

Typed errors: `PERIOD_CLOSED`, `CATEGORY_INACTIVE`, `ACCOUNT_NOT_EXPENSE`, `ACCOUNT_NOT_POSTABLE`, `VAT_NOT_CONFIGURED`, `RATE_NOT_FOUND_FOR_DATE` (effective-dated catalogue — `features/13` C5), `DUPLICATE_RECEIPT`, `PARTY_INACTIVE`, `CONTAINER_INACTIVE`, `ALREADY_REVERSED`, `IDEMPOTENCY_MISMATCH`, `MAPPING_MISSING`, `PERMISSION_DENIED`. No RPC accepts a client-issued number, client-resolved account, or client-asserted membership.

## J. Tests and acceptance criteria
**Positive:** the four §G examples post with ΣDR = ΣCR and header = Σ lines = GL legs; inclusive split conserves gross to the cent; mixed-category receipt splits across two bound accounts; credit expense partial allocation leaves derived open amount; reversal swaps the VAT direction and, with active allocations, restores capacity in the same transaction; offline expense syncs in transaction order with a server number; category deactivated after drafting ⇒ posting re-resolution rejects (server authority over cache).
**Negative:** category bound to a non-expense account ⇒ `ACCOUNT_NOT_EXPENSE`; same `(party, external_ref)` re-entered after posting ⇒ `DUPLICATE_RECEIPT`; the same receipt entered as a purchase bill **and** an expense ⇒ guard fires (or documented classification rejection under O29); a payment document containing expense lines ⇒ structurally impossible (template test — C3); UPDATE/DELETE on posted rows ⇒ three-layer rejection; closed-period post; key reuse with changed payload ⇒ `IDEMPOTENCY_MISMATCH`; unmapped `VAT_INPUT` ⇒ `MAPPING_MISSING`; cross-company category/party/container refs ⇒ FK/RLS rejection; `anon` everywhere; a pending offline expense appearing in any report total ⇒ test failure (I29).
**Concurrency:** two devices posting the same `external_ref` receipt simultaneously ⇒ exactly one succeeds (guard serialization); parallel `expense_post` numbering ⇒ unique server numbers; payment racing the expense's remaining capacity ⇒ Σ allocations ≤ amount (I13); delayed-ack idempotent replay.
**Reconciliation:** expense-module Σ GL legs ≡ expense summary report (features/12); cash-mode container movement ≡ cash statement lines; credit-mode AP movement ≡ party statement rows; trial balance Σ = 0 after a month with cash + credit + reimbursed expenses, a settlement payment and a reversal; **C3 cash-movement uniqueness proof: total container outflow equals the sum of distinct cash-mode entries + payment documents, with zero overlap** (consistency item C). Test only disposable datasets (`13_TEST_STRATEGY.md`); database execution belongs to the isolated PoC.

## K. Rollout and migration
Depends on: identity/authorization (`features/01/02`, DRAFT pending security PoC), CoA + category binding (`features/03`, needs O1/O4), GL engine (`features/04`, needs O2/O3/O5/O6), parties (`features/05`), containers + allocations (`features/09`, needs O7/O10 — the `target_kind` extension of §C8 is **specified in `features/09` C6/D since audit batch 2**), purchases guard interoperability (`features/07`, O29). Additive migrations; **no VAT-rate seed until D-023**; no Storage bucket until D-011/O24; no V1 data migration (D-002).

## L. Open questions and decisions
- [ ] **O23 (REQUIRES_OWNER_DECISION):** expense approval workflow — **recommended default: none in v1** (posting permission suffices).
- [ ] **O24 (REQUIRES_OWNER_DECISION):** receipt attachments — storage, retention, offline capture; **recommended default: per-company Storage folder, online-only capture in v1** (D-011 also blocks disposition).
- [ ] **O28 (REQUIRES_OWNER_DECISION):** reimbursement vehicle — **recommended default: employee-as-party via `settlement='employee'`**; alternative: separate employee-payable or defer to `features/11`.
- [ ] **O29 (REQUIRES_OWNER_DECISION):** Expenses↔Purchases ownership boundary and duplicate-guard scope — **recommended default: goods/inventory costs with supplier invoices → Purchases; standalone operating costs → Expenses; guard on `(party, external_ref)` across both modules.**
- [ ] **Carried OPEN:** D-023 (VAT rates/legal forms — blocks VAT finalization), D-011 (Storage disposition), D-024 (payroll — separation rule C9), D-025 (pending-stock display), **O20** (non-recoverable VAT — shared default with purchases), O5 (accrual basis confirmation).
- [ ] C3 direct-cash-posting vs I24-style linked payment for cash expenses — **RECOMMENDED_PENDING_VALIDATION** (owner/accountant may overturn; test C3 proof required).
- [ ] Category direct-binding vs dynamic map roles; guard release mechanism on reversal; account-resolution caching — **RECOMMENDED_PENDING_VALIDATION (PoC)**.
- [ ] Follow-up alignment items: `features/03` C7 wording — **completed (audit batch 3)**; `features/09` payment-allocation `target_kind` extension — **completed (audit batch 2, C6/D)**; **still open:** shared `party_statement` RPC ownership with `features/12` (not modified in this batch).

## M. Source evidence
| Claim | Evidence source | Observed on | Confidence |
|---|---|---|---|
| ILS, 2dp HALF_UP, inclusive/exclusive, by-rate group rounding, strict periods | `15_DECISION_LOG.md` D-005 | 2026-10-20 | OWNER_APPROVED (rate/form OPEN → D-023) |
| Offline pending → server order; typed rejections preserved | `15_DECISION_LOG.md` D-006 | 2026-10-20 | OWNER_APPROVED |
| Server-issued numbering per company+type+FY | `15_DECISION_LOG.md` D-013, D-018 | 2026-10-20 | OWNER_APPROVED |
| Immutability + linked reversals | `15_DECISION_LOG.md` D-019 | 2026-10-20 | OWNER_APPROVED |
| Derived balances, no stored totals | `15_DECISION_LOG.md` D-017 | 2026-10-20 | OWNER_APPROVED |
| Non-recoverable VAT expense role | `15_DECISION_LOG.md` adjacency — O20 (purchases) shared default | 2026-10-20 | REQUIRES_OWNER_DECISION |
| Storage disposition | `15_DECISION_LOG.md` D-011 | 2026-10-20 | OPEN (owner) |
| Settlement model, duplicate guard, category binding, worked examples | 2026-10-20 expenses & reports planning report (consistency items A–G applied) | 2026-10-20 | PROPOSED / RECOMMENDED_PENDING_VALIDATION |
| Effective-dated VAT resolution referenced to `features/13` C5 (server-side by document date; line snapshots preserved; `RATE_NOT_FOUND_FOR_DATE`); `features/03` C7 and `features/09` target_kind follow-ups marked completed | 2026-10-21 audit corrections batch 3 — Tasks 1–2 alignment | 2026-10-21 | PROPOSED (D-023 stays OPEN) |

**Gate:** keep DRAFT until O23/O24/O28/O29 (and carried D-023/D-011) are decided, C3/G mechanism choices are validated, and the security PoC validates the RPC/RLS model.
