# Hasad ERP V2 - Cleanup Scripts Index

**Target:** Supabase DEV `sxasnunzspkuwbxiddqd`  
**Status:** NOT AUTHORIZED FOR EXECUTION - LOCAL TEMPLATES ONLY  
**Created:** Local files only, no remote execution

## Executable Script Files Created

| Script | Type | Phase | Purpose | Safety |
|---|---|---|---|---|
| `scripts/cleanup/00_preflight_check.sh` | Bash | Preflight | Validate environment, project ref, required files | READ-ONLY validation |
| `scripts/cleanup/01_remove_cron_job5.sql` | SQL Template | 1 | Remove/suspend cron job 5 BEFORE functions | Requires authorization, dependency check first |
| `scripts/cleanup/02_drop_triggers.sql` | SQL Template | 2 | Drop 6 legacy triggers | Explicit drops, no schema CASCADE |
| `scripts/cleanup/03_drop_rls_policies.sql` | SQL Template | 3 | Drop 53 legacy RLS policies (all in `public`) | Explicit per-policy drops |
| `scripts/cleanup/03b_remove_legacy_storage_policies.sql` | SQL Template | 3b | Drop **3** legacy application policies on `storage.objects` (`tenant_isolated_pdf_select/_insert/_delete`) | **Separate scope item**; exact-identity, no CASCADE, own authorization token; must run **before** Stage 4 |
| `scripts/cleanup/04_drop_functions.sql` | SQL Template | 4 | Drop 33 legacy functions with full signatures | After triggers/policies/cron **and Stage 3b** |
| `scripts/cleanup/05_drop_tables.sql` | SQL Template | 5 | Drop 22 legacy tables in FK leaf-first order | No broad CASCADE, coordinate with Auth |
| `scripts/cleanup/06_remove_auth_users.sh` | Bash Template | 6 | Remove 4 auth.users via Auth Admin API | NO direct SQL on auth.users, uses service_role securely |
| `scripts/cleanup/07_remove_storage_bucket.sh` | Bash Template | 7 | Remove bucket pdfs via Storage API | Only if empty (0 objects), verified ownership |
| `scripts/cleanup/08_post_cleanup_verify.sql` | SQL (Read-Only) | 8 | Post-cleanup verification | SAFE - runs in READ ONLY transaction with ROLLBACK |

## Execution Order (When Authorized)
1. Run `00_preflight_check.sh`
2. Run `scripts/inventory/cron_job5_dependency_readonly.sql` (owner-operated)
3. Execute Phase 1: `01_remove_cron_job5.sql` (if authorized)
4. Execute Phase 2: `02_drop_triggers.sql`
5. Execute Phase 3: `03_drop_rls_policies.sql` (53 `public` policies)
6. Execute Phase 3b: `03b_remove_legacy_storage_policies.sql` (3 `storage.objects` policies; **separate authorization required**)
7. Execute Phase 4: `04_drop_functions.sql`
8. Execute Phase 5: `05_drop_tables.sql`
9. Execute Phase 6: `06_remove_auth_users.sh` (Auth Admin API)
10. Execute Phase 7: `07_remove_storage_bucket.sh` (Storage API)
11. Execute Phase 8: `08_post_cleanup_verify.sql`

## Critical Notes
- Stage 3b exists because three `storage.objects` policies (`tenant_isolated_pdf_*`) depend on `public.get_my_tenant_id()` and block Stage 4. They are **not** part of the 53 `public` policies and are **not** covered by the public-schema cleanup authorization; they need their own token (`cleanup_storage_policy_scope`).
- All SQL templates use an authorization gate plus an explicit transaction; destructive statements run only in `EXECUTE` mode, otherwise the transaction is rolled back
- Auth removal MUST use Auth Admin API, NOT direct SQL
- Cron jobid 5 is **owner-confirmed ABSENT** (2026-10-25); recheck `cron.job` at execution. Stage 3b must still run before Stage 4
- Protected objects preserved: auth, storage, realtime, cron, extensions, net, vault, pgtap, pg_net
- No DROP SCHEMA, no V2 object creation
- D-026 waiver applies to backup/restore prerequisites only
- Status: NOT AUTHORIZED FOR EXECUTION
