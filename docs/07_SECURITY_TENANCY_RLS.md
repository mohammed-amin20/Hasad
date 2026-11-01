# HASAD V2 — Security, Tenancy and RLS
**Status: DRAFT**

Roles and allowed operations require a signed permission matrix: company owner, administrator, accountant, sales, warehouse, payroll (actual list TBD).

## Mandatory threat cases
- Authenticated user A cannot read/write tenant B data.
- Sales role cannot call hidden accounting/employee RPCs.
- No direct insert/update/delete of posted financial or stock records.
- Membership revocation applies on next synchronized operation, including offline-queued changes.
- RPC DEFINER/INVOKER decisions documented with effective SQL permissions, search_path, and RLS approach.
- Anonymous and PUBLIC grants explicitly inspected; do not alter `auth`/`storage` managed schemas on assumption.

## Acceptance
Real JWT positive and negative tests, role switching A→B→A, deny-by-default audit, fresh-project grants tested, no bypass through PostgREST direct table endpoints.

## Proposed security model — two-schema exposure (PROPOSED 2026-10-20)
RECOMMENDED_PENDING_VALIDATION (extends R-01/R-02/R-03 in `15_DECISION_LOG.md`):
- **`hasad`** — private schema: all tables. Not listed in `PGRST_DB_SCHEMAS`; direct PostgREST table access returns 404.
- **`hasad_api`** — exposed schema: RPC functions only, no tables. `GRANT USAGE` to `authenticated`; **nothing for `anon`**.
- Changing `PGRST_DB_SCHEMAS` affects the whole reused DEV project — must be validated against the legacy app before the reset (D-010).

### Grant requirements (role `authenticated`; `anon` = zero everywhere)
- `EXECUTE` per function only, after **`REVOKE EXECUTE ... FROM PUBLIC, anon`** (PostgreSQL grants PUBLIC by default — checked in every future migration).
- Table grants via INVOKER functions, deliberately minimal: `SELECT` on tenant tables read; `INSERT` on append-only finance/document tables; `UPDATE` only on workflow (mutable) tables; **no `DELETE` anywhere; no `UPDATE` on posted finance rows** (D-019) — immutability also enforced by rejecting triggers.
- `audit_log`: **no direct write grants for `authenticated`** — rows are written only through a narrow audit helper (see "Corrected flaw 1 — audit write path" below); `UPDATE`/`DELETE` are never granted and are additionally blocked by rejection triggers.
- Residual, documented, non-eliminable paths: the `service_role` key bypasses RLS by design, and SQL-editor/`postgres` access bypasses everything (human, audited). Never ship service_role in clients.

### RPC authorization rules
- Company identity derives from `auth.uid()` joined against **live** `company_memberships` (`status='active'`); `UNIQUE(user_id)` guarantees a single row. Client-supplied company ids are consistency checks only; mutable session variables are **never** proof of membership (R-03).
- `SECURITY INVOKER` is the default: it runs with caller privileges, so the grant set is part of the design (an INVOKER function cannot write tables once its role's privileges are revoked).
- `SECURITY DEFINER` is exceptional: allowed only with a locked **non-superuser** owner, pinned `search_path`, schema-qualified references, explicit internal authorization, and dedicated tests. A DEFINER function owned by a superuser is forbidden.
- Every protected action calls the single permission resolver `has_permission` (owner → deny override → allow → deny-by-default); client checks are UX only.

### Approved catalogue code — product read (D-030)
`products.read` is an explicitly approved, read-only permission code in module
`products`. This catalogue decision does not approve an RPC implementation,
security/grant design, or deployment. It is not assigned to any role or user
automatically. Product reads must remain company-scoped and checked server-side
if/when a separately reviewed RPC contract is approved. This security document
remains DRAFT; hosted JWT/PostgREST verification is still required.

### DEV exception — direct customer writes (APPROVED 2026-10-30, local only)
In the DEV training project only, `authenticated` may `INSERT`/`UPDATE`
`hasad.parties` directly through the exposed Data API. This is an owner-approved
DEV exception, not the production model (see `15_DECISION_LOG.md`). The
implemented boundary:
- FORCE RLS stays enabled on `parties` and `audit_log`.
- Authorization is resolved inside RLS: active membership, active company,
  founding-owner precedence, otherwise `parties.manage`, with `deny` overrides
  winning for non-owners. The authorization function is `SECURITY DEFINER`
  owned by the dedicated locked role `hasad_party_writer`
  (NOLOGIN/NOINHERIT/NOSUPERUSER/NOCREATEDB/NOCREATEROLE/NOREPLICATION/
  NOBYPASSRLS), created by the deploying executor.
- `id` and `company_id` are outside the `UPDATE` column grant, so they are
  immutable through the API; `DELETE` is never granted.
- The audit trigger is `SECURITY DEFINER`, owned by the same locked role, and
  derives the actor from `request.jwt.claims`/`request.jwt.claim.sub`. This
  avoids the established DEV blocker that `hasad_rpc_owner` has no USAGE on
  schema `auth`; `auth.uid()` is used only in policies evaluated as
  `authenticated`. No object is owned by `hasad_rpc_owner`.
- `anon` receives no schema USAGE and no table privilege.
Status: candidate `security/candidates/dev_direct_data_api_customers_write_v2_candidate.sql`
is locally verified on disposable PostgreSQL; hosted installation, PostgREST
exposure and remote deployment are not authorized or verified here.

The exception is void if any of the following is weakened: FORCE RLS, audit
atomicity, actor binding, deny-override precedence, the immutable columns, or
the absence of `anon`/`service_role` access. Any such change needs a new owner
decision, not a candidate revision.

### Coherent security contract (PROPOSED 2026-10-21, audit batch 1 — implementation UNVERIFIED, not executable proof)
One authoritative statement of the intended boundary (R-02 as clarified in
`15_DECISION_LOG.md` 2026-10-21). Every clause is `PROPOSED` pending the isolated
executable security PoC; **no clause below is claimed VERIFIED**:
1. **Tenant data access only through appropriately authorized RPCs.** Business reads and
   writes flow through the `hasad_api` function surface; each RPC rederives company from
   live membership server-side (R-03) and resolves the specific permission code via
   `has_permission` — client checks are UX only.
2. **No arbitrary direct financial-table reads from application roles.** Direct table
   reads on financial/authoritative tables are not the intended access path; reads
   belong in permission-gated RPCs (reports, statements, derived balances — D-017).
   Where a least-privilege `SELECT` grant is deliberately retained for an INVOKER
   function's operation, it must be enumerated, reviewed and recorded per function —
   never implicit, never widened by surface changes.
3. **No direct writes to authoritative posting tables from application roles.** Posted
   rows (journal entries/lines, posted documents, movements) accept no client
   `INSERT`/`UPDATE`/`DELETE`; posting happens only inside the documented posting RPCs
   (D-019 three-layer rule). `INSERT` grants exist only on append-only/draft-workflow
   paths; `UPDATE` only on workflow (mutable) tables; **no `DELETE` anywhere**.
4. **RPC execution must not bypass domain-level permission checks.** Every protected
   action rechecks membership, permission code and fiscal-period state inside the
   transaction — invoking an RPC is not authorization by itself; `EXECUTE` is granted
   per function after `REVOKE ... FROM PUBLIC, anon`.
5. **Sensitive payroll data is separately protected.** `employees`, payroll run/line/
   component tables, advances, settlements and statutory config have no direct client
   reads; masking RPCs enforce `payroll.*` codes with audit on unmasked reads and
   payslips (`features/11` C13).
6. **INVOKER vs DEFINER, the exact table-grant set, and the RLS implementation remain
   pending proof.** `SECURITY INVOKER` with pinned `search_path` is the default and
   `SECURITY DEFINER` is exceptional (locked non-superuser owner, pinned
   `search_path`, explicit authorization, dedicated tests) — but which variant each
   function uses, and the exact grant set, is **UNVERIFIED** until the PoC runs the
   real-JWT permission matrix.

**Follow-up alignment items (recorded, NOT modified in this batch).** The following
files record feature-level statements that predate this contract and must be
reconciled in a later batch — each currently states `SELECT` grants for
`authenticated` on financial-domain tables (features 04–10, 12) or a "no direct table
access" phrasing that the contract above supersedes in wording (R-02):
`features/04`, `features/05`, `features/06`, `features/07`, `features/08`,
`features/09` (§E), `features/10`, `features/12`, plus `05_DATABASE_SCHEMA.md`
per-feature security sections. Reconciliation options (INVOKER-with-enumerated-grants
vs RPC-only reads) resolve only after the PoC; until then both wordings stand recorded
here and in `15_DECISION_LOG.md` R-02 — no silent grant changes.

### Unresolved security requirements (must be validated before schema approval)
1. A private schema or hidden PostgREST surface **does not replace** PostgreSQL privileges and server-side business-rule enforcement.
2. `SECURITY INVOKER` uses caller privileges; granting table INSERT/UPDATE can expose bypass paths if the surface is ever widened.
3. `SECURITY DEFINER` requires tightly controlled ownership, `search_path`, explicit authorization and tests.
4. Company identity must derive from verified Supabase Auth identity and current membership — never from client input or session settings.
5. Ownership transfer and last-owner protection must be concurrency-safe: a deferred constraint check **alone does not hold** (two concurrent revokes can each observe the other owner before commit). The corrected design needs advisory/row locking **plus** the deferred check, must cover creation, transfer, status change (suspension) and deletion restrictions, and must be tested for all four.
6. Invitation acceptance must validate identity (verified matching email) and enforce `UNIQUE(token_hash)`, expiry, one-time acceptance under row lock, and prevent multi-company membership races (`UNIQUE(user_id)` as the final arbiter).
7. Account suspension/revocation must be checked under concurrent financial activity: authorization is evaluated at the start of each RPC; already-running single transactions complete under isolation semantics (documented, not retroactive).

### Corrected design flaws (PROPOSED 2026-10-20 — RECOMMENDED_PENDING_VALIDATION until tested in the isolated PoC)

**Corrected flaw 1 — audit write path.**
Contradiction: INVOKER RPCs run with `authenticated` privileges, so "no write grants on `audit_log`" makes every in-RPC audit insert fail. Options compared:
- **Option A (recommended): narrow `SECURITY DEFINER` audit helper.** A single function (e.g. `audit_write(p_company, p_action, p_entity, p_details)`) owned by a **locked non-superuser role** (never `postgres`), pinned `search_path`, schema-qualified, `EXECUTE` granted only to `authenticated`. Internally it derives the actor from `auth.uid()` (never caller-supplied), verifies the caller's live active membership in `p_company`, and inserts into one fixed table/column set — it is not a generic write primitive. Residual risk: any flaw in the helper's argument validation becomes an audit-injection path; the locked owner role's availability in Supabase is **untested**.
- **Option B: INVOKER + `INSERT`-only grant on `audit_log` to `authenticated`.** Append-only still holds three ways (no `UPDATE`/`DELETE` grants + rejection trigger + private unexposed schema). Simplest, no special roles; but it is a **standing grant** — every future INVOKER code path can append arbitrary audit rows (spoofed actor/action), and the grant survives any widening of the HTTP surface.
- **Option C (complement, later): `SECURITY DEFINER` trigger functions** owned by the same locked role, capturing data mutations automatically (cannot be forgotten by RPC authors) — but they express *row changes*, not semantic RPC events, and are harder to attribute per operation.
**Recommendation:** Option A as primary, Option C as a possible complement for data-mutation capture; **fallback Option B only if the locked-role approach proves infeasible**, with the spoofing residual risk documented. All three remain `RECOMMENDED_PENDING_VALIDATION` until the PoC tests them.

**Corrected flaw 2 — company ownership integrity (layered; deferred trigger alone is NOT sufficient).**
1. **Creation path:** `company_create` is the only way a company row can appear — profile upsert → company insert → **owner membership insert in the same transaction**, plus an immediate assertion before commit; there is no separate path that can commit a company without its owner row.
2. **Deferred invariant:** a `DEFERRABLE INITIALLY DEFERRED` constraint trigger on `company_memberships` (INSERT/UPDATE/DELETE) re-verifies `≥1 active owner` at COMMIT — covering transfers, revokes **and status changes** (suspending the sole owner must fail too).
3. **Concurrency lock:** every operation that mutates `is_owner`/`status` of owner rows first takes `pg_advisory_xact_lock(company)` (or ordered `FOR UPDATE` on membership rows). Without this, two transactions revoking two different co-owners can each pass the deferred check while the other's revoke is uncommitted → both commit → ownerless company. The lock serializes them so the second fails `LAST_OWNER`.
4. **Deletion restrictions:** no `DELETE` grant on `companies`/`company_memberships` for `authenticated`; rejection triggers additionally refuse; company deletion itself is out of scope (suspension-only pending owner decision).

**Corrected flaw 3 — invitation security.**
- **`UNIQUE(token_hash)`** (global): a token collision or duplicate row is rejected at the index; the server regenerates rather than retries.
- **Expiry:** `expires_at NOT NULL`; acceptance requires `now() < expires_at` **and** `status='pending'`; expired invitations fail `INVITATION_EXPIRED` and are lazily (or via scheduled job) transitioned to `expired`. Recommended default TTL: 7 days — `RECOMMENDED_PENDING_VALIDATION`, duration is an open item for the owner.
- **One-time acceptance:** inside `SELECT ... FOR UPDATE` on the invitation row: status check → identity check → membership insert (`UNIQUE(user_id)` final arbiter) → status := `accepted` (`accepted_by`, `accepted_at`). After acceptance the token is dead; a replayed token returns `INVITATION_ALREADY_USED`. The raw token is never stored or logged — only its hash; it is delivered once (transport via Supabase Auth invite mechanics still `RECOMMENDED_PENDING_VALIDATION`), and never placed in URLs/query strings where logs would capture it.
- **Concurrent acceptance:** the row lock serializes simultaneous attempts; the loser sees `status <> 'pending'` and is rejected; even a lock-avoiding path is stopped by `UNIQUE(user_id)`.
- **Pending-uniqueness scope:** **global** `UNIQUE (lower(email)) WHERE status='pending'` is recommended (consistent with one-company-per-user D-003: a pending invitation already claims eligibility for exactly one company; competing cross-company invites are rejected early instead of racing at acceptance). Alternative — per-company scope `(company_id, lower(email))` — pushes the conflict to acceptance time where `UNIQUE(user_id)` still decides; rejected for now because it allows confusing duplicate pending invites. Trade-off: a stale global invite blocks re-invitation until it expires or is revoked — mitigated by the TTL. Both scopes `RECOMMENDED_PENDING_VALIDATION`.

### Negative security test matrix (minimum before the first migration)
`anon` denied on every RPC · direct access to `hasad.*` via PostgREST = 404 · cross-company read/write with real JWTs rejected · forged company id in sync payloads rejected · mismatched/unverified invitation email rejected · concurrent double-acceptance yields one membership · second-company join violates `UNIQUE(user_id)` · revoking the final owner fails at commit (`LAST_OWNER`) · ownership transfer to suspended/non-member rejected · deny-override beats role allow; owner ignores overrides · suspended/revoked members get typed errors · `UPDATE/DELETE` on `audit_log` rejected · search-path hijack rejected (pinned, qualified) · any DEFINER owned by a superuser fails policy review · membership change racing a posting RPC behaves per the documented snapshot semantics · **direct `INSERT` on `audit_log` as `authenticated` rejected (no grant)** · **audit helper called with a company the caller does not belong to → rejected** · **duplicate `token_hash` → index violation** · **expired token → `INVITATION_EXPIRED`; replayed accepted token → `INVITATION_ALREADY_USED`** · **second pending invite for the same email (any company) → unique-violation under the global scope** · **two concurrent revokes of two co-owners → exactly one succeeds, company keeps ≥1 active owner** · **company creation racing its own owner-membership failure → no orphan company row** · **suspending the sole owner → `LAST_OWNER`**.
