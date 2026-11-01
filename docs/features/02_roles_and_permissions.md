# Feature: الصلاحيات / 02_roles_and_permissions
**Status: DRAFT** | **Version:** 0.4 | **Owner approval:** PENDING | **Last reviewed:** 2026-10-21
**Source:** V2 clean-slate design (no Hasad V1 reuse). Bound by `15_DECISION_LOG.md` (D-004 owner guarantee context, D-020 re-authorization at sync) and `02_REQUIREMENTS_AND_SCOPE.md` (approved shared requirements).
**Evidence labels:** `PROPOSED` unless marked `APPROVED` or `RECOMMENDED_PENDING_VALIDATION`.

## A. Why this feature exists
Defines who can perform which business action inside one company. The **company owner has all business permissions** (owner-approved rule); employees receive **predefined roles** with **individually customizable allow/deny overrides** (owner-approved rule). Client-side checks are UX only; **server-side authorization is mandatory for every protected action**.

## B. Roles and user stories
- **Owner** → full permissions, cannot be denied by overrides, assigns roles and overrides, transfers ownership.
- **Manager/admin (recommended role)** → everything except ownership transfer.
- **Employee** (sales, purchaser, warehouse, cashier, accountant, payroll_officer, auditor — recommended set) → works within role permissions, customized per person.
- Forbidden: any client-supplied role/company/ownership flag being trusted; permission changes without audit; denying the owner.

## C. Business rules and state transitions
- C1 Resolution order (single source of truth, SQL function `has_permission`, STABLE, pinned `search_path`):
  **owner → deny override → allow (role or allow override) → deny-by-default**.
- C2 Owner guarantee: `is_owner AND status='active'` ⇒ allow for every permission code; overrides do not apply to the owner.
- C3 Overrides are per membership and per permission code, `effect ∈ {allow, deny}`; exactly one row per (membership, permission).
- C4 Role assignment and override changes take effect on the **next** server-authorized operation; in-flight single transactions complete under isolation semantics; synchronization re-authorizes every mutation at apply time (D-020 APPROVED).
- C5 Every role or override change writes an audit event (`member.role_changed`, `override.set`, `override.removed`) in the same transaction, through the narrow audit helper — no direct `INSERT` grant on `audit_log` for application roles (see `07_SECURITY`, corrected flaw 1).
- C6 Permission catalogue is a **static seed** changed only by reviewed migrations; module feature specs own their code enumerations.
- C7 **Approved catalogue extension (D-030, 2026-10-28):** `products.read` is an explicit, read-only permission code in module `products`. This approves the code only; it does not approve or assign any role mapping or user override. The original 37 catalogue codes and meanings are unchanged; the proposed total is 38 only after the candidate changes are separately approved and deployed. This feature remains DRAFT and the role-permission matrix remains unapproved.

## D. Data model (PostgreSQL — proposal until approved)
| Table | Purpose | Tenant scope | Key references | Status |
|---|---|---|---|---|
| `roles` | Predefined/custom roles per company; `code`, `is_system` | `company_id NOT NULL` | UNIQUE(company_id, code) | PROPOSED |
| `permissions` | Static catalogue: `code` PK, `module`, `description` | none (global seed) | — | PROPOSED |
| `role_permissions` | Role → permission grants | via role | PK(role_id, permission_code) | PROPOSED |
| `user_permission_overrides` | Per-membership allow/deny | via membership | UNIQUE(membership_id, permission_code) | PROPOSED |

Permission namespaces (categories): `company.*, members.*, roles.*, coa.*, journals.*, fiscal.*, parties.*, cash.*, sales.*, purchases.*, inventory.*, expenses.*, reports.*, payroll.*, products.*`. Owner permissions are not rows; they follow from `is_owner`.

**Permission families adopted from the completed feature specifications (audit batch 3 — catalogue content PROPOSED, owner-pending; no role mapping is approved here):**
- `company.settings`, `company.tax`, `company.numbering` (features/13 B/E); `company.templates` — recorded as a **proposed refinement** (features/13 currently gates template RPCs with `company.settings`; separating template management is a catalogue-pending candidate, not a decided change).
- `payroll.setup`, `payroll.run`, `payroll.reverse`, `payroll.view`, `payroll.payslip` (features/11 B/E).
- `inventory.adjust` (features/08 B — tier owner-pending with this feature).
- `reports.view`, `reports.export` (features/12 B — **explicitly supported by the report specification**: `report_export` RPC + mandatory `report.exported` audit; whether `reports.export` folds into `reports.view` remains owner-pending, features/12 §L).

These codes join the **owner-pending role catalogue (§L)** — this list records what the completed specs use; it does **not** approve preset staff-role mappings or alter the owner-approved resolution model (C1/C2).

**Approved exception to the owner-pending catalogue status:** D-030 explicitly
approves the single `products.read` code. No existing role or user is assigned
that code automatically. Other product permissions and all proposed role
mappings remain unapproved.

## E. RLS / grants / RPCs
- Authorization decisions are made only by server-side functions/RPCs in `hasad_api`; tables live in the private `hasad` schema (RECOMMENDED_PENDING_VALIDATION).
- `has_permission` is the **only** permission-resolution implementation (no duplicated logic in clients).
- RLS uses live membership existence; it does not encode the permission catalogue (row access = company membership; action access = RPC-level `has_permission`).
- Denied by default; `anon` has nothing (details in `07_SECURITY_TENANCY_RLS.md`).

## F. Offline SQLite and synchronization
- The client caches the permission set for **UX gating only** (D-020): it may show a button, but the server re-checks at every apply.
- Offline entry uses last-known permissions; the synchronization step reauthorizes each operation (D-006/D-020); rejection returns typed errors and preserves the pending operation locally.
- Access to local company data expires 24 hours after the last successful server verification (D-020).

## G. Accounting impact (if any)
`No accounting posting` in this feature. Posting RPCs call `has_permission` before writing journals; permission denial must never leave partial financial state (single transaction).

## H. UI and Arabic RTL
Arabic RTL screens: role assignment, per-permission override editor with allow/neutral/deny states (neutral = inherit role), audit history of permission changes. Denial messages explain the next action in domain-safe Arabic ("هذا الإجراء غير مسموح لدورك — راجع مدير الشركة").

## I. API / RPC contract
| RPC | Input | Output | Auth | Audit |
|---|---|---|---|---|
| `member_set_role(p_membership_id, p_role_code)` | ref, role | updated | members.manage (owner/admin) | member.role_changed |
| `member_set_override(p_membership_id, p_permission, p_effect)` | ref, code, allow/deny/null | updated | members.manage | override.set/removed |
| `role_list()` / `permission_catalog()` | — | rows | any active membership | — |
| `has_permission(p_code)` | code | boolean | any active membership (STABLE helper used by all RPCs) | — |

No RPC accepts a client-asserted role or ownership flag. All mutations are single-transaction and idempotency-keyed at the sync layer (D-006/D-018).

## J. Tests and acceptance criteria
Positive: owner passes every sampled permission; override allow elevates a role; override deny blocks a role grant; audit rows for each change; change effective on next operation.
Negative: deny override beats role allow; overrides cannot deny the owner; non-manager calling `member_set_role` ⇒ `PERMISSION_DENIED`; `anon` ⇒ denied; direct table writes on `roles`/`overrides` ⇒ blocked (unexposed schema + grants); **direct `INSERT` on `audit_log` as `authenticated` ⇒ rejected (no grant — helper only)**; **audit helper abused for a foreign company ⇒ rejected (live-membership check)**; permission change racing a concurrent posting ⇒ posting authorized under the pre-change snapshot (documented semantics) and under the new state thereafter.
SQL↔client parity test: client UX gating never substitutes server checks (attempt a denied action with a forged local permission cache ⇒ server rejects).

## K. Rollout and migration
Depends on: membership model (`features/01`), permission namespace ownership per module spec (06–12 pending). Seed `permissions` and the role catalogue in a reviewed migration **only after owner approval** of the role list (section L). Additive; no destructive steps.

## L. Open questions and decisions
- [ ] **Owner decision:** the predefined role catalogue — proposed set RECOMMENDED_PENDING_VALIDATION: `admin`, `accountant`, `sales`, `purchaser`, `warehouse`, `cashier`, `payroll_officer`, `auditor` with the draft scope:
  `admin` = all except ownership transfer; `accountant` = coa/journals/fiscal(no close)/parties/cash/expenses/reports + read of sales/purchases; `sales` = sales, parties(customers), inventory read, cash receipts; `purchaser` = purchases, parties(suppliers), inventory read; `warehouse` = inventory movements/counts + fulfillment reads; `cashier` = cash + expense payments; `payroll_officer` = `payroll.setup/run/reverse/view/payslip` — **HR setup and payroll drafting/calculation are in scope now** (features/11: employees, contracts, component catalogue, run drafts and calculation); only **statutory run posting** is gated by D-024 (features/11 C5 — `STATUTORY_CONFIG_INCOMPLETE` until the owner answers; by design, not a deferral of the role); `auditor` = read-all financial + audit_log; **preset role→permission mappings remain unapproved (audit batch 3 clarification — no silent approval).**
- [ ] Exact permission-code enumeration per module — decided with each feature spec, not here.
- [ ] Whether admin may manage other admins — owner decision.

## M. Source evidence
| Claim | Evidence source | Observed on | Confidence |
|---|---|---|---|
| Owner has all permissions; predefined roles + per-user customization | Owner-approved rules (2026-10-20 session) + `02_REQUIREMENTS_AND_SCOPE.md` | 2026-10-20 | APPROVED (rule), PROPOSED (catalogue) |
| `products.read` as an explicit read-only catalogue code | Owner decision D-030 in `15_DECISION_LOG.md` | 2026-10-28 | **APPROVED (code only); no role/user assignment or RPC approval** |
| Permission families from completed specs (`company.settings/tax/numbering/templates`, `payroll.setup/run/reverse/view/payslip`, `inventory.adjust`, `reports.view/export`); payroll_officer scope clarified — HR setup + drafting in scope, statutory posting gated by D-024 | 2026-10-21 audit corrections batch 3 — features/02 §D/§L alignment with completed feature specs | 2026-10-21 | PROPOSED (owner-pending catalogue; no preset mapping approved) |
| Re-authorization at sync, 24h expiry | `15_DECISION_LOG.md` D-020 | 2026-10-20 | APPROVED decision |
| Resolution algorithm | This spec §C + `07_SECURITY_TENANCY_RLS.md` | 2026-10-20 | PROPOSED |

**Gate:** keep DRAFT until the owner signs the role catalogue and this spec; the role-permission matrix is **not** owner-approved.
