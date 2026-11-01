# HASAD V2 — Requirements and Scope
**Status: DRAFT (revised 2026-10-20; business scope approved — decisions recorded in `15_DECISION_LOG.md`)**
Decisions are owner-owned. This document states **approved business requirements**;
implementation details live in `15_DECISION_LOG.md` and are explicitly separated below.

## Approved initial scope — 12 business modules (APPROVED, D-004)

| # | Module | Feature spec | Approved highlights (decision IDs) |
|---|---|---|---|
| 1 | Tenants, companies and users | `features/01` | Each user belongs to **one company only** (D-003) |
| 2 | Roles and permissions | `features/02` | Company owner has **full business permissions** and assigns employees **predefined roles with individually customizable permissions** (D-004) |
| 3 | Chart of accounts | `features/03` | — |
| 4 | Journal entries and fiscal periods | `features/04` | Balanced postings; **no edit/delete of posted documents** — corrections via **linked reversals or credit/debit notes** (D-019); FY Jan 1–Dec 31, monthly periods, **strict closing, audited privileged reopening** (D-005) |
| 5 | Customers and suppliers | `features/05` | **One unified party record**; receivables and payables kept **distinct** (D-016) |
| 6 | Cash and bank management | `features/09` | — |
| 7 | Sales and invoicing | `features/06` | VAT **optional/configurable**; invoice-level **inclusive/exclusive** choice; tax grouped **by rate**, group-total rounded (D-005); final amounts **2dp, HALF_UP**, base currency **ILS** (D-005) |
| 8 | Purchases | `features/07` | Same monetary/tax rules as sales (D-005) |
| 9 | Inventory and warehouses | `features/08` | **Moving weighted average**; **negative inventory prohibited** (D-014) |
| 10 | Expenses | `features/10` | Same monetary/tax rules (D-005) |
| 11 | Financial reports | `features/12` | AR/AP balances **derive from posted entries**, optional rebuildable summaries (D-017) |
| 12 | Employees and payroll (full) | `features/11` | Included in initial scope (D-015); **statutory rules pending** → D-024 |

## Approved shared requirements (cross-cutting, binding on all modules)

1. **Offline-first** — entry is allowed offline but documents remain **pending**; the server validates, assigns official numbers, and posts **in transaction order**; **inventory conflicts are rejected and kept locally** for correction and retry (D-006, D-018). Offline documents show **temporary local references**; official sequential numbers come from the server on final approval (D-013, D-018).
2. **Security and tenancy** — one company per user (D-003); offline uses last-known permissions, **rechecked at sync**; after detected revocation the **local company data is locked** and pending operations are preserved; offline access **expires 24 hours** after the last successful server-side permission verification (D-020). Local SQLite **encrypted**, keys in platform secure storage, **local PIN** unlock (D-021).
3. **Document numbering** — per **company + document type + fiscal year**, restarting annually; official numbers are server-issued and gap-controlled by the posting transaction (D-013, D-018).
4. **Audit logging** — every posting, reversal, period reopening, and permission change is recorded with actor, time, company, and reference; audit records are append-only. (Full audit-trail specification is pending in `features/02`/`features/04`; this requirement is binding.)
5. **Arabic RTL and printing** — Arabic RTL is the default interface; number and date formats follow **tenant settings, not the device locale**; printed documents (invoices, reports, receipts) must support Arabic; PDF/printing engine validation is pending (see R-05/R-06 note in the decision log).
6. **Accounting integrity** — double-entry, balanced per entry, server-atomic posting, immutability of posted entries (D-019); GL, subledgers, and stock valuation must reconcile (`09_ACCOUNTING_INVARIANTS.md`).

## Approved decisions that still contain OPEN sub-items
- D-005 approved the tax **mechanics**; the actual **VAT rate and jurisdiction-specific requirements** remain OPEN → **D-023**.
- D-015 approved the payroll **scope**; **payroll legislation and statutory deductions** remain OPEN → **D-024**.
- D-022 approved the recovery **requirement**; the **exact encryption-key/PIN recovery mechanism** remains OPEN within D-022.
- **D-025 OPEN**: whether pending offline documents affect displayed inventory availability (recommendation: only server-posted stock counts).
- D-011 OPEN: Storage objects, external integrations, and migration history at reset time.

## Undecided implementation details (RECOMMENDED_PENDING_VALIDATION — NOT approved)
Recorded as R-01…R-09 in `15_DECISION_LOG.md`: Supabase schema organization; RPC
security model and grants; tenant isolation and session context; cross-device sync
sequence and changelog ordering; SQLCipher implementation and key recovery; Flutter
libraries and state management; monetary intermediate precision; UUID version;
migration tooling. **No schema, API contract, or Flutter structure may be treated
as approved until validated and recorded.**

## Proposed later phases (PROPOSED — confirm at release review)
Bank reconciliation, fixed assets, multi-currency, credit limits, stock speed
reports, POS, external integrations (SMS/accounting exports). Not approved scope;
list is revisited after first release.

## Approval gate
No final SQL until all financial and tenancy rules are agreed and recorded in
`15_DECISION_LOG.md`. Each module follows `FEATURE_SPEC_TEMPLATE.md` (sections
A–M); nothing moves to implementation until its specification is `APPROVED`.
