# Feature: [MODULE NAME]

**Status:** DRAFT  
**Version:** 0.1  
**Owner / approval:** TBD  
**Last reviewed:** TBD  
**Evidence:** distinguish OBSERVED / PROPOSED / APPROVED / VERIFIED

## A. Why this feature exists
Business problem, scope, terminology and exclusions.

## B. Roles and user stories
For each role: actor → action → expected outcome, plus forbidden operations.

## C. Business rules and state transitions
State chart: draft → approved → posted → reversed/cancelled as applicable. Invariants, document numbering, required approvals, rounding, currencies, taxes, fiscal lock behavior. Do not invent rules; mark undecided points.

## D. Data model (PostgreSQL — proposal until approved)
For each table: name, purpose, PK, columns + types + nullability + default, tenant key, FKs, UNIQUE, CHECK, indexes, archive/delete policy, row ownership, created/updated timestamps.

| Table | Purpose | Tenant scope | Key references | Status |
|---|---|---|---|---|
| TBD | TBD | TBD | TBD | PROPOSED |

## E. RLS / grants / RPCs
Role permissions matrix. Explicit deny rules. Safe SQL functions, search_path, SECURITY INVOKER/DEFINER justification, tenant isolation and idempotency.

## F. Offline SQLite and synchronization
Local schema or cache, sync ownership/direction, offline creates/updates, UUID generation, client mutation queue, conflict policy, deletion/tombstones, retry and error recovery.

## G. Accounting impact (if any)
Event → debit / credit accounts, journal relationships, balancing checks, immutability, reversal and period locks. If none, write `No accounting posting` and explain.

## H. UI and Arabic RTL
Screens, fields, validation messages, keyboard/navigation, printing, loading/error/empty states.

## I. API / RPC contract
Request, response, errors, authorization, idempotency, example payloads without secrets.

## J. Tests and acceptance criteria
Unit, integration, permissions/RLS, offline/sync, concurrency, accounting and recovery tests; clear pass/fail examples. Test only disposable datasets.

## K. Rollout and migration
Dependencies, additive migration plan, compatibility, verified backup preconditions, explicit data migration strategy, rollback decision. No destructive steps until approved.

## L. Open questions and decisions
- [ ] [Question] — owner decision required

## M. Source evidence
| Claim | Evidence source/path or DEV query | Observed on | Confidence |
|---|---|---|---|
| TBD | TBD | TBD | TBD |
