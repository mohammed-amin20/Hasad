# HASAD V2 — Offline-First Sync Contract
**Status: DRAFT** | **Version:** 0.2 | **Last reviewed:** 2026-10-20
This document is the **single source of truth for sync and conflict policy** (per `docs/README.md`).
Feature-level narrative lives in `features/14_sync_and_conflicts.md`; binding invariants I31–I33 live in
`09_ACCOUNTING_INVARIANTS.md`; server tables live in `05_DATABASE_SCHEMA.md` ("Sync foundation").
Evidence labels: `PROPOSED` unless `OWNER_APPROVED` by decision ID (D-006, D-018, D-020, D-021) or
`RECOMMENDED_PENDING_VALIDATION`. Stale pre-decision questions in the previous version of this file
are resolved below and removed (D-006, D-018, D-020, D-021 citations).

## 1. Canonical pipeline
encrypted local SQLite (D-021) → durable outbox (stable `client_op_id` + canonical payload hash) →
ordered, dependency-aware upload (per-device FIFO, one op per `sync_apply` call) → server-side domain
validation identical to direct RPCs → atomic posting **in transaction order** (D-006) with
server-issued official number (D-018) → durable acknowledgment (applied/rejected/held) → local
reconciliation; download via commit-visible publication feed (`public_seq` watermark) + master-data
snapshots; permission lock + 24-hour offline expiry (D-020).

## 2. Outbox states and allowed transitions
`pending → inflight → acked` (terminal) | `rejected` (terminal, correctable) | `held` (dependency or
permission hold). Extra transitions: `pending|inflight → held` (revocation detected / dependency not
acked); `held → pending` (hold cleared); `rejected → superseded` (a **new** op with `supersedes_op_id`
was sent). Discard of any un-acked op: explicit confirmation + local audit only; dependents prompt for
cascade. **Recovery never deletes SQLite or pending local records** — the failed queue is always
visible with typed Arabic reasons and per-item actions (correct / retry / supersede / discard).

## 3. RPC contracts
- **`sync_apply(op)`** — input: `client_op_id`, kind, payload, `depends_on[]`, `supersedes_op_id?`.
  Executes, in one outer server transaction: (i) membership + permission gate (R-03); (ii) idempotency
  arbitration on `UNIQUE(company_id, client_op_id)`; (iii) dependency check; (iv) the **domain posting
  contract of the target feature (04–10) inside a savepoint-scoped subtransaction**; (v) on success —
  business writes, official number, audit, provisional change row, and the `applied` outcome row commit
  together; on typed domain failure — the subtransaction rolls back (no partial business writes) and
  the handler commits the `rejected` outcome + audit **in the outer transaction** (rejection evidence
  survives precisely because it is written after the savepoint rollback, outside the failed block);
  transport/infrastructure failure ⇒ nothing committed, client resends (idempotency converges).
  Output: `applied {server_id, official_number?, public_seq, outcome}` |
  `rejected {code, detail, current server quantities where relevant}` | `held {reason}`.
- **`sync_pull(after_seq, limit)`** — first runs the **publication step** (assign `public_seq` to
  committed, unpublished rows under a per-company advisory lock), then returns rows with
  `public_seq > after_seq` in ascending order, plus server time and the retention floor.
- **`sync_snapshot(kind)`** — master-data snapshot with `snapshot_seq` + freshness stamp; client swaps
  cache and watermark atomically in one local transaction.
- **`sync_status()`** — watermark floor (retention), pending-publication count, server time.

## 4. Server-side domain validation
Sync is a **transport, never a validation bypass** (I32): every op runs the identical membership,
permission, fiscal-period, mapping, capacity, stock and immutability checks of the direct RPCs, in the
same transaction, with the same typed error codes (`STOCK_INSUFFICIENT`, `PERIOD_CLOSED`,
`ORDER_OVER_INVOICED`, `RETURN_EXCEEDS`, `ALLOCATION_EXCEEDS`, `MAPPING_MISSING`,
`PERMISSION_DENIED`, …). Client-supplied company/entity values are consistency checks only; company is
derived server-side from verified membership on **every** call — **including duplicate-ack resends**,
which never disclose stored outcomes or protected data to a revoked or foreign caller (C11/I32).

## 5. Idempotency and corrections
- Applied op + identical canonical payload ⇒ resend returns the **original committed outcome**
  byte-for-byte (server id, official number, `public_seq`); zero new effects (I31).
- Same `client_op_id` + **different** content ⇒ `IDEMPOTENCY_MISMATCH`, no execution.
- Rejected op resend ⇒ **re-evaluation** of domain checks (safe: rejections have no business effects;
  prevents permanent queue blockage from correctable conditions); attempt count recorded.
- Corrections are always a **new `client_op_id` with explicit `supersedes_op_id`** — sent ops are
  never mutated client- or server-side.

## 6. Dependency resolution and ordering
Per-device FIFO is strict (client submits sequentially; server enforces device sequence). Cross-device
processing order = arrival order serialized by the per-company apply/publication locks
(RECOMMENDED_PENDING_VALIDATION). `depends_on[]` must reach `acked` before execution; otherwise the
dependent returns `DEPENDENCY_HELD`, stays `pending` with a visible reason, and is **never dropped or
silently reordered**. A dependency in `rejected` holds its dependents with the dependency's typed
reason; the queue unblocks only via explicit user action (retry / supersede / confirmed discard with
dependent cascade prompt).

## 7. Download ordering (protocol risk A — corrected)
A PostgreSQL sequence/bigserial alone does **not** guarantee commit order (R-04). Publication design:
1. Business transactions write **provisional** change rows that are invisible to clients.
2. The publication step (piggybacked on `sync_pull`, under a per-company advisory lock) assigns
   `public_seq` **only to rows whose transaction has committed**, monotonically in publication order.
3. Clients watermark strictly over `public_seq` ranges actually received; a later-committing row with
   a lower provisional order simply receives a **higher** `public_seq` — so no client can advance past
   a transaction that commits later.
4. The feed is contiguous by construction; received gaps are tolerated (R-04) but **snapshots
   supplement, never replace, the feed**: they are a resync fast path (`FEED_TRUNCATED` when the
   watermark predates retention), not the only protection.
Uniqueness of provisional payload (txn/change id) is required because notification-style dedup must
not collapse distinct changes (RECOMMENDED_PENDING_VALIDATION).

## 8. Conflict correction using linked new operations
Domain conflicts arrive as typed rejections with enough server state to correct locally (e.g., current
authoritative quantity). Correction flow: edit the local draft → **send as a new op** with
`supersedes_op_id` (audit chain preserved); the original rejected record remains as evidence. Draft
version conflicts: stale versions rejected `DRAFT_CONFLICT` → manual reconciliation (**O27,
REQUIRES_OWNER_DECISION — recommended default: no silent auto-merge**). No conflict policy ever
mutates posted data (D-019).

## 9. Durable acknowledgment handling
Acks are committed server-side with the effects they describe (applied) or after savepoint rollback
(rejected) — never assumed committable inside a failed transaction. The client persists the ack
transactionally with the local entity state it governs; a crash between server commit and local ack
write resolves on resend (idempotent replay returns the same outcome). Ack replay always passes the
membership gate (§4).

## 10. Multi-device synchronization
Each device keeps its own outbox and watermark over the shared feed; server-issued numbers and
capacities arbitrate races (exactly one device wins any last-unit/last-capacity contest, the loser
receives a preserved typed rejection). Master-data changes propagate down the same feed; local UUIDs
resolve via `local_ref_map`. Cached figures are labeled with last-received `public_seq`/server time and
pending-op counts; **pending local operations never appear in authoritative server totals** (I33), and
availability display remains governed by **D-025 (OPEN — server-posted-only recommended, not
approved)**.

## 11. Retention, snapshots, restore (protocol risk F — corrected)
Feed retention is bounded (recommended ≥ 90 days or a row floor — RECOMMENDED_PENDING_VALIDATION);
clients below the retention floor get `FEED_TRUNCATED` → mandatory atomic snapshot resync (snapshot +
watermark swapped in one local transaction) — **never silent truncation**. Feed rows are covered by the
backup policy (`12_BACKUP_AND_RECOVERY.md`). **Rebuildability claims are conditional:** regenerating
the feed from business tables can reproduce *state at a point* under documented deterministic ordering,
but not historical op order — such claims require verified source data and are never marked VERIFIED
without executable evidence.

## 12. Revocation, expiry, recovery (D-020, D-021 — OWNER_APPROVED)
Last-known permissions are used offline and **rechecked at every server apply**; on detected
revocation the local company data is **locked** and pending operations **preserved** for authorized
review; offline access **expires 24 hours** after the last successful server-side permission
verification (server time authoritative). Local store is encrypted with keys in platform secure
storage, PIN unlock (D-021); recovery mechanism remains OPEN within D-022. Five consecutive failed
retries surface the failed queue; **recovery without deleting SQLite is a hard requirement.**

## 13. Tests (contract-level; detail in `features/14` §J and `13_TEST_STRATEGY.md`)
Crash/restart at each pipeline stage; duplicate submissions with identical and changed payloads;
two-device last-unit race; delayed acknowledgement (24 h); A/B tenant switch; five failed retries with
visible queue; offline report freshness labels; SQL↔Dart rounding/serialization parity (R-07 set);
publication gap-injection (late-commit lower-order row still delivered); watermark-forgery negative;
revoked-caller duplicate-ack denial; rejection-evidence-survival proof (savepoint pattern);
feed-regeneration state-equivalence (conditional rebuildability); convergence after full resync.

**Decisions still OPEN at this contract:** D-025 (pending-stock display), O27 (draft-conflict policy),
D-010/D-011/D-012/D-022 (schema exposure, Storage disposal, migration tooling, recovery mechanism),
R-04/R-05 validation items, publication/retention/canonical-hash mechanics (RECOMMENDED_PENDING_VALIDATION).
