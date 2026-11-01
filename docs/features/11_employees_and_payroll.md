# Feature: الموظفون والرواتب / 11_employees_and_payroll
**Status: DRAFT** | **Version:** 0.2 | **Owner approval:** PENDING | **Last reviewed:** 2026-10-21
**Source:** V2 clean-slate design (no Hasad V1 reuse). Bound by `15_DECISION_LOG.md` (D-003, D-005, D-006, D-013, D-015, D-017, D-018, D-019, D-020, D-024, R-07) and the 2026-10-21 employees & payroll planning report.
**Evidence labels:** `PROPOSED` unless marked `OWNER_APPROVED` (by decision ID), `RECOMMENDED_PENDING_VALIDATION`, or `REQUIRES_OWNER_DECISION`.
**Supersedes:** legacy skeleton OPEN "Is payroll in MVP?" — **answered OWNER_APPROVED by D-015** (full employees and payroll in the first release). Skeleton OPEN "Statutory payroll rules?" — **remains OPEN under D-024** and blocks statutory seeding and every actual run posting (§C5).

## A. Why this feature exists
Owns employee HR master data (departments, job titles, employment status), effective-dated contracts and compensation history, the payroll component catalogue (earnings, allowances, deductions, statutory withholdings, employer costs), effective-dated statutory configuration, monthly payroll runs and their calculation snapshots, salary advances and their settlement, net-wage payments (through `features/09`), payroll GL posting through the shared engine (`features/04`), linked-reversal corrections, and privacy-classified access to individual salary data.

Explicit ownership boundaries (never conflated): **employee records are not Supabase Auth identities** (owner rule 3; `features/01` keeps auth identity separate) and **not `parties`** (`features/05` — trade counterparties); **employee payroll liabilities never touch `AP_CONTROL`** (safeguard — I12 untouched); **reimbursements belong entirely to `features/10`** (`settlement='employee'`, O28 — plain expense-plus-payable, no payroll component or statutory treatment; `features/10` C9 boundary preserved); **payment mechanics belong to `features/09`**; **payroll-cost reporting aggregates belong to `features/12`** (report #13 detail gate = `payroll.view`, single definition here); **statutory legislation belongs to D-024**.

Exclusions: leave/attendance module (**O32** — recommended: none in v1), employee self-service portal (**O33** — recommended: none in v1), proration/final-settlement rules (D-024), statutory rates/brackets/entitlements (D-024 — **nothing statutory is invented anywhere in this spec**), report layouts (features/12), Storage disposition (D-011).

## B. Roles and user stories
- **`payroll.setup` holder (recommended: owner/admin/payroll_officer — catalogue pending)** → manages departments, job titles, employees, contracts, component catalogue and statutory configuration rows.
- **`payroll.run` holder** → drafts, calculates and posts monthly payroll runs (server issues the official number at posting, D-018 OWNER_APPROVED) and posts salary advances and net payments through the documented RPCs.
- **`payroll.reverse` holder** → linked reversals of posted runs/advances (D-019 correction model); never edits/deletes posted rows.
- **`payroll.view` / `payroll.payslip` holders** → read payroll data; `payroll.payslip` additionally unlocks unmasked individual fields and payslip generation (the most sensitive codes).
- **All members** → nothing by default on employee PII; module pickers use masked employee list RPCs (§E privacy).
- Forbidden: trusting client-supplied amounts/accounts/company; editing/deleting posted rows; posting a run without complete statutory configuration for its period; exposing salary/national ID/bank details through generic reads or reports; mixing payroll lines onto `AP_CONTROL`; inventing statutory values.

## C. Business rules and state transitions
- C1 **Employee master (PROPOSED):** `departments` and `job_titles` are per-company (`UNIQUE(company_id, code)`, Arabic name mandatory, `active ⇄ inactive` only). `employees` rows carry `UNIQUE(company_id, employee_code)`, `name_ar NOT NULL`, hire/termination dates, `status ∈ {active, suspended, terminated}` (deactivation = status change, never deletion — HR history is permanent), department/job-title FKs, and **nullable sensitive fields** (national ID, bank details) that are masked on every read unless the caller holds the specific sensitive permission (§E).
- C2 **Identity separation (owner rule 3, OWNER_APPROVED):** an employee is **not** a user. Optional `user_id` links an employee to an application account of the **same company** (composite same-company FK + uniqueness guard — the one-company-per-user rule D-003 is never weakened); the link is nullable and convenience-only (e.g., default payslip recipient UI) and **grants nothing**. Optional nullable `party_id` exists **only** as future interop for the O28 employee-as-party reimbursement proposal — payroll itself never reads or writes it.
- C3 **Effective-dated compensation (append-only):** `employee_contracts` (`UNIQUE(employee_id, effective_from)`, `wage_basis ∈ {monthly, daily, hourly}`, `base_amount numeric(18,2)`, R-07 intermediates pending) and `employee_component_assignments` (per-employee component parameters) version by effective date. **Windows for one employee never overlap** (`EFFECTIVE_DATE_OVERLAP`); a change closes the old version and appends a new one; used rows are never mutated or deleted. Posting always resolves the contract/assignments **in effect on the run date, server-side** (client caches UX-only — server authority over cache, mirroring features/10 C1).
- C4 **Component catalogue (PROPOSED):** per-company `payroll_components` (`UNIQUE(company_id, code)`, Arabic name) with `kind ∈ {earning, allowance, deduction, statutory_deduction, employer_cost}` and `method ∈ {fixed, percent_of_base, quantity_rate, manual}`. Each non-statutory component binds **directly** to a same-company active postable account of the matching type (expense for earnings/allowances/employer costs; liability for deductions) — validated at creation **and re-resolved at posting**; shared roles still flow through `module_account_map` (features/03 C7). Statutory components exist as **names and kinds only until D-024** seeds their rates and obligations. `active ⇄ inactive`; deactivation blocks new runs, never history.
- C5 **Statutory configuration gate (safeguard — blocking until D-024):** `payroll_statutory_config` rows are per-company, per-parameter, **effective-dated** (same inclusive-boundary discipline as `features/13` tax versions). **A run can never post unless complete statutory configuration exists for its period** ⇒ `STATUTORY_CONFIG_INCOMPLETE`. The catalogue ships **empty** — no rate, bracket, contribution, minimum wage or entitlement is invented anywhere (D-024 OPEN). Until the owner answers D-024, every post attempt is expected to fail with this typed error; drafting, calculation fixtures and tests still run on disposable datasets.
- C6 **Run lifecycle — safe duplicate prevention (corrected design, audit batch 1):** run states are `draft` and `posted`; **`reversed` is DERIVED, never stored.** A reversal is a **new posted reversal run** linked to the original by `reversal_of_id` (the same pattern as journal-entry and payment-document reversals, D-019) — the original posted run row is **never updated**, preserving the three-layer immutability rule (I3/I34: no `UPDATE` on posted rows, including the status column). Duplicate prevention is **lifecycle-aware** so it never blocks legitimate correction or replacement:
  1. an **active run** is defined as a `posted` run with no posted linked reversal (reversal runs themselves never count as active; draft runs are active by intent);
  2. a per-(company, period) **advisory lock** during create/calculate/post/reverse so racing operations serialize;
  3. under that lock, an RPC-level `RUN_EXISTS` check evaluates the **derived** reversal relationship — at most one active run per `(company, period)`;
  4. optionally, a **deferred constraint trigger** as a second defense line (mirroring the ownership-integrity layering in `features/01` C5 / `07` flaw 2). A partial unique index **cannot** express this guard by itself (derived state is not a column), which is precisely why the layered design replaces the earlier stored-`reversed` + partial-index sketch.
  After a posted run is reversed (derived), a **replacement run** may be drafted as a new revision (`supersedes_run_id` links the chain) and receives a **fresh server-issued number** (never reusing the reversed run's number — committed numbers are never reassigned, I8). **The exact lock/check/trigger mechanics remain flagged RECOMMENDED_PENDING_VALIDATION** — required test: reverse → replacement → trial balance holds.
- C7 **Calculation:** deterministic order per employee — earnings/allowances → statutory deductions → employer costs → voluntary deductions → advance settlements; header totals asserted equal Σ line totals and Σ component details (I28-analogous) before anything posts. Draft runs are recalculable; calculation results are **snapshots** (component code, rate/qty/amount, resolved account) frozen at posting — later catalogue or config changes never rewrite them.
- C8 **Posting (atomic, idempotent):** through `je_post` in one server transaction: recheck membership, permission, open period (04-I11); validate statutory completeness (C5); freeze lines/components; resolve accounts server-side (`MAPPING_MISSING`); allocate the official number per company+doc_type+FY (D-013/D-018); post the §G entries **and append the run's advance-settlement rows in the same transaction**; idempotency key UNIQUE per company — replay returns the original run and number (`IDEMPOTENCY_MISMATCH` on changed payload, I31). A failed posting freezes nothing, settles nothing and **consumes no number** (rollback semantics, features/13 C8/C9).
- C9 **Salary advances and settlement:** `employee_advances` are **assets** (`EMPLOYEE_ADVANCES`) until validly settled — posted via their own doc_type and server-issued number, or drafted offline as pending (§F). Their **open amount is derived** (amount − Σ active settlements; no stored balance — D-017). Settlement happens **only** through a posted run's `payroll_settlements` rows (append-only; `UNIQUE(run_id, advance_id)`; `amount ≤` derived open ⇒ `SETTLEMENT_EXCEEDS`; capacity races serialize on a per-employee advisory lock — RECOMMENDED_PENDING_VALIDATION, I13-analogous). The settlement entry touches **only** `PAYROLL_CLEARING` and `EMPLOYEE_ADVANCES` — it can never duplicate salary expense (I35).
- C10 **Net payments (exactly-once; cross-reference aligned audit batch 3):** net wages are paid through the **employee-kind payment vehicle now specified in `features/09` C2/C12/D** — a `payment_documents` row with `doc_kind='payment'` and `employee_id` set (**never** `party_id` — exactly-one counterparty CHECK). The GL template debits **`PAYROLL_CLEARING` (employee dimension) and credits the container — never `AP_CONTROL`** (I12/I36 safeguard, structural template test in `features/09` §J). Rules inherited from `features/09` C12: amount must be `≤` the **derived unpaid clearing capacity** (Σ posted run net credits − Σ active settlements − Σ non-reversed net payments; never stored, never negative — `PAYROLL_CLEARING_EXCEEDED`); concurrent payments serialize on the **per-employee advisory lock**; idempotency keys prevent duplicates (`IDEMPOTENCY_MISMATCH` on changed payload). **Partial salary payments are the recommended default (paying less than full net, capacity-bounded, full cycle reconciling to zero) — pending owner/accountant approval (`features/09` §L); statutory payment-timing obligations are D-024-adjacent and never assumed.** Employee net payments reduce `PAYROLL_CLEARING` **exactly once** (I36). Payment of `net − settled advances` reconciles the employee's clearing balance to zero after a full cycle.
- C11 **Corrections and audited reopening:** a posted run/advance is corrected only by a **linked reversal** — a new posted reversal document/run with swapped entries, mandatory reason and open period (D-019); the original row is never mutated (the reversed state is **derived** from the link, C6). Run reversal also flips its active `payroll_settlements` rows (`active → reversed`, audit-logged) in the same transaction (advance capacity restored — I15-analogous; settlement rows are append-only **workflow** records, consistent with the `payment_allocations` precedent in `features/09` C7 — workflow-row status flips do not touch posted financial facts). Double reversal ⇒ `ALREADY_REVERSED` (derived check — the original already has a posted reversal). **Run-reversal payment guard (recommended policy — audit batch 3; owner/accountant approval required, `features/09` §L):** reversing a **paid or partially paid** run is **blocked until the linked net payment(s) are reversed** — a run reversal that would drive any affected employee's derived `PAYROLL_CLEARING` balance negative is rejected (`RUN_REVERSAL_BLOCKED`); the required workflow reverses the payment(s) first (restoring clearing capacity), then reverses the run. The alternative (tolerating negative clearing with employee repayment) is **not assumed** — the guard preserves the never-negative derived balance (I36) and keeps every sequence prefix trial-balance-clean. Reversal inside a closed period requires the audited privileged reopen of `features/04` first; nothing bypasses strict closing (D-005).
- C12 **Reimbursement boundary (binding):** reimbursements are **not** payroll — no component, no statutory treatment, no clearing line; they follow `features/10` `settlement='employee'` (O28, unapproved proposal). If payroll later nets an employee advance against a reimbursement, that requires an explicit linked design reviewed across both specs — never assumed.
- C13 **Privacy and authorization (safeguard):** `employees`, run/line/component rows, advances, settlements and statutory config have **no direct client `SELECT` grants** — reads are permission-gated RPCs that rederive membership (R-03), check the specific `payroll.*` code, and **mask** national ID/bank/salary fields unless the caller holds `payroll.payslip`/`payroll.setup`; **per-employee reads and payslip generation write audit events** (`payroll.employee_viewed`, `payroll.payslip_generated` — privacy auditing recommended here where generic report views deliberately are not, features/12 C7 contrast). Generic reports expose payroll only as account aggregates (`reports.view`); report #13 per-employee detail requires `payroll.view` (features/12 — single definition, no re-implementation).
- C14 **Offline (D-006 OWNER_APPROVED — capture stays allowed):** payroll run **drafts and advances may be captured offline** and enter the outbox as pending operations; the server validates and posts **in transaction order** with server-issued numbers (D-018); typed rejections (`STATUTORY_CONFIG_INCOMPLETE`, `PERIOD_CLOSED`, `RUN_EXISTS`, `EMPLOYEE_INACTIVE`, `CONTRACT_MISSING`, `SETTLEMENT_EXCEEDS`, `PERMISSION_DENIED`/revocation per D-020) are preserved locally for correction and retry. **Recommended limitation, flagged as an unresolved recommendation (not a rule):** run **posting finalization**, reversals and payslip generation are recommended online-only in v1 (fresh authorization + PII minimization; same pending-entry vs server-acceptance distinction as features/09 allocations) — **owner confirmation requested (§L)**. Pending payroll operations never appear in authoritative totals (I29); cached employee pickers are masked and UX-only; offline access expires per D-020.
- C15 **Audit events (mandatory):** `employee.created/updated/status_changed`, `contract.added/closed`, `component.created/updated/deactivated`, `statutory_config.added/closed`, `payroll_run.draft_created`, `payroll_run.calculated`, `payroll.posted`, `payroll.reversed`, `advance.posted`, `advance.reversed`, `settlement.active/reversed`, `payroll.employee_viewed`, `payroll.payslip_generated`, `number.issued`.
- C16 **Arabic RTL payslips:** payslips are generated documents from the `features/13` template registry (`PAYSLIP` **presentation** template — wording aligned in `features/13` C10, audit batch 3: a payslip's own reference is a **presentation artifact, not an official financial document number**; the payslip derives its identity from the posted run's official number + fiscal period + employee, and payslip generation never touches the `doc_numbers` counters — no new numbering type is invented, D-023/D-024 untouched), rendered **only** from posted snapshots (component names/amounts, net, withholdings, settlements); official numbers and tenant date/currency formats only; never rendered from mutable configuration.

State chart: employees `active ⇄ suspended → terminated` (status only, never deleted); contracts/assignments `open → closed` (append-only successors); components/statutory config `active ⇄ inactive` / `open → closed`; runs `draft ⇄ (recalculate/edit/delete)` → `posted` (immutable facts, numbered; **derived `reversed`** once a posted linked reversal points at it — the posted row is never updated); replacement run allowed only after derived reversal; advances `draft → posted → derived reversed`; settlements `active → reversed` (append-only).

## D. Data model (PostgreSQL — proposal until approved)
| Table | Purpose | Tenant scope | Key constraints | Status |
|---|---|---|---|---|
| `departments`, `job_titles` | Org master data | `company_id NOT NULL` | `UNIQUE(company_id, code)`; `name_ar NOT NULL`; `is_active` | PROPOSED |
| `employees` | HR master | `company_id NOT NULL` | `UNIQUE(company_id, employee_code)`; `name_ar NOT NULL`; `status CHECK(active,suspended,terminated)`; hire/termination dates; department/job-title same-company FKs; **nullable sensitive columns masked on read**; nullable `user_id` (composite same-company FK + UNIQUE guard, D-003 safe); nullable `party_id` (O28 interop only — never used by payroll logic) | PROPOSED |
| `payroll_components` | Component catalogue | `company_id NOT NULL` | `UNIQUE(company_id, code)`; `kind CHECK(earning,allowance,deduction,statutory_deduction,employer_cost)`; `method CHECK(fixed,percent_of_base,quantity_rate,manual)`; `is_statutory`; direct `account_id` binding (validated at create and post); `is_active` | PROPOSED |
| `employee_contracts` | Effective-dated compensation | `company_id NOT NULL` | `UNIQUE(employee_id, effective_from)`; non-overlapping windows per employee; `wage_basis CHECK`; `base_amount numeric(18,2)`; append-only, never deleted | PROPOSED |
| `employee_component_assignments` | Per-employee component parameters | `company_id NOT NULL` | `UNIQUE(employee_id, component_id, effective_from)`; typed parameters (amount/percent/default qty); append-only | PROPOSED |
| `payroll_statutory_config` | Effective-dated statutory parameters | `company_id NOT NULL` | `UNIQUE(company_id, param_code, effective_from)`; inclusive boundaries (features/13 C5 discipline); **empty until D-024**; append-only | PROPOSED |
| `payroll_runs` | Monthly run header | `company_id NOT NULL` | `status CHECK(draft,posted)` — **`reversed` is derived, never stored** (a posted linked reversal points here via `reversal_of_id`; the posted row is never updated — three-layer immutability, I3/I34); **active-run uniqueness (at most one active run per (company, period); active = posted without a posted linked reversal, drafts active by intent) enforced by a layered guard, mechanics RECOMMENDED_PENDING_VALIDATION:** per-(company, period) advisory lock + RPC-level `RUN_EXISTS` under the lock evaluating the derived reversal + optional deferred constraint trigger as second defense (a partial unique index alone cannot express derived state); `period_id` same-company FK → `fiscal_periods`; `doc_no` server-issued at posting; `reversal_of_id` self-FK (posted reversal link; derived reversed state); `supersedes_run_id` self-FK (replacement chain, fresh number); `idempotency_key` UNIQUE per company; frozen totals + `config_snapshot jsonb`; `posted_at/by` | PROPOSED |
| `payroll_run_lines` | Per-employee results | `company_id NOT NULL` | `UNIQUE(run_id, employee_id)`; frozen `gross/net/withholding/settled numeric(18,2)` posted facts | PROPOSED |
| `payroll_run_components` | Per-component detail | `company_id NOT NULL` | FK line + component; frozen `qty/rate/amount` + `account_id` binding snapshot + component code snapshot | PROPOSED |
| `employee_advances` | Salary advances (asset) | `company_id NOT NULL` | `amount numeric(18,2) CHECK > 0`; own doc_type, server-issued number; `status CHECK(draft,posted)` + derived reversed; `reversal_of_id`; `idempotency_key` UNIQUE per company; **open amount always derived** | PROPOSED |
| `payroll_settlements` | Append-only advance settlement records | `company_id NOT NULL` | `UNIQUE(run_id, advance_id)`; `amount CHECK > 0`; `status CHECK(active,reversed)`; capacity ≤ derived open advance (RPC-enforced) | PROPOSED |

### D.1 Phase 9A employee and organization master — APPROVED CONTRACT / LOCAL SQL AUTHORIZED / NOT DEPLOYABLE

This owner-approved contract is limited to department, job-title, and employee
master data. It does not approve or finalize the broader payroll model in §D.
The feature remains **DRAFT** and the full feature remains **BLOCKED** by the
decisions and gates in §L and `docs/17_ERP_STRUCTURAL_READINESS_PACKAGE.md`.

For this Phase 9A candidate, the employee row in §D is narrowed: do not include
`user_id`, `party_id`, `sensitive_data`, national ID, bank details, contact
details, address, date of birth, compensation, attendance, leave, self-service,
advance/loan, or payroll fields. Employee/Auth identity separation remains
binding; O28 reimbursement interop is not part of this scope. No existing
accounting or payment table is changed. The broader fields remain proposed only
where they already appear elsewhere in this DRAFT specification.

#### Table contracts — Phase 9A approved scope

All three tables live in private schema `hasad`. UUID primary keys have no
database-generated default, matching the existing structural migrations. Every
company-scoped unique key includes `company_id`; references between tenant-owned
rows use composite `(company_id, id)` foreign keys and `ON DELETE RESTRICT`.
There are no seeds, policies, grants, functions, triggers, RPCs, or application
 access in this structural contract.

**`hasad.departments`**

| Column | Type | Nullability / default | Purpose |
|---|---|---|---|
| `id` | `uuid` | NOT NULL; no default | Primary key |
| `company_id` | `uuid` | NOT NULL | Owning company |
| `code` | `text` | NOT NULL | Company-scoped department code |
| `name_ar` | `text` | NOT NULL | Required Arabic display name |
| `is_active` | `boolean` | NOT NULL DEFAULT `true` | Deactivation state |

- Primary key: `departments_pkey PRIMARY KEY (id)`.
- Foreign key: `departments_company_fkey FOREIGN KEY (company_id)` references
  `hasad.companies(id) ON DELETE RESTRICT`.
- Unique constraints: `departments_company_id_id_key UNIQUE (company_id, id)`
  for tenant-safe references; `departments_company_code_key UNIQUE
  (company_id, code)`.
- Check constraints: `code` and `name_ar` must each contain at least one
  non-whitespace character. No format, length, transliteration, or other field
  is inferred.
- Delete behavior: company deletion is restricted while a department exists.
  Employee references restrict department deletion. The proposed application
  lifecycle is deactivate-only; SQL immutability is not claimed.
- Indexes: the unique constraints provide indexes on `(company_id, id)` and
  `(company_id, code)`. No additional index proposed.

**`hasad.job_titles`**

| Column | Type | Nullability / default | Purpose |
|---|---|---|---|
| `id` | `uuid` | NOT NULL; no default | Primary key |
| `company_id` | `uuid` | NOT NULL | Owning company |
| `code` | `text` | NOT NULL | Company-scoped job-title code |
| `name_ar` | `text` | NOT NULL | Required Arabic display name |
| `is_active` | `boolean` | NOT NULL DEFAULT `true` | Deactivation state |

- Primary key: `job_titles_pkey PRIMARY KEY (id)`.
- Foreign key: `job_titles_company_fkey FOREIGN KEY (company_id)` references
  `hasad.companies(id) ON DELETE RESTRICT`.
- Unique constraints: `job_titles_company_id_id_key UNIQUE (company_id, id)`
  for tenant-safe references; `job_titles_company_code_key UNIQUE
  (company_id, code)`.
- Check constraints: `code` and `name_ar` must each contain at least one
  non-whitespace character. No format, length, transliteration, or other field
  is inferred.
- Delete behavior: company deletion is restricted while a job title exists.
  Employee references restrict job-title deletion. The proposed application
  lifecycle is deactivate-only; SQL immutability is not claimed.
- Indexes: the unique constraints provide indexes on `(company_id, id)` and
  `(company_id, code)`. No additional index proposed.

**`hasad.employees`**

| Column | Type | Nullability / default | Purpose |
|---|---|---|---|
| `id` | `uuid` | NOT NULL; no default | Primary key |
| `company_id` | `uuid` | NOT NULL | Owning company |
| `employee_code` | `text` | NOT NULL | Company-scoped internal identifier |
| `name_ar` | `text` | NOT NULL | Required Arabic employee name |
| `status` | `text` | NOT NULL; no default | Employment state |
| `hire_date` | `date` | NOT NULL | Employment start date |
| `termination_date` | `date` | NULL | Optional termination date |
| `department_id` | `uuid` | NULL | Optional department assignment |
| `job_title_id` | `uuid` | NULL | Optional job-title assignment |

- Primary key: `employees_pkey PRIMARY KEY (id)`.
- Foreign keys, all `ON DELETE RESTRICT`:
  - `employees_company_fkey FOREIGN KEY (company_id)` references
    `hasad.companies(id)`.
  - `employees_company_department_fkey FOREIGN KEY (company_id, department_id)`
    references `hasad.departments(company_id, id)`.
  - `employees_company_job_title_fkey FOREIGN KEY (company_id, job_title_id)`
    references `hasad.job_titles(company_id, id)`.
- Unique constraints: `employees_company_id_id_key UNIQUE (company_id, id)`
  for tenant-safe references; `employees_company_employee_code_key UNIQUE
  (company_id, employee_code)`.
- Check constraints:
  - `employee_code` and `name_ar` must each contain at least one
    non-whitespace character.
  - `employees_status_check CHECK (status IN ('active','suspended','terminated'))`.
  - `employees_termination_status_check CHECK
    ((status = 'terminated' AND termination_date IS NOT NULL) OR
    (status IN ('active','suspended') AND termination_date IS NULL))`.
  - `employees_termination_date_check CHECK
    (termination_date IS NULL OR termination_date >= hire_date)`.
- Required local disposable-test cases: each code/name constraint rejects empty
  and whitespace-only input; accept `(active, NULL)`, `(suspended, NULL)`,
  and `(terminated, valid date >= hire_date)`; reject active or suspended with
  a termination date, terminated with a NULL termination date, any termination
  date before hire, and any status outside the three allowed values. These are
  test expectations. They are not executed tests or SQL authorization.
- Delete behavior: company, department, and job-title deletion is restricted
  when referenced. The proposed application lifecycle changes employee status
  rather than deleting an employee. The database does not claim immutable rows;
  no application write path is granted by Phase 9A.
- Indexes: unique constraints provide indexes on `(company_id, id)` and
  `(company_id, employee_code)`. No additional index is included in Phase 9A.

**RLS and access — applies to all three Phase 9A tables:**

- `ENABLE ROW LEVEL SECURITY` and `FORCE ROW LEVEL SECURITY` on each table.
- Create no RLS policies and grant no table or schema privileges to
  `PUBLIC`, `anon`, `authenticated`, or `service_role`.
- Keep `hasad` unexposed through PostgREST. No direct client reads or writes;
  no RPC or masking behavior is introduced in Phase 9A.
- RLS flags alone are not the acceptance proof: catalog ACLs, schema exposure,
  and actual role behavior must also be verified. Superuser/BYPASSRLS access is
  outside the application boundary and must not be exposed to clients.

**Relationship to the broader Payroll draft — OPEN reconciliation:** D-015
continues to approve full Employees and Payroll in release scope, while D-024
and O32–O34 remain open. Other sections of this draft and the structural
readiness sketch include broader employee links/fields (including `user_id`,
`party_id`, and `sensitive_data`) and downstream payroll structures. They are
not silently removed or resolved by this Phase 9A contract; they are excluded
from this candidate only. The owner must reconcile the complete feature and
its later-phase contracts without treating this subset as approval of the
broader Payroll draft.

#### PII, retention, and read-access — P9A-03

**OWNER_APPROVED minimum for structural Phase 9A:** the purpose is company HR
administration of employee identity, lifecycle, and organizational assignment.
The approved fields are the exact §D.1 columns; national ID, bank details,
contact details, address, date of birth, compensation, and arbitrary sensitive
data are excluded. Phase 9A grants no application read, write, export, or
generic audit/log access.

Terminated employee records are retained. Phase 9A creates no automatic
deletion, purge, anonymization, archival, or retention job. The legal retention
period, any later retention trigger, backup disposition, and a future deletion
or anonymization policy remain **OPEN**; this specification asserts no legal
requirement. Those choices are required before data collection or an application
access path, not for this empty structural scope.

Future readers are restricted to authorized owner/HR roles in the same company,
subject to a later approved access contract that specifies permissions, fields,
masking, audit, exports, support access, and backup/operator handling. Values
must not be copied to routine logs, diagnostics, or generic audit payloads.

#### Encryption threat assessment — P9A-04 — CONDITIONAL PASS (2026-10-28)

**Scope:** empty Phase 9A tables, private/default-deny structure, no application
access, and no real employee data. This is a platform-documentation review only;
it did not connect to or verify any project setting.

| Field | Encryption direction for this structural stage |
|---|---|
| `id` | No field encryption; primary/composite key. |
| `company_id` | No field encryption; tenant discriminator and composite-FK key. |
| `employee_code` | No field encryption; company-scoped unique/equality lookup. |
| `name_ar` | No field encryption while tables are empty and inaccessible; reopen before real data. |
| `status` | No field encryption; status check/filter field. |
| `hire_date` | No field encryption; required by date-consistency check. |
| `termination_date` | No field encryption; required by status/date checks. |
| `department_id` | No field encryption; same-company FK key. |
| `job_title_id` | No field encryption; same-company FK key. |

**Observed official-platform evidence:** Supabase states that customer data is
encrypted at rest with AES-256 and in transit with TLS
([Security](https://supabase.com/security)). Project HTTP APIs accept only TLS
1.2/1.3; Postgres SSL enforcement is optional and must be enabled per project
([secure configuration](https://supabase.com/docs/guides/platform/security),
[SSL enforcement](https://supabase.com/docs/guides/platform/ssl-enforcement)).
Paid projects receive daily backups by plan; PITR is an optional add-on with
plan/compute requirements ([Backups](https://supabase.com/docs/guides/platform/backups)).
The Data API requires both object grants and RLS; a dedicated private schema
narrows the API surface but does not replace privileges
([Securing the Data API](https://supabase.com/docs/guides/database/hardening-data-api)).
`postgres` is administrative, Dashboard SQL runs as `postgres`, and
`service_role` bypasses RLS ([Postgres roles](https://supabase.com/docs/guides/database/postgres/roles)).
Logs can be inspected and exported by project users
([Logs](https://supabase.com/docs/guides/platform/logs)); secret/service keys
must remain in controlled secret storage and never in clients or source control
([API keys](https://supabase.com/docs/guides/api/api-keys)).

**Not verified for DEV:** database SSL enforcement and client verification mode;
backup plan, retention, PITR, restore access; organization/team/MFA and database
administrator access; network restrictions; Data API schema exposure/default
privileges; log/export access and retention; key inventory, storage, rotation,
or use. Supabase's shared-responsibility guidance assigns these access, data,
and secret-management controls to the customer as applicable.

**Recommendation:** do not add field-level encryption to the empty Phase 9A
structural migration. It provides no protection while no values exist and would
weaken the approved relational checks, FKs, and unique lookup. Reopen this
assessment before the first real employee record, any application/API access,
or any export/logging path; then verify the listed project controls and decide
whether confidentiality from privileged database/backup operators requires an
application-layer encryption and key-management design. Residual risk before
that review is privileged/platform and authorized-dashboard access to plaintext
once data exists; RLS and private schemas do not mitigate it.

#### Phase 9A verification boundary and remaining gate

No hosted PoC or separate Supabase project is authorized for Phase 9A. A local
disposable PostgreSQL run may later verify schema syntax, constraints,
same-company foreign keys, delete restrictions, RLS flags, and absence of local
policies/ACLs. It cannot prove Supabase Auth JWT claims, PostgREST exposure,
managed-role privileges, service-role behavior, or hosted backup/operator
controls.

P9A-G1 is owner-approved for local SQL preparation and disposable-local testing
only. Full Payroll remains **DRAFT/BLOCKED**. This authorization does not permit
a DEV/production write, deployment, policy, grant, RPC, Auth change, hosted
PoC, application access, or real employee data.

**Follow-up extensions (batch-3 status):** `payment_documents` += nullable `employee_id` + "exactly one of party/employee per `doc_kind`" CHECK — **specified in `features/09` C2/C12/D (audit batch 2; mechanics RECOMMENDED_PENDING_VALIDATION)**; `journal_lines` gains nullable `employee_id` dimension (same-company composite FK, mirrors `party_id`) for clearing/payable derivation — **still proposed, not yet specified anywhere**; `doc_numbers` consumes types `PAYROLL_RUN` and `EMPLOYEE_ADVANCE` (features/04/13); `module_account_map` gains module `payroll` roles — **core mapping roles** (`PAYROLL_CLEARING`, `EMPLOYEE_ADVANCES`, `SALARY_EXPENSE`) now enumerated in `features/03` C7 (audit batch 3), **statutory payable role names** (`INCOME_TAX_WITHHOLDING_PAYABLE`, `SOCIAL_INSURANCE_EMPLOYEE_PAYABLE`, `SOCIAL_INSURANCE_EMPLOYER_PAYABLE`) remain names only — never seeded until D-024.

**Future full-payroll indexes — excluded from Phase 9A:** `employees (company_id, employee_code)` unique, `(company_id, department_id)`, `(company_id, status)` partial for run selection; `payroll_runs (company_id, period_id)` **non-unique supporting index for the layered active-run guard (C6 — a partial unique index cannot express derived reversal state)**; `payroll_run_lines (run_id)`, `(employee_id)`; `payroll_run_components (line_id)`; `employee_advances (company_id, employee_id, doc_date)`; `payroll_settlements (advance_id)` partial active. **No stored balances anywhere** (D-017): advance open amounts, clearing balances and run-open figures all derive from posted rows. Deletion policy: **no DELETE anywhere in this feature** — master data by status/`active⇄inactive`; contracts/config append-only; posted runs/lines/components/advances immutable (**no `UPDATE` either — including the status column; the reversed state is derived**); settlement rows append-only (workflow status flips audited); drafts deletable with audit.

## E. RLS / grants / RPCs
- Private `hasad` schema; RPCs in `hasad_api` **INVOKER**, pinned `search_path`; `EXECUTE` revoked from `PUBLIC`/`anon`. **The INVOKER/RLS privilege model is DRAFT — not verified** (`07`, pending the isolated security PoC).
- **No direct table `SELECT` grants** for `authenticated` on `employees`, `payroll_runs/lines/components`, `employee_advances`, `payroll_settlements`, `payroll_statutory_config` — all reads flow through masking RPCs (privacy design, RECOMMENDED_PENDING_VALIDATION; grant set per R-02 documented per function).
- Writes only through RPCs gated by `payroll.setup` / `payroll.run` / `payroll.reverse`; payslip/unmasked reads require `payroll.payslip` (or `payroll.setup`); **no client UPDATE/DELETE on posted rows** (three-layer rule, mechanisms pending PoC); posting/reversal only through the documented RPCs.
- Every RPC rederives company from live membership server-side (R-03) — including reads and duplicate-ack resends; client-supplied employee/amount/account/company values are consistency inputs, never trusted; account resolution happens server-side (`MAPPING_MISSING`).

## F. Offline SQLite and synchronization
- **Owner-approved capture (D-006) applies to payroll:** run drafts (employee selection + component quantities/amounts) and advance documents may be created offline and queued in the outbox as pending operations; the server posts **in transaction order** with server-issued numbers; typed rejections are preserved locally with correct/retry/supersede actions per `08_OFFLINE_SYNC.md`; rejected operations commit no business effects and their rejection evidence follows the savepoint rule (I31/I32).
- **Unresolved recommendation (§L, not a rule):** run **posting finalization**, reversals and payslip generation recommended online-only in v1 — pending-entry vs server-acceptance remain explicitly distinct states (features/09 precedent); if the owner confirms, the client simply queues drafts and requires connection for the post action, without ever blocking or discarding captured pending data.
- Cached masked employee pickers, component lists and draft run calculations are UX-only; the server re-resolves contracts, assignments, statutory config and accounts at posting (§C3/C5). Permission revocation mid-pending ⇒ lock/preserve/deny-post (D-020). Pending payroll operations are excluded from every authoritative total and report (I29) and appear only in the sync queue's pending count.

## G. Accounting impact (if any)
This feature **posts** through the `features/04` engine. Roles consumed (`features/03` C7, module `payroll`): `SALARY_EXPENSE` and per-component direct expense bindings; `EMPLOYEE_ADVANCES` (asset); `PAYROLL_CLEARING` (liability, **employee-dimensioned**); statutory payables (`INCOME_TAX_WITHHOLDING_PAYABLE`, `SOCIAL_INSURANCE_EMPLOYEE_PAYABLE`, `SOCIAL_INSURANCE_EMPLOYER_PAYABLE`) — **names only, never seeded until D-024**. Invariants **I34–I37** in `09_ACCOUNTING_INVARIANTS.md` bind this feature. **Balance-proven matrix (every row ΣDR = ΣCR):**

| Document | Journal lines | Subledger |
|---|---|---|
| Run posting (entry 1) | DR earning/allowance/employer-cost accounts (G + E) / CR `PAYROLL_CLEARING` (N, per-employee dimension) + CR withholding payables (W) + CR employer-contribution payable (E) | clearing ↑ per employee |
| Advance settlement (entry 2, same transaction) | DR `PAYROLL_CLEARING` (X) / CR `EMPLOYEE_ADVANCES` (X) | advance open ↓ derived |
| Net payment (`features/09` C12 employee-kind vehicle — specified, audit batch 3) | DR `PAYROLL_CLEARING` (N − X, employee dimension) / CR container — **amount ≤ derived unpaid capacity; `PAYROLL_CLEARING_EXCEEDED` otherwise; never `AP_CONTROL`** | clearing ↓ **exactly once** |
| Run reversal | **new posted reversal run** with linked swapped entries + settlement rows flipped (same transaction); the original posted run row is untouched — reversed state derived (C6/C11) | capacity restored |
| Advance reversal | linked swapped entry (`DR container / CR EMPLOYEE_ADVANCES`), rejected while active settlements exist (`ADVANCE_IN_USE`) | — |

Worked example (exact integer cents; **all rates illustrative only — nothing statutory, D-024**): base 5,000.00 + transport allowance 300.00 → G = 5,300.00; illustrative employer cost E = 525.00; illustrative withholdings W = 500.00 (income-tax-style) + 275.00 (social-insurance-style) = 775.00; net N = 4,525.00; advance settlement X = 1,000.00; cash = 3,525.00. Entry 1: DR 5,000.00 + 300.00 + 525.00 = 5,825.00 / CR 4,525.00 + 500.00 + 275.00 + 525.00 = 5,825.00 ✓. Entry 2: DR clearing 1,000.00 / CR advances 1,000.00 ✓. Payment: DR clearing 3,525.00 / CR bank 3,525.00 ✓. Clearing nets to zero (4,525 − 1,000 − 3,525). **G + E = N + W + E by construction**; withholdings and employer contributions remain **distinct obligations** (separate payable accounts, never netted); no `AP_CONTROL` line exists anywhere in the matrix (safeguard; I12 untouched).

## H. UI and Arabic RTL
Arabic RTL screens: department/job-title/employee lists and forms (sensitive fields hidden behind the payslip/setup permission with a خاص badge and partial masking `••••1234`); contract timeline (العقود السارية/المنتهية, effective-date pickers, overlap error inline); component catalogue with account preview and statutory components visibly marked (تتطلب إعدادًا قانونيًا — D-024); statutory-configuration screen showing completeness per period; run wizard (period picker → eligible employees → per-employee component grid with quantity inputs for `quantity_rate`/`manual` methods → totals summary with balance indicator); posting confirmation (official number only **after** posting, D-018; blocked posting explains the next action — `إعدادات الرواتب القانونية غير مكتملة`); runs list with active/reversed badges and replacement-run action after reversal; advance list with derived open amounts + freshness label; **payslip generation and print preview** (RTL, tenant formats, template-driven per features/13 — number shown only for posted runs); reversal confirmation with mandatory reason; sync queue with pending payroll drafts and typed Arabic rejections. Empty/loading/error/failed-sync states per `14_UI_ARABIC_RTL_STANDARDS`. Number/date/currency formats from tenant settings, never device locale.

## I. API / RPC contract
| RPC | Input → Output | Permission | Audit |
|---|---|---|---|
| `department/job_title_create/update/deactivate` | fields → id | `payroll.setup` | — (master.*) |
| `employee_create/update/status_change(id, ...)` | fields (masked sensitive inputs) → id | `payroll.setup` | employee.* |
| `employee_get/list(masked=true)` | filters → rows (**masked unless permitted**) | `payroll.setup` (unmasked); masked list for module pickers | employee_viewed (unmasked reads) |
| `contract_add/close`, `component_assignment_add/close` | effective-dated rows | `payroll.setup` | contract.added/closed |
| `component_create/update/deactivate`, `statutory_config_add/close` | fields | `payroll.setup` | component.*, statutory_config.* |
| `payroll_run_draft_create(period, selection)` | period → run id | `payroll.run` | payroll_run.draft_created |
| `payroll_run_calculate(run_id)` | run → snapshot lines + totals | `payroll.run` | payroll_run.calculated |
| `payroll_run_post(run_id, idempotency_key)` | key → posted run + number + settlements | `payroll.run` | payroll.posted, settlement.active, number.issued |
| `payroll_run_reverse(run_id, reason)` | ref → reversal run/entry | `payroll.reverse` | payroll.reversed, settlement.reversed |
| `advance_draft_create/post(doc, key)`, `advance_reverse(ref, reason)` | document → id/number | `payroll.run` / `payroll.reverse` | advance.posted/reversed, number.issued |
| `payslip_generate(run_id, employee_id)` | refs → payslip render (from posted snapshots) | **`payroll.payslip`** | payroll.payslip_generated |
| `payroll_employee_statement(employee, range)` | filters → derived rows (clearing, advances, settlements) | `payroll.view` | — |

Typed errors: `STATUTORY_CONFIG_INCOMPLETE`, `RUN_EXISTS`, `RUN_NOT_DRAFT`, `ALREADY_REVERSED`, `EFFECTIVE_DATE_OVERLAP`, `CONTRACT_MISSING`, `COMPONENT_INACTIVE`, `EMPLOYEE_INACTIVE`, `SETTLEMENT_EXCEEDS`, `ADVANCE_IN_USE`, `PERIOD_CLOSED`, `MAPPING_MISSING`, `IDEMPOTENCY_MISMATCH`, `PERMISSION_DENIED`, `MEMBERSHIP_REQUIRED`, `PAYROLL_DETAIL_DENIED`. No RPC accepts a client-issued number, client-resolved account, client-computed authoritative total, or client-asserted membership.

## J. Tests and acceptance criteria
**Positive:** §G worked example posts with ΣDR = ΣCR, header = Σ lines = Σ components, and clearing nets to zero after settlement + payment; effective-dated contract switch mid-year resolves by run date; component deactivated between draft and post ⇒ re-resolution rejects (server authority over cache); advance open derived correctly across two partial settlements; **reverse a posted run → its status is derived-reversed with zero UPDATEs on the original row (three-layer proof), and a replacement run posts in the same period with a fresh number and a correct trial balance** (C6 lifecycle proof); idempotent replay returns the identical run/number with zero new rows; offline advance captured pending posts in transaction order with a server number; masked RPC redacts national ID/bank/salary without `payroll.payslip`; unmasked read and payslip generation each write exactly one audit event; audit row set per posting exactly: one `payroll.posted`, one `number.issued`, one `settlement.active` per settlement.
**Negative:** run post with incomplete statutory configuration ⇒ `STATUTORY_CONFIG_INCOMPLETE` (the expected state for every company until D-024 answers); second active run for the same period ⇒ `RUN_EXISTS`/layered-guard rejection (C6 — advisory lock + derived-state RPC check; optional deferred trigger); **net payment exceeding derived unpaid capacity (or before any posted run) ⇒ `PAYROLL_CLEARING_EXCEEDED`; run reversal while a non-reversed net payment leaves derived clearing below the reversal debit ⇒ `RUN_REVERSAL_BLOCKED` (recommended policy — payment reversed first, then the run; C11)**; any `UPDATE` of a posted run's status column (including a manual attempt to flip it to `reversed`) ⇒ three-layer rejection; posting into a closed period; reversal of a reversal ⇒ `ALREADY_REVERSED` (derived); settlement exceeding derived open ⇒ `SETTLEMENT_EXCEEDS`; advancing a terminated employee; unmapped `PAYROLL_CLEARING` ⇒ `MAPPING_MISSING`; **any payroll journal line resolving to `AP_CONTROL` ⇒ template test failure (safeguard)**; a payroll payment document requiring a party ⇒ structurally impossible (employee-kind CHECK); report #13 per-employee detail without `payroll.view` ⇒ zero rows (features/12 negative test); UPDATE/DELETE on posted runs/lines/advances/components ⇒ three-layer rejection; direct `SELECT` on payroll tables as `authenticated` ⇒ denied (no grants); client-supplied totals overwritten by server recomputation at post; cross-company employee/period/component/advance refs ⇒ FK/RLS rejection; `anon` everywhere ⇒ denied.
**Concurrency:** two simultaneous run posts for one period ⇒ serialize on the advisory lock — one succeeds, one `RUN_EXISTS`; parallel posts across different periods ⇒ unique numbers, no cross-blocking; two runs/advances racing one advance's capacity ⇒ serialized per-employee lock, Σ active settlements ≤ advance amount; duplicate idempotent replay racing the original ⇒ single execution, identical outcomes; payment racing run reversal ⇒ clearing never over-debited; replacement-run creation racing a concurrent reversal ⇒ serialized.
**Reconciliation:** Σ run GL legs ≡ payroll-cost report #13 aggregates (features/12 I30); per-employee `PAYROLL_CLEARING` derived three ways (Σ posted lines vs Σ runs − settlements − payments vs statement RPC) identical; trial balance Σ = 0 across a month with two runs, an advance, a settlement, a payment and a reversal; Σ posted withholding lines ≡ Σ withholding component details (statutory-liability proof); **G + E ≡ N + W + E asserted per run**; `Σ number.issued` ≡ posted runs + advances; run reversal + replacement reproduces identical totals when inputs are identical. Test only disposable datasets (`13_TEST_STRATEGY.md`); database execution belongs to the isolated PoC.

## K. Rollout and migration
Depends on: identity/authorization (`features/01/02`, DRAFT pending security PoC — `payroll.*` codes join the owner-pending role catalogue; `features/02` §D/§L now carry the payroll families and the clarified payroll_officer scope, audit batch 3); GL engine + periods (`features/04`, needs O2/O3/O5/O6 context); account roles (`features/03` C7 — core payroll mapping roles enumerated, statutory role names D-024-gated); containers + payment vehicle (`features/09`, needs O7/O10 — **employee-kind vehicle specified in C2/C12/D, audit batch 2**); template registry (`features/13` — `PAYSLIP` presentation template aligned, audit batch 3); report #13 boundary (`features/12` — verify wording only). Additive migrations; **no statutory seed of any kind until D-024**; no V1 data migration (D-002). **The spec cannot be finalized before D-024** (15_DECISION_LOG scope note on D-015).

## L. Open questions and decisions
- [ ] **D-024 (REQUIRES_OWNER_DECISION — blocking):** jurisdiction, statutory contribution rates/brackets, mandatory benefits, proration/final-settlement rules, leave entitlements, statutory deduction limits — **blocks all statutory seeding and every actual run posting (C5 gate)**; no value is assumed anywhere in this spec.
- [ ] **O32 (REQUIRES_OWNER_DECISION):** leave/attendance boundary — **recommended default: no leave/attendance module in v1**; manual quantity inputs on run lines only; entitlements deferred to D-024.
- [ ] **O33 (REQUIRES_OWNER_DECISION):** employee access to own data/payslips — **recommended default: none in v1** (no employee logins; PDF payslips generated by `payroll.payslip` holders); self-service is a later-phase candidate.
- [ ] **O34 (REQUIRES_OWNER_DECISION):** advance settlement flexibility — **recommended default: no deduction cap in v1** (capacity ≤ derived open advance only); any statutory cap arrives with D-024.
- [ ] **Offline finalization limitation (this spec's recommendation — owner confirmation requested):** run posting/reversal and payslip generation recommended online-only in v1 while **draft capture stays fully offline-capable per D-006**; no pending data is ever blocked or discarded under either answer.
- [ ] **Carried OPEN:** D-010/D-011/D-012 (schema exposure, Storage, migrations), D-023 (VAT — no payroll interaction), D-025 (pending-stock display — no payroll interaction), role-catalogue mapping for `payroll.setup/run/reverse/view/payslip` (features/02 owner decision), O28 (reimbursement vehicle — boundary in C12).
- [ ] **Net-payment policies carried from `features/09` §L (owner/accountant approval required — batch 3 cross-reference):** partial salary payment as recommended default (C10) and the run-reversal-after-payment guard (`RUN_REVERSAL_BLOCKED`, C11) — both **recommended, unapproved**; nothing here assumes statutory payment timing (D-024-adjacent).
- [ ] Technical (**RECOMMENDED_PENDING_VALIDATION**): layered active-run guard with **derived** reversal — advisory lock + RPC derived-state `RUN_EXISTS` check + optional deferred constraint trigger (C6 mechanics; the earlier partial-unique-index + stored-`reversed` sketch was removed in audit batch 1 as an immutability contradiction); employee dimension on `journal_lines` (still proposed); `payment_documents` employee-kind extension **mechanics** (specified in `features/09` C2/C12 — PoC validation pending); append-only settlement mechanics; per-employee advisory lock; masking-RPC privacy layer (column encryption pending D-021/R-05 patterns); statutory-config completeness check; INVOKER/RLS model (unverified — `07`); component direct-binding vs map-role indirection (same debate as features/10 C1, both documented).

## M. Source evidence
| Claim | Evidence source | Observed on | Confidence |
|---|---|---|---|
| Full employees & payroll in first release | `15_DECISION_LOG.md` D-015 | 2026-10-20 | OWNER_APPROVED (scope only; spec not finalizable before D-024) |
| Statutory payroll legislation unresolved — gate designed accordingly | `15_DECISION_LOG.md` D-024 | 2026-10-20 | OPEN (owner) — blocking |
| Employee records distinct from Auth identities | Owner-approved shared requirement 3; `features/01` | 2026-10-20 | OWNER_APPROVED |
| ILS; 2dp HALF_UP; strict monthly periods; audited reopening | `15_DECISION_LOG.md` D-005 | 2026-10-20 | OWNER_APPROVED |
| Offline entry pending → server posts in transaction order; typed rejections preserved | `15_DECISION_LOG.md` D-006 | 2026-10-20 | OWNER_APPROVED |
| Numbering per company+type+FY; server-issued official numbers | `15_DECISION_LOG.md` D-013, D-018 | 2026-10-20 | OWNER_APPROVED |
| Immutability + linked reversals | `15_DECISION_LOG.md` D-019 | 2026-10-20 | OWNER_APPROVED |
| Derived balances; no stored totals | `15_DECISION_LOG.md` D-017 | 2026-10-20 | OWNER_APPROVED |
| Offline permissions, revocation, 24h expiry | `15_DECISION_LOG.md` D-020 | 2026-10-20 | OWNER_APPROVED |
| Payroll architecture, posting matrix, worked example, lifecycle uniqueness guard, privacy model | 2026-10-21 employees & payroll planning report (build corrections applied: offline capture preserved per D-006; run lifecycle guard replaces naive unique-per-period) | 2026-10-21 | PROPOSED / RECOMMENDED_PENDING_VALIDATION |
| Derived reversal (no stored status flip on posted runs); layered active-run guard replaces the partial-unique sketch | 2026-10-21 audit corrections batch 1 — immutability contradiction resolution (I3/I34) | 2026-10-21 | PROPOSED (mechanics RECOMMENDED_PENDING_VALIDATION) |
| Employee-kind payment vehicle now specified in `features/09` C2/C12/D (PAYROLL_CLEARING debit, never AP; derived-capacity validation; per-employee lock; partial payment + run-reversal guard = recommended, approval pending); replacement runs use derived reversal state (no stored flip); `features/03` C7 payroll role enumeration | 2026-10-21 audit corrections batch 3 — cross-reference alignment (C10/C11/§G/§K/§L) | 2026-10-21 | PROPOSED (policies owner/accountant-pending; D-024 untouched) |

**Gate:** keep DRAFT until **D-024** is decided (blocking — statutory seeding and run posting), O32/O33/O34 and the offline-finalization recommendation are answered, the lifecycle uniqueness mechanics and payment/privacy mechanisms are validated, and the security PoC validates the RPC/RLS model.
