-- =====================================================================
-- Hasad ERP V2 - DEV CLEANUP SCRIPT 02: Drop Triggers (FIXED v1)
-- =====================================================================
-- Target: Supabase DEV project sxasnunzspkuwbxiddqd
-- Status: REQUIRES EXPLICIT AUTHORIZATION
-- Purpose: Drop exactly 6 legacy triggers before policies/functions
-- Safety: Strict identity assertions, project-bound auth, allowlist only, fail-closed
-- =====================================================================

\set ON_ERROR_STOP on

-- Map psql variables to session GUCs (psql -v vars are not auto-GUCs)
SELECT set_config('cleanup.authorized', COALESCE(NULLIF(:'cleanup_authorized',''), 'false'), false);
SELECT set_config('cleanup.project_ref', COALESCE(NULLIF(:'cleanup_project',''), ''), false);
SELECT set_config('cleanup.mode', COALESCE(NULLIF(:'cleanup_mode',''), 'DRY_RUN'), false);

-- Authorization gate (top level, fail-closed)
DO $cleanup_authz$
BEGIN
  IF current_setting('cleanup.authorized', true) IS DISTINCT FROM 'true' THEN
    RAISE EXCEPTION 'AUTHORIZATION REQUIRED: cleanup.authorized not set to true';
  END IF;
  IF current_setting('cleanup.project_ref', true) IS DISTINCT FROM 'sxasnunzspkuwbxiddqd' THEN
    RAISE EXCEPTION 'PROJECT MISMATCH: cleanup.project_ref must be sxasnunzspkuwbxiddqd';
  END IF;
  IF current_setting('cleanup.mode', true) NOT IN ('DRY_RUN', 'EXECUTE') THEN
    RAISE EXCEPTION 'INVALID MODE: cleanup.mode must be DRY_RUN or EXECUTE';
  END IF;
END
$cleanup_authz$;

BEGIN;

-- Verify expected triggers exist with exact identities
DO $verify_triggers_before$
DECLARE
  v_count_trg_set_tenant int;
  v_count_trg_seed int;
  v_total int;
BEGIN
  -- trg_set_tenant on specific tables
  SELECT COUNT(*) INTO v_count_trg_set_tenant
  FROM pg_trigger t
  JOIN pg_class c ON c.oid = t.tgrelid
  JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'public'
    AND NOT t.tgisinternal
    AND t.tgname = 'trg_set_tenant'
    AND c.relname IN ('customers', 'employees', 'expenses', 'products', 'suppliers');

  IF v_count_trg_set_tenant != 5 THEN
    RAISE EXCEPTION 'TRIGGER IDENTITY MISMATCH: expected trg_set_tenant on 5 tables (customers,employees,expenses,products,suppliers), found %', v_count_trg_set_tenant;
  END IF;

  -- trg_seed_tenant_settings on tenants
  SELECT COUNT(*) INTO v_count_trg_seed
  FROM pg_trigger t
  JOIN pg_class c ON c.oid = t.tgrelid
  JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'public'
    AND NOT t.tgisinternal
    AND t.tgname = 'trg_seed_tenant_settings'
    AND c.relname = 'tenants';

  IF v_count_trg_seed != 1 THEN
    RAISE EXCEPTION 'TRIGGER IDENTITY MISMATCH: expected trg_seed_tenant_settings on public.tenants, found %', v_count_trg_seed;
  END IF;

  v_total := v_count_trg_set_tenant + v_count_trg_seed;
  IF v_total != 6 THEN
    RAISE EXCEPTION 'TRIGGER COUNT MISMATCH: expected 6 triggers total, found %', v_total;
  END IF;

  RAISE NOTICE 'Verified 6 legacy triggers: trg_set_tenant on customers/employees/expenses/products/suppliers (5), trg_seed_tenant_settings on tenants (1)';
END
$verify_triggers_before$;

-- DRY_RUN/EXECUTE gating (valid psql boolean)
SELECT (current_setting('cleanup.mode', true) = 'EXECUTE') AS exec_flag_bool \gset

\if :exec_flag_bool
  -- Drop triggers explicitly (EXECUTE only)
  DROP TRIGGER IF EXISTS trg_set_tenant ON public.customers;
  DROP TRIGGER IF EXISTS trg_set_tenant ON public.employees;
  DROP TRIGGER IF EXISTS trg_set_tenant ON public.expenses;
  DROP TRIGGER IF EXISTS trg_set_tenant ON public.products;
  DROP TRIGGER IF EXISTS trg_set_tenant ON public.suppliers;
  DROP TRIGGER IF EXISTS trg_seed_tenant_settings ON public.tenants;

  -- Verify removal
  DO $verify_triggers_after$
  DECLARE
    v_count int;
  BEGIN
    SELECT COUNT(*) INTO v_count
    FROM pg_trigger t
    JOIN pg_class c ON c.oid = t.tgrelid
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public'
      AND NOT t.tgisinternal
      AND t.tgname IN ('trg_set_tenant', 'trg_seed_tenant_settings');

    IF v_count != 0 THEN
      RAISE EXCEPTION 'POST-DROP VERIFICATION FAILED: % triggers remain', v_count;
    END IF;

    RAISE NOTICE 'All legacy triggers dropped successfully - VERIFIED REMOVED';
  END
  $verify_triggers_after$;

  COMMIT;
  SELECT 'SCRIPT 02 COMPLETED (EXECUTE)' AS status;
\else
  -- DRY_RUN: read-only checks, no drops
  ROLLBACK;
  SELECT 'SCRIPT 02 COMPLETED (DRY_RUN - ROLLED BACK, NO DROPS)' AS status;
\endif
