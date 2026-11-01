# LEGACY_BACKUP_OBSERVATIONS.md — REFERENCE ONLY — NOT V2 DESIGN

This file contains legacy DEV backup observations extracted from older documentation. They are preserved for reference only and must not be used to derive V2 design.

- Reported Oct 16 `full_20261016_110832_8117893_e738f231ad84439491908f5d5fb404e4.sql.gz` archive checksum passed locally; this is **integrity-only**.
- A fresh Oct 19 artifact was not found in `supabase/production/backups`; do not report it as completed.
- `backup.ps1` stores the password in process `PGPASSWORD`; its parameter invocation can expose secret through logging. Use a reviewed private invocation; do not paste secret into AI chat.
