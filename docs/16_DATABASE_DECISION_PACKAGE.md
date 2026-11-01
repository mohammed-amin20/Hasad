# Hasad ERP V2 — Database Decision Package

**Status:** DRAFT — OWNER DECISION PACKAGE, NOT SQL AUTHORIZATION  
**Date:** 2026-10-26  
**Scope:** Remaining V2 database work after the deployed schema and identity foundations.  
**Evidence:** `OBSERVED` deployment evidence is in `15_DECISION_LOG.md`; all unapproved items below retain their source status.

## 1. Current verified baseline

`VERIFIED` in DEV `sxasnunzspkuwbxiddqd`:

- Private `hasad` and reserved `hasad_api` schemas.
- `hasad.user_profiles`, `hasad.companies`, `hasad.roles`, and
  `hasad.company_memberships`.
- Forced, policy-free RLS and no application grants on those tables.
- CLI migration history reconciled for `20261026000000` and
  `20261026000100`.

No permissions, invitations, audit, application-facing RLS policies, grants,
RPCs, accounting, operational, reporting, or Storage objects are deployed.

## 2. Classification rule

| Class | Meaning | Implementation handling |
|---|---|---|
| A — Approved requirement | Owner decision already fixes the business outcome | May be used as a constraint on a future approved SQL contract. |
| B — Safe technical detail | Does not select a business outcome or broaden access | Use standard PostgreSQL implementation once its table/RPC contract is approved. |
| C — Material decision | Changes business lifecycle, legal/accounting treatment, authorization, or security boundary | Requires owner approval and, where noted, a security/accounting PoC before SQL deployment. |

## 3. A — Approved requirements that bind future migrations

| Area | Approved requirement | Source |
|---|---|---|
| Tenancy | One company per user; server derives company from verified active membership | D-003; D-020; R-03 requirement |
| Access | Owner has full business permissions; staff roles can have per-user overrides | D-004; `features/02` C1–C3 |
| Identity baseline | Four-table identity contract with default-deny forced RLS | Owner decisions recorded 2026-10-26 |
| Accounting | ILS; final amounts 2dp HALF_UP; Jan–Dec monthly fiscal year; strict close/audited reopen; configurable VAT mechanics | D-005 |
| Offline | Pending offline operations are server-validated and posted in transaction order; no client-issued official numbers | D-006; D-018 |
| Financial history | Posted records immutable; corrections are linked reversals or notes | D-019 |
| Inventory | Moving weighted average; no negative stock | D-014 |
| Parties | One party model; AR/AP remain distinct | D-016; D-017 |
| Payroll | Payroll is MVP scope; statutory values are not assumed | D-015; D-024 |
| Migration safety | Forward-only additive migrations; no destructive SQL without separate approval | D-012; `11_MIGRATION_AND_RESET_PLAN.md` |

## 4. B — Safe implementation choices once the relevant contract is approved

These do not authorize a table or RPC on their own.

1. Use forward-only timestamped migrations in `supabase/migrations/`; preflight
   catalog state and verify actual deployment after each migration.
2. Keep V2 tables in `hasad`; reserve `hasad_api` for a later approved RPC
   surface. Do not expose either schema through PostgREST in the meantime.
3. Use named primary, foreign-key, unique, CHECK, and index constraints so
   deployment verification can be catalog-based and fail closed.
4. Index every foreign-key access path used by approved queries, and enforce
   same-company relationships with composite keys where a child has a
   tenant-scoped reference.
5. Before application access is approved, use `ENABLE` + `FORCE ROW LEVEL
   SECURITY`, create no policies, and grant no application privileges. This
   is a deliberate default-deny staging state, not a substitute for the PoC.
6. Use `ON DELETE RESTRICT` for retained business history where the owner has
   approved no hard-delete lifecycle; never introduce `CASCADE` as a shortcut.
7. Use explicit transaction-scoped locking only inside approved concurrency
   contracts; do not add generic `SECURITY DEFINER` helpers or role ownership
   changes without the security decision below.

## 5. C1 — Permission model and tenant-isolation security PoC

### Decisions required

1. **Permission catalogue:** approve the exact permission codes and whether
   `reports.export` is separate from `reports.view`; approve the final tiers
   for `inventory.adjust`, module-account-map changes, and whether an admin
   manages another admin.
2. **Predefined roles:** approve the staff-role set and each role→permission
   mapping. The documented candidate (`admin`, `accountant`, `sales`,
   `purchaser`, `warehouse`, `cashier`, `payroll_officer`, `auditor`) is a
   recommendation only.
3. **Security PoC contract:** approve a disposable-target PoC that proves the
   exact policy/grant matrix with real JWTs: `anon` denial; active-member
   same-company access only; cross-company denial; suspended/revoked denial;
   no direct writes; no direct financial reads; no search-path bypass.
4. **RPC execution model:** choose, per approved RPC, INVOKER with enumerated
   table grants or the narrowly reviewed DEFINER alternative. A DEFINER helper
   requires a locked non-superuser owner, pinned search path, and explicit
   tests; no such role/function exists today.

### Recommended default

Approve an RPC-only application surface: no direct application table grants;
`anon` receives nothing; default to `SECURITY INVOKER` only where the exact
per-RPC privileges are enumerated and PoC-tested. Defer any DEFINER helper
until the locked-role feasibility test passes.

### Blocked migrations

- `permissions`, `role_permissions`, `user_permission_overrides`.
- `has_permission` and all application-facing RLS policies/grants/RPCs.

## 6. C2 — Invitations, membership lifecycle, and audit infrastructure

### Decisions required

1. Invitation identity rule: exact verified-email claim behavior.
2. Invitation TTL value and global-vs-per-company pending invitation scope.
3. Audit write path: approved locked-role DEFINER helper or explicitly accepted
   INSERT-only fallback with its spoofing residual risk.
4. Company/membership ownership operations: approve the concurrency contract
   that combines atomic creation, per-company lock, deferred last-owner check,
   no-delete policy, and required tests.

### Recommended default

Use a global pending-invitation uniqueness rule; require verified email; use a
seven-day TTL; retain revoked memberships; and adopt the narrow audit helper
only after the non-superuser ownership PoC succeeds. Do not deploy an audit
fallback before that result.

### Blocked migrations

- `company_invitations`, `audit_log`, ownership protection triggers, invitation
  acceptance/member-management RPCs.

## 7. C3 — Accounting, configuration, and operational modules

| Bundle | Material decisions required | Recommended defaults already documented |
|---|---|---|
| CoA / fiscal / numbering | O1–O6; account mapping authority; O30/O31 | owner-only audited reopen; accrual basis; immutable posted account codes; `PREFIX-YYYY-NNNN`; historical legal snapshot |
| VAT / legal | D-023; Israeli tax-ID validation policy | Tax ID stored as text without a compliance CHECK until legal rules are approved |
| Parties / cash | O7–O10 | Manual bank entry; reference-only tender fields; unapplied overpayment credits; no automatic cash variance posting |
| Inventory | O11–O13; R-07 precision proof; D-025 display rule | Original issue cost for returns; company-wide moving average; reject negative counts for investigation |
| Sales / purchases | O14–O22 | Clearing-account receipts; linked cash payment/allocation; number quotes/orders at creation; defer standalone goods issue and landed cost; variance account treatment |
| Expenses | O23, O24, O28, O29 | No approval workflow; online-only Storage attachment; employee-as-party reimbursement; purchases own supplier-invoiced goods costs |
| Payroll | D-024; O32–O34; payroll role mapping | No leave/attendance module; no employee self-service; no advance deduction cap until statutory rules |
| Reporting / sync | O25–O27; R-04 validation; report export permission | 0–30/31–60/61–90/90+ aging; no v1 cash-flow statement; manual stale-draft reconciliation |

No table/RPC migration in this bundle is independently deployable before C1
and its own listed business/accounting decisions: every authoritative action
requires the permission, tenant-isolation, posting, and audit boundary.

## 8. Deployment sequence after approvals

1. Run the approved security PoC on a disposable target; record executable
   results and select the exact RPC/grant model.
2. Deploy the permission and override tables with the approved static catalogue
   and still-default-deny access until their RPC contract passes the PoC.
3. Deploy invitation/audit lifecycle only with the selected audit mechanism.
4. Deploy CoA/fiscal/numbering before every posting-dependent module.
5. Deploy parties, containers, inventory, trade, cash, expenses, payroll,
   reporting, and sync only in their validated dependency order.

## 9. Owner approval response format

Approve or amend bundles `C1`, `C2`, and the applicable rows of `C3` as a
single decision record. Each accepted bundle must state whether the documented
recommended defaults are adopted. Approval does not authorize a migration until
the corresponding table/RPC definitions and PoC evidence are marked approved.

## 10. C1 + C2 implementation-ready approval contract

This section records the C1 and C2 approval block. The owner approved §11 on
2026-10-26 for preparing and deploying the default-deny structural permissions
foundation. Implementation-status labels below remain authoritative: approved
contract values are not evidence that a role row, mapping, policy, grant, or RPC
has been deployed.

### 10.1 Permission catalogue and roles

| Item | Status | Contract / recommendation |
|---|---|---|
| Owner allowance | **APPROVED** | An active `is_owner=true` membership allows every catalogue code. Owner overrides never deny the owner. |
| Override precedence | **PROPOSED** | Resolve one code as: active owner allow → membership deny override → role grant or membership allow override → deny. Inactive, suspended, revoked, or missing membership denies. |
| Override storage | **PROPOSED** | One `allow` or `deny` row per `(membership_id, permission_code)`; removing the row means inherit. |
| Catalogue mutation | **PROPOSED** | Catalogue rows are seeded/changed only by reviewed migrations; no application write path. |
| Staff role names | **PROPOSED** | `admin`, `accountant`, `sales`, `purchaser`, `warehouse`, `cashier`, `payroll_officer`, `auditor`. |
| `members.manage` | **PROPOSED** | Include this documented RPC-gate code in the catalogue. It covers invites, suspension, activation, revocation, role assignment, and overrides; ownership transfer stays owner-only and is not delegated by this code. |
| Auditor audit-log read | **CONFLICT** | The documented auditor description includes audit-log access, but no `audit.*` permission code exists. Recommendation: defer audit-log read RPCs and grant the auditor only `reports.view` until an exact audit-read code and privacy contract are approved. |
| Sales receipt authority | **CONFLICT** | The candidate sales role includes cash receipts, but `cash.post` is not receipt-specific. Recommendation: do not map `cash.post` to `sales` until the owner approves a scoped receipt code or explicitly accepts broad cash-post authority. |
| Fine-grained read permissions | **PARTIALLY APPROVED — D-030** | `products.read` is an explicitly named, read-only catalogue extension. Other unnamed read permissions remain unspecified; do not add implicit codes or assign `products.read` to roles/users automatically. |

#### Original approved 37-code catalogue (deployed DEV baseline)

The following are the documented action-code vocabulary plus documented
`members.manage`; event names are excluded. This is the original owner-approved
37-code set and remains the deployed DEV catalogue until a separately approved
migration is applied. No role rows or role mappings were seeded by this
catalogue migration.

```text
members.manage
company.settings, company.tax, company.numbering, company.templates
coa.manage
journals.create, journals.post, journals.reverse
fiscal.manage, fiscal.close
parties.manage
cash.create, cash.post, cash.allocate, cash.reconcile, cash.manage
sales.create, sales.post, sales.reverse
purchases.create, purchases.post, purchases.reverse
inventory.manage, inventory.post, inventory.adjust
expenses.create, expenses.post, expenses.reverse, expenses.manage
reports.view, reports.export
payroll.setup, payroll.run, payroll.reverse, payroll.view, payroll.payslip
```

#### Approved catalogue extension — `products.read` (D-030)

The owner approved `products.read` as one explicit, read-only permission code in
module `products`. The original 37 codes and their meanings are unchanged. The
recorded DEV catalogue remains **37** while the review candidate is not
deployed; the proposed catalogue after its changes are separately approved and
deployed would contain **38** codes (the original 37 plus this extension). This
decision approves the code only: it assigns `products.read` to no existing role
or user and does not approve the candidate RPC, its grants/security design, or
DEV deployment.

#### Proposed predefined role mappings

| Role | Status | Proposed mapping |
|---|---|---|
| `admin` | **PROPOSED** | Every catalogue code except `fiscal.close`; ownership transfer remains owner-only. |
| `accountant` | **PROPOSED** | `coa.manage`, `journals.*`, `fiscal.manage`, `parties.manage`, `cash.*`, `expenses.*`, `reports.view`, `reports.export`; no ownership transfer. |
| `sales` | **PROPOSED / CONDITIONAL** | `sales.*`, `parties.manage`; no `cash.post` until the sales-receipt conflict above is resolved. |
| `purchaser` | **PROPOSED** | `purchases.*`, `parties.manage`; no cash, accounting, or inventory-adjust authority. |
| `warehouse` | **PROPOSED / CONDITIONAL** | `inventory.manage`, `inventory.post`; `inventory.adjust` only if the owner approves its tier. |
| `cashier` | **PROPOSED** | `cash.create`, `cash.post`, `cash.allocate`, `cash.reconcile`, `cash.manage`; no journal, CoA, or ownership authority. |
| `payroll_officer` | **PROPOSED** | `payroll.setup`, `payroll.run`, `payroll.reverse`, `payroll.view`, `payroll.payslip`; statutory posting still fails until D-024 configuration exists. |
| `auditor` | **PROPOSED / LIMITED** | `reports.view` only until audit-read and sensitive-data contracts are approved. |

### 10.2 C1 security and application-RPC contract

| Item | Status | Contract / recommendation |
|---|---|---|
| Private schemas | **APPROVED** | Tables remain in `hasad`; `hasad_api` remains unexposed until separately configured and reviewed. |
| Anonymous access | **APPROVED REQUIREMENT** | `anon` receives no table or RPC access. |
| Default deny | **DEPLOYED / VERIFIED** | Existing identity and permission tables retain forced RLS, zero policies, and no application grants. |
| Application surface | **PROPOSED** | RPC-only; no direct application table grants. Every protected RPC derives membership from `auth.uid()` and validates the action through one `has_permission` resolver. |
| Security mode | **PROPOSED** | Prefer `SECURITY INVOKER`, pinned `search_path`, schema-qualified SQL, explicit per-function grants. Any DEFINER function is deferred to the audit PoC. |
| PoC target | **PROPOSED** | Disposable Supabase project only; never the shared DEV project. |

**Required PoC tests (all must pass before application grants/policies/RPCs):**

1. `anon` cannot call any RPC or access any table.
2. Active member A can reach only A’s company through an approved RPC.
3. Active member A cannot read/write company B, including forged company IDs.
4. Suspended/revoked members are denied on the next RPC call.
5. Direct `authenticated` table reads/writes remain denied.
6. Owner allow, deny override, allow override, and default deny resolve exactly as
   specified; owner override denial is ineffective.
7. `PUBLIC` has no accidental EXECUTE grant; pinned search paths prevent object
   shadowing.
8. Membership/permission mutations racing a protected operation follow the
   documented transaction snapshot and reauthorization rule.

### 10.3 C2 invitation, ownership, and audit contract

| Item | Status | Contract / recommendation |
|---|---|---|
| Invitation is not membership | **APPROVED REQUIREMENT** | A pending invitation never supplies access; acceptance inserts the membership atomically. |
| Token persistence | **APPROVED REQUIREMENT** | Store only a unique hash; raw token is returned/delivered once and never logged or stored. |
| Invitation states | **PROPOSED** | `pending`, `accepted`, `revoked`, `expired`; acceptance is one-way from `pending`. |
| Email verification | **APPROVED (2026-10-27)** | At acceptance, read the current `auth.uid()` server-side from `auth.users`; require non-null `email_confirmed_at`; compare invitation and Auth emails with `LOWER(BTRIM(email))`; reject missing, empty, unverified, or mismatched values. Do not apply provider-specific normalization. Client email, `user_metadata`, and unverified JWT email claims are never authoritative. No direct `auth.users` access is granted to application roles; the narrow mechanism remains subject to the hosted PoC. |
| TTL | **PROPOSED** | Seven days from creation; `expires_at NOT NULL`; expiry rejects acceptance with `INVITATION_EXPIRED`. |
| Pending uniqueness | **PROPOSED** | Global unique `lower(email)` only while `status='pending'`; expired/revoked rows no longer block a replacement invitation. |
| Acceptance concurrency | **PROPOSED** | Lock invitation row with `FOR UPDATE`, then validate pending/expiry/identity, insert membership, and mark accepted. `UNIQUE(user_id)` remains the final one-company guard. |
| Ownership safety | **PROPOSED** | `company_create` atomically creates the company and active owner membership; all owner/status mutations take a per-company transaction advisory lock plus a deferred last-active-owner check; no application deletion path. |
| Audit model | **APPROVED REQUIREMENT** | Mandatory semantic audit events are append-only and actor/company/time/reference bound; application roles have no direct audit insert. |
| Audit writer | **PROPOSED** | Narrow `SECURITY DEFINER` helper, locked non-superuser owner, pinned search path, fixed insert shape, `auth.uid()` actor derivation, and live company-membership check. If this cannot be proven on a disposable target, stop; do not silently use the INSERT-only fallback. |

**Required C2 PoC tests:** verified/mismatched email; expired/replayed token;
global pending collision; concurrent acceptance; duplicate membership; owner creation
rollback; dual-owner concurrent revoke; sole-owner suspension; audit helper foreign
company attempt; direct audit insert/update/delete denial; helper owner is not a
superuser; raw invitation token absent from database/audit output.

### 10.4 Structural migration eligibility

| Structural object | Eligibility before C1/C2 approval | Reason |
|---|---|---|
| `permissions`, `role_permissions`, `user_permission_overrides` | **DEPLOYED / VERIFIED** | Table shape, constraints, indexes, and default-deny RLS were deployed by `20261026000200_v2_permissions_foundation.sql`; the 37-code catalogue was deployed by `20261026000210_v2_permission_catalogue_seed.sql`. Post-deploy catalog verification is recorded in `docs/15_DECISION_LOG.md`. Application policies, grants, functions, triggers, and RPCs remain blocked pending the C1/C2 PoC. |
| `company_invitations` | **DEPLOYED / VERIFIED — STRUCTURE ONLY** | `20261027000300_v2_invitation_audit_structure.sql` deployed to DEV on 2026-10-27. Token lifecycle, expiry behavior, acceptance, grants/policies/RPCs, and hosted-PoC gates remain unresolved and absent. |
| `audit_log` | **DEPLOYED / VERIFIED — STRUCTURE ONLY** | The same migration deployed only the default-deny table shape. Append-only enforcement, action/payload registry, helper ownership, grants/policies/RPCs, and hosted-PoC gates remain unresolved and absent. |
| Ownership triggers/RPCs | **BLOCKED** | Requires the approved concurrency and audit implementation plus PoC evidence. |

Beyond the prepared invitation/audit review artifact, no new default-deny
structural table is sufficiently specified to migrate. The deployed identity and
permission tables remain the only deployed safe subset; the prepared invitation
and audit tables, plus all application-facing objects, remain blocked from DEV
deployment.

## 11. OWNER APPROVAL BLOCK — C1 + C2

**Status:** OWNER-APPROVED (2026-10-26) — the two prepared structural migrations
were deployed and verified. The application surface remains gated: no grant,
policy, function, trigger, RPC, role row, or role mapping in this block has been
deployed, and the C1/C2 PoC remains mandatory before any application-facing
surface is introduced.

> **Owner-approved on 2026-10-26 for the default-deny structural deployment.
> The clauses below remain the approved contract; application-facing deployment
> is still gated by the C1/C2 PoC.**
>
> 1. Adopt the original static permission catalogue (37 codes; no implicit read
>    codes):
>
>    ```text
>    members.manage
>    company.settings, company.tax, company.numbering, company.templates
>    coa.manage
>    journals.create, journals.post, journals.reverse
>    fiscal.manage, fiscal.close
>    parties.manage
>    cash.create, cash.post, cash.allocate, cash.reconcile, cash.manage
>    sales.create, sales.post, sales.reverse
>    purchases.create, purchases.post, purchases.reverse
>    inventory.manage, inventory.post, inventory.adjust
>    expenses.create, expenses.post, expenses.reverse, expenses.manage
>    reports.view, reports.export
>    payroll.setup, payroll.run, payroll.reverse, payroll.view, payroll.payslip
>    ```
>
>    **Later extension — D-030 (2026-10-28):** the owner explicitly approved
>    `products.read` as one read-only catalogue code in module `products`. This
>    leaves the original 37 codes and meanings intact. DEV remains at 37 until
>    the candidate changes are separately approved and deployed; the proposed
>    post-migration catalogue would contain 38. No role mapping or user override
>    is approved or assigned by this decision.
>
> 2. Adopt exactly these predefined staff roles and mappings. Owner access is
>    implicit for every catalogue code; ownership transfer is owner-only and is
>    not delegated by any catalogue code.
>
>    | Role | Granted codes |
>    |---|---|
>    | `admin` | Every listed code except `fiscal.close`; ownership transfer remains owner-only. |
>    | `accountant` | `coa.manage`, `journals.create`, `journals.post`, `journals.reverse`, `fiscal.manage`, `parties.manage`, `cash.create`, `cash.post`, `cash.allocate`, `cash.reconcile`, `cash.manage`, `expenses.create`, `expenses.post`, `expenses.reverse`, `expenses.manage`, `reports.view`, `reports.export`. |
>    | `sales` | `sales.create`, `sales.post`, `sales.reverse`, `parties.manage`. **No `cash.post`.** |
>    | `purchaser` | `purchases.create`, `purchases.post`, `purchases.reverse`, `parties.manage`. |
>    | `warehouse` | `inventory.manage`, `inventory.post`. **No `inventory.adjust`.** |
>    | `cashier` | `cash.create`, `cash.post`, `cash.allocate`, `cash.reconcile`, `cash.manage`. |
>    | `payroll_officer` | `payroll.setup`, `payroll.run`, `payroll.reverse`, `payroll.view`, `payroll.payslip`; statutory posting still requires the D-024 gate. |
>    | `auditor` | `reports.view` only. **No audit-log read and no payroll detail.** |
>
> 3. Adopt resolution semantics: active owner allow → explicit membership deny
>    override → role grant or explicit membership allow override → deny. There
>    is at most one override per `(membership, permission)`; removing it means
>    inherit. Missing, suspended, or revoked memberships always deny. The
>    following guards apply before any authorization RPC is exposed:
>    (a) `fiscal.close` is never granted by a role or an allow override; only an
>        active owner passes;
>    (b) `inventory.adjust` allow-overrides are rejected; only an active owner
>        or a membership whose role is `admin` may hold it;
>    (c) a `sales` membership never holds `cash.post`, including through an
>        allow override;
>    (d) only the owner may change the role or overrides of an owner or another
>        `admin`; admin-manages-admin remains unapproved.
>
> 4. Adopt the C1 security boundary: RPC-only application access; no direct
>    application table grants; `anon` denied; no implicit master-data access;
>    `hasad` remains unexposed. The owner confirmed `hasad_api` is exposed in
>    PostgREST on 2026-10-28; exposure alone does not grant access to any
>    function. `SECURITY INVOKER`, pinned search path, schema-qualified
>    references, and explicit per-function grants are the default. No DEFINER
>    function is deployed before its PoC and separate approval.
>
> 5. Authorize the disposable-target C1 PoC and require every §10.2 test to
>    pass before any application-facing policy, grant, RPC, or privilege is
>    deployed to DEV.
>
> 6. Adopt C2 invitation behaviour: states are
>    `pending|accepted|revoked|expired`; only a token hash is stored; raw token
>    is delivered once and never logged; expiry is seven days; pending
>    invitations are globally unique by case-folded email; acceptance locks the
>    invitation row, requires verified matching identity email, creates the
>    membership, and relies on `UNIQUE(user_id)` as final arbitration.
>
> 7. Adopt ownership safety: company creation atomically creates its active
>    owner membership; owner/status mutation uses a per-company advisory lock
>    plus deferred last-active-owner validation; application deletion of company
>    or membership rows is not permitted.
>
> 8. Adopt audit option A only: a narrow DEFINER audit helper owned by a locked
>    non-superuser, with pinned search path, actor derivation from `auth.uid()`,
>    and live membership validation. If the C2 PoC cannot prove that boundary,
>    halt invitation/audit rollout. Do not enable the INSERT-only fallback
>    without a separate owner decision.

### 11.1 Contradiction audit of the original 37 codes, eight mappings, and D-030

The deployed seed contains the original 37 unique codes and the original eight
proposed staff-role mappings. D-030 approves one additional catalogue code for
a proposed total of 38 after migration; it does not change any mapping. The
original mapping checks remain: every mapping entry resolves to an original
catalogue code, no role receives an out-of-catalogue code, and `fiscal.close`,
`inventory.adjust`, and `cash.post` remain absent where the owner direction
forbids them.

The following non-mechanical findings are resolved by clause 3 or remain
explicitly owner-pending:

| # | Finding | Status | Resolution in this block |
|---|---|---|---|
| 1 | `members.manage` (held by `admin`) can write an allow-override for `fiscal.close`, which would defeat owner-only closing | **CONFLICT → RESOLVED** | Clause 3(a): `fiscal.close` is never overridable and never role-granted. |
| 2 | `admin` holds `members.manage` and `inventory.adjust`, so it could allow-override `inventory.adjust` for `warehouse`, defeating the owner/admin tier | **CONFLICT → RESOLVED** | Clause 3(b): allow-overrides for `inventory.adjust` are rejected. |
| 3 | `admin` holds `cash.post`, so it could allow-override `cash.post` for `sales`, defeating the owner direction | **CONFLICT → RESOLVED** | Clause 3(c): a `sales` membership never holds `cash.post`. |
| 4 | `admin` holds `members.manage`; features/02 leaves “may an admin manage another admin?” open | **UNSPECIFIED → CONSERVATIVE DEFAULT** | Clause 3(d): only the owner may change an owner or admin membership. |
| 5 | `sales` and `purchaser` both receive `parties.manage`, but the draft role scope says customers and suppliers respectively; no scoped code exists | **COARSE-GRANT GAP — OWNER DECISION** | Keep the single documented code for v1 with mandatory audit, or withhold it from both roles until scoped codes are approved. No new code is invented. |
| 6 | Draft `cashier` scope mentions expense payments, but the mapping contains no `expenses.*` code | **SCOPE REDUCTION — OWNER DECISION** | Default: cashier operates the cash module only; expense posting stays with `accountant`/`admin`. |
| 7 | Draft `accountant` scope says “read of sales/purchases”, but no corresponding codes exist | **NO IMPLICIT CODE** | `products.read` is the only explicitly approved read-code extension (D-030); sales/purchases read codes and RPCs remain unspecified and require separate approval. |
| 8 | Draft `auditor` scope includes audit-log access, but the owner direction restricts it to `reports.view` | **OWNER-RESTRICTED** | Deliberate; no audit-read permission or privacy contract exists. |

### 11.2 Artifacts and deployment state

| Artifact | Contents | Deployment state |
|---|---|---|
| `supabase/migrations/20261026000200_v2_permissions_foundation.sql` | `hasad.permissions`, `hasad.role_permissions`, `hasad.user_permission_overrides`; 4 restrictive FKs; 2 non-unique FK indexes; forced RLS; zero policies/grants/functions/triggers/rows | **DEPLOYED / VERIFIED** (2026-10-26) |
| `supabase/migrations/20261026000210_v2_permission_catalogue_seed.sql` | Exactly the 37 catalogue rows; no role rows and no role mappings (roles are company-scoped) | **DEPLOYED / VERIFIED** (2026-10-26) |
| `security/candidates/20261029001100_v2_company_product_access.sql` | Review-only forward migration candidate; adds the D-030 `products.read` catalogue row and company/product RPC security objects; no role/user assignment | **REVIEW ONLY / NOT DEPLOYED**; proposed catalogue total would be 38 only after separate approval and deployment |
| `scripts/security/poc_c1_c2_default_deny.sql` | Read-only, target-guarded baseline assertions for the disposable PoC | **LOCAL DISPOSABLE HARNESS — PASS** (2026-10-26); not a Supabase-service proof |
| `scripts/security/poc_c1_c2_real_jwt.md` | Real-JWT tenant-isolation matrix and run prerequisites | **LOCAL CLAIM-SIMULATION / TEST-ONLY RPC HARNESS — PASS** (2026-10-26); **REAL SUPABASE JWT EXECUTION — BLOCKED** |
| `scripts/deploy/deploy_v2_permissions_foundation.ps1` | Fail-closed CLI apply: local static checks, read-only catalog/history preflight, `migration list`, dry-run, push of only the two versions, post-deploy verification | **PREPARED — NOT RUN; direct CLI push used instead** |
| `supabase/migrations/20261027000300_v2_invitation_audit_structure.sql` | Only `hasad.company_invitations` and `hasad.audit_log`; 7 restrictive FKs; 5 indexes; forced RLS; zero policies/grants/functions/triggers/rows | **DEPLOYED / VERIFIED** (2026-10-27) |
| `scripts/security/validate_v2_c2_structure.ps1` | Static no-surface scan plus fresh-local-PostgreSQL catalog validation for the prepared C2 migration | **VERIFIED LOCALLY** (2026-10-27) |

Deployment note: the two migrations were applied on 2026-10-26 with
`supabase db push --linked --skip-vault --yes` (exit `0`) after the dry-run
listed exactly them. The prepared PowerShell wrapper was not used. Full
preflight and post-deploy catalog evidence is recorded in
`docs/15_DECISION_LOG.md`.

### 11.3 Local isolated C1/C2 PoC evidence (not the Supabase release gate)

The reproducible local PostgreSQL 17 harness ran on 2026-10-26 with no
connection to DEV. It created a fresh cluster under the approved temporary path,
applied the four deployed migrations, ran the target-guarded default-deny
baseline, installed a **test-only** RPC surface and fixtures, and destroyed the
cluster after the run. Evidence is retained at
`local_audit/C1_C2_LOCAL_POC_20261026_223540.log`.

The harness passed 36 cases: anonymous RPC/table denial; direct authenticated
table read/write denial; same-company success; cross-company denial; suspended
and revoked denial; owner allowance; deny and allow override precedence; default
deny; the `fiscal.close`, `inventory.adjust`, and `sales`/`cash.post` guards;
test write authorization; an append-only audit helper with foreign-company
denial; no direct audit mutation; pinned search-path resistance; no `PUBLIC`
execute on the test RPCs; and a locked non-superuser `SECURITY DEFINER` owner.

**Limitations / status:** this is a PostgreSQL-mechanics proof only. The local
auth stub supplied `request.jwt.claims`; it did not validate a Supabase-issued,
signed JWT or exercise Supabase Auth, PostgREST, transaction pooling, or actual
Supabase role ownership. The test schemas/functions/fixtures were never applied
to DEV and do not authorize any DEV policy, grant, function, trigger, role row,
role mapping, or RPC. The real-JWT matrix remains a mandatory disposable-Supabase
release gate before any application-facing surface.

Implementation note: `role_permissions.role_id` uses `ON DELETE RESTRICT`
instead of the illustrative “cascade with unassigned role” in
`docs/05_DATABASE_SCHEMA.md`. No role-delete lifecycle is approved, and the
workspace forbids `CASCADE` shortcuts; this is recorded as a documentation
deviation, not a new business rule.

### 11.4 Consolidated invitation/audit implementation decision package — OPEN

No invitation, audit, ownership-safeguard, policy, grant, or RPC migration is
eligible until the following exact contracts are approved and then proven on a
disposable Supabase project. The local proof in §11.3 does not settle them.

1. **RESOLVED — verified-email authority (2026-10-27):** read
   `auth.users.email` server-side for current `auth.uid()`; require
   `auth.users.email_confirmed_at IS NOT NULL`; compare exactly with
   `LOWER(BTRIM(email))`; reject missing, empty, or mismatched values; do not
   perform provider-specific normalization; and never trust client email,
   `user_metadata`, or unverified JWT email claims. The hosted PoC must still
   prove the narrow internal access boundary without application-role access to
   `auth.users`.
2. **Invitation row contract:** approve every column, type, nullability,
   default, FK/action, status-transition/error contract, token-hash algorithm
   and encoding, acceptance stamps, revocation/expiry actor stamps, and indexes
   for `company_invitations`. The high-level requirements remain: only a unique
   token hash is stored, seven-day expiry, global pending-email uniqueness, and
   row-locked one-time acceptance.
3. **Audit-event row contract:** approve the exact `audit_log` columns, action
   vocabulary/validation, entity/reference representation, details-payload
   limits/redaction, retention, and read/privacy boundary. `auditor` remains
   `reports.view` only; no audit-read permission is implied.
4. **Actual Supabase helper ownership:** prove on the disposable Supabase target
   that a locked non-superuser function owner can be provisioned and retained,
   owns only the narrow helper, has a pinned search path, cannot bypass the
   intended checks, and exposes no `PUBLIC` or `anon` execute path. The local
   feasibility result does not prove managed-Supabase role administration.
5. **Ownership/membership mutation surface:** approve the exact company-create,
   invitation-create, invitation-accept, revoke, suspend, activate, role-change,
   and override-change RPC contracts and typed errors. Each owner/status mutation
   must take the approved per-company transaction lock and preserve the final
   active-owner invariant under the two-session concurrency test.
6. **Disposable Supabase real-JWT execution:** provide an isolated Supabase
   target and authorization to create disposable test identities/fixtures there.
   The matrix must use real issued tokens, capture only pseudonymous identifiers
   and HTTP/result counts, and pass every §10.2/§10.3 case before any DEV
   application-facing deployment.

### 11.5 SQL-ready C2 draft proposal — PROPOSED, NOT MIGRATION-AUTHORIZED

This section records the C2 structural candidate contract. The owner approved
and deployed only the two default-deny table shapes in §11.5.1 and §11.5.3 via
`20261027000300_v2_invitation_audit_structure.sql` on 2026-10-27. The remaining
token/lifecycle, internal-role, trigger, and RPC mechanisms are still proposed;
the hosted PoC remains mandatory before any application-facing policy, grant,
function, trigger, or RPC.

#### 11.5.1 Candidate invitation structure

```sql
CREATE TABLE hasad.company_invitations (
  id uuid PRIMARY KEY,
  company_id uuid NOT NULL
    REFERENCES hasad.companies(id) ON DELETE RESTRICT,
  role_id uuid NOT NULL,
  email text NOT NULL,
  token_hash bytea NOT NULL,
  status text NOT NULL DEFAULT 'pending',
  expires_at timestamptz NOT NULL,
  invited_by uuid NOT NULL
    REFERENCES hasad.user_profiles(id) ON DELETE RESTRICT,
  created_at timestamptz NOT NULL DEFAULT now(),
  accepted_by uuid NULL
    REFERENCES hasad.user_profiles(id) ON DELETE RESTRICT,
  accepted_at timestamptz NULL,
  revoked_by uuid NULL
    REFERENCES hasad.user_profiles(id) ON DELETE RESTRICT,
  revoked_at timestamptz NULL,
  expired_at timestamptz NULL,
  CONSTRAINT company_invitations_company_role_fkey
    FOREIGN KEY (company_id, role_id)
    REFERENCES hasad.roles(company_id, id) ON DELETE RESTRICT,
  CONSTRAINT company_invitations_email_normalized_check
    CHECK (email = LOWER(BTRIM(email)) AND email <> ''),
  CONSTRAINT company_invitations_token_hash_length_check
    CHECK (octet_length(token_hash) = 32),
  CONSTRAINT company_invitations_status_check
    CHECK (status IN ('pending', 'accepted', 'revoked', 'expired')),
  CONSTRAINT company_invitations_expires_after_create_check
    CHECK (expires_at > created_at),
  CONSTRAINT company_invitations_terminal_stamp_check
    CHECK (
      (status = 'pending'
       AND accepted_by IS NULL AND accepted_at IS NULL
       AND revoked_by IS NULL AND revoked_at IS NULL AND expired_at IS NULL)
      OR (status = 'accepted'
          AND accepted_by IS NOT NULL AND accepted_at IS NOT NULL
          AND revoked_by IS NULL AND revoked_at IS NULL AND expired_at IS NULL)
      OR (status = 'revoked'
          AND accepted_by IS NULL AND accepted_at IS NULL
          AND revoked_by IS NOT NULL AND revoked_at IS NOT NULL AND expired_at IS NULL)
      OR (status = 'expired'
          AND accepted_by IS NULL AND accepted_at IS NULL
          AND revoked_by IS NULL AND revoked_at IS NULL AND expired_at IS NOT NULL)
    )
);

CREATE UNIQUE INDEX company_invitations_token_hash_key
  ON hasad.company_invitations (token_hash);
CREATE UNIQUE INDEX company_invitations_pending_email_key
  ON hasad.company_invitations ((LOWER(BTRIM(email))) )
  WHERE status = 'pending';
CREATE INDEX company_invitations_company_status_expiry_idx
  ON hasad.company_invitations (company_id, status, expires_at);

ALTER TABLE hasad.company_invitations ENABLE ROW LEVEL SECURITY;
ALTER TABLE hasad.company_invitations FORCE ROW LEVEL SECURITY;
```

The email column persists only the canonical `LOWER(BTRIM(...))` value. This
implements the owner-approved comparison rule while avoiding a second raw-email
copy. The membership insert supplies `role_id` and `is_owner = false`, so the
already-deployed membership role requirement remains satisfied.

#### 11.5.2 Candidate token/lifecycle contract

- The server generates 32 cryptographically random bytes, encodes them as a
  transport-safe token, returns that token once, and stores only the SHA-256
  digest in `token_hash`. The database accepts exactly a 32-byte digest.
- Token generation, SHA-256 digest support, encoding/decoding, and raw-token
  delivery are performed only in a reviewed server path. Tokens never enter a
  URL, exception, audit row, database log, or application telemetry.
- Invitation creation requires active owner or `members.manage`, derives the
  company from the caller's live membership, validates the same-company role,
  and creates `expires_at = created_at + interval '7 days'`.
- Acceptance finds the digest row `FOR UPDATE`, rechecks expiry and all terminal
  states, reads the approved verified-email source at that point, creates the
  membership, records acceptance, and writes the semantic audit event in one
  transaction. `UNIQUE(user_id)` remains the final multi-company guard.
- Expected domain outcomes are `INVITATION_INVALID`, `INVITATION_EXPIRED`,
  `INVITATION_ALREADY_USED`, `INVITATION_REVOKED`, `EMAIL_UNVERIFIED`,
  `EMAIL_MISMATCH`, and `ALREADY_MEMBER`. The expiry transition/error-transport
  choice remains an approval item in §11.6 because raising an exception rolls
  back an in-transaction transition to `expired`.

#### 11.5.3 Candidate audit structure

```sql
CREATE TABLE hasad.audit_log (
  id uuid PRIMARY KEY,
  company_id uuid NOT NULL
    REFERENCES hasad.companies(id) ON DELETE RESTRICT,
  actor_user_id uuid NOT NULL
    REFERENCES hasad.user_profiles(id) ON DELETE RESTRICT,
  action text NOT NULL,
  entity_type text NOT NULL,
  entity_id uuid NULL,
  details jsonb NOT NULL DEFAULT '{}'::jsonb,
  request_id uuid NULL,
  occurred_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT audit_log_action_nonempty_check CHECK (BTRIM(action) <> ''),
  CONSTRAINT audit_log_entity_type_nonempty_check CHECK (BTRIM(entity_type) <> ''),
  CONSTRAINT audit_log_details_object_check CHECK (jsonb_typeof(details) = 'object')
);

CREATE INDEX audit_log_company_time_idx
  ON hasad.audit_log (company_id, occurred_at DESC, id);
CREATE INDEX audit_log_entity_idx
  ON hasad.audit_log (entity_type, entity_id)
  WHERE entity_id IS NOT NULL;

ALTER TABLE hasad.audit_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE hasad.audit_log FORCE ROW LEVEL SECURITY;
```

The candidate retention rule is append-only/no application delete and no
application audit-read. `details` may contain only action-specific allow-listed
operational identifiers and before/after state; it must never contain a raw
token, email, verified-email evidence, credential, JWT, password, or sensitive
payroll value. The exact action/payload registry and legal retention period remain
owner choices in §11.6.

#### 11.5.4 Candidate internal security topology

- `hasad_c2_audit_owner`: `NOLOGIN`, `NOINHERIT`, non-superuser, no
  `CREATEROLE`, no `CREATEDB`, no `BYPASSRLS`; owns only the internal audit
  writer and has only the privileges it requires.
- `hasad_c2_api_owner`: a separately locked non-login role for reviewed narrow
  mutation RPCs. It can invoke the internal audit writer; `authenticated` cannot.
- A narrow internal verified-email reader uses `auth.uid()` and reads only the
  current identity's `auth.users.email` and `email_confirmed_at`. It is not
  executable by `PUBLIC`, `anon`, or `authenticated` directly.
- All internal functions use `SECURITY DEFINER`, a pinned
  `search_path = pg_catalog, pg_temp`, schema-qualified relations, explicit
  revocation of `PUBLIC` execute, and explicit internal-only grants. Actual
  role creation, ownership, RLS policies for those owners, and `auth.users`
  privilege feasibility are hosted-PoC gates, not deployment authorization.

#### 11.5.5 Candidate ownership and mutation contracts

- `company_create`: authenticated user with no membership; atomically creates
  profile (if absent), company, and active owner membership; verifies an active
  owner before commit; writes `company.created` and `membership.owner_granted`.
  Its documented `p_name` input is blocked until an approved `companies.name`
  column contract exists.
- `member_invite`, `invite_accept`, `member_suspend`, `member_activate`,
  `member_revoke`, `member_set_role`, `member_set_override`, and
  `ownership_transfer` derive company/actor from live membership and never
  accept a client company or ownership assertion as authorization evidence.
- Every mutation of an owner row's `is_owner` or `status` obtains the same
  transaction-scoped per-company advisory lock. A deferred constraint trigger
  rechecks at commit that the company retains at least one active owner. No
  application deletion path exists for companies or memberships.
- The future trigger/RPC migration must be accompanied by two-session tests for
  dual-owner concurrent revocation, sole-owner suspension, ownership transfer,
  and company-create rollback.

### 11.6 Owner approval block — remaining C2 choices

Approve or amend each clause. The structural table portions in clauses 1 are
already deployed and verified; the remaining clauses govern deferred behavior.
Hosted-PoC success remains required before any application-facing policy, grant,
function, trigger, or RPC.

1. **RESOLVED (2026-10-27):** The owner approved and DEV deployed the invitation
   and audit table shapes, constraints, index set, `ON DELETE RESTRICT` FKs, and
   forced-RLS statements in §11.5.1 and §11.5.3. No behavioral object was part
   of that authorization.
2. Adopt 32-byte random token material, SHA-256 `bytea` digest storage, and a
   transport-safe raw token returned once. Name the approved token-delivery path
   and confirm it has no URL or telemetry/logging exposure.
3. Choose expiry semantics: **A** return a committed domain-result code after
   changing the row to `expired`; or **B** retain expected-error exceptions and
   use a separately authorized expiry transition/cleanup path. The two cannot be
   conflated in one rollbacking transaction.
4. Approve the audit action vocabulary, allowed `details` keys per action,
   legal retention/archive rule, and confirm no application audit-read path in
   v1. `auditor` remains `reports.view` only unless separately changed.
5. Approve the two-role internal ownership topology in §11.5.4, subject to the
   hosted PoC proving it is supportable by Supabase. If unsupported, halt; do
   not fall back to an `authenticated` audit-insert grant without a new decision.
6. Approve the mutation RPC set, typed outcomes, and company-name column contract
   required by `company_create`; approve the advisory-lock plus deferred-trigger
   last-active-owner design in §11.5.5.
7. Authorize a named disposable Supabase project and disposable Auth test
   identities for the hosted real-JWT/managed-role PoC. DEV remains excluded.

### 11.7 C2 behavioral implementation preparation — PROPOSED, NOT EXECUTABLE

No deployable C2 behavioral migration, function, trigger, policy, grant, or RPC
file is prepared by this section. The existing local PoC harness remains
test-only and is not a deployable implementation. The following interfaces and
proof obligations are the implementation-ready outline for review after §11.6
is resolved:

| Candidate internal surface | Required boundary | Current blocker |
|---|---|---|
| Verified-email reader | Reads only the current `auth.uid()` row's `auth.users.email` and `email_confirmed_at`; normalizes with `LOWER(BTRIM(...))`; no direct application execute/access | Hosted Supabase proof of locked-owner `auth.users` access |
| Invitation token issue/hash | Generates 32 random bytes server-side; returns raw token once through the approved delivery channel; persists only a SHA-256 digest | Approved delivery channel, digest/encoding support, and no-log proof |
| Invitation acceptance | Locks invitation by digest; checks terminal/expiry state and current verified email; inserts membership; records acceptance and audit atomically | Expiry result semantics; helper topology; hosted real-JWT proof |
| Internal audit writer | Derives actor from `auth.uid()`, checks live active membership for the company, accepts only reviewed action/payload shapes, and inserts a fixed audit row | Action/payload registry; locked role support; no generic application execute path |
| Last-owner assertion | Deferred active-owner check paired with the same per-company transaction advisory lock used by every owner/status mutation | Approved company/membership mutation contracts and two-session hosted PoC |
| Public mutation RPC interfaces | `company_create`, `member_invite`, `invite_accept`, member status/role/override changes, and ownership transfer derive authorization server-side | No application-facing RPC is authorized before hosted PoC success |

The local 36/36 mechanics PoC provides no authorization to turn these interfaces
into a migration or to grant execution. The hosted real-JWT/managed-role PoC is
the next implementation gate.

### Material decisions still requiring explicit owner approval

The following are not silently settled by the block above:

1. **RESOLVED — verified-email source:** the owner-approved server-side
   `auth.users` / `email_confirmed_at` / `LOWER(BTRIM(...))` contract is recorded
   in §10.3 and §11.4. Hosted proof of its narrow internal access mechanism is
   still required.
2. **`fiscal.close` delegation:** the block deliberately keeps it owner-only
   until O3 is separately decided; clause 3(a) makes it non-overridable.
3. **`inventory.adjust` delegation:** the block deliberately withholds it from
   `warehouse` until its owner/admin tier is separately decided; clause 3(b)
   blocks allow-overrides.
4. **Sales receipt scope:** the block deliberately withholds broad `cash.post`
   from `sales`; clause 3(c) keeps it out of any `sales` membership. A future
   receipt-specific permission requires a separate owner decision and code.
5. **Audit-log read:** the block deliberately withholds it from `auditor` until
   a privacy-filtered read contract and a named permission are approved.
6. **Party-scope granularity:** `parties.manage` is not customer/supplier
   scoped. Approve the coarse grant for `sales` and `purchaser` with audit, or
   withhold it until scoped codes are separately approved. No new code is
   proposed here.
7. **Cashier expense payments:** approve cashier as cash-only, or separately
   add the exact `expenses.*` codes to the cashier mapping. The current block
   is cash-only.

Owner approval of this block authorized deployment of the already prepared
`20261026000200_v2_permissions_foundation.sql` and
`20261026000210_v2_permission_catalogue_seed.sql` to DEV. Both migrations were
deployed and verified on 2026-10-26 after a read-only preflight and
migration-list verification, with all application access still denied. The
approval did not authorize role rows or role mappings (roles are company-scoped),
invitation/audit deployment, application-facing policies, grants, or RPCs; those
remain blocked until their own contracts and the disposable-target PoC pass.
