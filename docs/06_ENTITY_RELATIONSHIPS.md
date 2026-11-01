# HASAD V2 — Entity Relationships
**Status: DRAFT**

Proposed logical graph:
`Tenant -> Membership(User, Role)`
`Tenant -> Accounts -> Journal Lines <- Journal Header <- Posted Business Document`
`Tenant -> Fiscal Period -> Journal Header`
`Tenant -> Parties -> Sales/Purchase/Payment Documents`
`Tenant -> Warehouses -> Stock Movements <- Business Document`
`Tenant -> Sync Requests -> Posted Result`

Design deliverables before DB build:
- ERD with cardinality, cascade/restrict policies, tenant composite FKs.
- Unique indexes scoped by tenant and fiscal period.
- Parent/child posting references and reversal chains.
- A cross-table FK audit proof, including nullable edges.

## Trade relationships — sales & purchases (PROPOSED 2026-10-20 — not SQL-ready)
Sources: `features/06_sales_and_invoicing.md`, `features/07_purchases.md`, "Trade foundation" in
`05_DATABASE_SCHEMA.md`. **Every edge below is tenant-safe:** each FK is a composite
`(fk_id, company_id)` pair asserting the same `company_id` as both endpoints (mechanism pending the
security PoC; requirement OWNER_APPROVED via D-003/D-016 context, invariant I9).

```text
companies 1──* sales_documents 1──* sales_document_lines *──1 products (08) *──1 parties (05)
companies 1──* purchase_documents 1──* purchase_document_lines *──1 products
companies 1──* tax_rates ──(rate snapshotted onto each document line)──► sales/purchase lines

sales_documents:    quotation ──convert──► order ──invoice lines carry──► order_line_id
                    invoice/credit_note/debit_note ──notes carry──► original_document_id
                    posted financial docs ──1──1► journal_entries (04)
                    lines ──► stock_movements (08) source document (same company)
purchase_documents: quotation ──convert──► order ──receipt lines carry──► order_line_id
                    bill lines carry receipt_line_id ──► goods_receipt lines (clearing)
                    credit/debit notes carry original_document_id
                    receipt/bill/notes ──1──1► journal_entries + stock_movements
sales/purchase documents *──1 parties (D-016) 
cash settlement: payment_documents (09) *──* posted sales/purchase/expense docs via payment_allocations
                            (target_kind registry; expense targets = credit/employee-settlement only — 09 C6)
                            employee-kind payments: payment_documents *──1 employees (net wages → PAYROLL_CLEARING, never AP)
```

### Cardinality, deletion and referential rules
- `sales_documents 1—* sales_document_lines` (cascade only for **drafts**; posted lines restricted);
  same for purchases.
- Quotation/order conversion and all capacities (invoiced ≤ ordered, received ≤ ordered, billed ≤
  received, returned ≤ original) are **derived from posted children** — no stored counters, no FK
  cycles.
- Notes (`original_document_id`/`original_line_id`), bill→receipt (`receipt_line_id`) and
  invoice→order (`order_line_id`) edges **RESTRICT** while referenced by posted rows; a cancelled
  order with posted invoice children cannot be deleted (it is never deleted anyway — workflow rows
  are cancelled, not deleted, once children exist).
- Reversal chains: `sales_documents/purchase_documents.reversal_of_id` self-FK, same company, one
  level deep (no reversal of a reversal — `ALREADY_REVERSED`), mirroring `journal_entries`.
- Payment linkage: `payment_allocations` (09) references posted financial documents only via the
  per-kind `target_kind` registry (sales invoice/debit note on the AR side; purchase bill/supplier
  credit note and **credit/employee-settlement expense documents** on the AP side — 09 C6, audit
  batch 2); direction rules per I13 apply and capacity stays derived (amount − Σ active
  allocations, never stored).
- Deletion policy summary: workflow documents cancelled (never hard-deleted after children);
  financial posted documents immutable and never deleted (D-019).

### Unique indexes scoped by tenant (trade)
- `(company_id, doc_type, fiscal_year)` for `doc_no` — realized as `UNIQUE(company_id, doc_no)`
  plus the issuance constraint per fiscal year (I8 numbering policy).
- `(company_id, idempotency_key)` on both document tables.
- `UNIQUE(company_id, party_id, supplier_ref)` on purchase documents when `supplier_ref` is present
  (partial index — duplicate-bill guard, recommended).

### Required FK audit proof additions (with the existing cross-table audit)
- Nullable edges to prove: `sales_document_lines.product_id` (service lines), `order_line_id`,
  `original_line_id`, `receipt_line_id`, `sales_documents.reversal_of_id` — each nullable path must
  still reject cross-company values when present (composite FK evaluated on write).

## Expense relationships (PROPOSED 2026-10-20 — not SQL-ready)
Sources: `features/10_expenses.md`, "Expenses foundation" in `05_DATABASE_SCHEMA.md`, invariants
I27–I30. Every edge is tenant-safe: composite `(fk_id, company_id)` pairs asserting the same
`company_id` as both endpoints (mechanism pending the security PoC; requirement OWNER_APPROVED via
D-003 context, invariant I9).

```text
companies 1──* expense_categories *──1 accounts (03) ── direct GL binding (proposed, C1)
companies 1──* expense_documents *──1 parties (05)   (party_id NULLABLE — cash mode only)
expense_documents 1──* expense_document_lines *──1 expense_categories
expense_documents 1──* expense_attachments           (Storage path, per-company folder)
expense_documents 1──1 expense_receipt_dedup         (guard row on posting)

expense_documents: posted ──1──1► journal_entries (04)
                   cash mode:     CR container account (09) — direct line, NO payment_documents row
                   credit/employee: CR AP_CONTROL (party) ──settlement──► payment_documents (09)
                                    via payment_allocations (target_kind += expense_document)
                   reversal_of_id self-FK (one level, D-019) + guard-row release
```

### Cardinality, deletion and referential rules
- `expense_documents 1—* expense_document_lines` (cascade only for **drafts**; posted lines
  restricted) and `1—* expense_attachments` (removed only with draft deletion, audited).
- `expense_categories` deactivate only; deactivating a category with posted lines blocks **new**
  documents — resolved account snapshots on posted lines preserve history.
- `party_id` nullable only for cash mode; credit/employee modes require it (RPC-enforced; composite
  same-company FK when present).
- Reversal chain: `reversal_of_id` self-FK, same company, one level deep (`ALREADY_REVERSED`),
  mirroring `journal_entries`, `sales_documents` and `purchase_documents`.
- **Payment-allocation target integration (proposed, additive — specified, audit batch 2):** posted
  credit/employee expense documents are AP-direction targets of `payment_allocations` (09) through
  the extended `target_kind` registry — `features/09` C6/D now carries the full rule set (per-kind
  same-company FK column + matching CHECK, derived capacity, over-allocation forbidden, reversals
  restore capacity in the same transaction per I15, cash-mode expenses structurally excluded).
  **No change to authoritative AR/AP rules**: direction compatibility (I13) and GL-derived balances
  (D-017/I14) are untouched.
- Deletion policy summary: posted expense documents/lines immutable and never deleted (D-019);
  drafts deletable with audit; guard rows retained (released only via the documented reversal
  mechanism — unvalidated).

### Unique indexes scoped by tenant (expenses)
- `(company_id, doc_type, fiscal_year)` for `doc_no` — realized as `UNIQUE(company_id, doc_no)` plus
  per-fiscal-year issuance (I8 numbering policy).
- `(company_id, idempotency_key)` on `expense_documents`.
- `(company_id, party_id, external_ref)` on `expense_receipt_dedup` — duplicate-recognition guard
  (I27), interoperable with `UNIQUE(company_id, party_id, supplier_ref)` on purchase documents.

### Required FK audit proof additions (expenses)
- Nullable edge to prove: `expense_documents.party_id` (cash mode) and
  `expense_documents.container_account_id` (credit/employee mode) — each nullable path must still
  reject cross-company values when present; guard-table FK must prove same-company enforcement on
  both sides; the allocation-target edge must prove a company-B expense can never be a target of a
  company-A payment (now realized as a real same-company composite FK column `expense_document_id`
  — audit batch 2).

## Settings, tax-rate, document-type, template and numbering relationships (`features/13`; PROPOSED)

- `companies 1—1 company_settings` — PK `company_id` both sides: the settings row is created with
  the company (or on first audited write) and can never exist without its company or be shared.
- `companies 1—* tax_rates` — additive effective-dating of the sales/purchases catalogue: one
  company owns its own version chain per tax `code`; version rows are appended/closed, never
  deleted; **no cross-company rate sharing**, and resolution is always by (company, code,
  document-date) with the posted line snapshot as the historical fact.
- `companies 1—* document_types 1—* doc_numbers` — the per-company numbering registry (formats,
  issuance point) feeds the counter keyed by `(company_id, doc_type, fiscal_year)` (**D-013**;
  counter owned by `features/04` — relationship only, no ownership move). A fiscal-year edge
  (`doc_numbers.fiscal_year → fiscal_years`, same company) keeps restart-per-year tenant-safe.
- `companies 1—* document_templates *—1 document_types` — a template renders exactly one document
  type per company (`UNIQUE(company_id, template_code)`); the same-company composite FK on
  `doc_type` prevents a company-B template from referencing a company-A type.
- **Configuration vs history boundary:** no settings/tax/type/template row is ever an *authority*
  for a posted document — posted documents carry immutable snapshots (`tax_rate` per line,
  totals; and, under **O31 (RECOMMENDED_PENDING_VALIDATION)**, a `company_snapshot` of legal
  identity). Configuration changes therefore break **zero** FK edges and renumber/reprice nothing.
- Deletion policy summary: settings rows updated-with-audit only; tax versions closed, never
  removed; types/templates deactivated (`DOC_TYPE_IN_USE` when posted documents exist); counter
  rows never deleted; **no `DELETE` anywhere in the feature**.

### Unique indexes scoped by tenant (settings)
- `company_settings (company_id)` PK — exactly one row per company.
- `tax_rates (company_id, code, valid_from)` — version identity; windows disjoint by construction
  (successor `valid_from` = predecessor `valid_to + 1 day`; both boundaries inclusive on
  documents; server rejects `EFFECTIVE_DATE_OVERLAP`).
- `document_types (company_id, code)`; `document_templates (company_id, template_code)`; format
  changes never touch `doc_numbers` (counter key per D-013 unchanged; committed `doc_no` strings
  immutable — I8).

### Required FK audit proof additions (settings)
- `document_templates.doc_type` and `doc_numbers.fiscal_year` composite same-company paths must
  reject cross-company values.
- Prove that no settings RPC path can write `doc_no` or `doc_numbers` (allocation stays inside
  posting transactions of `features/04/06/07/09/10`); prove a company-B rate version can never
  resolve for a company-A document date (server-side resolution test).

## Payroll relationships (`features/11`; PROPOSED — statutory content blocked by D-024)

**Phase 9A exception (OWNER_APPROVED 2026-10-28):** only the company,
department, job-title, and employee-master edges in the first bullet are in the
three-table subset. The `user_profiles`, `parties`, payroll, payment, and
journal edges below are excluded and remain future DRAFT/BLOCKED work.

- `companies 1—* departments | 1—* job_titles | 1—* employees *—1 departments *—1 job_titles` —
  org master data is tenant-scoped with same-company composite FKs; an employee row can never
  reference another company's department or title.
- `employees *—1 user_profiles` (**optional, nullable, guarded**): the employee-to-application-
  user link is convenience only and grants nothing; a composite same-company FK plus the
  `UNIQUE(user_id)` membership rule (D-003) prove a company-B user can never be linked to a
  company-A employee, and the link weakens no authorization path.
- `employees *—1 parties` (**optional, nullable — O28 interop only**): present solely for the
  employee-as-party reimbursement proposal in `features/10`; payroll logic never traverses it,
  so reimbursement/payroll separation (features/10 C9 / features/11 C12) is structural.
- `employees 1—* employee_contracts` and `employees 1—* payroll_components *—*
  employee_component_assignments` — effective-dated, append-only version chains; resolution is
  always by (employee, run date) with posted calculation rows as the historical fact (frozen
  snapshots in `payroll_run_components`).
- `companies 1—* payroll_components | 1—* payroll_statutory_config | 1—* employee_advances`;
  `payroll_components *—1 accounts` (direct binding, same company); statutory config rows are
  configuration **only** — posted runs carry a `config_snapshot`, so later config changes break
  zero FK edges and rewrite nothing (configuration-vs-history boundary, same philosophy as
  `features/13`).
- `payroll_runs *—1 fiscal_periods` (same-company composite FK) — the period edge makes the
  monthly, FY-anchored run semantics tenant-safe; `payroll_runs 1—* payroll_run_lines *—1
  employees 1—* payroll_run_components`.
- `payroll_runs 1—* payroll_settlements *—1 employee_advances` — settlement rows are the
  **only** path reducing an advance's derived open amount; append-only with status flips
  (`active → reversed`) audit-logged inside the reversal transaction (I15-analogous).
- `payment_documents *—1 employees` (**specified in `features/09` C2/C12 — audit batch 2, PROPOSED**):
  net-wage payments use an employee-kind `payment` document (exactly one counterparty per
  `doc_kind` — simultaneous party + employee structurally impossible); the GL template debits
  `PAYROLL_CLEARING` (employee dimension) and credits the container; amount ≤ derived unpaid
  clearing (`PAYROLL_CLEARING_EXCEEDED`), per-employee advisory-lock serialization, idempotent
  replay — **no payroll edge ever reaches `AP_CONTROL`**, keeping payroll liabilities structurally
  separate from supplier AP (safeguard; I12 untouched). A run reversal that would drive derived
  clearing negative is rejected (`RUN_REVERSAL_BLOCKED` — recommended default, owner/accountant
  approval pending; `features/11` C11 alignment is a recorded follow-up).
- `journal_lines *—1 employees` (**proposed nullable dimension**, mirrors `party_id`): the
  employee dimension on clearing/payable lines is what makes per-employee balances **derived**
  (D-017) instead of stored.
- **Privacy boundary:** relationships to `employees`/payroll tables are traversed only by
  permission-gated masking RPCs — no generic read path (reports, pickers) may expose salary,
  national ID or bank details without `payroll.payslip`/`payroll.view`.
- Deletion policy summary: employees/status toggles only; contracts/components/statutory config
  append-only or deactivated; posted runs/lines/components/advances immutable; settlement rows
  never deleted; **no `DELETE` anywhere in the feature**.

### Unique indexes scoped by tenant (payroll)
- `employees (company_id, employee_code)`; `payroll_components (company_id, code)`;
  `employee_contracts (employee_id, effective_from)`; `employee_component_assignments
  (employee_id, component_id, effective_from)`; `payroll_statutory_config (company_id,
  param_code, effective_from)`; `payroll_settlements (run_id, advance_id)`; `employee_advances
  (company_id, idempotency_key)`.
- **Lifecycle-aware run uniqueness (derived-reversal design, audit batch 1/2 — exact mechanics
  RECOMMENDED_PENDING_VALIDATION):** **at most one active run per (company, period)**, where an
  **active** run is a `posted` run with no posted linked reversal (reversal runs never count as
  active; drafts are active by intent). The stored-`reversed` status + partial-unique-index sketch
  was **removed** — a posted run row is never updated (three-layer immutability, I3/I34), and a
  partial unique index cannot express derived reversal state. The replacement is a **layered
  guard**: per-(company, period) advisory lock around create/calculate/post/reverse + an
  RPC-level `RUN_EXISTS` check under that lock evaluating the derived reversal relationship +
  optionally a deferred constraint trigger as a second defense line (ownership-integrity pattern,
  `07` flaw 2). A legitimate **replacement run** drafts as a new revision (`supersedes_run_id`)
  and receives a **fresh** server-issued number (committed numbers never reassigned, I8).

### Required FK audit proof additions (payroll)
- `employees.user_id` and `employees.party_id` nullable paths must still reject cross-company
  values when present; `payroll_runs.period_id`, run-line employee, component-account and
  settlement/advance edges must prove same-company enforcement on both sides.
- Prove a company-B advance can never receive a settlement from a company-A run; prove a run can
  never post against a fiscal period of another company; prove the reversal/replacement chain
  (`reversal_of_id`/`supersedes_run_id`) stays within one company and one period lineage.
- Prove structurally that no payroll posting path can write an `AP_CONTROL` line or a party
  dimension on payroll entries (template test), and that no generic read RPC returns unmasked
  employee sensitive fields without the specific permission.
- `payment_documents.employee_id` nullable path must still reject cross-company values when
  present; a company-B payment can never settle a company-A employee's clearing (composite FK +
  RPC rederivation — audit batch 2); an employee-kind payment exceeding derived unpaid capacity
  ⇒ `PAYROLL_CLEARING_EXCEEDED`; a run reversal driving derived clearing negative ⇒
  `RUN_REVERSAL_BLOCKED` (recommended default — approval pending, `features/09` C12.4).
