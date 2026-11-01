# HASAD V2 — Backup, Integrity and Restore
**Status: DRAFT / RECOVERY NOT VERIFIED (updated 2026-10-21: D-026 scoped exception
for the Hasad V1 DEV legacy cleanup — see below; D-028 inventory recorded)**

> Legacy findings about the OLD environment (Oct 16 archive, Oct 19 artifact,
> `backup.ps1`) moved verbatim to `legacy_audit/LEGACY_BACKUP_OBSERVATIONS.md`
> — REFERENCE ONLY — NOT V2 DESIGN.

- Locate failure/warning logs and check which command actually executed; do not assume output path or success from a silent shell prompt.
- Full DEV backup must identify source host, project ref, timestamp, catalog/version, artifact and SHA-256 manifest.
- Restore test requires separately approved isolated database, actual restore and catalog/security/accounting checks. An isolated restore drill is a mandatory prerequisite of the future DEV reset (`11_MIGRATION_AND_RESET_PLAN.md`, Part B).
- Backups carry sensitive data: local encrypted storage, restricted access, no Git or OpenCode sharing.
- Older archives are preserved unless an explicit retention policy is approved.

## Scoped exception — D-026 (owner Decision A, 2026-10-21)

For the **specific disposal of Hasad V1 disposable test data in DEV project
`sxasnunzspkuwbxiddqd`**, the mandatory **fresh full backup** and **isolated
restore drill** prerequisites (policy lines above and `11_MIGRATION_AND_RESET_PLAN.md`
Part B items 4–5) are **WAIVED**. The owner understands and accepts that deleted
legacy test data may be **permanently unrecoverable**.

**Scope limits — the exception applies ONLY to:**
- the identified Hasad V1 legacy cleanup in DEV project `sxasnunzspkuwbxiddqd`.

**The exception does NOT waive** backup, recovery or verification requirements for:
- future **V2 production operations**,
- any **other project**,
- any **unrelated destructive action**.

All other backup/restore rules in this document remain in force.
