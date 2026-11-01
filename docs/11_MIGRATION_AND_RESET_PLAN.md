# HASAD V2 — Migration and Environment Plan
**Status: DRAFT — NO DELETION AUTHORIZED (updated 2026-10-21: owner Decisions A/B
recorded as D-026/D-027; D-010/D-012 approval status reflected in Part A)**

This document is the **single source of truth** for (A) how V2 migrations are
applied to the reused DEV project and (B) the plan for the **future DEV reset**.
No step below is authorized to execute now. Any destructive operation requires a
separate explicit authorization naming the exact project and objects.

- Reused DEV project (approved D-001): `sxasnunzspkuwbxiddqd`.
- Production remains out of scope entirely.
- Existing DEV may contain business data; do not assume otherwise.
- Hasad V1 source/migrations do not determine V2 (approved D-008); migration
  numbering must not be inferred from any V1 filenames.
- Complete read-only metadata inventory **VERIFIED** 2026-10-21:
  `local_audit/DEV_INVENTORY_20261021_192155.txt` (see D-028).

## Part A — V2 migration plan (forward-only, additive)
1. V2 migrations live in `supabase/migrations/` (folder to be created when the
   first migration is approved), numbered forward-only and reviewed one by one.
   Tooling and numbering convention: **APPROVED as D-012 (2026-10-21, tooling
   scope only — no files created and no CLI run)**.
2. Migrations are applied to the reused DEV project **additively**; V2 objects are
   isolated from legacy objects (isolation strategy: **APPROVED as D-010
   (2026-10-21, design scope only): private `hasad` + exposed `hasad_api` — no
   schema created**). Legacy tables are neither read, modified, nor dropped by V2
   migrations.
3. Each migration records its actual deployment evidence (project ref, date,
   checksum). Deployment is never inferred from a filename.
4. Every migration is tested first on a disposable target and accompanied by the
   acceptance checks of `13_TEST_STRATEGY.md`.
5. No drop/truncate/delete/reset statement may appear in a V2 migration without a
   separately approved and executed plan.

## Part B — Future DEV reset plan (SEPARATE OPERATION — NOT AUTHORIZED)
The reset is designed as a standalone operation that must be explicitly approved
on its own. It must include, at minimum:

1. **Exact project identity** — operator confirms the DEV project ref
   `sxasnunzspkuwbxiddqd` and that production is unreachable from every step.
2. **Complete read-only inventory** — affected database objects (tables, views,
   functions, triggers, policies, grants, indexes, extensions), **Supabase Auth
   users**, Storage buckets/objects, Edge Functions, scheduled jobs, webhooks,
   API keys in use, and external integrations. SELECT-only; results recorded in
   `legacy_audit/`.
3. **Removal scope (approved in principle by Decision B, 2026-10-21; execution
   not authorized)** —
   - old Hasad business data,
   - application-owned database objects (legacy public tables, views, RPC functions),
   - **old Supabase Auth users** (identities and their dependent records),
   - **Storage buckets and objects** (owner Decision B, 2026-10-21),
   - **Edge Functions** (owner Decision B, 2026-10-21),
   - **webhooks, cron jobs and external integrations** (owner Decision B, 2026-10-21),
   - **legacy application-specific configuration and secrets**, where ownership is
     confirmed (owner Decision B, 2026-10-21).
   Supabase-managed infrastructure, platform roles, extensions (including
   extension-owned objects in `public` such as `pgtap` and `pg_net`) and shared
   services are **preserved** unless separately reviewed and explicitly authorized.
   Residual D-011 items remain PENDING INVENTORY (see §9 below).
4. **Fresh full backup** of the DEV project with exact source, timestamp, and
   SHA-256 manifest, passing integrity verification. Integrity alone is not
   enough: backups contain sensitive data and stay out of Git and AI chat.
   > **EXCEPTION — D-026 (owner Decision A, 2026-10-21).** For the specific
   > disposal of Hasad V1 disposable test data in this DEV project
   > (`sxasnunzspkuwbxiddqd`), this fresh-backup prerequisite is **WAIVED**. The
   > owner accepts that deleted legacy test data may be permanently unrecoverable.
   > The exception applies **ONLY** to the identified Hasad V1 cleanup in this DEV
   > project. It does **not** waive backup, recovery or verification requirements
   > for future V2 production operations, other projects, or unrelated destructive
   > actions.
5. **Isolated restore drill** proving recoverability on a separate database,
   followed by catalog/security/accounting spot checks. A restore has never been
   proven by checksum checks alone.
   > **EXCEPTION — D-026 (owner Decision A, 2026-10-21).** For the specific
   > disposal of Hasad V1 disposable test data in this DEV project, this
   > isolated-restore-drill prerequisite is **WAIVED**, with the same scope and
   > limits as item 4 above.
6. **Reviewed deletion plan** listing every object and Auth user to remove, with
   preflight and postflight verification queries, plus post-reset verification
   that Supabase-managed services still function.
7. **Separate explicit authorization** from the owner naming the exact project,
   the exact objects/Auth users/data, the destructive method, and the recovery
   plan — issued only after items 1–6 are satisfied (items 4–5 as excepted by D-026).
8. **Wording guard** — dropping the `public` schema does **not** reset Supabase
   completely: Auth users, Storage, Realtime, Edge Functions, extensions,
   webhooks, and scheduled jobs survive a schema drop and must each be addressed
   explicitly. Supabase-managed schemas and Auth tables must never be altered
   through arbitrary SQL; identity removal uses supported Supabase tooling under
   the approved plan.

Historical checklist preserved verbatim at
`legacy_audit/DEV_RESET_SAFETY_GATE.md` (**REFERENCE ONLY — NOT V2 DESIGN**);
this Part B supersedes it as the authoritative plan.

### Part B §9 — Remaining platform inventory (PENDING INVENTORY)

The database-object inventory is complete and verified (D-028). The following
platform resources are **PENDING INVENTORY** and must be captured metadata-only
before any destructive step. **Never collect passwords, tokens, secret values,
API keys, or business records** — names, counts, timestamps and configuration
keys only.

| Resource | Method (metadata only) | Status |
|---|---|---|
| Auth users and hooks | Supabase Dashboard / Auth admin API — list user IDs, email-domain counts, created_at, provider; **never** password hashes | PENDING INVENTORY |
| Storage buckets and objects | `supabase storage ls` — bucket names and object counts only | PENDING INVENTORY |
| Edge Functions | `supabase functions list` — names and versions only | PENDING INVENTORY |
| Webhooks / external API consumers | Dashboard Database Webhooks + Network restrictions; list names/targets | PENDING INVENTORY |
| Cron jobs | `cron.job` metadata (job name, schedule, active) — no job payloads if they embed secrets | PENDING INVENTORY |
| Application secrets and configuration | Dashboard secrets **name list only**; values never read or exported | PENDING INVENTORY |

Until this inventory is complete, D-011's residual remainder stays OPEN and the
affected resources remain **NOT AUTHORIZED FOR EXECUTION**.

### Part B §10 — Draft cleanup manifest

The exact object-level cleanup manifest (verified facts, proposed cleanup
objects, protected objects, dependency-aware sequence, post-cleanup verification
checklist, and unresolved-ownership items) is maintained separately at
`docs/legacy_audit/DEV_CLEANUP_MANIFEST_DRAFT.md` (**DRAFT — NOT AUTHORIZED FOR
EXECUTION**). That manifest is evidence and planning only and does not itself
authorize any deletion.
