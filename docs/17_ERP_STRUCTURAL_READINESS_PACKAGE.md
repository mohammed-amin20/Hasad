# HASAD V2 — ERP Structural Readiness Package
**Status: DRAFT — NOT SQL-READY**

## Purpose and evidence

This is the single consolidation of why the accounting and operational modules
cannot yet produce a safe V2 migration. It does not approve a business rule,
schema, seed, policy, grant, trigger, RPC, or deployment. The authoritative
source for each decision remains the referenced feature specification and
`15_DECISION_LOG.md`.

**OBSERVED (2026-10-27):** all feature specifications 03–12 remain `DRAFT`.
The owner made a narrow exception for the approved Core-nine default-deny
structural subset, which is now deployed and verified. All remaining ERP tables
still lack complete table/API/security contracts and are not migration-eligible.

## Readiness matrix

| Module | Candidate structural area | Existing approved basis | Missing decision/contract gate | Status |
|---|---|---|---|---|
| Accounting / CoA / journals | accounts, mappings, fiscal years/periods, document counters, journals/lines | D-005, D-006, D-013, D-017, D-018, D-019 | O1–O6, O30, D-023, R-07, exact table/RPC/trigger contract, hosted security PoC | **BLOCKED** |
| Parties / cash / banking | parties, cashboxes, bank accounts, payment documents/allocations, reconciliation | D-005, D-006, D-013, D-016–D-019 | O7–O10, allocation target/FK contract, tender enum, lock semantics, hosted security PoC | **BLOCKED** |
| Inventory | products, warehouses, UOM, levels, movements, counts | D-005, D-006, D-013, D-014, D-018, D-019 | O11–O13, D-025, R-07, movement/lock/replay contract, hosted security PoC | **BLOCKED** |
| Sales / purchases | documents, lines, effective-dated tax rates, receipt/bill links | D-005, D-006, D-013, D-016–D-019 | D-023, O14–O22, R-07, posting/capacity/settlement contract, hosted security PoC | **BLOCKED** |
| Expenses | categories, documents, lines, attachments | D-005, D-006, D-013, D-017–D-019 | D-011, D-023, O20, O23, O24, O28, O29, hosted security PoC | **BLOCKED** |
| Payroll | employees, contracts, components, runs, lines, advances | D-003, D-005, D-006, D-013, D-015, D-017–D-020 | D-024, O32–O34, PII/read contract, hosted security PoC | **BLOCKED** |
| Reporting | derived report RPCs/exports only; no authoritative report tables | D-005, D-006, D-017, D-020 | O25, O26, export/audit-read granularity, hosted security PoC | **BLOCKED** |

## Consolidated owner-decision bundles

### E1 — Accounting/legal baseline

Resolve O1–O6, O30, D-023, and R-07. Existing recommendations remain only
recommendations: no statutory chart seed, VAT rate, legal invoice format,
opening-balance process, number format, intermediate precision, or year-end
automation is assumed.

### E2 — Inventory and trade valuation

Resolve O11–O22 and D-025. The documented alternatives include original issue
cost versus current average for returns, company-wide versus warehouse pools,
clearing versus bill-only receipt models, linked payment settlement versus direct
cash lines, and deferral of landed costs. Accountant/legal validation remains
required for O18–O21.

### E3 — Cash, expenses, and retention

Resolve O7–O10, O23–O29, and D-011. The documented recommended defaults are
reference-only tender handling, manual statement entry, no automatic cash-count
posting, unapplied credits for overpayments, no expense approval workflow,
online-only attachment capture, employee-as-party reimbursement, and a
Purchases-versus-Expenses boundary. None is adopted by this package.

### E4 — Payroll and reporting privacy

Resolve D-024 and O32–O34, plus O25/O26 and report-export/audit-read
granularity. No statutory rate, employee self-service path, payroll detail read
path, aging buckets, or cash-flow statement is inferred.

### E5 — Security execution gate

Complete the remaining C2 §11.6 decisions and the hosted disposable-Supabase
real-JWT/managed-role PoC. Every future module depends on this for its tenant
RLS, direct-table-denial, privileged posting, audit, and permission boundary.

## Migration eligibility

No accounting, inventory, sales, purchases, cash, expenses, payroll, or reporting
migration is prepared by this package. A migration becomes eligible only after:

1. its feature spec reaches `APPROVED` with exact table columns, constraints,
   deletion semantics, indexes, RLS, grants, and API contract;
2. all cross-module decision dependencies above are approved; and
3. the hosted security gate authorizes the required access model.

## Phase 9A structural subset — consolidated, still blocked

The owner-approved Phase 9A contract is in
`features/11_employees_and_payroll.md` §D.1: exactly `hasad.departments`,
`hasad.job_titles`, and `hasad.employees`; basic listed columns only; nonblank
codes/names; termination-status consistency; retained terminated records; and
private/default-deny structure with no application access. D-024 and O32–O34
are deferred only from this subset and remain **OPEN** for Payroll.

The global rule in §Migration eligibility still requires an approved feature
and a hosted real-JWT PoC. No separate Supabase project, Auth identity, hosted
PoC, or DEV write is authorized. Therefore that global rule remains controlling:
full Payroll is **DRAFT/BLOCKED** and Phase 9A is **NOT SQL-ELIGIBLE**.

### Exact remaining Phase 9A gates

1. **P9A-04 assessment — CONDITIONAL PASS:** official-platform capabilities
   support no field encryption for empty, default-deny Phase 9A tables. DEV
   settings were not inspected; the assessment must reopen before real employee
   data, any application access, or exports/logging. No retention duration or
   legal rule is needed for the empty structural stage.
2. **Scoped readiness amendment — P9A-G1:** owner-approved on 2026-10-28 for
   local SQL preparation and fresh disposable-local PostgreSQL testing only.
   It does not authorize any remote operation or change the full Payroll status.

### Decision P9A-G1 — local-only structural readiness amendment

**OWNER_APPROVED (2026-10-28) — LOCAL ONLY.** The owner approved this limited
exception:

> Phase 9A §D.1 is an approved structural sub-contract notwithstanding that
> the full Employees and Payroll feature remains DRAFT/BLOCKED. For only
> `hasad.departments`, `hasad.job_titles`, and `hasad.employees`, local SQL
> preparation and execution against a fresh disposable local PostgreSQL
> database are eligible. The required local evidence is successful creation;
> approved nonblank, status/date, unique, composite-FK, and `ON DELETE
> RESTRICT` checks; RLS enabled and forced; and zero policies, application
> grants, functions, RPCs, or exposed API paths. This exception neither changes
> D-024 or O32–O34, nor authorizes any DEV/production write, Supabase project or
> Auth change, hosted PoC, policy, grant, RPC, or application access. Hosted
> real-JWT/PostgREST validation remains required before any application-facing
> access work and is not represented as passed.

### Lightest defensible evidence path

1. Generate and run the Phase 9A candidate only in a fresh local disposable
   PostgreSQL database with synthetic rows; retain sanitized catalog and
   pass/fail evidence.
2. Seek a separate authorization before any DEV change. Do not add application
   access until a future hosted real-JWT
   proof is authorized and passes.

If later needed before real data, a DEV review requires separate explicit
read-only authorization naming the target and method; it must not retrieve
secrets or query employee data.

Local PostgreSQL can prove PostgreSQL schema, constraints, FKs, local role/RLS
mechanics, and default-deny catalog state. It cannot prove Supabase Auth JWT
claim handling, PostgREST exposure/effective HTTP behavior, managed-role and
service-role behavior, transaction-pooler behavior, or the actual hosted
platform/backup/operator controls. It is evidence for structural SQL only, not
a replacement proof for application access.

**VERIFIED local evidence (2026-10-28):** the approved candidate passed the
fresh-local baseline and negative-test suite recorded in `15_DECISION_LOG.md`.
This is not DEV deployment evidence and does not change full Payroll's
**DRAFT/BLOCKED** status.

**Conditional DEV deployment authorization (2026-10-28):** only the exact
Phase 9A migration/hash recorded in `15_DECISION_LOG.md` may proceed through a
guarded operator-run preflight and separate explicit deployment command. No DEV
operation has run; full Payroll remains **DRAFT/BLOCKED**.

## Owner approval response

Approve or amend one bundle at a time (`E1` through `E5`). An approval must name
the chosen documented alternative for every listed decision; silence does not
adopt a recommendation.

## Candidate SQL contract conventions — PROPOSED

These conventions apply to every candidate table below and are part of the
approval block, not an implicit implementation decision:

- Every tenant table has `id uuid PRIMARY KEY`, `company_id uuid NOT NULL`, and
  `UNIQUE (company_id, id)` where a same-company composite FK needs it. IDs have
  no database default; the future approved server path supplies them.
- Every tenant FK is composite `(company_id, referenced_id)` where its parent is
  tenant-scoped. All FKs use `ON DELETE RESTRICT` unless a later owner decision
  says otherwise. No ERP hard-delete path is proposed.
- All candidate tables are private `hasad` tables with `ENABLE` and `FORCE ROW
  LEVEL SECURITY`, zero policies, zero grants, zero functions, zero triggers,
  zero seed rows, and no PostgREST exposure in their structural migration.
- `numeric(18,2)` is used only for owner-approved final monetary facts. The
  candidate intermediate quantity/unit-price/cost fields use `numeric(19,4)` or
  `numeric(19,6)` only as **R-07 proposed precision**, never as an approved rule.
- Any behavior requiring audit, posting, append-only enforcement, overlap
  detection, advisory locking, or cross-row validation remains a later function/
  trigger/RPC contract. A structural table alone does not claim to enforce it.

## E1 — Accounting, legal, and configuration candidate contract

**Approved basis:** D-005 (ILS, final 2dp HALF_UP, FY/period baseline), D-006,
D-013, D-017–D-019. **Still proposed:** all exact rows below.

| Table | Candidate columns | Candidate constraints and indexes |
|---|---|---|
| `company_settings` | `company_id uuid NOT NULL`, `name_ar text NOT NULL`, `name_en text NULL`, `display_name text NULL`, address/contact text fields NULL, `tax_id text NULL`, `registry_no text NULL`, `currency text NOT NULL DEFAULT 'ILS'`, `vat_enabled boolean NOT NULL DEFAULT false`, `logo_storage_path text NULL`, `preferences jsonb NOT NULL DEFAULT '{}'::jsonb`, `updated_at timestamptz NOT NULL DEFAULT now()`, `updated_by uuid NULL` | PK `company_id`; company FK; `currency='ILS'`; preferences object; updater profile FK. One row/company. No Storage-object operation is implied. |
| `accounts` | `id uuid`, `company_id uuid`, `code text`, `name_ar text NOT NULL`, `name_en text NULL`, `account_type text`, `parent_id uuid NULL`, `is_active boolean NOT NULL DEFAULT true` | PK id; `UNIQUE(company_id,id)` and `UNIQUE(company_id,code)`; account type in asset/liability/equity/revenue/expense; composite self-FK `(company_id,parent_id)`; index `(company_id,parent_id)`. Cycle/leaf/posting behavior is deferred. |
| `module_account_map` | `id uuid`, `company_id uuid`, `module text`, `account_role text`, `account_id uuid` | PK id; `UNIQUE(company_id,id)` and `UNIQUE(company_id,module,account_role)`; composite account FK; index `(company_id,account_id)`. No mapping seed. |
| `fiscal_years` | `id uuid`, `company_id uuid`, `start_date date`, `end_date date`, `status text NOT NULL DEFAULT 'open'`, close/reopen stamps nullable | PK id; `UNIQUE(company_id,id)`, `UNIQUE(company_id,start_date)`; `start_date` Jan 1, `end_date` Dec 31, end = start + one year − one day; status open/closed; index `(company_id,status)`. Period generation is deferred. |
| `fiscal_periods` | `id uuid`, `company_id uuid`, `fiscal_year_id uuid`, `period_no smallint`, `start_date date`, `end_date date`, `status text NOT NULL DEFAULT 'open'`, `reopen_count integer NOT NULL DEFAULT 0`, close/reopen stamps nullable | PK id; `UNIQUE(company_id,id)`, `UNIQUE(fiscal_year_id,period_no)`; composite FY FK; period 1..12; start ≤ end; status open/closed; reopen_count ≥ 0; index `(company_id,status,start_date,end_date)`. Exact contiguous-period enforcement is deferred. |
| `document_types` | `id uuid`, `company_id uuid`, `code text`, `name_ar text NOT NULL`, `issuance text`, `format_prefix text`, `pad_length smallint`, `is_active boolean NOT NULL DEFAULT true` | PK id; `UNIQUE(company_id,id)`, `UNIQUE(company_id,code)`; issuance posting/creation; padding 1..10. Catalogue/seed and creation issuance remain blocked by O16/O30. |
| `tax_rates` | `id uuid`, `company_id uuid`, `code text`, `rate numeric(6,3)`, `valid_from date`, `valid_to date NULL`, `is_active boolean NOT NULL DEFAULT true` | PK id; `UNIQUE(company_id,id)`, `UNIQUE(company_id,code,valid_from)`; rate ≥ 0; valid_to null or ≥ valid_from; active lookup index. Overlap enforcement and statutory values are deferred; no seed. |
| `doc_numbers` | `company_id uuid`, `document_type_id uuid`, `fiscal_year_id uuid`, `next_value bigint NOT NULL DEFAULT 1` | PK `(company_id,document_type_id,fiscal_year_id)`; same-company FKs to document type/FY; next_value > 0. Advisory-lock allocation and formatting are deferred. |
| `journal_entries` | `id uuid`, `company_id uuid`, `fiscal_year_id uuid`, `period_id uuid`, `entry_date date`, `entry_kind text`, `status text NOT NULL DEFAULT 'draft'`, `entry_no text NULL`, `reversal_of_id uuid NULL`, `idempotency_key uuid NULL`, `posted_at timestamptz NULL`, `posted_by uuid NULL`, `reason text NULL` | PK id; `UNIQUE(company_id,id)`; composite FY/period/self FKs; kinds standard/opening/closing/reversal/adjustment; status draft/posted; partial unique `(company_id,idempotency_key)` where non-null; partial unique `(company_id,entry_no)` where entry_no non-null; index reversal. Balance, period, immutability and numbering behavior are deferred. |
| `journal_lines` | `id uuid`, `company_id uuid`, `entry_id uuid`, `line_no integer`, `account_id uuid`, `party_id uuid NULL`, `debit numeric(18,2) NOT NULL DEFAULT 0`, `credit numeric(18,2) NOT NULL DEFAULT 0`, `description text NULL` | PK id; `UNIQUE(company_id,id)`, `UNIQUE(entry_id,line_no)`; composite entry/account/party FKs; debit/credit ≥ 0 and exactly one positive; indexes `(company_id,account_id)`, `(company_id,party_id)`, `(entry_id)`. Employee dimension is not included until its exact contract is approved. |

**E1 lifecycle proposal:** fiscal-year creation creates twelve periods atomically;
posting obtains the document-counter lock only after all business validation;
balance, leaf-account, period-open, idempotency, posting immutability, and number
allocation are server-side transaction rules, not table-grant behavior.

## E2 — Parties, inventory, sales, and purchases candidate contract

**Approved basis:** D-005, D-006, D-013, D-014, D-016–D-019. **Still proposed:**
all structures and algorithms below.

| Area | Candidate tables and required columns | Candidate constraints/indexes |
|---|---|---|
| Parties | `parties(id uuid, company_id uuid, code text, name_ar text NOT NULL, name_en text NULL, party_type text NOT NULL, is_customer boolean NOT NULL DEFAULT false, is_supplier boolean NOT NULL DEFAULT false, tax_id text NULL, phone text NULL, email text NULL, address text NULL, payment_terms_days integer NULL, is_active boolean NOT NULL DEFAULT true)` | PK/id composite unique; unique company/code; party_type individual/company; payment terms ≥ 0; search `(company_id,lower(name_ar))`; customer/supplier partial picker indexes. Tax-ID format is not assumed. |
| Inventory masters | `warehouses`, `product_categories`, `units_of_measure`: each `id/company_id/code/name_ar/is_active`; UOM also `is_base boolean NOT NULL DEFAULT false`. `products(id,company_id,code,name_ar,name_en NULL,barcode NULL,category_id NULL,base_uom_id,track_inventory boolean NOT NULL DEFAULT true,is_active boolean NOT NULL DEFAULT true)`. `product_uom_conversions(id,company_id,product_id,uom_id,factor numeric(19,6))`. | Unique company/code per master; product barcode unique when non-null; composite category/UOM/product FKs; conversion unique product/UOM and factor > 0; product search and barcode indexes. One-base-UOM, conversion lock, and track-inventory freeze are deferred. |
| Stock | `stock_levels(company_id,product_id,warehouse_id,qty numeric(19,4) NOT NULL DEFAULT 0,last_unit_cost numeric(19,4) NOT NULL DEFAULT 0)`. `stock_movements(id,company_id,product_id,warehouse_id,movement_type text,direction text,qty numeric(19,4),unit_cost numeric(19,4),value numeric(18,2),seq bigint,source_document_type text NULL,source_document_id uuid NULL,journal_line_id uuid NULL,posted_at timestamptz)`. `stock_counts(id,company_id,warehouse_id,count_date date,status text)` and `stock_count_lines(id,company_id,count_id,product_id,counted_qty numeric(19,4))`. | Levels PK `(company_id,product_id,warehouse_id)`, qty/cost ≥ 0. Movement unique `(product_id,seq)`, quantity > 0, cost ≥ 0, direction in/out, documented movement-type check, movement indexes. Count status open/posted, line unique count/product, counted qty ≥ 0. Replay, lock, immutable, and count-post behavior deferred. |
| Sales | `sales_documents(id,company_id,doc_kind,status,party_id,doc_date,vat_mode,doc_type_id,fiscal_year_id,doc_no NULL,original_document_id NULL,idempotency_key NULL,net numeric(18,2),tax numeric(18,2),gross numeric(18,2),posted_at NULL,posted_by NULL)`. `sales_document_lines(id,company_id,document_id,line_no,product_id NULL,warehouse_id NULL,qty numeric(19,4),unit_price numeric(19,4),discount_amount numeric(18,2) NOT NULL DEFAULT 0,tax_rate numeric(6,3),net numeric(18,2),tax numeric(18,2),gross numeric(18,2),order_line_id NULL,original_line_id NULL)`. | Composite party/document/self/line/product/warehouse/FY/type FKs; document-kind and state checks; VAT inclusive/exclusive; line unique document/line; quantities > 0, price/discount ≥ 0; doc/idempotency uniques; posting/capacity/tax resolution deferred. |
| Purchases | `purchase_documents` and `purchase_document_lines` mirror sales, with kinds quotation/order/goods_receipt/purchase_bill/credit_note/debit_note, `supplier_ref text NULL`, line `receipt_line_id NULL`. | Partial unique `(company_id,party_id,supplier_ref)` when supplied; composite same-company receipt/original/order links; same money, VAT, idempotency, numbering and lifecycle checks. Clearing, variance, capacity and return behavior deferred. |

**E2 lifecycle proposal:** master rows deactivate rather than delete; document states
separate workflow drafts from posted financial facts; all fulfillment, return,
receipt/bill, movement, tax-date, pricing, and valuation capacities are derived
and validated under transaction locks, never stored as authoritative counters.

## E3 — Cash, expenses, and retention candidate contract

| Area | Candidate tables and required columns | Candidate constraints/indexes |
|---|---|---|
| Containers | `cashboxes(id,company_id,code,name_ar,account_id,is_active boolean NOT NULL DEFAULT true)`; `bank_accounts(id,company_id,code,name_ar,account_id,bank_name NULL,branch_no NULL,account_no NULL,iban NULL,is_active boolean NOT NULL DEFAULT true)` | Composite account FKs; unique company/code; container/account active-leaf validation deferred. |
| Payments/allocations | `payment_documents(id,company_id,doc_kind,status,party_id NULL,employee_id NULL,from_account_id,to_account_id NULL,amount numeric(18,2),doc_type_id,fiscal_year_id,doc_no NULL,reversal_of_id NULL,idempotency_key NULL,tender_method NULL,tender_reference NULL,posted_at NULL)`. `payment_allocations(id,company_id,payment_id,target_kind,sales_document_id NULL,purchase_document_id NULL,expense_document_id NULL,amount numeric(18,2),status,supersedes_id NULL)`. | Payment kind receipt/payment/transfer/refund; amount > 0; exact party/employee shape per kind; transfer accounts differ; composite account/party/document FKs; allocation exactly-one target check and amount > 0; active/superseded/reversed status; per-target partial indexes. Tender enum, employee path, allocation capacity/direction and append-only behavior deferred. |
| Reconciliation | `reconciliation_statements(id,company_id,account_id,statement_date,opening_balance numeric(18,2),closing_balance numeric(18,2),status,closed_at NULL,closed_by NULL)`; `reconciliation_items(id,company_id,statement_id,value_date,description,amount numeric(18,2),journal_line_id NULL,is_external boolean NOT NULL DEFAULT true)` | Statement status open/closed; same-company account/journal FKs; statement/item indexes. Import and matching semantics deferred. |
| Expenses | `expense_categories(id,company_id,code,name_ar,account_id,is_active boolean NOT NULL DEFAULT true)`. `expense_documents(id,company_id,settlement,party_id NULL,container_account_id NULL,doc_date,vat_mode,doc_type_id,fiscal_year_id,doc_no NULL,external_ref NULL,reversal_of_id NULL,idempotency_key NULL,net numeric(18,2),tax numeric(18,2),gross numeric(18,2),status,posted_at NULL)`. `expense_document_lines(id,company_id,document_id,line_no,category_id,amount numeric(19,4),tax_rate numeric(6,3),net numeric(18,2),tax numeric(18,2),gross numeric(18,2),account_id NULL)`. | Category unique company/code and composite account FK; settlement cash/credit/employee; document/line uniqueness and money checks; line category/account snapshots; posting/party/container/settlement semantics deferred. |
| Expense evidence/guard | `expense_attachments(id,company_id,expense_document_id,storage_path,content_hash bytea,byte_size bigint,mime text,uploaded_by,uploaded_at)` and `expense_receipt_dedup(id,company_id,party_id,external_ref,expense_document_id,status)` | Attachment/Storage scope blocked by D-011; byte size > 0; dedup unique company/party/external_ref; release-on-reversal remains deferred. |

**E3 lifecycle proposal:** containers/categories deactivate only; financial rows are
draft/posted with linked reversals; allocation and dedup release behaviors require
the deferred posting/audit functions. The structural migration never creates a
Storage bucket, policy, or attachment upload path.

## E4 — Payroll and reporting-privacy candidate contract

| Area | Candidate tables and required columns | Candidate constraints/indexes |
|---|---|---|
| Payroll masters | `departments`, `job_titles`: `id,company_id,code,name_ar,is_active`. `employees(id,company_id,employee_code,name_ar,status,hire_date,termination_date NULL,department_id NULL,job_title_id NULL,user_id NULL,party_id NULL,sensitive_data jsonb NULL)`. `payroll_components(id,company_id,code,name_ar,kind,method,is_statutory boolean NOT NULL DEFAULT false,account_id,is_active boolean NOT NULL DEFAULT true)`. | Unique company/code; employee status active/suspended/terminated; date consistency; composite master/account refs; sensitive data must have no direct application-table grant. User/party interop remains blocked pending exact same-company FK contract. |
| Effective-dated payroll | `employee_contracts(id,company_id,employee_id,effective_from,effective_to NULL,wage_basis,base_amount numeric(18,2),status)`. `employee_component_assignments(id,company_id,employee_id,component_id,effective_from,effective_to NULL,amount NULL,percent NULL,default_qty NULL)`. `payroll_statutory_config(id,company_id,param_code,effective_from,effective_to NULL,value jsonb,status)`. | Unique start dates per documented key; positive base/amount/qty where present; effective range checks; overlap prevention and D-024 statutory content deferred. |
| Runs/advances | `payroll_runs(id,company_id,period_id,status,reversal_of_id NULL,supersedes_run_id NULL,doc_type_id,fiscal_year_id,doc_no NULL,idempotency_key NULL,config_snapshot jsonb NOT NULL DEFAULT '{}'::jsonb,posted_at NULL,posted_by NULL)`. `payroll_run_lines(id,company_id,run_id,employee_id,gross numeric(18,2),net numeric(18,2),withholding numeric(18,2),settled numeric(18,2))`. `payroll_run_components(id,company_id,run_line_id,component_id,component_code text,qty numeric(19,4),rate numeric(19,4),amount numeric(18,2),account_id)`. `employee_advances(id,company_id,employee_id,doc_date,amount numeric(18,2),status,reversal_of_id NULL,doc_type_id,fiscal_year_id,doc_no NULL,idempotency_key NULL,posted_at NULL)`. `payroll_settlements(id,company_id,run_id,advance_id,amount numeric(18,2),status)`. | Run/advance status draft/posted; reversed state derived; money checks; same-company refs; run/employee unique; settlement run/advance unique; supporting indexes. Active-run guard, statutory posting, clearing/payment capacity, reversal and privacy read logic remain deferred. |
| Reporting | **No report table.** Required indexes belong to the source tables; future report functions are read-only and remain blocked by hosted security validation. | No stored balance/cache is proposed. Payroll detail is never exposed by a structural table grant. |

## Proposed transaction and security boundary

All posting, mutation, audit, idempotency, tenant derivation, append-only,
effective-date overlap, and lock behavior remains outside the structural migration
and must execute atomically inside later approved server transactions. The
structural migration only establishes tenant-safe relations, checks that are purely
row-local, and forced default-deny RLS. It adds no application policy, table grant,
function, trigger, or RPC.

## Consolidated E1–E4 OWNER APPROVAL BLOCK — PROPOSED

> Approve exactly the following bundle, or amend individual clauses. Approval
> authorizes preparation—not deployment—of reviewed default-deny ERP structural
> migrations. Application policies, grants, functions, triggers, RPCs, seeds,
> Storage changes, and hosted-PoC work remain separately gated.
>
> 1. Adopt the candidate structural conventions and E1–E4 table contracts in
>    this document, including UUID keys without database defaults, composite
>    tenant-safe FKs, `ON DELETE RESTRICT`, private schemas, and forced RLS.
> 2. E1: adopt no statutory CoA/tax seed; retain accounts as deactivate-only;
>    use 12 Jan–Dec periods; keep number allocation transactional with no
>    gap-free claim; approve or amend O1–O6, O30, D-023, and R-07.
> 3. E2: adopt the documented recommendations for original-issue sales-return
>    cost, company-wide moving-average pool, reject-for-investigation negative
>    counts, and deferred standalone goods issue; approve or amend O11–O22 and
>    D-025, including the accountant/legal alternatives.
> 4. E3: adopt reference-only tender handling, manual bank statement entry, no
>    automatic cash-count posting, unapplied credits for overpayments, no expense
>    approval workflow, online-only attachments, employee-as-party reimbursement,
>    and the documented Purchases-versus-Expenses boundary; approve or amend
>    O7–O10, O20, O23–O29, and D-011.
> 5. E4: retain payroll statutory configuration empty and block payroll posting
>    until D-024; adopt no employee self-service, no leave/attendance module in
>    v1, no deduction cap, no audit-log read for the auditor, and no report table;
>    approve or amend D-024, O25, O26, O32–O34, and report-export granularity.
> 6. Accept that all cross-row lifecycle enforcement (balances, numbering,
>    overlap prevention, posting, audit, idempotency, capacity, and immutability)
>    is deferred to separately approved behavioral contracts and hosted security
>    proof; no structural migration claims to enforce those rules alone.

## First ERP structural migration group — DEPLOYED / VERIFIED

The first approved group, `v2_erp_core_master_fiscal_settings`, is private,
default-deny structures for `company_settings`, `accounts`, `module_account_map`,
`fiscal_years`, `fiscal_periods`, `document_types`, `tax_rates`, `doc_numbers`,
and `parties`. It would contain no seeds, policies, grants, functions, triggers,
or RPCs. It was deployed by
`20261027000400_v2_erp_core_master_fiscal_settings.sql` on 2026-10-27 after the
Core-nine block was accepted and local/DEV verification passed.

## Core-nine migration contract — DEPLOYED / VERIFIED, STRUCTURE ONLY

This narrows the first group to the owner's exact nine tables. Every table is a
private `hasad` table with `ENABLE` and `FORCE ROW LEVEL SECURITY`, zero policies,
grants, functions, triggers, seeds, or exposure changes. Every relation is
`ON DELETE RESTRICT`. IDs have no database default; the future approved server
path supplies UUIDs. Unless marked `NULL`, every listed candidate column is
`NOT NULL`; defaults are shown explicitly. The columns below are approved only
for the deployed structural subset; no behavioral mechanism is approved by them.

| Table | Exact candidate columns | Keys, checks, and indexes |
|---|---|---|
| `company_settings` | `company_id uuid`, `name_ar text`, `name_en text NULL`, `display_name text NULL`, `address_line1/2 text NULL`, `city/region/postal_code text NULL`, `phone/email/website text NULL`, `tax_id/registry_no text NULL`, `currency text DEFAULT 'ILS'`, `vat_enabled boolean DEFAULT false`, `logo_storage_path text NULL`, `preferences jsonb DEFAULT '{}'`, `updated_at timestamptz DEFAULT now()`, `updated_by uuid NULL` | PK company_id; company/profile FKs; `name_ar`, currency, VAT, preferences, updated_at non-null; currency = ILS; preferences object. Tax ID, email, address, logo and website have no format check or Storage behavior. |
| `accounts` | `id uuid`, `company_id uuid`, `code text`, `name_ar text`, `name_en text NULL`, `account_type text`, `parent_id uuid NULL`, `is_active boolean DEFAULT true` | PK id; `UNIQUE(company_id,id)` and `(company_id,code)`; company FK; account type asset/liability/equity/revenue/expense; composite self-FK; index `(company_id,parent_id)`. No seed, cycle, leaf, or immutability behavior. |
| `module_account_map` | `id uuid`, `company_id uuid`, `module text`, `account_role text`, `account_id uuid` | PK id; `UNIQUE(company_id,id)` and `(company_id,module,account_role)`; company and composite account FK; index `(company_id,account_id)`. No mapping seed. |
| `fiscal_years` | `id uuid`, `company_id uuid`, `start_date date`, `end_date date`, `status text DEFAULT 'open'`, `closed_at/reopened_at timestamptz NULL`, `closed_by/reopened_by uuid NULL`, `reopen_count integer DEFAULT 0` | PK id; `UNIQUE(company_id,id)` and `(company_id,start_date)`; company/profile FKs; status open/closed; reopen count ≥0; start must be Jan 1; end must equal start + one year − one day; index `(company_id,status)`. |
| `fiscal_periods` | `id uuid`, `company_id uuid`, `fiscal_year_id uuid`, `period_no smallint`, `start_date/end_date date`, `status text DEFAULT 'open'`, `closed_at/reopened_at timestamptz NULL`, `closed_by/reopened_by uuid NULL`, `reopen_count integer DEFAULT 0` | PK id; `UNIQUE(company_id,id)` and `(fiscal_year_id,period_no)`; composite FY FK; profile FKs for close/reopen actors; period 1..12; end ≥ start; status open/closed; reopen count ≥0; index `(company_id,status,start_date,end_date)`. |
| `document_types` | `id uuid`, `company_id uuid`, `code text`, `name_ar text`, `issuance text`, `format_prefix text NULL`, `pad_length smallint DEFAULT 4`, `is_active boolean DEFAULT true` | PK id; `UNIQUE(company_id,id)` and `(company_id,code)`; company FK; issuance posting/creation; padding 1..10. No document-type seed. |
| `tax_rates` | `id uuid`, `company_id uuid`, `code text`, `rate numeric(6,3)`, `valid_from date`, `valid_to date NULL`, `is_active boolean DEFAULT true` | PK id; `UNIQUE(company_id,id)` and `(company_id,code,valid_from)`; company FK; rate ≥0; valid-to null or ≥ valid-from; active lookup index. No rate seed or overlap/lifecycle function. |
| `doc_numbers` | `company_id uuid`, `document_type_id uuid`, `fiscal_year_id uuid`, `next_value bigint DEFAULT 1` | PK `(company_id,document_type_id,fiscal_year_id)`; composite FKs to document types and fiscal years; next value >0. No allocation/locking function. |
| `parties` | `id uuid`, `company_id uuid`, `code text`, `name_ar text`, `name_en text NULL`, `party_type text`, `is_customer/is_supplier boolean DEFAULT false`, `tax_id/phone/email/address text NULL`, `payment_terms_days integer NULL`, `is_active boolean DEFAULT true` | PK id; `UNIQUE(company_id,id)` and `(company_id,code)`; company FK; party type individual/company; payment terms ≥0; search index `(company_id,lower(name_ar))`; customer/supplier partial indexes. |

All non-null/default requirements shown in the table are deliberate candidate
choices. Fiscal overlap, period contiguity, tax-window overlap, CoA cycles,
active-leaf validation, lifecycle transitions, counter locking, classification,
and deactivation-in-use checks are cross-row behavior deferred to later approved
transactions. The structural migration does not claim to enforce them.

## Owner-approved structural decisions for this migration (2026-10-27)

1. **APPROVED:** Use the listed `company_settings` and `parties` free-text legal/contact
   fields, nullable where shown; this makes the group legally neutral with no
   backfill or statutory assumption.
2. **APPROVED:** Include fiscal close/reopen stamp fields and `reopen_count`; later lifecycle
   RPCs can then audit state without changing the table shape.
3. **APPROVED:** Use nullable `format_prefix`, pad default 4, and both issuance values with
   no seed; this does not choose an official format or enable quote/order numbers.
4. **APPROVED:** Start with empty/default-deny data for all nine tables; no chart, mapping,
   rate, fiscal calendar, document type, or party seed is implied.
5. **APPROVED:** Defer all cross-row lifecycle enforcement to later approved
   transaction logic; application access remains denied in the meantime.

## Core-nine OWNER APPROVAL BLOCK — APPROVED (2026-10-27)

> **Accepted by the owner on 2026-10-27.** I approve the exact nine-table structural contract above for preparation and
> deployment to DEV: `company_settings`, `accounts`, `module_account_map`,
> `fiscal_years`, `fiscal_periods`, `document_types`, `tax_rates`, `doc_numbers`,
> and `parties`. I approve the five material choices above, including empty
> default-deny tables, tenant-safe composite FKs, `ON DELETE RESTRICT`, and
> `ENABLE` plus `FORCE ROW LEVEL SECURITY` on every table. No seed, policy,
> grant, function, trigger, RPC, PostgREST exposure, Auth/Storage change, account
> mapping, VAT rate, tax obligation, posting behavior, or application access is
> authorized. Deploy only a reviewed migration containing exactly these tables
> after the normal CLI preflight and dry run.

## Phase 8 local FK correction - candidate only (2026-10-27)

- APPROVED - local candidate scope only: Add the tenant-safe constraint `payment_allocations_company_expense_fkey` in `20261029000900_v2_expenses_structure.sql` after `expense_documents` is created: `(company_id, expense_document_id)` references `expense_documents(company_id, id) ON DELETE RESTRICT`. The existing `expense_documents_company_id_id_key` provides the referenced composite uniqueness. The nullable allocation column remains compatible with the exactly-one-target check, which requires it for expense targets.
- OBSERVED - candidate correction: 00800 is unchanged. Corrected 00900 adds only this FK; its candidate SHA-256 is recorded in the decision log. No DEV deployment is authorized or performed, and both candidates remain NOT DEPLOYED.
- BLOCKED - local migration execution: Direct foreground PostgreSQL 17 startup succeeded after `pg_ctl` failed with restricted-token errors 87 and 3. Applying the baseline stopped at migration 00100 because the fresh plain PostgreSQL cluster lacks Supabase-managed `auth.users`. No Auth/Storage test objects were created. Neither candidate execution nor catalog validation was performed; static checks are recorded in the decision log.
## Phase 8 local PostgreSQL execution - VERIFIED structurally (2026-10-27)

- VERIFIED - local-only fixture: `scripts/testing/phase8_local_supabase_compat.sql` creates only `auth` and a minimal `auth.users(id uuid PRIMARY KEY)` target required by baseline migration 00100. The nine baseline migrations reference no other Supabase-managed schemas or objects. This fixture is not Supabase Auth and carries no identity/security behavior or user data.
- VERIFIED - CASE A: On fresh local PostgreSQL 17 database `phase8_case_a`, all nine baseline migrations ran in original order, followed by 00800 alone. Catalog assertions passed: 6 candidate tables, 60 columns, 19 FKs, 8 checks, 8 unique constraints, 6 primary keys, 24 indexes, forced RLS on all 6, 0 policies, 0 non-internal triggers, 0 ACLs, and 0 candidate rows. Exact column names/order were checked against catalog attributes.
- VERIFIED - CASE B: On separate fresh local PostgreSQL 17 database `phase8_case_b`, all nine baseline migrations ran in original order, followed by 00800 and corrected 00900. Catalog assertions passed: 11 candidate tables, 110 columns, 37 FKs, 17 checks, 16 unique constraints, 11 primary keys, 40 indexes, forced RLS on all 11, 0 policies, 0 non-internal triggers, 0 ACLs, and 0 candidate rows after rollback. Exact column names/order were checked against catalog attributes; composite FKs include `company_id` on both sides and use `ON DELETE RESTRICT`.
- VERIFIED - expense FK: `payment_allocations_company_expense_fkey` exists on `(company_id, expense_document_id)` and references `expense_documents(company_id, id) ON DELETE RESTRICT`; catalog confirms `expense_documents_company_id_id_key` is `UNIQUE(company_id, id)`. Synthetic disposable rows confirmed that a nonexistent target and a target belonging to another company are both rejected by this FK. All synthetic rows were rolled back.
- VERIFIED - hashes: 00800 `EF076C57F723113A1689405EFFD6B047A3ED5675EC5613D1E00388C1332207BE`; corrected 00900 `49AA093E04A5C2F113E6051BFD45DB5B02C04A92F340DF3B5DBBEFC9349F94CA`.
- STATUS: Both candidates remain NOT DEPLOYED. No DEV/production connection or Auth/Storage change was made.
- CLEANUP LIMITATION: The local PostgreSQL server was stopped, but the sandbox automatically rejected the requested `dropdb` and temporary-cluster removal commands (`sandbox_approval` is disabled). The disposable database files remain under `%TEMP%\hasad-phase8-validation-20261027`; they are not running. Remove them after local cleanup is permitted.
- OBSERVED - runner invocation: `scripts/testing/validate_phase8_local.ps1` parses successfully, but this Windows PowerShell session blocks direct `.ps1` invocation by execution policy. The policy was left unchanged; the equivalent migration and catalog commands were executed directly.


## Phase 8 controlled DEV deployment attempt - blocked before preflight (2026-10-27)

- OBSERVED: `supabase/.temp/project-ref` contains the authorized project ref `sxasnunzspkuwbxiddqd`; both candidate hashes match the owner's approved values. Static inspection confirms the approved six-plus-five table scope and the corrected tenant-safe expense allocation FK.
- BLOCKED: Supabase CLI initialization failed with `EPERM` while writing `%USERPROFILE%\.supabase\telemetry.json.tmp` outside the writable workspace. No workaround or security/credential changes were attempted. Remote migration history, catalog, pending migrations and dry-run were not checked.
- NOT STARTED: No migration isolation, dry-run, push or remote connection occurred. Stage A and Stage B were not attempted; no deployment result is claimed. Both candidates remain NOT DEPLOYED.
- LOCAL CLEANUP: The previous temporary cluster remains stopped at `%TEMP%\hasad-phase8-validation-20261027`; listener check on port 55441 was false. Sandbox review disallows cleanup, so files remain pending a permitted cleanup path.

## Phase 8 deployment resume - execution unavailable (2026-10-27)

- BLOCKED: This agent session does not expose the trusted OpenCode terminal requested by the owner. Its only shell is the restricted Codex sandbox, which the owner instructed not to use for Supabase CLI.
- No CLI, remote preflight, dry-run, migration isolation, or deployment was attempted. No new remote results are claimed; both approved Phase 8 migrations remain NOT DEPLOYED.

## Phase 8 Codex CLI diagnosis - sandbox filesystem block (2026-10-27)

- The specified native Supabase CLI binary is present, but --version exits before initialization completes because sandbox filesystem access denies creation of %USERPROFILE%\.supabase\telemetry.json.tmp.* (EPERM). This is a local permission failure, not a proven network or database failure.
- Local link metadata equals the authorized project ref and both migration hashes match. Remote ref/history/catalog were not checked; pooler DNS/TCP and PostgreSQL authentication were not reached.
- No migration was isolated, dry-run, or pushed. Both Phase 8 stages remain not started; no remote state changed.
- Operator requirement: permit the CLI telemetry temp-file operation under %USERPROFILE%\.supabase or use a normal-user approved terminal. Pooler DNS/outbound TCP can be diagnosed only after CLI initialization and the configured endpoint is available.
