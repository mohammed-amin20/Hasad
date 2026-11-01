# HASAD V2 — Test and Release Gates
**Status: DRAFT**

1. Fresh migration install on an isolated disposable Supabase project; verify object catalog matches canonical schema.
2. SQL/RLS: real JWT tests for all roles, tenant A/B, anon denial, direct finance write denial, unsafe DEFINER paths.
3. Accounting: debit=credit, GL/subledger inventory reconciliation, discounts/taxes/rounding, reversed and locked periods.
4. Offline: crash/restart, outbox idempotency, two devices, connection drop, failed queue recovery, stale report messaging.
5. Flutter: logic, golden/widget, Arabic RTL, keyboard focus, large layout, print/PDF, installed Windows release.
6. Operations: artifacts and restore rehearsal on isolated target, minimal privileges, rollout and rollback decision.

Never run state-creating financial regression SQL against live business tenants without a disposable test database and separate approval.
