# HASAD V2 — Target Architecture
**Status: PROPOSED, not existing implementation proof**

`Flutter Windows Arabic RTL` → `application/use-cases + domain` → `SQLite local store/outbox` ↔ `Sync/reconciliation` ↔ `Supabase Auth + Postgres tables/RPC/RLS`.

## Boundaries
- Widgets never write finance tables directly.
- One server-authoritative transaction RPC per posting action; atomic, tenant scoped, role gated, idempotent.
- UI reports state freshness and pending/failed local mutations.
- SQLite stores explicit local projections and outbox; schema versioned with tested migrations.
- PostgreSQL source of truth for posted financial and stock effects.

## Layering (proposal)
`lib/app`, `lib/core`, `lib/features/<module>/{domain,application,data,presentation}`, `lib/sync`, `lib/database`.
Do not restructure the existing app until approved, and audit its actual layout before naming physical paths.
