-- =====================================================================
-- Hasad ERP V2 - DEV CLEANUP SCRIPT 03: Drop RLS Policies (PREPARED)
-- =====================================================================
-- Target: Supabase DEV project sxasnunzspkuwbxiddqd
-- Status: PREPARED - NOT EXECUTED - REQUIRES EXPLICIT AUTHORIZATION
-- Purpose: Drop exactly the 53 legacy RLS policies verified against the
--          saved inventory in local_audit/DEV_INVENTORY_20261021_192155.txt
-- Safety: Exact identity set (not just a count), catalog-only allowlist,
--          permission + RLS preconditions, fail-closed, project-bound auth
-- Alignment: Same authorization GUC mapping and psql transaction controls
--            as the successful Stage 2 script (02_drop_triggers.sql)
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

-- ---------------------------------------------------------------------
-- Preconditions: exact policy identities + permissions + RLS state
-- DRY_RUN stops after this block and rolls back; no DROP is sent.
-- ---------------------------------------------------------------------
DO $verify_policies_exact$
DECLARE
  -- 22 allowlisted legacy tables (from saved inventory)
  v_tables text[] := ARRAY[
    'accounts','commission_dues','customers','employee_movements','employees',
    'expenses','invoice_counters','invoice_items','invoices','journal_entries',
    'journal_entry_lines','payments','processed_requests','products','reminder_log',
    'salaries','stock_moves','suppliers','tenant_settings','tenants',
    'user_tenants','users'
  ];

  -- Exact 53 legacy policies from saved inventory, encoded as table|policy
  v_expected text[] := ARRAY[
    'accounts|tenant_isolation_insert',
    'accounts|tenant_isolation_select',
    'commission_dues|tenant_isolation_insert',
    'commission_dues|tenant_isolation_select',
    'commission_dues|tenant_isolation_update',
    'customers|Users can insert customers',
    'customers|Users can select customers',
    'customers|tenant_isolation',
    'employee_movements|tenant_isolation_insert',
    'employee_movements|tenant_isolation_select',
    'employees|tenant_isolation',
    'expenses|tenant_isolation',
    'invoice_counters|tenant_isolation',
    'invoice_items|Users can delete invoice_items',
    'invoice_items|Users can insert invoice_items',
    'invoice_items|Users can select invoice_items',
    'invoice_items|Users can update invoice_items',
    'invoice_items|tenant_isolation_insert',
    'invoice_items|tenant_isolation_select',
    'invoices|Users can delete invoices',
    'invoices|Users can insert invoices',
    'invoices|Users can select invoices',
    'invoices|Users can update invoices',
    'invoices|tenant_isolation_insert',
    'invoices|tenant_isolation_select',
    'invoices|tenant_isolation_update',
    'journal_entries|tenant_isolation_insert',
    'journal_entries|tenant_isolation_select',
    'journal_entry_lines|Users can insert journal_entry_lines',
    'journal_entry_lines|Users can select journal_entry_lines',
    'journal_entry_lines|tenant_isolation_insert',
    'journal_entry_lines|tenant_isolation_select',
    'payments|tenant_isolation_insert',
    'payments|tenant_isolation_select',
    'processed_requests|tenant_isolation',
    'processed_requests|tenant_isolation_insert',
    'processed_requests|tenant_isolation_select',
    'products|Users can delete products',
    'products|Users can insert products',
    'products|Users can select products',
    'products|Users can update products',
    'products|tenant_isolation',
    'reminder_log|tenant_isolation_select',
    'salaries|tenant_isolation_insert',
    'salaries|tenant_isolation_select',
    'stock_moves|Users can insert stock_moves',
    'stock_moves|Users can select stock_moves',
    'stock_moves|tenant_isolation_insert',
    'stock_moves|tenant_isolation_select',
    'suppliers|tenant_isolation',
    'tenant_settings|tenant_isolation',
    'tenants|tenant_isolation_select',
    'users|own_or_same_tenant'
  ];

  v_expected_count int;
  v_actual text[];
  v_actual_count int;
  v_missing_names text;
  v_extra_names text;
  v_bad_tables text;
  v_rls_disabled text;
  v_app_owned text;
  v_no_drop_priv text;
  v_extension_tables int;
  v_extension_policies int;
  v_bypass_roles text;
  v_forced_count int;
BEGIN
  -- 1. Exactly 53 distinct expected identities in this script
  SELECT COUNT(DISTINCT e.value) INTO v_expected_count FROM unnest(v_expected) AS e(value);
  IF v_expected_count <> 53 THEN
    RAISE EXCEPTION 'SCRIPT ALLOWLIST ERROR: expected 53 distinct identities, found %', v_expected_count;
  END IF;

  -- 2. All 22 allowlisted tables exist in public as ordinary/partitioned tables
  SELECT string_agg(t.name, ', ' ORDER BY t.name) INTO v_bad_tables
  FROM unnest(v_tables) AS t(name)
  LEFT JOIN pg_class c
    ON c.relname = t.name
   AND c.relnamespace = 'public'::regnamespace
  WHERE c.oid IS NULL
     OR c.relkind NOT IN ('r', 'p');

  IF v_bad_tables IS NOT NULL THEN
    RAISE EXCEPTION 'TABLE IDENTITY MISMATCH: missing or non-table allowlisted objects: %', v_bad_tables;
  END IF;

  -- 3. RLS must already be enabled on every allowlisted table. If it is not,
  --    policy removal is not a safe temporary control change -> blocker.
  SELECT string_agg(c.relname, ', ' ORDER BY c.relname) INTO v_rls_disabled
  FROM pg_class c
  JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'public'
    AND c.relname = ANY (v_tables)
    AND NOT c.relrowsecurity;

  IF v_rls_disabled IS NOT NULL THEN
    RAISE EXCEPTION 'RLS PRECONDITION FAILED: RLS is disabled on legacy table(s): % - policy removal cannot be assured safe', v_rls_disabled;
  END IF;

  -- 4. Application roles must not own these tables, and must not bypass RLS
  SELECT string_agg(c.relname, ', ' ORDER BY c.relname) INTO v_app_owned
  FROM pg_class c
  JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'public'
    AND c.relname = ANY (v_tables)
    AND pg_get_userbyid(c.relowner) IN ('anon', 'authenticated', 'service_role');

  IF v_app_owned IS NOT NULL THEN
    RAISE EXCEPTION 'OWNERSHIP PRECONDITION FAILED: application role owns legacy table(s): %', v_app_owned;
  END IF;

  SELECT string_agg(rolname, ', ' ORDER BY rolname) INTO v_bypass_roles
  FROM pg_roles
  WHERE rolname IN ('anon', 'authenticated')
    AND rolbypassrls;

  IF v_bypass_roles IS NOT NULL THEN
    RAISE EXCEPTION 'RLS PRECONDITION FAILED: application role(s) bypass RLS: %', v_bypass_roles;
  END IF;

  -- 5. Current role must be able to drop policies (table owner or superuser)
  IF NOT EXISTS (
    SELECT 1 FROM pg_roles WHERE rolname = current_user AND rolsuper
  ) THEN
    SELECT string_agg(c.relname, ', ' ORDER BY c.relname) INTO v_no_drop_priv
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public'
      AND c.relname = ANY (v_tables)
      AND NOT pg_has_role(current_user, c.relowner, 'USAGE');

    IF v_no_drop_priv IS NOT NULL THEN
      RAISE EXCEPTION 'PERMISSION PRECONDITION FAILED: current role % cannot drop policies on: %', current_user, v_no_drop_priv;
    END IF;
  END IF;

  -- 6. No allowlisted table or expected policy may be extension-owned
  SELECT COUNT(*) INTO v_extension_tables
  FROM pg_class c
  JOIN pg_namespace n ON n.oid = c.relnamespace
  JOIN pg_depend d
    ON d.classid = 'pg_class'::regclass
   AND d.objid = c.oid
   AND d.deptype = 'e'
  WHERE n.nspname = 'public'
    AND c.relname = ANY (v_tables);

  IF v_extension_tables <> 0 THEN
    RAISE EXCEPTION 'EXTENSION-OWNED TABLE DETECTED: % allowlisted table(s) belong to an extension', v_extension_tables;
  END IF;

  SELECT COUNT(*) INTO v_extension_policies
  FROM pg_policy p
  JOIN pg_class c ON c.oid = p.polrelid
  JOIN pg_namespace n ON n.oid = c.relnamespace
  JOIN pg_depend d
    ON d.classid = 'pg_policy'::regclass
   AND d.objid = p.oid
   AND d.deptype = 'e'
  WHERE n.nspname = 'public'
    AND c.relname = ANY (v_tables);

  IF v_extension_policies <> 0 THEN
    RAISE EXCEPTION 'EXTENSION-OWNED POLICY DETECTED: % allowlisted policy/policies belong to an extension', v_extension_policies;
  END IF;

  -- 7. Exact identity reconciliation against live catalog (not count-only)
  SELECT COALESCE(
           array_agg(c.relname::text || '|' || p.polname::text ORDER BY c.relname, p.polname),
           ARRAY[]::text[]
         )
  INTO v_actual
  FROM pg_policy p
  JOIN pg_class c ON c.oid = p.polrelid
  JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'public'
    AND c.relname = ANY (v_tables);

  v_actual_count := cardinality(v_actual);

  SELECT string_agg(e.value, ', ' ORDER BY e.value) INTO v_missing_names
  FROM unnest(v_expected) AS e(value)
  WHERE NOT (e.value = ANY (v_actual));

  SELECT string_agg(a.value, ', ' ORDER BY a.value) INTO v_extra_names
  FROM unnest(v_actual) AS a(value)
  WHERE NOT (a.value = ANY (v_expected));

  IF v_actual_count <> 53
     OR v_missing_names IS NOT NULL
     OR v_extra_names IS NOT NULL THEN
    RAISE EXCEPTION 'POLICY SET MISMATCH: expected 53 exact identities; actual=%, missing=[%], unexpected=[%]',
      v_actual_count,
      COALESCE(v_missing_names, 'none'),
      COALESCE(v_extra_names, 'none');
  END IF;

  SELECT COUNT(*) INTO v_forced_count
  FROM pg_class c
  JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'public'
    AND c.relname = ANY (v_tables)
    AND c.relforcerowsecurity;

  RAISE NOTICE 'Verified exact legacy policy set: 53/53 identities present; no missing or extra policies on the 22 allowlisted tables';
  RAISE NOTICE 'Permission preconditions OK as role % (owner/superuser; no extension-owned targets)', current_user;
  RAISE NOTICE 'Access-control precondition: 22/22 tables have RLS enabled (% forced); anon/authenticated do not own or bypass RLS; dropping all policies leaves non-owner table access default-deny (no grants are changed)', v_forced_count;
END
$verify_policies_exact$;

-- DRY_RUN/EXECUTE gating (valid psql boolean)
SELECT (current_setting('cleanup.mode', true) = 'EXECUTE') AS exec_flag_bool \gset

\if :exec_flag_bool
  -- Drop exactly the 53 verified legacy policies (EXECUTE only)
  DROP POLICY IF EXISTS "tenant_isolation_insert" ON public.accounts;
  DROP POLICY IF EXISTS "tenant_isolation_select" ON public.accounts;
  DROP POLICY IF EXISTS "tenant_isolation_insert" ON public.commission_dues;
  DROP POLICY IF EXISTS "tenant_isolation_select" ON public.commission_dues;
  DROP POLICY IF EXISTS "tenant_isolation_update" ON public.commission_dues;
  DROP POLICY IF EXISTS "Users can insert customers" ON public.customers;
  DROP POLICY IF EXISTS "Users can select customers" ON public.customers;
  DROP POLICY IF EXISTS "tenant_isolation" ON public.customers;
  DROP POLICY IF EXISTS "tenant_isolation_insert" ON public.employee_movements;
  DROP POLICY IF EXISTS "tenant_isolation_select" ON public.employee_movements;
  DROP POLICY IF EXISTS "tenant_isolation" ON public.employees;
  DROP POLICY IF EXISTS "tenant_isolation" ON public.expenses;
  DROP POLICY IF EXISTS "tenant_isolation" ON public.invoice_counters;
  DROP POLICY IF EXISTS "Users can delete invoice_items" ON public.invoice_items;
  DROP POLICY IF EXISTS "Users can insert invoice_items" ON public.invoice_items;
  DROP POLICY IF EXISTS "Users can select invoice_items" ON public.invoice_items;
  DROP POLICY IF EXISTS "Users can update invoice_items" ON public.invoice_items;
  DROP POLICY IF EXISTS "tenant_isolation_insert" ON public.invoice_items;
  DROP POLICY IF EXISTS "tenant_isolation_select" ON public.invoice_items;
  DROP POLICY IF EXISTS "Users can delete invoices" ON public.invoices;
  DROP POLICY IF EXISTS "Users can insert invoices" ON public.invoices;
  DROP POLICY IF EXISTS "Users can select invoices" ON public.invoices;
  DROP POLICY IF EXISTS "Users can update invoices" ON public.invoices;
  DROP POLICY IF EXISTS "tenant_isolation_insert" ON public.invoices;
  DROP POLICY IF EXISTS "tenant_isolation_select" ON public.invoices;
  DROP POLICY IF EXISTS "tenant_isolation_update" ON public.invoices;
  DROP POLICY IF EXISTS "tenant_isolation_insert" ON public.journal_entries;
  DROP POLICY IF EXISTS "tenant_isolation_select" ON public.journal_entries;
  DROP POLICY IF EXISTS "Users can insert journal_entry_lines" ON public.journal_entry_lines;
  DROP POLICY IF EXISTS "Users can select journal_entry_lines" ON public.journal_entry_lines;
  DROP POLICY IF EXISTS "tenant_isolation_insert" ON public.journal_entry_lines;
  DROP POLICY IF EXISTS "tenant_isolation_select" ON public.journal_entry_lines;
  DROP POLICY IF EXISTS "tenant_isolation_insert" ON public.payments;
  DROP POLICY IF EXISTS "tenant_isolation_select" ON public.payments;
  DROP POLICY IF EXISTS "tenant_isolation" ON public.processed_requests;
  DROP POLICY IF EXISTS "tenant_isolation_insert" ON public.processed_requests;
  DROP POLICY IF EXISTS "tenant_isolation_select" ON public.processed_requests;
  DROP POLICY IF EXISTS "Users can delete products" ON public.products;
  DROP POLICY IF EXISTS "Users can insert products" ON public.products;
  DROP POLICY IF EXISTS "Users can select products" ON public.products;
  DROP POLICY IF EXISTS "Users can update products" ON public.products;
  DROP POLICY IF EXISTS "tenant_isolation" ON public.products;
  DROP POLICY IF EXISTS "tenant_isolation_select" ON public.reminder_log;
  DROP POLICY IF EXISTS "tenant_isolation_insert" ON public.salaries;
  DROP POLICY IF EXISTS "tenant_isolation_select" ON public.salaries;
  DROP POLICY IF EXISTS "Users can insert stock_moves" ON public.stock_moves;
  DROP POLICY IF EXISTS "Users can select stock_moves" ON public.stock_moves;
  DROP POLICY IF EXISTS "tenant_isolation_insert" ON public.stock_moves;
  DROP POLICY IF EXISTS "tenant_isolation_select" ON public.stock_moves;
  DROP POLICY IF EXISTS "tenant_isolation" ON public.suppliers;
  DROP POLICY IF EXISTS "tenant_isolation" ON public.tenant_settings;
  DROP POLICY IF EXISTS "tenant_isolation_select" ON public.tenants;
  DROP POLICY IF EXISTS "own_or_same_tenant" ON public.users;

  -- Post-drop verification: every expected identity absent and no policy
  -- remaining on any allowlisted legacy table.
  DO $verify_after$
  DECLARE
    v_tables text[] := ARRAY[
      'accounts','commission_dues','customers','employee_movements','employees',
      'expenses','invoice_counters','invoice_items','invoices','journal_entries',
      'journal_entry_lines','payments','processed_requests','products','reminder_log',
      'salaries','stock_moves','suppliers','tenant_settings','tenants',
      'user_tenants','users'
    ];
    v_expected text[] := ARRAY[
      'accounts|tenant_isolation_insert',
      'accounts|tenant_isolation_select',
      'commission_dues|tenant_isolation_insert',
      'commission_dues|tenant_isolation_select',
      'commission_dues|tenant_isolation_update',
      'customers|Users can insert customers',
      'customers|Users can select customers',
      'customers|tenant_isolation',
      'employee_movements|tenant_isolation_insert',
      'employee_movements|tenant_isolation_select',
      'employees|tenant_isolation',
      'expenses|tenant_isolation',
      'invoice_counters|tenant_isolation',
      'invoice_items|Users can delete invoice_items',
      'invoice_items|Users can insert invoice_items',
      'invoice_items|Users can select invoice_items',
      'invoice_items|Users can update invoice_items',
      'invoice_items|tenant_isolation_insert',
      'invoice_items|tenant_isolation_select',
      'invoices|Users can delete invoices',
      'invoices|Users can insert invoices',
      'invoices|Users can select invoices',
      'invoices|Users can update invoices',
      'invoices|tenant_isolation_insert',
      'invoices|tenant_isolation_select',
      'invoices|tenant_isolation_update',
      'journal_entries|tenant_isolation_insert',
      'journal_entries|tenant_isolation_select',
      'journal_entry_lines|Users can insert journal_entry_lines',
      'journal_entry_lines|Users can select journal_entry_lines',
      'journal_entry_lines|tenant_isolation_insert',
      'journal_entry_lines|tenant_isolation_select',
      'payments|tenant_isolation_insert',
      'payments|tenant_isolation_select',
      'processed_requests|tenant_isolation',
      'processed_requests|tenant_isolation_insert',
      'processed_requests|tenant_isolation_select',
      'products|Users can delete products',
      'products|Users can insert products',
      'products|Users can select products',
      'products|Users can update products',
      'products|tenant_isolation',
      'reminder_log|tenant_isolation_select',
      'salaries|tenant_isolation_insert',
      'salaries|tenant_isolation_select',
      'stock_moves|Users can insert stock_moves',
      'stock_moves|Users can select stock_moves',
      'stock_moves|tenant_isolation_insert',
      'stock_moves|tenant_isolation_select',
      'suppliers|tenant_isolation',
      'tenant_settings|tenant_isolation',
      'tenants|tenant_isolation_select',
      'users|own_or_same_tenant'
    ];
    v_remaining int;
    v_expected_present text;
    v_rls_disabled text;
  BEGIN
    SELECT COUNT(*) INTO v_remaining
    FROM pg_policy p
    JOIN pg_class c ON c.oid = p.polrelid
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public'
      AND c.relname = ANY (v_tables);

    IF v_remaining <> 0 THEN
      RAISE EXCEPTION 'POST-DROP VERIFICATION FAILED: % policies remain on allowlisted legacy tables', v_remaining;
    END IF;

    SELECT string_agg(e.value, ', ' ORDER BY e.value) INTO v_expected_present
    FROM unnest(v_expected) AS e(value)
    WHERE EXISTS (
      SELECT 1
      FROM pg_policy p
      JOIN pg_class c ON c.oid = p.polrelid
      JOIN pg_namespace n ON n.oid = c.relnamespace
      WHERE n.nspname = 'public'
        AND c.relname::text || '|' || p.polname::text = e.value
    );

    IF v_expected_present IS NOT NULL THEN
      RAISE EXCEPTION 'POST-DROP VERIFICATION FAILED: expected policies still present: %', v_expected_present;
    END IF;

    SELECT string_agg(c.relname, ', ' ORDER BY c.relname) INTO v_rls_disabled
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public'
      AND c.relname = ANY (v_tables)
      AND NOT c.relrowsecurity;

    IF v_rls_disabled IS NOT NULL THEN
      RAISE EXCEPTION 'POST-DROP VERIFICATION FAILED: RLS was disabled on: %', v_rls_disabled;
    END IF;

    RAISE NOTICE 'All 53 legacy RLS policies absent - VERIFIED REMOVED; 22/22 tables still exist with RLS enabled';
  END
  $verify_after$;

  COMMIT;
  SELECT 'SCRIPT 03 COMPLETED (EXECUTE)' AS status;
\else
  -- DRY_RUN: identities/permissions/RLS checked above; no DROP POLICY was sent
  ROLLBACK;
  SELECT 'SCRIPT 03 COMPLETED (DRY_RUN - ROLLED BACK, NO DROPS)' AS status;
\endif
