# Feature: دليل الحسابات / 03_chart_of_accounts
**Status: DRAFT** | **Version:** 0.3 | **Owner approval:** PENDING | **Last reviewed:** 2026-10-21
**Source:** V2 clean-slate design (no Hasad V1 reuse). Bound by `15_DECISION_LOG.md` (D-003, D-017, D-019) and the 2026-10-20 accounting planning report.
**Evidence labels:** `PROPOSED` unless marked `OWNER_APPROVED` (by decision ID), `RECOMMENDED_PENDING_VALIDATION`, or `REQUIRES_OWNER_DECISION`.

## A. Why this feature exists
Defines each company's hierarchical chart of accounts (CoA): the classification structure every financial posting depends on. The CoA is **per-company** (tenant-scoped); it provides the account tree, posting eligibility rules, lifecycle states, and the **module-to-account-role mapping** that lets sales/purchases/inventory/cash/expenses/payroll modules post through one shared GL engine without knowing any company's concrete account IDs.

Exclusions: journal mechanics (see `features/04`), fiscal calendars (see `features/04`), report layouts (module 12).

## B. Roles and user stories
- **Owner / `coa.manage` holder** → creates/edits/deactivates accounts, sets parent links, maintains module account mappings.
- **All active members** → read the tree (`coa_tree`); posting modules consume mapped accounts indirectly.
- Forbidden: cross-company account references; editing codes of posted accounts (see O4); creating hierarchy cycles; posting to non-leaf accounts.

## C. Business rules and state transitions
- C1 **Hierarchy:** accounts form a forest (self-FK `parent_id`); every account belongs to exactly one company. **Cycle prevention:** the parent must be in the same company and the create/update RPC rejects any parent that is a descendant of the target (`PARENT_CYCLE`, path check inside the same transaction). RECOMMENDED_PENDING_VALIDATION (path-check implementation).
- C2 **Account types:** `asset | liability | equity | revenue | expense` (`text + CHECK`, consistent with the identity design). Normal balance is **derived** from type (asset/expense = debit; others = credit) and is never stored.
- C3 **Codes:** `UNIQUE(company_id, code)`; code strings are owner-defined. Codes are **immutable once the account has posted journal lines** (enforced server-side); Arabic/English names are editable at any time with an audit event. REQUIRES_OWNER_DECISION (O4 — mutability rule recommended, not yet owner-signed).
- C4 **Posting eligibility (leaf rule):** an account is postable **iff it has no active children**. Eligibility is evaluated live at posting time (no stored `posting_allowed` flag — avoids flag drift). Control accounts (AR/AP) are leaves mapped via `module_account_map`. RECOMMENDED_PENDING_VALIDATION.
- C5 **Lifecycle:** `active ⇄ inactive` (deactivate blocks new postings; history preserved; no hard delete ever). Reactivation allowed. Audit events: `account.created`, `account.updated`, `account.deactivated`, `account.reactivated`, `mapping.changed`.
- C6 **Per-company isolation:** accounts, mappings, and every reference to them are tenant-scoped; composite same-tenant FKs plus RLS (per `07_SECURITY_TENANCY_RLS.md` — itself still DRAFT pending security validation).
- C7 **Module account mapping (aligned audit batch 3):** `(company_id, module, account_role) → account_id` UNIQUE per triple. Posting fails with `MAPPING_MISSING` if a required role is unmapped or mapped to an inactive/non-postable account. **Role families (PROPOSED — accountant-dependent choices remain RECOMMENDED_PENDING_VALIDATION):**
  - **Trade/cash roles:** `AR_CONTROL`, `AP_CONTROL`, `SALES_REVENUE`, `COGS`, `INVENTORY`, `INVENTORY_CONTROL`, `INVENTORY_ADJUSTMENT` (O13), `CASH`, `BANK`, `VAT_OUTPUT`, `VAT_INPUT`, `PURCHASE_CLEARING`, `PURCHASE_PRICE_VARIANCE` (O18), `NONRECOVERABLE_VAT` (O20).
  - **Expense shared roles vs category binding (mechanism per `features/10` C1):** the map resolves per-company **shared** module roles (`VAT_INPUT`, `NONRECOVERABLE_VAT`, default `CASH`/`BANK`) — **per-category accounts are NOT dynamic map roles**; each expense category binds **directly** to its own same-company expense-type leaf account on `expense_categories.account_id` (validated at creation and re-resolved at posting). The alternative (one dynamic map role per category code) is documented, not chosen; both mechanisms remain RECOMMENDED_PENDING_VALIDATION (`features/10` C1).
  - **Payroll roles — core mapping roles vs statutory role names:** core mapping roles used by `features/11` are `PAYROLL_CLEARING` (liability, **employee-dimensioned**), `EMPLOYEE_ADVANCES` (asset) and `SALARY_EXPENSE` (expense; per-component direct bindings coexist). Statutory payable roles exist as **names only** — `INCOME_TAX_WITHHOLDING_PAYABLE`, `SOCIAL_INSURANCE_EMPLOYEE_PAYABLE`, `SOCIAL_INSURANCE_EMPLOYER_PAYABLE` — and are **never seeded until D-024** answers the legislation. **`PAYROLL_CLEARING` must never be mapped to, mixed with, or replaced by an `AP_CONTROL` supplier-payable account** — payroll liabilities are structurally separate from supplier AP (I12/I36 safeguard; a payroll line resolving to `AP_CONTROL` is a template-test failure).
- C8 **Starter chart:** new companies may be seeded from a template chart before first posting; the template is owner-editable afterward. REQUIRES_OWNER_DECISION (template contents depend on O1 statutory layer); RECOMMENDED_PENDING_VALIDATION (seed mechanism).

## D. Data model (PostgreSQL — proposal until approved)
| Table | Purpose | Tenant scope | Key constraints | Status |
|---|---|---|---|---|
| `accounts` | CoA tree nodes | `company_id NOT NULL` | PK UUIDv7 (R-08); `UNIQUE(company_id, code)`; `account_type` CHECK; `parent_id` self-FK with same-company composite FK; `is_active` | PROPOSED |
| `module_account_map` | Module role → account | `company_id NOT NULL` | `UNIQUE(company_id, module, account_role)`; FK account (same company) | PROPOSED |

Deletion policy: accounts are never deleted; deactivate only. Indexes: `(company_id, parent_id)`; `(company_id, code)` unique. Open implementation choices (UUIDv7 site, cycle-check method, template seeding) listed in `05_DATABASE_SCHEMA.md`.

## E. RLS / grants / RPCs
- Private `hasad` schema, RPCs in `hasad_api` (RECOMMENDED_PENDING_VALIDATION — the proposed RPC privilege model has **not** passed security testing; see `07`).
- Grants: `SELECT` on accounts/map for `authenticated`; `INSERT/UPDATE` only via INVOKER RPCs with `coa.manage`; no `DELETE`.
- Mandatory audit events (C5) written through the narrow audit helper (pending validation — corrected flaw 1 in `07`).

## F. Offline SQLite and synchronization
- The client caches a read-only CoA snapshot (`company_id`, code, name, type, parent) for account pickers — UX only.
- CoA edits are online-only operations (no offline account creation): they require fresh server authorization and are never queued in the outbox.
- Cached mappings feed draft document construction offline; the server re-validates every mapping at posting time.

## G. Accounting impact (if any)
`No direct posting` from this feature. It **gates all postings** indirectly: `features/04` posting rule I5 (postable leaf, same company) and C7 mapping resolution are read here. VAT-related roles (`VAT_OUTPUT`/`VAT_INPUT`) exist as role names only — actual rates and statutory treatment remain OPEN (D-023); the approved invoice-level inclusive/exclusive treatment and grouping **by tax rate** with group-total rounding (D-005 OWNER_APPROVED) are consumed by modules 06/07/10 and must not be altered by CoA design.

## H. UI and Arabic RTL
Arabic RTL screens: account tree (expand/collapse, code + Arabic name), account form (code, type, parent picker showing only valid same-company parents), lifecycle toggle with warning that deactivation blocks new postings, module mapping editor grouped by module with per-role selectors. Number/date formats follow tenant settings (approved shared requirement 5). Denial/error messages are domain-safe Arabic (`لا يمكن ربط حساب بابنه`).

## I. API / RPC contract
| RPC | Input | Output | Auth | Audit |
|---|---|---|---|---|
| `coa_account_create(...)` | code, name, type, parent? | account id | `coa.manage` | account.created |
| `coa_account_update(...)` | id, name?, parent? (code only if no posted lines) | — | `coa.manage` | account.updated |
| `coa_account_deactivate/reactivate(id)` | id | — | `coa.manage` | account.deactivated/reactivated |
| `coa_tree()` | — | full tree | any active member | — |
| `module_account_map_set(module, role, account)` | triple | — | `coa.manage` (or `company.settings`) | mapping.changed |

Typed errors: `PARENT_CYCLE`, `CODE_IN_USE`, `ACCOUNT_IN_USE` (code change blocked), `ACCOUNT_INACTIVE`, `ACCOUNT_NOT_POSTABLE`, `MAPPING_MISSING`. All RPCs recheck company membership and permission atomically server-side (approved shared requirement 2; validation pending).

## J. Tests and acceptance criteria
Positive: create 3-level tree; map `SALES_REVENUE`; deactivate blocks posting but keeps history; reactivate restores; rename audited; code change allowed before first posting, rejected after.
Negative: cycle creation (parent = self or descendant) ⇒ `PARENT_CYCLE`; duplicate code in same company ⇒ constraint violation; **same code in a different company is allowed** (isolation proof); account of company B mapped/attached in company A ⇒ same-company FK/RLS rejection; code change on posted account ⇒ `ACCOUNT_IN_USE`; posting to parent/non-postable account ⇒ rejected by `features/04` rule I5; unmapped role at module posting ⇒ `MAPPING_MISSING`; `anon`/`nonsense role` calls ⇒ denied.
SQL↔client parity: cached offline tree never substitutes server validation.
Test only disposable datasets (`13_TEST_STRATEGY.md`).

## K. Rollout and migration
Depends on: identity/authorization foundation (`features/01`/`02`, still DRAFT pending security validation), GL engine (`features/04`). Additive first migration; **no seed of any statutory chart until O1 is answered**; no V1 data migration (D-002).

## L. Open questions and decisions
- [ ] **O1 (REQUIRES_OWNER_DECISION, feeds D-023):** Israeli statutory/accountant requirements — any mandated account structure or minimum accounts for financial statements; the starter-chart template content. We do not assume a government-mandated CoA either way.
- [ ] **O4 (REQUIRES_OWNER_DECISION):** account-code immutability after posting (recommendation: immutable; names always editable).
- [ ] Starter-chart seeding mechanism — RECOMMENDED_PENDING_VALIDATION.
- [ ] Cycle-check and leaf-rule implementation details — RECOMMENDED_PENDING_VALIDATION (pending PoC).
- [ ] Whether `module_account_map` changes require owner-only vs `company.settings` — REQUIRES_OWNER_DECISION (feeds role catalogue).

## M. Source evidence
| Claim | Evidence source | Observed on | Confidence |
|---|---|---|---|
| One company per user; tenant isolation requirement | `15_DECISION_LOG.md` D-003 | 2026-10-20 | OWNER_APPROVED |
| AR/AP derived from posted entries (no stored balances) | `15_DECISION_LOG.md` D-017 | 2026-10-20 | OWNER_APPROVED |
| Posted documents immutable; linked reversals | `15_DECISION_LOG.md` D-019 | 2026-10-20 | OWNER_APPROVED |
| VAT mechanics: optional/configurable, inclusive/exclusive, by-rate grouping | `15_DECISION_LOG.md` D-005 | 2026-10-20 | OWNER_APPROVED (mechanics); rate OPEN → D-023 |
| CoA design, leaf rule, mapping | 2026-10-20 accounting planning report | 2026-10-20 | PROPOSED / RECOMMENDED_PENDING_VALIDATION |
| Mapping alignment: expense-category direct binding (features/10 C1 mechanism); payroll core mapping roles vs statutory role names (D-024-gated); PAYROLL_CLEARING / supplier-AP separation | 2026-10-21 audit corrections batch 3 — C7 alignment with completed feature specs | 2026-10-21 | PROPOSED (mechanisms RECOMMENDED_PENDING_VALIDATION; accountant-dependent choices open) |

**Gate:** keep DRAFT until O1 and O4 are decided and the security validation of the RPC/RLS model completes.
