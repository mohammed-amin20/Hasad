# Supabase DEV reset — safety and approval gate

> **MOVED TO `docs/legacy_audit/` — REFERENCE ONLY — NOT V2 DESIGN.**
> Historical checklist, preserved verbatim. The authoritative reset plan is
> `docs/11_MIGRATION_AND_RESET_PLAN.md` (Part B), which supersedes this file.

**Status: NOT AUTHORIZED.** This checklist is informational; it provides no destructive SQL.

## Target
Existing DEV project reference: `sxasnunzspkuwbxiddqd`. Production remains out of scope. Existing DEV may contain business data; do not assume otherwise.

## Required discovery (read-only)
- Inventory public tables, rows by category (not personal/secret values), views, sequences, functions, triggers, policies, grants, extensions and dependencies.
- Inventory Supabase-managed objects and external integrations (Auth users, Storage buckets/objects, Realtime, scheduled jobs, Edge Functions, secrets, application keys, webhooks).
- Record current app configuration, offline SQLite dependencies, and services pointing at DEV.
- Decide whether a **new, isolated Supabase project** is safer than deleting existing DEV objects.

## Backup/recoverability prerequisites
- Create a fresh full DEV backup, confirm exact source and timestamp, checksum-verify archive and manifest.
- Prefer a separate isolated restore drill; integrity validation alone does not establish restoration capability.
- Preserve older backups, preserve repository state, never put dumps in git.

## Design and authorization prerequisites
- Approved canonical V2 schema and migration order, security policies, API contracts, seed rules and data migration/retention decision.
- Owner explicitly confirms the project ref, the exact objects/data to be removed, the irreversible consequences, and the approved operation.
- Separate execution plan with preflight and postflight checks; production guard verified.

## Stop conditions
Unknown object ownership or dependencies; stale/unverified backup; no restore strategy; unclear current database; any chance of production connection; unread/unclassified data; insufficient explicit approval.

## Current finding to preserve
Previous verified catalog checks found 0031 get_my_role and 0032 get_party_statement matching expected bodies and access, 0033 targeted 17 RPCs secured; main 0035 objects absent. An Oct 16 archive passed checksum integrity, but a fresh Oct 19 backup was **not confirmed created**. None of these checks authorizes deletion.
