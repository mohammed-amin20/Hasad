# Feature: العملاء والموردون / 05_customers_and_suppliers
**Status: DRAFT** | **Version:** 0.2 | **Owner approval:** PENDING | **Last reviewed:** 2026-10-20
**Source:** V2 clean-slate design (no Hasad V1 reuse). Bound by `15_DECISION_LOG.md` (D-003, D-005, D-016, D-017, D-018, D-019) and the 2026-10-20 parties/cash planning report.
**Evidence labels:** `PROPOSED` unless marked `OWNER_APPROVED` (by decision ID), `RECOMMENDED_PENDING_VALIDATION`, or `REQUIRES_OWNER_DECISION`.
**Supersedes:** the legacy skeleton question "Can the same party be both customer and supplier?" — **resolved OWNER_APPROVED by D-016** (one unified party record; AR and AP remain distinct).

## A. Why this feature exists
Defines **parties** — the unified counterparty record every sales, purchase, cash and allocation document references. One party can be a customer, a supplier, or both, while **accounts receivable and accounts payable stay strictly separate ledgers** (D-016 OWNER_APPROVED). Party balances, statements and aging **derive from posted accounting entries** (D-017 OWNER_APPROVED) — no independent authoritative balance columns exist anywhere.

Exclusions: payment/cash mechanics (see `features/09`), invoice documents (modules 06/07), GL engine mechanics (`features/04`).

## B. Roles and user stories
- **`parties.manage` holder** → creates/edits parties, sets customer/supplier classification, deactivates.
- **All active members** → read parties in pickers and derived statements (with `reports.view` for statements/aging).
- Sales/purchase/cash modules → reference `party_id` on their documents; posting validates classification (C2) and same-company integrity.
- Forbidden: cross-company party references; deleting a party referenced by any document; mixing AR and AP amounts on one ledger query.

## C. Business rules and state transitions
- C1 **Unified record:** one `parties` row per counterparty per company; `UNIQUE(company_id, code)`; Arabic name mandatory.
- C2 **Explicit classification (corrected design):** each party carries **stored, user-set flags** `is_customer` and `is_supplier` (both may be true; both may be false for a newly created record). Classification is **usable before the first financial transaction** — it is *not* derived exclusively from posted activity. Posting behavior (RECOMMENDED_PENDING_VALIDATION): posting an AR-side document to a non-classified party **auto-enables** `is_customer` with an audit event (`party.classified`) rather than blocking the posting; the flags are **never auto-disabled**. Activity-derived indicators ("has made purchases") remain query-level conveniences only and never override the stored flags.
- C3 **AR/AP separation (OWNER_APPROVED D-016):** AR lives on the mapped `AR_CONTROL` account, AP on `AP_CONTROL`; party dimension (`journal_lines.party_id`) attaches to the control-account line. A single party naturally appears in **both** ledgers with **independent** balances; no query, report or RPC ever nets them.
- C4 **Derived balances (OWNER_APPROVED D-017):** party AR balance, AP balance, statements and aging are computed from **posted** journal lines (signed GL sums) and posted documents. **Signed GL balance ≠ settlement amount** — the GL balance includes every posted line (including opening-balance lines carrying a party dimension), while *document settlement* is tracked through allocations (`features/09`); the two are reconciled by proof test, not assumed equal by a simplified equation (see §G and invariants I12–I14 in `09`).
- C5 **Lifecycle:** `active ⇄ inactive`; no hard delete if referenced by any document, allocation or journal line (RESTRICT); deactivate blocks **new** documents but preserves all history and derived reports.
- C6 **Tenant safety:** every reference to a party is composite same-company FK validated (GL lines, payments, allocations, invoices) — an approved cross-cutting requirement; enforcement pending the security PoC (`07`).
- C7 **Identifiers:** `tax_id` stored as text with optional format CHECK; legal-format validation for Israeli IDs/tax numbers is **not** assumed (feeds D-023-adjacent legal layer; REQUIRES_OWNER_DECISION if a compliance check is wanted).
- C8 **Audit events (mandatory):** `party.created`, `party.updated`, `party.deactivated`, `party.classified` (flag changes), all via the audit helper (pending validation).

## D. Data model (PostgreSQL — proposal until approved)
| Table | Purpose | Tenant scope | Key constraints | Status |
|---|---|---|---|---|
| `parties` | Unified counterparty | `company_id NOT NULL` | PK UUIDv7 (R-08); `UNIQUE(company_id, code)`; `name_ar NOT NULL`; `party_type CHECK ('individual','company')`; `is_customer`, `is_supplier` booleans (stored classification); `tax_id` nullable; contact columns; `payment_terms_days` nullable; `is_active` | PROPOSED |

Deletion policy: deactivate only; RESTRICT while referenced. Indexes: `(company_id, code)` unique; `(company_id, name_ar)` (or lower() functional) for search; partial `(company_id) WHERE is_customer` / `WHERE is_supplier` for filtered pickers (RECOMMENDED). Contacts: v1 keeps phone/email/address columns on the party; a separate contacts table is deferred until a real multi-contact need appears (RECOMMENDED_PENDING_VALIDATION).

## E. RLS / grants / RPCs
- Private `hasad` schema; RPCs in `hasad_api` INVOKER; the privilege model is still DRAFT pending the isolated security PoC (`07_SECURITY_TENANCY_RLS.md`).
- Grants (target design): `SELECT` for `authenticated`; `INSERT/UPDATE` only through RPCs with `parties.manage`; no `DELETE`.
- **DEV exception (OWNER_APPROVED 2026-10-30 — see `15_DECISION_LOG.md`):** in the DEV training project, `authenticated` may `INSERT`/`UPDATE` `hasad.parties` directly through the exposed Data API instead of an RPC. RLS enforces active identity, active membership, active company, owner precedence or `parties.manage` with deny-overrides, same-company writes, immutable `id`/`company_id`, and same-transaction audit. `DELETE` stays forbidden and `anon` gets nothing. The target (production) design remains RPC-only; this exception is not a production decision.
- Statements/aging read paths re-derive membership server-side like all RPCs.

## F. Offline SQLite and synchronization
- Parties are cached locally for pickers and offline document creation (UX); the cache is never an authorization boundary.
- New parties may be created offline → **pending** in the outbox, posted in transaction order by the server (D-006 OWNER_APPROVED); a pending party is usable by other pending documents of the same outbox batch via local UUID references resolved at sync.
- Server re-validates code uniqueness, classification changes and deactivation state at apply time; typed rejections are preserved locally.

## G. Accounting impact (if any)
`No direct posting` from party CRUD. The party is the **subledger dimension** of control-account postings produced by modules 06/07/09/10. Reconciliation obligations (invariants I12–I14, `09`):
- **Signed GL AR balance** for a party = Σ posted debit lines − Σ posted credit lines on `AR_CONTROL` with that party (includes opening-balance lines if they carry the party dimension, and credit/debit notes).
- **Settlement view** per invoice = invoice amount − Σ active allocations (invoices, credit notes, debit notes, receipts) — allocations live in `features/09`.
- The reconciliation proof must account for **credit notes, debit notes, reversals and opening balances**; the naive equation "AR = open invoices − unapplied receipts" is **not assumed to hold** without those terms (corrected design; proof is a required test, not a documentation claim).

## H. UI and Arabic RTL
Arabic RTL screens: party list with filters (عميل/مورد/الكل), party form with explicit classification toggles (تصنيف: عميل، مورد), duplicate-code warning, statement view (كشف حساب) with running derived totals and freshness labels, AR and AP shown as **separate tabs/sections — never netted**, aging buckets view. Deactivation warning in domain-safe Arabic. Number/date formats from tenant settings.

## I. API / RPC contract
| RPC | Input | Output | Auth | Audit |
|---|---|---|---|---|
| `party_create(...)` | code, name, type, flags | party id | `parties.manage` | party.created (+party.classified if flags set) |
| `party_update(id, ...)` | fields; classification flags | — | `parties.manage` | party.updated / party.classified |
| `party_deactivate(id)` | id | — | `parties.manage` | party.deactivated |
| `party_list(filter, search)` | derived/flag filters | rows | any active member | — |
| `party_statement(party, range)`, `party_aging(as_of)` | refs | derived rows | `reports.view` | — |

Typed errors: `PARTY_IN_USE` (delete/invalid transition), `PARTY_INACTIVE`, `PARTY_NOT_CUSTOMER`/`PARTY_NOT_SUPPLIER` (only where a module elects strict validation instead of auto-classification), `PERMISSION_DENIED`. No RPC returns a stored "balance" — all balances are derived at query time.

## J. Tests and acceptance criteria
Positive: create one party with **both** flags before any transaction and immediately use it on a sales invoice and a purchase bill; statement lists posted documents in order; AR and AP balances reported independently for the same party; auto-classification audit event fires when posting to an unclassified party; deactivation blocks new documents but statements still render; offline party creation syncs in order and resolves local references.
Negative: duplicate code in same company ⇒ constraint violation; same code in another company ⇒ allowed (isolation proof); party referenced by a document cannot be deleted ⇒ `PARTY_IN_USE`/restricted; cross-company `party_id` on any document ⇒ composite FK/RLS rejection; strict-mode `PARTY_NOT_SUPPLIER` rejection when a module elects strict validation; `anon` ⇒ denied.
**Reconciliation proofs (core):** signed GL AR balance ≡ settlement view **including** credit notes, debit notes, reversal effects and any party-dimensioned opening-balance lines — exercised with partial payments, a credit note, one full reversal pair, and an opening balance; naive-equation divergence cases must be **demonstrated** (not hidden).
Test only disposable datasets (`13_TEST_STRATEGY.md`).

## K. Rollout and migration
Depends on: identity/authorization foundation (`features/01`/`02`, DRAFT pending security validation), CoA control-account mappings (`features/03`, needs O1/O4), GL engine (`features/04`). Additive migrations; no V1 data migration (D-002); no party seed data.

## L. Open questions and decisions
- [ ] **O7 (REQUIRES_OWNER_DECISION, with `features/09`):** tender methods and check handling — party-side fields (bank/IBAN for refunds) depend on it.
- [ ] **O10 (REQUIRES_OWNER_DECISION, with `features/09`):** overpayment/unapplied-credit policy confirmation.
- [ ] Tax-ID format validation for Israeli IDs — REQUIRES_OWNER_DECISION if compliance checking is required (else stored as text only, recommended default).
- [ ] Auto-classification on posting vs strict rejection — RECOMMENDED_PENDING_VALIDATION (auto-classify recommended; strict mode available per module).
- [ ] Multi-contact table — deferred until needed (RECOMMENDED_PENDING_VALIDATION).

## M. Source evidence
| Claim | Evidence source | Observed on | Confidence |
|---|---|---|---|
| Unified party; distinct AR/AP | `15_DECISION_LOG.md` D-016 | 2026-10-20 | OWNER_APPROVED |
| AR/AP derived from posted entries; no stored balances | `15_DECISION_LOG.md` D-017 | 2026-10-20 | OWNER_APPROVED |
| Immutability + linked reversals | `15_DECISION_LOG.md` D-019 | 2026-10-20 | OWNER_APPROVED |
| Offline pending → server posts in transaction order | `15_DECISION_LOG.md` D-006 | 2026-10-20 | OWNER_APPROVED |
| ILS / 2dp HALF_UP | `15_DECISION_LOG.md` D-005 | 2026-10-20 | OWNER_APPROVED |
| Classification flags, reconciliation proofs | 2026-10-20 parties/cash planning report + this spec | 2026-10-20 | PROPOSED / RECOMMENDED_PENDING_VALIDATION |

**Gate:** keep DRAFT until O7/O10 (shared with `features/09`) and the security validation of the RPC/RLS model are resolved.
