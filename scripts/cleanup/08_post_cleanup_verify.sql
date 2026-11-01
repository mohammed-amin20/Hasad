-- =====================================================================
-- Hasad ERP V2 - DEV CLEANUP SCRIPT 08: Post-Cleanup Verification (PHASE 8)
-- =====================================================================
-- Target: Supabase DEV project sxasnunzspkuwbxiddqd
-- Status: READ-ONLY VERIFICATION - SAFE TO RUN
-- Purpose: Verify cleanup completed correctly
-- =====================================================================

\set ON_ERROR_STOP on

SET default_transaction_read_only = on;
SET statement_timeout = '60s';

BEGIN TRANSACTION READ ONLY;

\echo '=================================================='
\echo 'HASAD V2 DEV CLEANUP - POST-CLEANUP VERIFICATION'
\echo '=================================================='
\echo ''

-- 1. Check legacy tables removed
\echo '--- Legacy Tables (expect 0) ---'
SELECT COUNT(*) AS legacy_tables_remaining
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public'
  AND c.relkind = 'r'
  AND c.relname IN (
    'accounts','commission_dues','customers','employee_movements','employees',
    'expenses','invoice_counters','invoice_items','invoices','journal_entries',
    'journal_entry_lines','payments','processed_requests','products','reminder_log',
    'salaries','stock_moves','suppliers','tenant_settings','tenants','user_tenants','users'
  );

-- 2. Check legacy functions removed
\echo ''
\echo '--- Legacy Functions (postgres-owned, expect 0) ---'
SELECT COUNT(*) AS legacy_functions_remaining
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proowner = 'postgres'::regrole
  AND p.proname IN (
    '_fire_reminder','add_employee_movement','adjust_inventory','create_account',
    'create_journal_entry','create_purchase_invoice','create_sale_invoice',
    'get_balance_sheet','get_chart_of_accounts','get_dashboard_summary',
    'get_employee_entitlement','get_income_statement','get_journal_entries',
    'get_ledger','get_my_role','get_my_tenant_id','get_my_user',
    'get_party_statement','get_trial_balance','get_user_tenants',
    'next_invoice_no','next_journal_no','pay_salary','record_payment',
    'register_tenant','seed_chart_of_accounts','seed_tenant_settings',
    'send_due_reminders','send_reminder_now','send_reminders_to_all',
    'set_master_tenant','settle_supplier','switch_tenant'
  );

-- 2b. Stage 3b: the 3 authorized legacy storage.objects policies (expect 0)
\echo ''
\echo '--- Stage 3b: legacy storage.objects policies (expect 0) ---'
SELECT COUNT(*) AS legacy_storage_policies_remaining
FROM pg_policy po
JOIN pg_class c ON c.oid = po.polrelid
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'storage'
  AND c.relname = 'objects'
  AND po.polname IN (
    'tenant_isolated_pdf_select',
    'tenant_isolated_pdf_insert',
    'tenant_isolated_pdf_delete'
  );

-- 2c. Stage 3b side effect: storage.objects must have 0 policies in total
--     (the known pre-cleanup state was exactly these 3).
\echo ''
\echo '--- storage.objects policy total + names (expect 0 / none) ---'
SELECT COUNT(*) AS storage_objects_policy_total,
       COALESCE(string_agg(po.polname, ', ' ORDER BY po.polname), '(none)') AS policy_names
FROM pg_policy po
JOIN pg_class c ON c.oid = po.polrelid
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'storage'
  AND c.relname = 'objects';

-- 2d. No policy anywhere may still depend on public.get_my_tenant_id()
\echo ''
\echo '--- Policies depending on public.get_my_tenant_id (expect 0) ---'
SELECT COUNT(*) AS policies_depending_on_get_my_tenant_id
FROM pg_policy po
JOIN pg_depend d
  ON d.classid = 'pg_policy'::regclass
 AND d.objid = po.oid
 AND d.refclassid = 'pg_proc'::regclass
JOIN pg_proc p ON p.oid = d.refobjid
JOIN pg_namespace pn ON pn.oid = p.pronamespace
WHERE pn.nspname = 'public'
  AND p.proname = 'get_my_tenant_id';

-- 2e. storage.objects management state (must match the pre-cleanup values:
--     owner supabase_storage_admin, RLS enabled, force RLS off)
\echo ''
\echo '--- storage.objects state (no change expected) ---'
SELECT pg_get_userbyid(c.relowner) AS table_owner,
       c.relrowsecurity          AS rls_enabled,
       c.relforcerowsecurity     AS force_rls
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'storage'
  AND c.relname = 'objects';

-- 3. Check cron job 5 removed/suspended
\echo ''
\echo '--- Cron Job 5 (expect removed or inactive) ---'
SELECT jobid, jobname, active 
FROM cron.job 
WHERE jobid = 5;

-- 4. Check protected schemas exist
\echo ''
\echo '--- Protected Schemas Check ---'
SELECT schema_name 
FROM information_schema.schemata 
WHERE schema_name IN ('auth','storage','realtime','cron','extensions','net','vault')
ORDER BY schema_name;

-- 5. Check pgtap still present (protected)
\echo ''
\echo '--- pgtap Protection Check ---'
SELECT COUNT(*) AS pgtap_objects_in_public
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public'
  AND c.relname IN ('pg_all_foreign_keys','tap_funky');

-- 6. Check for V2 schemas (should not exist)
\echo ''
\echo '--- V2 Schemas (expect 0) ---'
SELECT schema_name 
FROM information_schema.schemata 
WHERE schema_name IN ('hasad','hasad_api');

ROLLBACK;
\echo ''
\echo 'ROLLBACK COMPLETE - NO CHANGES'
\echo '=================================================='
