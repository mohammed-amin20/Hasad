# Feature: التقارير / 12_reports
**Status: DRAFT** | **Version:** 0.2 | **Owner approval:** PENDING | **Last reviewed:** 2026-10-20
**Source:** V2 clean-slate design (no Hasad V1 reuse). Bound by `15_DECISION_LOG.md` (D-003, D-005, D-017, D-020, D-024, D-025, R-06/R-07) and the 2026-10-20 expenses & financial reports planning report. Invariants I27–I30 (and I1–I26, I31–I33) in `09_ACCOUNTING_INVARIANTS.md` bind this feature.
**Evidence labels:** `PROPOSED` unless marked `OWNER_APPROVED` (by decision ID), `RECOMMENDED_PENDING_VALIDATION`, or `REQUIRES_OWNER_DECISION`.
**Supersedes:** legacy skeleton OPEN "Freshness and accounting reconciliation scope?" — **answered by design**: freshness = watermark/server-time labels + separate pending counts (§F), reconciliation scope = the identity set in §G/§J (I30). Aging bucket boundaries remain open → **O25**; cash-flow classification remains open → **O26**.

## A. Why this feature exists
Owns the **financial and business reporting catalogue**: 13 reports computed as **pure read projections of posted data** — trial balance, general ledger, P&L, balance sheet, cash/bank statements, party statements, AR/AP aging, sales/purchases summaries, VAT management summary, inventory quantity & valuation, expenses summary, payroll-cost summary — plus Arabic RTL export (PDF/spreadsheet), report authorization (including payroll-data restrictions), offline freshness labeling and reconciliation proofs.

Exclusions: authoring or storing any balance (D-017 — reports never store authoritative figures); statutory tax returns (**the VAT management summary is explicitly NOT an official tax return — D-023**); payroll per-employee reporting (features/11, D-024); document semantics (features/04–10); cash-flow statement (**not in v1 — O26**).

## B. Roles and user stories
- **`reports.view` holder** → runs all standard financial reports, sees freshness labels and pending counts.
- **`reports.export` holder (recommended code; may fold into `reports.view` — open with the role catalogue)** → exports Arabic PDF/CSV/XLSX (writes `report.exported` audit).
- **`payroll.view` holder** → additionally sees payroll-cost **drill-down** (per-employee detail lives in features/11); **`reports.view` alone never exposes per-employee data** (consistency item G).
- **All members** → see cached report snapshots offline with freshness labels.
- Forbidden: any report figure not derived from posted data; merging pending offline operations into report totals (I29); presenting the VAT summary as a statutory return; netting AR and AP (I12); trusting client-side company/period input without server re-derivation.

## C. Business rules and state transitions
- C1 **Posted-data-only authority:** every figure derives from posted `journal_entries/lines`, posted documents, `payment_allocations`, and `stock_movements` at query time. **No report tables, no stored balances** (D-017 OWNER_APPROVED); optional future summaries must be rebuildable, versioned and never authoritative.
- C2 **Parameters:** each report takes `company_id` (derived server-side, R-03 — never trusted from the client), a date range or `as_of` that must resolve to real fiscal periods of the company; invalid ranges ⇒ `REPORT_RANGE_INVALID`. Responses carry the **meta block**: server `generated_at`, `last_public_seq` (sync watermark), per-period statuses, currency ILS + 2dp/HALF_UP note, and the report definition version.
- C3 **Fiscal-period and closed-period behavior:** reports reflect the **current posted state** of the filtered range. Closed periods are stable history (I4) — a period-closed report never changes from later postings **unless a privileged audited reopen occurs**, which legitimately changes reported history; the meta block exposes period statuses (`open/closed/reopened count`) so consumers can see this. **Opening balances** enter reports as ordinary posted opening entries (`entry_kind='opening'`, features/04 C10) — the balance sheet and trial balance include them by date; nothing is synthesized.
- C4 **Pending operations:** offline pending operations are **never merged into any figure** (I29). The client displays a separate line: "عمليات بانتظار المزامنة: N" (count from the local outbox) plus the freshness label (last `public_seq`/server time). **D-025 (stock availability display) remains OPEN** and is not resolved by this spec.
- C5 **Report definitions (the 13-report catalogue — deliverable 2):**
  1. **Trial balance** — Σ debit / Σ credit / balance per account for a range; opening + movement + closing; **Σ balance = 0 always** (I1).
  2. **General ledger** — posted lines by account (optionally party-filtered), date-ordered with running derived balance.
  3. **Profit & loss** — revenue − COGS − opex (grouped by expense category/account) for a range; net result ties to equity movement.
  4. **Balance sheet** — A = L + E at `as_of`; AR/AP from control accounts; current-period result line; all derived.
  5. **Cash & bank statement** — lines per container account + reconciliation status (`features/09`), ≡ Σ posted lines (I17).
  6. **Customer/supplier statements** — per party: posted documents, allocations, running derived balance; **AR and AP sections always separate, never netted** (I12).
  7. **AR/AP aging** — open document amounts bucketed by age as-of; bucket boundaries **O25 (REQUIRES_OWNER_DECISION; recommended 0–30 / 31–60 / 61–90 / 90+ days)**; open amounts derived exactly as in features/09 (amount − Σ active allocations).
  8. **Sales summary** — invoices/notes by period/party/product: net/tax/gross + revenue movement (ties to I22).
  9. **Purchases summary** — receipts/bills/notes by period/party/category: net/tax/gross (ties to I22/I25).
  10. **VAT management summary** — output vs input VAT by rate for a range. **Mandatory label on screen and export: "ملخص ضريبي إداري — ليس إقرارًا ضريبيًا" (management summary, not a statutory return)**; rates and legal forms remain OPEN (D-023).
  11. **Inventory quantity & valuation** — on-hand qty (rebuildable cache) and value = Σ movement values per product/warehouse; movement register; residual disclosure per I18 (no unrounded-value claims).
  12. **Expenses summary** — by category/account/period/party/container; receipt-missing indicator (C4 of features/10); ties to I27/I29.
  13. **Payroll-cost summary** — **aggregates only by default**: GL totals of payroll-cost accounts. Per-employee detail requires `payroll.view` and is served from features/11; this report is **blocked for detail by D-024** and never reimplements payroll logic (consistency item F/G).
- C6 **Reconciliation identity set (I30):** TB Σ = 0; A = L + E at any `as_of`; P&L net ≡ equity/period-result movement; party statement AR/AP ≡ control-account sums (I14); inventory valuation ≡ Σ movement values (I18); expense summary ≡ Σ expense-module GL legs; container statement ≡ Σ container lines (I17); **export parity**: identical parameters produce identical numbers in UI, PDF and CSV (§J).
- C7 **Audit events:** `report.exported` (report code, params, reporter, row count) — mandatory for exports; plain views are **not** audited (RECOMMENDED — avoids audit flooding; owner may require view auditing).

State chart: reports are stateless reads — no lifecycle. Cached snapshots on the client transition `fresh → stale` by watermark age only.

## D. Data model (PostgreSQL — proposal until approved)
**No tables.** This feature introduces **zero** server tables — no report-balance tables, no authoritative caches (D-017; deliverable 4 explicitly forbids them). The "data model" is **read-model/index requirements** on existing tables (documented in `05_DATABASE_SCHEMA.md` § read-model):
- `journal_lines (company_id, account_id)` covering index joined to `journal_entries (company_id, entry_date, status='posted')`.
- `journal_lines (company_id, party_id)` for statements/aging.
- Document indexes already specified in features/06/07/09/10 for summaries.
- `stock_movements (warehouse_id, posted_at)` and product/warehouse lookups (features/08).
All projections are computed at query time (or by `STABLE` RPC functions); any future summary structure must be rebuildable, versioned and non-authoritative.

## E. RLS / grants / RPCs
- Private `hasad` schema; report RPCs in `hasad_api` **INVOKER, read-only (`STABLE`)**; privilege model **DRAFT pending the isolated security PoC** (`07`).
- Grants: report RPCs only (`EXECUTE` revoked from `PUBLIC` and `anon`); **no table write grants flow from reporting**; report readers need no direct table privileges beyond what INVOKER SELECT requires (documented per-function grant set, R-02).
- Every RPC rederives company from verified membership server-side (R-03) — client-supplied company/period values are consistency checks only; permission gate: `reports.view` (+ `reports.export`, + `payroll.view` for payroll drill-down) via the single `has_permission` resolver (owner → deny → allow → deny).
- **Sensitive payroll restriction (consistency item G):** payroll-cost report rows are account-level aggregates for `reports.view`; any per-employee amount requires `payroll.view` and comes from `features/11` RPCs — report #13 never joins employee-level data without that permission; denied calls return `PERMISSION_DENIED` with no partial rows.

## F. Offline SQLite and synchronization
- Reports are **reads** — nothing is queued in the outbox (no state to post).
- Last successful responses are cached locally with the **meta block intact**: freshness label = last received `public_seq` + server `generated_at`; on offline display the UI shows `تقرير من [date/time] — قد لا يشمل أحدث العمليات` plus the separate pending-op count (C4, I29).
- Cached figures are **UX only**: the cache is never an authorization boundary; on reconnect the watermark resumes per `08_OFFLINE_SYNC.md` (I33); `FEED_TRUNCATED` forces re-fetch rather than trusting a stale cache for decisions.
- Export offline: **online-only in v1** (RECOMMENDED — exports must carry a verifiable freshness stamp and audit event).

## G. Accounting impact (if any)
`No accounting posting` — reports never write journal entries, movements or balances. Binding invariants: **I30** (report reconciliation, authorization, export parity), **I29** (derived figures, pending exclusion), plus every source invariant they surface (I1 TB, I14 party, I17 containers, I18 inventory, I22/I25 trade, I33 freshness). Payment movements are never re-classified as revenue/expense by any report — classification comes solely from posted account types (safeguard). The VAT summary reports `VAT_OUTPUT`/`VAT_INPUT` movements **as posted** and never computes a statutory liability.

## H. UI and Arabic RTL
Arabic RTL screens: report catalogue (١٣ تقرير) with grouped navigation (مالية/مبيعات/مشتريات/مخزون/مصروفات); parameter bar (date range with period-status chips مفتوحة/مغلقة, party/product/warehouse pickers as applicable); result grids with running totals; **freshness banner + separate pending count** (C4); AR/AP tabs always separate; aging bucket table; export sheet (PDF / CSV / XLSX) with `report.exported` confirmation; payroll section visibly marked خاص — restricted badge when `payroll.view` missing. Number/date formats from tenant settings (never device locale). Domain-safe Arabic errors (`النطاق المحدد خارج السنة المالية`). Empty/loading/error/failed-sync states per `14_UI_ARABIC_RTL_STANDARDS.md`; large reports paginate server-side with visible progress.

## I. API / RPC contract
| RPC | Input | Output | Auth | Audit |
|---|---|---|---|---|
| `report_trial_balance(from,to, account?)` | range | rows + meta | `reports.view` | — |
| `report_general_ledger(account, from,to, party?)` | filters | rows + meta | `reports.view` | — |
| `report_profit_loss(from,to)` | range | rows + meta | `reports.view` | — |
| `report_balance_sheet(as_of)` | date | rows + meta | `reports.view` | — |
| `report_cash_statement(container, from,to)` | container + range | rows + meta | `reports.view` | — |
| `report_party_statement(party, from,to)` | party + range | rows + meta | `reports.view` | — |
| `report_party_aging(as_of, side)` | date + AR/AP | buckets + meta | `reports.view` | — |
| `report_sales_summary(from,to, group_by)` | range | rows + meta | `reports.view` | — |
| `report_purchases_summary(from,to, group_by)` | range | rows + meta | `reports.view` | — |
| `report_vat_summary(from,to)` | range | rows + meta (**non-statutory label embedded**) | `reports.view` | — |
| `report_inventory_valuation(as_of, warehouse?)` | date | rows + meta | `reports.view` | — |
| `report_expenses_summary(from,to, group_by)` | range | rows + meta | `reports.view` | — |
| `report_payroll_costs(from,to, detail=false)` | range | aggregates (+ detail only if granted) | `reports.view`; **detail: `payroll.view`** | — |
| `report_export(report, params, format)` | report ref + format | file stream/rows | `reports.export` | `report.exported` |

Typed errors: `REPORT_RANGE_INVALID`, `PERMISSION_DENIED`, `MEMBERSHIP_REQUIRED`, `PAYROLL_DETAIL_DENIED` (or generic `PERMISSION_DENIED`), `REPORT_TOO_LARGE` (pagination required). Meta block always returned; no RPC accepts a client-asserted company.

## J. Tests and acceptance criteria
**Positive:** each of the 13 reports returns correct rows on a realistic month with invoices, bills, receipts, payments, expenses, a reversal and an opening entry; TB Σ = 0; A = L + E across several as-of dates; P&L net ties to equity movement; party statements show AR and AP independently; aging buckets sum exactly to open AR/AP; inventory valuation ≡ Σ movement values with disclosed residual (I18); expense summary ≡ Σ expense GL legs; VAT summary = posted `VAT_OUTPUT`/`VAT_INPUT` sums with the non-statutory label present; closed-period range renders stably and re-renders identically after an audited reopen only when data changed; identical params ⇒ byte-identical totals in UI, PDF and CSV (**export parity**); payroll aggregates visible with `reports.view` alone.
**Negative:** report call with forged/foreign `company_id` ⇒ still own-company rows only (or `MEMBERSHIP_REQUIRED`); period range outside the company's FY ⇒ `REPORT_RANGE_INVALID`; per-employee payroll detail without `payroll.view` ⇒ `PERMISSION_DENIED` **with zero rows disclosed**; `report.exported` missing on export ⇒ failure; any figure sourced from an unposted/draft row ⇒ test failure; pending offline expense/invoice merged into a total ⇒ test failure (I29); a payment movement reported as expense ⇒ classification test failure; VAT summary labeled as a statutory return anywhere in UI/export ⇒ copy test failure; `anon` on every RPC ⇒ denied.
**Concurrency:** two users running large reports while a posting occurs ⇒ each response internally consistent (single-transaction snapshot semantics — documented, not retroactive); export racing a posting ⇒ export stamped with a coherent `generated_at`/watermark; permission revoked mid-session ⇒ next call denied (D-020).
**Reconciliation/convergence:** the identity set of C6 executed as one test suite over the month-end sample (same dataset as features/04 §J); after full sync, device-cached report ≡ server report at equal watermarks (I33 freshness labels match `public_seq`); rebuildability statement: since no report tables exist, "rebuild" = re-query, trivially proven by re-running the suite on the same data. Test only disposable datasets (`13_TEST_STRATEGY.md`).

## K. Rollout and migration
Depends on: all posting modules (04–10) for source data; identity/authorization (`features/01/02`, pending security PoC) for `reports.view`/`payroll.view`/`reports.export` codes joining the owner-pending role catalogue; `features/11` for payroll-cost detail (blocked by D-024); sync watermark contract (`docs/08`). **No migrations** (no tables); index additions ride the migration for the underlying domains. Arabic PDF/CSV engine choice remains under R-06 validation. No V1 data migration (D-002).

## L. Open questions and decisions
- [ ] **O25 (REQUIRES_OWNER_DECISION):** aging bucket boundaries — **recommended default: 0–30 / 31–60 / 61–90 / 90+ days from due date.**
- [ ] **O26 (REQUIRES_OWNER_DECISION):** cash-flow classification/reporting — **recommended default: no cash-flow statement in v1** (container statements only; no cash-basis reporting assumed).
- [ ] **Carried OPEN:** D-023 (VAT rates/forms — VAT summary stays non-statutory), D-024 (payroll — report #13 detail blocked), D-025 (pending-stock display), D-011 (Storage — moot while export is online-only), O5 (accrual basis confirmation), role-catalogue mapping for `reports.view`/`reports.export`/`payroll.view` (features/02 owner decision).
- [ ] Permission granularity: separate `reports.export` vs folded into `reports.view`; view-auditing requirement — REQUIRES_OWNER_DECISION adjacency, recommended defaults above.
- [ ] Server-side aggregation vs client paging for large reports; PDF/CSV Arabic engine (R-06); `STABLE` snapshot semantics under pooling — RECOMMENDED_PENDING_VALIDATION (PoC/benchmark).
- [ ] Follow-up alignment item (file NOT modified in this task): `features/09`/`features/05` `party_statement` RPC ownership vs this catalogue — single implementation, catalogue entry here (recorded, not changed).

## M. Source evidence
| Claim | Evidence source | Observed on | Confidence |
|---|---|---|---|
| AR/AP derived from posted entries; optional rebuildable summaries; no stored balances | `15_DECISION_LOG.md` D-017 | 2026-10-20 | OWNER_APPROVED |
| ILS, 2dp HALF_UP, strict periods, opening entries | `15_DECISION_LOG.md` D-005; `features/04` | 2026-10-20 | OWNER_APPROVED |
| Server-side company isolation + permission checks mandatory | `15_DECISION_LOG.md` D-003; approved shared requirement 2 | 2026-10-20 | OWNER_APPROVED (mechanism pending PoC) |
| Offline freshness, pending exclusion | `15_DECISION_LOG.md` D-006/D-020/D-025; `08_OFFLINE_SYNC.md`; I29/I33 | 2026-10-20 | OWNER_APPROVED / D-025 OPEN |
| Payroll detail restriction | `15_DECISION_LOG.md` D-015/D-024 | 2026-10-20 | Scope APPROVED; rules OPEN |
| 13-report catalogue, meta/freshness design, export parity, reconciliation identities | 2026-10-20 expenses & reports planning report (consistency items A–G applied) | 2026-10-20 | PROPOSED / RECOMMENDED_PENDING_VALIDATION |

**Gate:** keep DRAFT until O25/O26 (and carried D-023/D-024) are decided, the role catalogue is owner-signed, and the security PoC validates the RPC/RLS model.
