-- =====================================================================
-- Hasad ERP V2 - DEV CLEANUP SCRIPT 04: Drop Functions (PREPARED)
-- =====================================================================
-- Target: Supabase DEV project sxasnunzspkuwbxiddqd
-- Status: PREPARED - NOT EXECUTED - REQUIRES EXPLICIT AUTHORIZATION
-- Purpose: Drop exactly the 33 legacy public functions with FULL exact
--          argument signatures verified against the saved inventory
-- Safety: After triggers/policies/cron cleared; dependency-checked across
--          ALL pg_depend catalog classes (not only pg_class/pg_proc), no
--          CASCADE, extension-owned/protected objects preserved, fail-closed:
--          any dependent object outside the 33 target functions and the 22
--          legacy tables aborts the run and is named in the error.
-- Scope : Drops only public functions. It does NOT drop, and must never
--         absorb via CASCADE, objects outside public. A dependency from
--         another schema (e.g. a storage.objects policy calling
--         public.get_my_tenant_id()) is a BLOCKER that requires separate
--         authorization and its own script - never CASCADE.
-- Alignment: Same authorization GUC mapping and psql transaction controls
--            as the successful Stage 3 script (03_drop_rls_policies.sql)
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
-- Preconditions: exact function identities, ownership, SECURITY DEFINER,
-- extension membership, and dependencies (no CASCADE)
-- DRY_RUN stops after this block and rolls back; no DROP is sent.
-- ---------------------------------------------------------------------
DO $verify_funcs_exact$
DECLARE
  -- 33 legacy functions with full argument signatures from saved inventory
  v_expected text[] := ARRAY[
    'public._fire_reminder(p_tenant_id uuid, p_customer_id uuid, p_customer_name text, p_phone text, p_amount numeric, p_webhook text, p_template text, p_company_name text)',
    'public.add_employee_movement(p_request_id uuid, p_employee_id uuid, p_month date, p_direction text, p_category text, p_amount bigint, p_description text, p_product_id uuid, p_qty numeric, p_date date)',
    'public.adjust_inventory(p_product_id uuid, p_counted_qty numeric, p_reason text, p_date date, p_request_id uuid)',
    'public.create_account(p_code text, p_name text, p_type text, p_parent_code text, p_request_id uuid)',
    'public.create_journal_entry(p_request_id uuid, p_date date, p_memo text, p_lines jsonb)',
    'public.create_purchase_invoice(p_request_id uuid, p_supplier_id uuid, p_items jsonb, p_invoice_date date, p_paid bigint, p_payment_method text, p_memo text)',
    'public.create_sale_invoice(p_request_id uuid, p_customer_id uuid, p_items jsonb, p_invoice_date date, p_paid bigint, p_payment_method text, p_memo text)',
    'public.get_balance_sheet(p_as_of_date date)',
    'public.get_chart_of_accounts()',
    'public.get_dashboard_summary()',
    'public.get_employee_entitlement(p_employee_id uuid, p_month date)',
    'public.get_income_statement(p_from date, p_to date)',
    'public.get_journal_entries(p_from date, p_to date)',
    'public.get_ledger(p_account_id uuid, p_from date, p_to date)',
    'public.get_my_role()',
    'public.get_my_tenant_id()',
    'public.get_my_user()',
    'public.get_party_statement(p_party_type text, p_party_id uuid, p_from date, p_to date)',
    'public.get_trial_balance(p_as_of_date date)',
    'public.get_user_tenants()',
    'public.next_invoice_no(p_type text)',
    'public.next_journal_no()',
    'public.pay_salary(p_request_id uuid, p_employee_id uuid, p_month date, p_paid bigint, p_method text, p_date date, p_note text)',
    'public.record_payment(p_request_id uuid, p_invoice_id uuid, p_amount bigint, p_method text, p_date date, p_note text)',
    'public.register_tenant(p_name text, p_owner_name text)',
    'public.seed_chart_of_accounts(p_tenant_id uuid)',
    'public.seed_tenant_settings()',
    'public.send_due_reminders()',
    'public.send_reminder_now(p_customer_id uuid)',
    'public.send_reminders_to_all()',
    'public.set_master_tenant()',
    'public.settle_supplier(p_request_id uuid, p_supplier_id uuid, p_amount bigint, p_method text, p_date date, p_note text)',
    'public.switch_tenant(p_tenant_id uuid)'
  ];

  -- 22 allowlisted legacy tables: the only pg_class dependents tolerated.
  -- Every other pg_class dependent (view, matview, index, foreign table...)
  -- is a blocker.
  v_tables text[] := ARRAY[
    'accounts','commission_dues','customers','employee_movements','employees',
    'expenses','invoice_counters','invoice_items','invoices','journal_entries',
    'journal_entry_lines','payments','processed_requests','products','reminder_log',
    'salaries','stock_moves','suppliers','tenant_settings','tenants',
    'user_tenants','users'
  ];

  v_expected_count int;
  v_actual text[];
  v_actual_count int;
  v_missing_names text;
  v_extra_names text;
  v_not_postgres text;
  v_extension_owned text;
  v_depending text;
  v_no_drop_priv text;
  v_bypass_roles text;
BEGIN
  -- Exactly 33 distinct expected identities
  SELECT COUNT(DISTINCT e.value) INTO v_expected_count FROM unnest(v_expected) AS e(value);
  IF v_expected_count <> 33 THEN
    RAISE EXCEPTION 'SCRIPT ALLOWLIST ERROR: expected 33 distinct functions, found %', v_expected_count;
  END IF;

  -- Application roles must not bypass RLS (defensive)
  SELECT string_agg(rolname, ', ' ORDER BY rolname) INTO v_bypass_roles
  FROM pg_roles
  WHERE rolname IN ('anon', 'authenticated')
    AND rolbypassrls;

  IF v_bypass_roles IS NOT NULL THEN
    RAISE EXCEPTION 'RLS PRECONDITION FAILED: application role(s) bypass RLS: %', v_bypass_roles;
  END IF;

  -- Current role permissions
  IF NOT EXISTS (
    SELECT 1 FROM pg_roles WHERE rolname = current_user AND rolsuper
  ) THEN
    SELECT string_agg('public.'||p.proname||'('||pg_get_function_identity_arguments(p.oid)||')', ', ' ORDER BY p.proname)
    INTO v_no_drop_priv
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.proowner != 'postgres'::regrole
      AND (n.nspname||'.'||p.proname||'('||pg_get_function_identity_arguments(p.oid)||')') = ANY (v_expected);

    IF v_no_drop_priv IS NOT NULL THEN
      RAISE EXCEPTION 'OWNERSHIP/PERMISSION PRECONDITION FAILED: non-postgres owned or not droppable by %: %', current_user, v_no_drop_priv;
    END IF;
  END IF;

  -- Reconcile exact identities from live catalog
  SELECT COALESCE(
           array_agg('public.'||p.proname||'('||pg_get_function_identity_arguments(p.oid)||')' ORDER BY p.proname, pg_get_function_identity_arguments(p.oid)),
           ARRAY[]::text[]
         )
  INTO v_actual
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND (n.nspname||'.'||p.proname||'('||pg_get_function_identity_arguments(p.oid)||')') = ANY (v_expected);

  v_actual_count := cardinality(v_actual);

  -- All must be owned by postgres
  SELECT string_agg('public.'||p.proname||'('||pg_get_function_identity_arguments(p.oid)||')', ', ' ORDER BY p.proname)
  INTO v_not_postgres
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND (n.nspname||'.'||p.proname||'('||pg_get_function_identity_arguments(p.oid)||')') = ANY (v_expected)
    AND p.proowner <> 'postgres'::regrole;

  IF v_not_postgres IS NOT NULL THEN
    RAISE EXCEPTION 'OWNERSHIP MISMATCH: expected postgres owner for: %', v_not_postgres;
  END IF;

  -- None may be extension-owned
  SELECT string_agg('public.'||p.proname||'('||pg_get_function_identity_arguments(p.oid)||')', ', ' ORDER BY p.proname)
  INTO v_extension_owned
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  JOIN pg_depend d
    ON d.classid = 'pg_proc'::regclass
   AND d.objid = p.oid
   AND d.deptype = 'e'
  WHERE n.nspname = 'public'
    AND (n.nspname||'.'||p.proname||'('||pg_get_function_identity_arguments(p.oid)||')') = ANY (v_expected);

  IF v_extension_owned IS NOT NULL THEN
    RAISE EXCEPTION 'EXTENSION-OWNED FUNCTION DETECTED: %', v_extension_owned;
  END IF;

  -- Dependencies: fail-closed across ALL pg_depend catalog classes.
  -- Tolerated dependent objects are ONLY:
  --   * the 33 target functions themselves, and
  --   * the 22 legacy tables (pg_class relkind 'r' in public).
  -- Everything else aborts the run and is named in the error, including
  -- dependents in other schemas, policies, views, column defaults,
  -- constraints, extensions, and any catalog class not resolved below.
  -- Storage objects/policies are NOT handled here: they are outside this
  -- cleanup scope and need their own separately authorized step.
  SELECT string_agg(dep.depended_on||' <- '||dep.dependent_object||' ('||dep.deptype||')',
                    E'\n  ' ORDER BY dep.depended_on, dep.dependent_object)
  INTO v_depending
  FROM (
    SELECT n1.nspname||'.'||p1.proname||'('||pg_get_function_identity_arguments(p1.oid)||')' AS depended_on,
           CASE d.classid::regclass::text
             WHEN 'pg_class'      THEN 'pg_class:'||COALESCE(c.relnamespace::regnamespace::text,'?')||'.'||COALESCE(c.relname,'?')||'('||COALESCE(c.relkind::text,'?')||')'
             WHEN 'pg_proc'       THEN 'pg_proc:'||COALESCE(pr.pronamespace::regnamespace::text,'?')||'.'||COALESCE(pr.proname,'?')
             WHEN 'pg_policy'     THEN 'pg_policy:"'||COALESCE(pol.polname,'?')||'" on '||COALESCE(pol.polrelid::regclass::text,'?')
             WHEN 'pg_trigger'    THEN 'pg_trigger:"'||COALESCE(tg.tgname,'?')||'" on '||COALESCE(tg.tgrelid::regclass::text,'?')
             WHEN 'pg_rewrite'    THEN 'pg_rewrite:"'||COALESCE(rw.rulename,'?')||'" on '||COALESCE(rw.ev_class::regclass::text,'?')
             WHEN 'pg_constraint' THEN 'pg_constraint:"'||COALESCE(con.conname,'?')||'"'
             WHEN 'pg_attrdef'    THEN 'pg_attrdef:default on '||COALESCE(ad.adrelid::regclass::text,'?')
             WHEN 'pg_type'       THEN 'pg_type:'||COALESCE(ty.typnamespace::regnamespace::text,'?')||'.'||COALESCE(ty.typname,'?')
             WHEN 'pg_operator'   THEN 'pg_operator:'||COALESCE(op.oprname,'?')
             WHEN 'pg_extension'  THEN 'pg_extension:'||COALESCE(ext.extname,'?')
             WHEN 'pg_ts_config'  THEN 'pg_ts_config:'||COALESCE(tsc.cfgname,'?')
             WHEN 'pg_ts_dict'    THEN 'pg_ts_dict:'||COALESCE(tsd.dictname,'?')
             WHEN 'pg_statistic_ext' THEN 'pg_statistic_ext:'||COALESCE(se.stxname,'?')
             ELSE 'catalog '||d.classid::regclass::text||':objid='||d.objid::text||' (unmapped class - treated as blocker)'
           END AS dependent_object,
           d.deptype::text AS deptype
    FROM pg_depend d
    JOIN pg_proc p1 ON p1.oid = d.refobjid AND d.refclassid = 'pg_proc'::regclass
    JOIN pg_namespace n1 ON n1.oid = p1.pronamespace
    LEFT JOIN pg_class         c   ON d.classid = 'pg_class'::regclass         AND c.oid   = d.objid
    LEFT JOIN pg_proc          pr  ON d.classid = 'pg_proc'::regclass          AND pr.oid  = d.objid
    LEFT JOIN pg_policy        pol ON d.classid = 'pg_policy'::regclass        AND pol.oid = d.objid
    LEFT JOIN pg_trigger       tg  ON d.classid = 'pg_trigger'::regclass       AND tg.oid  = d.objid
    LEFT JOIN pg_rewrite       rw  ON d.classid = 'pg_rewrite'::regclass       AND rw.oid  = d.objid
    LEFT JOIN pg_constraint    con ON d.classid = 'pg_constraint'::regclass    AND con.oid = d.objid
    LEFT JOIN pg_attrdef       ad  ON d.classid = 'pg_attrdef'::regclass       AND ad.oid  = d.objid
    LEFT JOIN pg_type          ty  ON d.classid = 'pg_type'::regclass          AND ty.oid  = d.objid
    LEFT JOIN pg_operator      op  ON d.classid = 'pg_operator'::regclass      AND op.oid  = d.objid
    LEFT JOIN pg_extension     ext ON d.classid = 'pg_extension'::regclass     AND ext.oid = d.objid
    LEFT JOIN pg_ts_config     tsc ON d.classid = 'pg_ts_config'::regclass     AND tsc.oid = d.objid
    LEFT JOIN pg_ts_dict       tsd ON d.classid = 'pg_ts_dict'::regclass       AND tsd.oid = d.objid
    LEFT JOIN pg_statistic_ext se  ON d.classid = 'pg_statistic_ext'::regclass AND se.oid  = d.objid
    WHERE n1.nspname = 'public'
      AND (n1.nspname||'.'||p1.proname||'('||pg_get_function_identity_arguments(p1.oid)||')') = ANY (v_expected)
      AND d.deptype <> 'p'
      AND NOT COALESCE(
            d.classid = 'pg_proc'::regclass
        AND d.objid IN (
              SELECT p3.oid
                FROM pg_proc p3
                JOIN pg_namespace n3 ON n3.oid = p3.pronamespace
               WHERE n3.nspname = 'public'
                 AND (n3.nspname||'.'||p3.proname||'('||pg_get_function_identity_arguments(p3.oid)||')') = ANY (v_expected)
            ), false)
      AND NOT COALESCE(
            d.classid = 'pg_class'::regclass
        AND c.relnamespace = 'public'::regnamespace
        AND c.relkind = 'r'
        AND c.relname = ANY (v_tables)
            , false)
  ) dep;

  IF v_depending IS NOT NULL THEN
    RAISE EXCEPTION 'DEPENDENCY MISMATCH: dependent object(s) outside the cleanup scope of the 33 target functions (no CASCADE is used): %', v_depending;
  END IF;

  SELECT string_agg(e.value, ', ' ORDER BY e.value) INTO v_missing_names
  FROM unnest(v_expected) AS e(value)
  WHERE NOT (e.value = ANY (v_actual));

  SELECT string_agg(a.value, ', ' ORDER BY a.value) INTO v_extra_names
  FROM unnest(v_actual) AS a(value)
  WHERE NOT (a.value = ANY (v_expected));

  IF v_actual_count <> 33
     OR v_missing_names IS NOT NULL
     OR v_extra_names IS NOT NULL THEN
    RAISE EXCEPTION 'FUNCTION SET MISMATCH: expected 33 exact identities; actual=%, missing=[%], unexpected=[%]',
      v_actual_count,
      COALESCE(v_missing_names, 'none'),
      COALESCE(v_extra_names, 'none');
  END IF;

  RAISE NOTICE 'Verified exact legacy function set: 33/33 identities present (postgres-owned, not extension-owned)';
  RAISE NOTICE 'Verified reverse dependencies across all pg_depend catalog classes: no dependent object outside the 33 target functions and the 22 legacy tables (no CASCADE will be used)';
  RAISE NOTICE 'SECURITY DEFINER count check performed by inventory (see notices); proceeding with allowlist-only drops';
END
$verify_funcs_exact$;

-- DRY_RUN/EXECUTE gating
SELECT (current_setting('cleanup.mode', true) = 'EXECUTE') AS exec_flag_bool \gset

\if :exec_flag_bool
  -- Drop exactly the 33 verified legacy functions (EXECUTE only, no CASCADE)
  DROP FUNCTION IF EXISTS public._fire_reminder(p_tenant_id uuid, p_customer_id uuid, p_customer_name text, p_phone text, p_amount numeric, p_webhook text, p_template text, p_company_name text);
  DROP FUNCTION IF EXISTS public.add_employee_movement(p_request_id uuid, p_employee_id uuid, p_month date, p_direction text, p_category text, p_amount bigint, p_description text, p_product_id uuid, p_qty numeric, p_date date);
  DROP FUNCTION IF EXISTS public.adjust_inventory(p_product_id uuid, p_counted_qty numeric, p_reason text, p_date date, p_request_id uuid);
  DROP FUNCTION IF EXISTS public.create_account(p_code text, p_name text, p_type text, p_parent_code text, p_request_id uuid);
  DROP FUNCTION IF EXISTS public.create_journal_entry(p_request_id uuid, p_date date, p_memo text, p_lines jsonb);
  DROP FUNCTION IF EXISTS public.create_purchase_invoice(p_request_id uuid, p_supplier_id uuid, p_items jsonb, p_invoice_date date, p_paid bigint, p_payment_method text, p_memo text);
  DROP FUNCTION IF EXISTS public.create_sale_invoice(p_request_id uuid, p_customer_id uuid, p_items jsonb, p_invoice_date date, p_paid bigint, p_payment_method text, p_memo text);
  DROP FUNCTION IF EXISTS public.get_balance_sheet(p_as_of_date date);
  DROP FUNCTION IF EXISTS public.get_chart_of_accounts();
  DROP FUNCTION IF EXISTS public.get_dashboard_summary();
  DROP FUNCTION IF EXISTS public.get_employee_entitlement(p_employee_id uuid, p_month date);
  DROP FUNCTION IF EXISTS public.get_income_statement(p_from date, p_to date);
  DROP FUNCTION IF EXISTS public.get_journal_entries(p_from date, p_to date);
  DROP FUNCTION IF EXISTS public.get_ledger(p_account_id uuid, p_from date, p_to date);
  DROP FUNCTION IF EXISTS public.get_my_role();
  DROP FUNCTION IF EXISTS public.get_my_tenant_id();
  DROP FUNCTION IF EXISTS public.get_my_user();
  DROP FUNCTION IF EXISTS public.get_party_statement(p_party_type text, p_party_id uuid, p_from date, p_to date);
  DROP FUNCTION IF EXISTS public.get_trial_balance(p_as_of_date date);
  DROP FUNCTION IF EXISTS public.get_user_tenants();
  DROP FUNCTION IF EXISTS public.next_invoice_no(p_type text);
  DROP FUNCTION IF EXISTS public.next_journal_no();
  DROP FUNCTION IF EXISTS public.pay_salary(p_request_id uuid, p_employee_id uuid, p_month date, p_paid bigint, p_method text, p_date date, p_note text);
  DROP FUNCTION IF EXISTS public.record_payment(p_request_id uuid, p_invoice_id uuid, p_amount bigint, p_method text, p_date date, p_note text);
  DROP FUNCTION IF EXISTS public.register_tenant(p_name text, p_owner_name text);
  DROP FUNCTION IF EXISTS public.seed_chart_of_accounts(p_tenant_id uuid);
  DROP FUNCTION IF EXISTS public.seed_tenant_settings();
  DROP FUNCTION IF EXISTS public.send_due_reminders();
  DROP FUNCTION IF EXISTS public.send_reminder_now(p_customer_id uuid);
  DROP FUNCTION IF EXISTS public.send_reminders_to_all();
  DROP FUNCTION IF EXISTS public.set_master_tenant();
  DROP FUNCTION IF EXISTS public.settle_supplier(p_request_id uuid, p_supplier_id uuid, p_amount bigint, p_method text, p_date date, p_note text);
  DROP FUNCTION IF EXISTS public.switch_tenant(p_tenant_id uuid);

  -- Post-drop verification
  DO $verify_after$
  DECLARE
    v_expected text[] := ARRAY[
      'public._fire_reminder(p_tenant_id uuid, p_customer_id uuid, p_customer_name text, p_phone text, p_amount numeric, p_webhook text, p_template text, p_company_name text)',
      'public.add_employee_movement(p_request_id uuid, p_employee_id uuid, p_month date, p_direction text, p_category text, p_amount bigint, p_description text, p_product_id uuid, p_qty numeric, p_date date)',
      'public.adjust_inventory(p_product_id uuid, p_counted_qty numeric, p_reason text, p_date date, p_request_id uuid)',
      'public.create_account(p_code text, p_name text, p_type text, p_parent_code text, p_request_id uuid)',
      'public.create_journal_entry(p_request_id uuid, p_date date, p_memo text, p_lines jsonb)',
      'public.create_purchase_invoice(p_request_id uuid, p_supplier_id uuid, p_items jsonb, p_invoice_date date, p_paid bigint, p_payment_method text, p_memo text)',
      'public.create_sale_invoice(p_request_id uuid, p_customer_id uuid, p_items jsonb, p_invoice_date date, p_paid bigint, p_payment_method text, p_memo text)',
      'public.get_balance_sheet(p_as_of_date date)',
      'public.get_chart_of_accounts()',
      'public.get_dashboard_summary()',
      'public.get_employee_entitlement(p_employee_id uuid, p_month date)',
      'public.get_income_statement(p_from date, p_to date)',
      'public.get_journal_entries(p_from date, p_to date)',
      'public.get_ledger(p_account_id uuid, p_from date, p_to date)',
      'public.get_my_role()',
      'public.get_my_tenant_id()',
      'public.get_my_user()',
      'public.get_party_statement(p_party_type text, p_party_id uuid, p_from date, p_to date)',
      'public.get_trial_balance(p_as_of_date date)',
      'public.get_user_tenants()',
      'public.next_invoice_no(p_type text)',
      'public.next_journal_no()',
      'public.pay_salary(p_request_id uuid, p_employee_id uuid, p_month date, p_paid bigint, p_method text, p_date date, p_note text)',
      'public.record_payment(p_request_id uuid, p_invoice_id uuid, p_amount bigint, p_method text, p_date date, p_note text)',
      'public.register_tenant(p_name text, p_owner_name text)',
      'public.seed_chart_of_accounts(p_tenant_id uuid)',
      'public.seed_tenant_settings()',
      'public.send_due_reminders()',
      'public.send_reminder_now(p_customer_id uuid)',
      'public.send_reminders_to_all()',
      'public.set_master_tenant()',
      'public.settle_supplier(p_request_id uuid, p_supplier_id uuid, p_amount bigint, p_method text, p_date date, p_note text)',
      'public.switch_tenant(p_tenant_id uuid)'
    ];
    v_remaining text;
  BEGIN
    SELECT string_agg('public.'||p.proname||'('||pg_get_function_identity_arguments(p.oid)||')', ', ' ORDER BY p.proname)
    INTO v_remaining
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND (n.nspname||'.'||p.proname||'('||pg_get_function_identity_arguments(p.oid)||')') = ANY (v_expected);

    IF v_remaining IS NOT NULL THEN
      RAISE EXCEPTION 'POST-DROP VERIFICATION FAILED: expected functions still present: %', v_remaining;
    END IF;

    RAISE NOTICE 'All 33 legacy functions dropped successfully - VERIFIED REMOVED';
  END
  $verify_after$;

  COMMIT;
  SELECT 'SCRIPT 04 COMPLETED (EXECUTE)' AS status;
\else
  -- DRY_RUN: identities/ownership/dependencies checked above; no DROP FUNCTION sent
  ROLLBACK;
  SELECT 'SCRIPT 04 COMPLETED (DRY_RUN - ROLLED BACK, NO DROPS)' AS status;
\endif
