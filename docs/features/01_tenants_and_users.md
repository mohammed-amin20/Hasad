# Feature: الشركات والمستخدمون / 01_tenants_and_users
**Status: DRAFT** | **Version:** 0.3 | **Owner approval:** PENDING | **Last reviewed:** 2026-10-20
**Source:** V2 clean-slate design (no Hasad V1 reuse). Business rules bound by `15_DECISION_LOG.md` (D-003, D-006, D-018, D-020, D-021, D-022).
**Evidence labels:** claims below are `PROPOSED` design unless marked `APPROVED` (owner decision IDs) or `OBSERVED`.

## A. Why this feature exists
Establishes the tenancy root of V2: a company (tenant) owns all business data; a user account belongs to **exactly one company** (D-003 APPROVED); invitations to join are distinct from active membership; company ownership is transferable but can never be left empty. This feature is the foundation every other module depends on for tenant isolation.

Exclusions: authentication UI flows, password/PIN policy, employee payroll records (module 12 — kept separate from auth identity), and business documents.

## B. Roles and user stories
- **Company owner** → creates the company, invites/suspends/revokes members, transfers ownership; has every business permission implicitly (D-004 context; see `features/02`).
- **Invited employee** → accepts an invitation, joins the company under a predefined role, works offline within permission-cache rules.
- **Suspended/revoked employee** → loses server access immediately at the next synchronization; local data is locked; pending operations are preserved for authorized review (D-020 APPROVED).
- Forbidden: any user acting in more than one company; any member modifying another member's company assignment; anyone accepting an invitation for another identity.

## C. Business rules and state transitions
Membership states: `active → suspended → active`, `active|suspended → revoked` (terminal for access; row retained for audit). No hard deletes.
- C1 Company creation is atomic **and owner-complete**: profile upsert → company insert → owner membership insert in one server transaction, with an immediate assertion that the owner row exists before commit; failure rolls back everything, so no company row can ever be committed without its owner (the deferred invariant in C5 is a second line of defense, not the only one).
- C2 One company per user: enforced by `UNIQUE(user_id)` on memberships — a second join attempt fails with `ALREADY_MEMBER` at the constraint, not in client logic.
- C3 Invitations are **pending records, not memberships** (`company_invitations` table); acceptance is a single transaction that locks the invitation row (`FOR UPDATE`), validates identity, inserts the membership, and marks the invitation accepted — one-time use; a replayed token fails `INVITATION_ALREADY_USED`.
- C3a Invitation token security: only a **hash** of a cryptographically random token is stored (`UNIQUE(token_hash)`); `expires_at` is mandatory and checked at acceptance (`INVITATION_EXPIRED`); the raw token is returned once, never stored or logged, and never placed in URLs/query strings. Concurrent acceptance attempts serialize on the row lock; `UNIQUE(user_id)` remains the final arbiter against double-join.
- C4 Invitation acceptance requires the authenticating identity's verified email to match the invited email (`email_verified=true`) — OPEN sub-decision in section L.
- C5 Ownership: ≥1 **active** owner always, enforced in layers — atomic creation (C1), a deferred constraint trigger at COMMIT covering insert/update/delete **and status changes** (suspending the sole owner must fail `LAST_OWNER`), an advisory per-company lock taken before any mutation of owner rows (closes the concurrent double-revoke race where each transaction sees the other co-owner uncommitted), and no DELETE grants on companies/memberships. Transfer is atomic (grant new owner → optionally revoke old). RECOMMENDED_PENDING_VALIDATION design (see `07_SECURITY`).
- C6 Suspension/revocation takes effect on the next server-authorized operation; already-running single transactions complete under isolation semantics (documented, not retroactive).
- C7 Audit events are mandatory for: company created, invitation invited/accepted/revoked/expired, role changed, override changed, suspended/activated/revoked, ownership transferred. They are written in the same transaction through the **narrow audit helper** (no direct `INSERT` grant on `audit_log` for application roles — see `07_SECURITY`, corrected flaw 1).

State chart: `invited(pending) → accepted → member(active) ⇄ suspended → revoked`; `owner` is a flag on an active membership, never a separate role row.

## D. Data model (PostgreSQL — proposal until approved)
| Table | Purpose | Tenant scope | Key references | Status |
|---|---|---|---|---|
| `companies` | Tenant root; `status` active/suspended | — (is the root) | `created_by → user_profiles` | PROPOSED |
| `user_profiles` | 1:1 with `auth.users`; `display_name`, `last_permission_check_at` | none (identity) | `id = auth.users.id ON DELETE RESTRICT` | PROPOSED |
| `company_memberships` | Active membership; `role_id`, `is_owner`, `status`, `invited_by`, `revoked_at` | `company_id NOT NULL` | FKs companies/users/roles; **UNIQUE(user_id)** (D-003); UNIQUE(company_id,user_id) | PROPOSED |
| `company_invitations` | Pending invites: `email`, `role_id`, `token_hash`, `expires_at`, `status`, `accepted_by/at` | `company_id NOT NULL` | FK company/role/inviter | PROPOSED |
| `audit_log` | Append-only trail; actor, action, entity, details jsonb | `company_id NOT NULL` | FK company | PROPOSED |

Constraints/indexes: `company_invitations` — **`UNIQUE(token_hash)`**, `expires_at NOT NULL`, partial `UNIQUE(lower(email)) WHERE status='pending'` with **global scope** (recommended; alternative per-company scope documented in `07`); `company_memberships` — `UNIQUE(user_id)` (D-003) + partial index `(company_id) WHERE status='active'`; `audit_log` — no direct write grants (audit helper only) + rejection triggers; UUIDv7 PKs (R-08), `text+CHECK` state columns (RECOMMENDED_PENDING_VALIDATION). Deletion policy: **no hard delete** for companies/memberships/invitations/audit; suspensions and revocations are state changes that preserve rows.
Open implementation choices are listed in `05_DATABASE_SCHEMA.md` (identity section) and section L.

## E. RLS / grants / RPCs
- RLS on every table with the unified membership-existence pattern; `auth.uid()` is the only identity source; client-supplied `company_id`/`role`/`is_owner` are never trusted (see `07_SECURITY_TENANCY_RLS.md`).
- All writes go through `hasad_api` RPCs; the private `hasad` schema is not PostgREST-exposed (RECOMMENDED_PENDING_VALIDATION R-01 extension).
- Mandatory audit events (C7) are written in the same transaction as the state change, through the narrow audit helper — application roles hold **no direct `INSERT` on `audit_log`** (see `07_SECURITY`, corrected flaw 1).
- Denied by default for `anon`; `authenticated` receives only the deliberate grants listed in `07_SECURITY`.

## F. Offline SQLite and synchronization
- The client caches company id, role code, permission set and `verified_at` (UX only — never the security boundary).
- Offline access expires **24 hours** after the last successful server-side permission verification (D-020 APPROVED); the local encrypted store (D-021) is then locked behind re-authentication + PIN.
- Revocation detected at sync ⇒ local company data locked; pending outbox operations are **preserved, never deleted** (D-020), and rejected at server apply-time with typed errors.
- Offline documents carry temporary local references; official numbers come from the server at approval (D-018).

## G. Accounting impact (if any)
`No accounting posting` in this feature. It only gates who may reach posting features; every financial RPC re-derives membership server-side at apply time.

## H. UI and Arabic RTL
Arabic RTL screens: company creation, member list with state badges (نشط/معلّق/ملغى), invitation form and pending list, ownership transfer with explicit confirmation, suspension warnings. Expired offline access shows a domain-safe Arabic message with the reason and the next action (not a raw error code). Official numbers and temporary references are visually distinguished (D-018).

## I. API / RPC contract
| RPC | Input | Output | Auth | Audit |
|---|---|---|---|---|
| `company_create(p_name)` | name | company id | any authenticated user **without** membership | company.created + membership.owner_granted |
| `member_invite(p_email, p_role_code)` | email, role code | invitation id | owner / members.manage | member.invited |
| `invite_accept(p_token)` | raw token (once, never re-sent in URLs) | membership id | authenticated; verified matching email; row-locked one-time acceptance; `INVITATION_EXPIRED` / `INVITATION_ALREADY_USED` on reuse | member.joined |
| `member_suspend / member_activate / member_revoke(p_membership_id)` | membership ref | new state | owner / members.manage; last-owner guard on revoke | member.* |
| `member_set_role(p_membership_id, p_role_code)` | ref, role | updated | members.manage | member.role_changed |
| `ownership_transfer(p_membership_id, p_revoke_self)` | ref, flag | — | **owner only** | ownership.transferred (from, to) |
| `whoami()` | — | company, role, permissions, `verified_at` | any active membership | — (refreshes check timestamp) |

Typed errors: `NOT_A_MEMBER`, `MEMBERSHIP_SUSPENDED`, `ALREADY_MEMBER`, `LAST_OWNER`, `INVITATION_INVALID/EXPIRED`, `PERMISSION_DENIED`. No RPC accepts a client company id as an authorization input.

## J. Tests and acceptance criteria
Positive: atomic company creation (rollback on failure); invite→accept produces exactly one membership; `whoami` matches DB state; transfer with two members succeeds in one transaction; every C7 action writes exactly one audit row (via the audit helper).
Negative (cross-ref `07_SECURITY` matrix): cross-company read/write with real JWTs; accept with mismatched/unverified email; concurrent double-accept ⇒ one membership; expired token ⇒ `INVITATION_EXPIRED`; replayed accepted token ⇒ `INVITATION_ALREADY_USED`; duplicate `token_hash` ⇒ index violation; second pending invite for the same email (any company) ⇒ unique violation; second-company join ⇒ constraint violation; revoke last owner (alone and inside a failed transfer) ⇒ `LAST_OWNER` at commit; **two concurrent revokes of two co-owners ⇒ exactly one succeeds, ≥1 active owner remains**; **suspending the sole owner ⇒ `LAST_OWNER`**; **direct `INSERT` on `audit_log` as `authenticated` ⇒ rejected**; **audit helper called for a foreign company ⇒ rejected**; suspended/revoked member RPCs ⇒ typed errors; direct table access via PostgREST ⇒ 404; `anon` everywhere ⇒ denied.
Test only disposable datasets (`13_TEST_STRATEGY.md`).

## K. Rollout and migration
Depends on: approved schema exposure decision (D-010/R-01), migration tooling (D-012/R-09). Additive first migration; no data migration (D-002); seed of role catalogue only after owner review (section L). Rollback = migration reversal decision documented before deployment; no destructive steps.

## L. Open questions and decisions
- [ ] Predefined role catalogue content and permission-code enumeration — **owner decision** (see `features/02`, RECOMMENDED_PENDING_VALIDATION set).
- [ ] Invitation email-verification policy (exact claim check) — security validation pending.
- [ ] Invitation TTL duration (7 days proposed) — **open item for the owner**; RECOMMENDED_PENDING_VALIDATION.
- [ ] Pending-invitation uniqueness scope: global per email (recommended, consistent with D-003) vs per-company — RECOMMENDED_PENDING_VALIDATION with trade-offs documented in `07`.
- [ ] Audit write mechanism: narrow DEFINER helper (recommended) vs INSERT-only grant fallback — pending PoC validation; locked non-superuser role feasibility in Supabase untested.
- [ ] Supabase Auth admin invite path (identity creation and raw-token transport outside SQL) — RECOMMENDED_PENDING_VALIDATION.
- [ ] `ON DELETE` behavior of `auth.users` → profiles (RESTRICT recommended) — pending owner/reset-plan alignment (D-011).
- [ ] Whether companies can ever be deleted (suspension-only recommended).

## M. Source evidence
| Claim | Evidence source | Observed on | Confidence |
|---|---|---|---|
| One company per user | `15_DECISION_LOG.md` D-003 (owner-approved) | 2026-10-20 | APPROVED decision |
| Offline 24h / revocation lock / preserved pending ops | `15_DECISION_LOG.md` D-020 | 2026-10-20 | APPROVED decision |
| Design tables/RPCs | This spec + `07_SECURITY_TENANCY_RLS.md` | 2026-10-20 | PROPOSED |

**Gate:** keep DRAFT until owner signs this spec (and the role catalogue), then create implementation tasks.
