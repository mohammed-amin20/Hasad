-- =====================================================================
-- Hasad ERP V2 - DEV CLEANUP SCRIPT 05: Drop 22 legacy public tables
-- =====================================================================
-- Target : Supabase DEV project sxasnunzspkuwbxiddqd
-- Status : PREPARED - NOT EXECUTED - requires explicit owner authorization
-- Safety : Exact allowlist; no CASCADE, no IF EXISTS, no DROP SCHEMA.
--          No Auth, Storage, extension, managed-schema, or role changes.
--          DRY_RUN verifies only and ROLLBACKs. EXECUTE requires separate
--          private Auth-ID preservation evidence before any DROP is sent.
-- =====================================================================

\set ON_ERROR_STOP on

-- psql leaves an undefined variable reference literal in SQL. Normalize every
-- input before interpolation so missing mandatory inputs reach the SQL gates
-- below as invalid values, while DRY_RUN may omit the Auth-audit attestation.
\if :{?cleanup_authorized}
\else
  \set cleanup_authorized ''
\endif
\if :{?cleanup_project}
\else
  \set cleanup_project ''
\endif
\if :{?cleanup_mode}
\else
  \set cleanup_mode ''
\endif
\if :{?cleanup_auth_audit_completed}
\else
  \set cleanup_auth_audit_completed ''
\endif

SELECT set_config('cleanup.authorized', COALESCE(NULLIF(:'cleanup_authorized',''), 'false'), false);
SELECT set_config('cleanup.project_ref', COALESCE(NULLIF(:'cleanup_project',''), ''), false);
SELECT set_config('cleanup.mode', COALESCE(NULLIF(:'cleanup_mode',''), 'DRY_RUN'), false);
SELECT set_config('cleanup.auth_audit_completed', COALESCE(NULLIF(:'cleanup_auth_audit_completed',''), 'false'), false);

DO $cleanup_authz$
BEGIN
  IF current_setting('cleanup.authorized', true) IS DISTINCT FROM 'true' THEN
    RAISE EXCEPTION 'AUTHORIZATION REQUIRED: cleanup.authorized must be true';
  END IF;
  IF current_setting('cleanup.project_ref', true) IS DISTINCT FROM 'sxasnunzspkuwbxiddqd' THEN
    RAISE EXCEPTION 'PROJECT MISMATCH: cleanup.project_ref must be sxasnunzspkuwbxiddqd';
  END IF;
  IF current_database() IS DISTINCT FROM 'postgres' THEN
    RAISE EXCEPTION 'DATABASE MISMATCH: expected postgres, got %', current_database();
  END IF;
  IF current_setting('cleanup.mode', true) NOT IN ('DRY_RUN', 'EXECUTE') THEN
    RAISE EXCEPTION 'INVALID MODE: cleanup.mode must be DRY_RUN or EXECUTE';
  END IF;
  IF current_setting('cleanup.mode', true) = 'EXECUTE'
     AND current_setting('cleanup.auth_audit_completed', true)
         IS DISTINCT FROM 'STAGE5_AUTH_ID_AUDIT_SXASNUNZSPKUWBXIDDQD_COMPLETE' THEN
    RAISE EXCEPTION 'AUTH-ID AUDIT REQUIRED: complete the private Stage 5 audit and supply its exact completion attestation before EXECUTE';
  END IF;
END
$cleanup_authz$;

BEGIN;

DO $verify_tables_exact$
DECLARE
  v_names text[] := ARRAY[
    'accounts','commission_dues','customers','employee_movements','employees',
    'expenses','invoice_counters','invoice_items','invoices','journal_entries',
    'journal_entry_lines','payments','processed_requests','products','reminder_log',
    'salaries','stock_moves','suppliers','tenant_settings','tenants','user_tenants','users'
  ];
  -- Derived from the saved FK inventory. Every non-self internal FK must put
  -- its referencing (child) table before its referenced (parent) table.
  v_drop_order text[] := ARRAY[
    'journal_entry_lines','invoice_items','payments','stock_moves','employee_movements',
    'salaries','commission_dues','expenses','reminder_log','processed_requests',
    'journal_entries','invoices','user_tenants','users','customers','products',
    'suppliers','invoice_counters','accounts','tenant_settings','employees','tenants'
  ];
  v_expected_internal_fks text[] := ARRAY[
    'accounts_parent_id_fkey|accounts|accounts',
    'accounts_tenant_id_fkey|accounts|tenants',
    'commission_dues_invoice_id_fkey|commission_dues|invoices',
    'commission_dues_product_id_fkey|commission_dues|products',
    'commission_dues_supplier_id_fkey|commission_dues|suppliers',
    'commission_dues_tenant_id_fkey|commission_dues|tenants',
    'customers_tenant_id_fkey|customers|tenants',
    'employee_movements_employee_id_fkey|employee_movements|employees',
    'employee_movements_product_id_fkey|employee_movements|products',
    'employee_movements_tenant_id_fkey|employee_movements|tenants',
    'employees_tenant_id_fkey|employees|tenants',
    'expenses_tenant_id_fkey|expenses|tenants',
    'invoice_counters_tenant_id_fkey|invoice_counters|tenants',
    'invoice_items_invoice_id_fkey|invoice_items|invoices',
    'invoice_items_product_id_fkey|invoice_items|products',
    'invoices_tenant_id_fkey|invoices|tenants',
    'journal_entries_created_by_fkey|journal_entries|users',
    'journal_entries_tenant_id_fkey|journal_entries|tenants',
    'journal_entry_lines_account_id_fkey|journal_entry_lines|accounts',
    'journal_entry_lines_entry_id_fkey|journal_entry_lines|journal_entries',
    'payments_invoice_id_fkey|payments|invoices',
    'payments_tenant_id_fkey|payments|tenants',
    'processed_requests_tenant_id_fkey|processed_requests|tenants',
    'products_supplier_id_fkey|products|suppliers',
    'products_tenant_id_fkey|products|tenants',
    'reminder_log_customer_id_fkey|reminder_log|customers',
    'reminder_log_tenant_id_fkey|reminder_log|tenants',
    'salaries_employee_id_fkey|salaries|employees',
    'salaries_tenant_id_fkey|salaries|tenants',
    'stock_moves_employee_id_fkey|stock_moves|employees',
    'stock_moves_product_id_fkey|stock_moves|products',
    'stock_moves_tenant_id_fkey|stock_moves|tenants',
    'suppliers_tenant_id_fkey|suppliers|tenants',
    'tenant_settings_tenant_id_fkey|tenant_settings|tenants',
    'user_tenants_tenant_id_fkey|user_tenants|tenants',
    'user_tenants_user_id_fkey|user_tenants|users',
    'users_current_tenant_id_fkey|users|tenants',
    'users_tenant_id_fkey|users|tenants'
  ];
  v_expected_count int;
  v_actual text[];
  v_missing text;
  v_extra text;
  v_wrong_kind text;
  v_wrong_owner text;
  v_no_privilege text;
  v_external_fk text;
  v_actual_internal_fks text[];
  v_missing_internal_fks text;
  v_extra_internal_fks text;
  v_fk_order_violation text;
  v_views text;
  v_policies text;
  v_user_triggers text;
  v_extension_owned text;
  v_blockers text;
BEGIN
  SELECT count(DISTINCT value) INTO v_expected_count FROM unnest(v_names) AS x(value);
  IF v_expected_count <> 22 THEN
    RAISE EXCEPTION 'SCRIPT ALLOWLIST ERROR: expected 22 distinct table names, found %', v_expected_count;
  END IF;
  IF cardinality(v_drop_order) <> 22
     OR EXISTS (SELECT 1 FROM unnest(v_names) AS x(name) WHERE NOT x.name = ANY (v_drop_order))
     OR EXISTS (SELECT 1 FROM unnest(v_drop_order) AS x(name) WHERE NOT x.name = ANY (v_names)) THEN
    RAISE EXCEPTION 'SCRIPT DROP-ORDER ERROR: order must contain exactly the 22 allowlisted tables';
  END IF;
  IF cardinality(v_expected_internal_fks) <> 38
     OR (SELECT count(DISTINCT value) FROM unnest(v_expected_internal_fks) AS x(value)) <> 38 THEN
    RAISE EXCEPTION 'SCRIPT FK-INVENTORY ERROR: expected 38 distinct internal foreign keys';
  END IF;

  SELECT COALESCE(array_agg(c.relname ORDER BY c.relname), ARRAY[]::text[])
    INTO v_actual
  FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'public' AND c.relname = ANY (v_names);
  SELECT string_agg(value, ', ' ORDER BY value) INTO v_missing
  FROM unnest(v_names) AS x(value) WHERE NOT (value = ANY (v_actual));
  SELECT string_agg(value, ', ' ORDER BY value) INTO v_extra
  FROM unnest(v_actual) AS x(value) WHERE NOT (value = ANY (v_names));
  IF cardinality(v_actual) <> 22 OR v_missing IS NOT NULL OR v_extra IS NOT NULL THEN
    RAISE EXCEPTION 'TABLE IDENTITY MISMATCH: missing=[%] extra=[%] actual_count=%',
      COALESCE(v_missing, 'none'), COALESCE(v_extra, 'none'), cardinality(v_actual);
  END IF;

  SELECT string_agg(c.relname::text||':'||c.relkind::text, ', ' ORDER BY c.relname) INTO v_wrong_kind
  FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'public' AND c.relname = ANY (v_names) AND c.relkind <> 'r';
  IF v_wrong_kind IS NOT NULL THEN
    RAISE EXCEPTION 'TABLE KIND MISMATCH: expected ordinary tables: %', v_wrong_kind;
  END IF;

  SELECT string_agg(c.relname||':'||pg_get_userbyid(c.relowner), ', ' ORDER BY c.relname) INTO v_wrong_owner
  FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'public' AND c.relname = ANY (v_names) AND c.relowner <> 'postgres'::regrole;
  IF v_wrong_owner IS NOT NULL THEN
    RAISE EXCEPTION 'OWNERSHIP MISMATCH: expected postgres-owned tables: %', v_wrong_owner;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = current_user AND rolsuper) THEN
    SELECT string_agg(c.relname, ', ' ORDER BY c.relname) INTO v_no_privilege
    FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public' AND c.relname = ANY (v_names)
      AND NOT pg_has_role(current_user, c.relowner, 'USAGE');
    IF v_no_privilege IS NOT NULL THEN
      RAISE EXCEPTION 'OWNERSHIP/PERMISSION PRECONDITION FAILED for: %', v_no_privilege;
    END IF;
  END IF;

  -- Block only inbound foreign keys owned outside this deletion set. An
  -- outbound FK (for example public.users -> auth.users) is owned by the
  -- target table and is removed with it without altering its referenced table.
  SELECT string_agg(con.conname||' ('||sn.nspname||'.'||src.relname||' -> '||rn.nspname||'.'||ref.relname||')', ', ' ORDER BY con.conname)
    INTO v_external_fk
  FROM pg_constraint con
  JOIN pg_class src ON src.oid = con.conrelid JOIN pg_namespace sn ON sn.oid = src.relnamespace
  JOIN pg_class ref ON ref.oid = con.confrelid JOIN pg_namespace rn ON rn.oid = ref.relnamespace
  WHERE con.contype = 'f'
    AND ref.oid IN (SELECT c.oid FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='public' AND c.relname=ANY(v_names))
    AND src.oid NOT IN (SELECT c.oid FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='public' AND c.relname=ANY(v_names));
  IF v_external_fk IS NOT NULL THEN
    RAISE EXCEPTION 'EXTERNAL FOREIGN-KEY BLOCKER: %', v_external_fk;
  END IF;

  -- Reconcile every saved internal FK. Any missing or newly appearing FK is
  -- a fail-closed inventory mismatch, not an invitation to infer a new order.
  SELECT COALESCE(array_agg(con.conname||'|'||src.relname||'|'||ref.relname ORDER BY con.conname), ARRAY[]::text[])
    INTO v_actual_internal_fks
  FROM pg_constraint con
  JOIN pg_class src ON src.oid=con.conrelid JOIN pg_namespace sn ON sn.oid=src.relnamespace
  JOIN pg_class ref ON ref.oid=con.confrelid JOIN pg_namespace rn ON rn.oid=ref.relnamespace
  WHERE con.contype='f'
    AND sn.nspname='public' AND rn.nspname='public'
    AND src.relname=ANY(v_names) AND ref.relname=ANY(v_names);
  SELECT string_agg(value, ', ' ORDER BY value) INTO v_missing_internal_fks
  FROM unnest(v_expected_internal_fks) AS x(value) WHERE NOT value=ANY(v_actual_internal_fks);
  SELECT string_agg(value, ', ' ORDER BY value) INTO v_extra_internal_fks
  FROM unnest(v_actual_internal_fks) AS x(value) WHERE NOT value=ANY(v_expected_internal_fks);
  IF cardinality(v_actual_internal_fks) <> 38 OR v_missing_internal_fks IS NOT NULL OR v_extra_internal_fks IS NOT NULL THEN
    RAISE EXCEPTION 'INTERNAL FK INVENTORY MISMATCH: missing=[%] extra=[%] actual_count=%',
      COALESCE(v_missing_internal_fks, 'none'), COALESCE(v_extra_internal_fks, 'none'), cardinality(v_actual_internal_fks);
  END IF;

  -- A non-self cycle necessarily violates this strict rank ordering. The one
  -- recorded self-FK (accounts -> accounts) is dropped with its own table.
  SELECT string_agg(con.conname||' ('||src.relname||' -> '||ref.relname||')', ', ' ORDER BY con.conname)
    INTO v_fk_order_violation
  FROM pg_constraint con
  JOIN pg_class src ON src.oid=con.conrelid JOIN pg_namespace sn ON sn.oid=src.relnamespace
  JOIN pg_class ref ON ref.oid=con.confrelid JOIN pg_namespace rn ON rn.oid=ref.relnamespace
  WHERE con.contype='f' AND sn.nspname='public' AND rn.nspname='public'
    AND src.relname=ANY(v_names) AND ref.relname=ANY(v_names) AND src.oid<>ref.oid
    AND array_position(v_drop_order, src.relname) >= array_position(v_drop_order, ref.relname);
  IF v_fk_order_violation IS NOT NULL THEN
    RAISE EXCEPTION 'INTERNAL FK DROP-ORDER/CYCLE BLOCKER: %', v_fk_order_violation;
  END IF;

  SELECT string_agg(vn.nspname||'.'||v.relname, ', ' ORDER BY vn.nspname, v.relname) INTO v_views
  FROM pg_depend d
  JOIN pg_rewrite r ON d.classid='pg_rewrite'::regclass AND d.objid=r.oid
  JOIN pg_class v ON v.oid=r.ev_class JOIN pg_namespace vn ON vn.oid=v.relnamespace
  WHERE d.refclassid='pg_class'::regclass
    AND d.refobjid IN (SELECT c.oid FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='public' AND c.relname=ANY(v_names))
    AND v.oid NOT IN (SELECT c.oid FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='public' AND c.relname=ANY(v_names))
    AND v.relkind IN ('v','m');
  IF v_views IS NOT NULL THEN
    RAISE EXCEPTION 'EXTERNAL VIEW/MATERIALIZED-VIEW BLOCKER: %', v_views;
  END IF;

  SELECT string_agg(c.relname||'.'||p.polname, ', ' ORDER BY c.relname, p.polname) INTO v_policies
  FROM pg_policy p JOIN pg_class c ON c.oid=p.polrelid JOIN pg_namespace n ON n.oid=c.relnamespace
  WHERE n.nspname='public' AND c.relname=ANY(v_names);
  IF v_policies IS NOT NULL THEN
    RAISE EXCEPTION 'UNEXPECTED POLICY BLOCKER: %', v_policies;
  END IF;

  SELECT string_agg(c.relname||'.'||t.tgname, ', ' ORDER BY c.relname, t.tgname) INTO v_user_triggers
  FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid JOIN pg_namespace n ON n.oid=c.relnamespace
  WHERE n.nspname='public' AND c.relname=ANY(v_names) AND NOT t.tgisinternal;
  IF v_user_triggers IS NOT NULL THEN
    RAISE EXCEPTION 'UNEXPECTED USER-TRIGGER BLOCKER: %', v_user_triggers;
  END IF;

  SELECT string_agg(c.relname, ', ' ORDER BY c.relname) INTO v_extension_owned
  FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
  JOIN pg_depend d ON d.classid='pg_class'::regclass AND d.objid=c.oid AND d.deptype='e'
  WHERE n.nspname='public' AND c.relname=ANY(v_names);
  IF v_extension_owned IS NOT NULL THEN
    RAISE EXCEPTION 'EXTENSION-OWNED TABLE BLOCKER: %', v_extension_owned;
  END IF;

  -- Any remaining normal catalog dependency outside an allowlisted table's
  -- own constraint/trigger/rule/default is named and blocks; no CASCADE.
  WITH targets AS (
    SELECT c.oid FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
    WHERE n.nspname='public' AND c.relname=ANY(v_names)
  )
  SELECT string_agg(pg_describe_object(d.classid,d.objid,d.objsubid), '; ' ORDER BY pg_describe_object(d.classid,d.objid,d.objsubid))
    INTO v_blockers
  FROM pg_depend d
  WHERE d.refclassid='pg_class'::regclass AND d.refobjid IN (SELECT oid FROM targets) AND d.deptype='n'
    AND NOT EXISTS (SELECT 1 FROM pg_constraint x WHERE d.classid='pg_constraint'::regclass AND d.objid=x.oid AND x.conrelid IN (SELECT oid FROM targets))
    AND NOT EXISTS (SELECT 1 FROM pg_trigger x WHERE d.classid='pg_trigger'::regclass AND d.objid=x.oid AND x.tgrelid IN (SELECT oid FROM targets))
    AND NOT EXISTS (SELECT 1 FROM pg_rewrite x WHERE d.classid='pg_rewrite'::regclass AND d.objid=x.oid AND x.ev_class IN (SELECT oid FROM targets))
    AND NOT EXISTS (SELECT 1 FROM pg_attrdef x WHERE d.classid='pg_attrdef'::regclass AND d.objid=x.oid AND x.adrelid IN (SELECT oid FROM targets));
  IF v_blockers IS NOT NULL THEN
    RAISE EXCEPTION 'EXTERNAL/UNCLASSIFIED DEPENDENCY BLOCKER: %', v_blockers;
  END IF;
END
$verify_tables_exact$;

SELECT COALESCE(current_setting('cleanup.mode', true) = 'EXECUTE', false) AS exec_flag_bool \gset
\if :exec_flag_bool
  DROP TABLE public.journal_entry_lines;
  DROP TABLE public.invoice_items;
  DROP TABLE public.payments;
  DROP TABLE public.stock_moves;
  DROP TABLE public.employee_movements;
  DROP TABLE public.salaries;
  DROP TABLE public.commission_dues;
  DROP TABLE public.expenses;
  DROP TABLE public.reminder_log;
  DROP TABLE public.processed_requests;
  DROP TABLE public.journal_entries;
  DROP TABLE public.invoices;
  DROP TABLE public.user_tenants;
  DROP TABLE public.users;
  DROP TABLE public.customers;
  DROP TABLE public.products;
  DROP TABLE public.suppliers;
  DROP TABLE public.invoice_counters;
  DROP TABLE public.accounts;
  DROP TABLE public.tenant_settings;
  DROP TABLE public.employees;
  DROP TABLE public.tenants;

  DO $verify_after$
  DECLARE v_remaining text;
  BEGIN
    SELECT string_agg(c.relname, ', ' ORDER BY c.relname) INTO v_remaining
    FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
    WHERE n.nspname='public' AND c.relname = ANY (ARRAY[
      'accounts','commission_dues','customers','employee_movements','employees','expenses',
      'invoice_counters','invoice_items','invoices','journal_entries','journal_entry_lines',
      'payments','processed_requests','products','reminder_log','salaries','stock_moves',
      'suppliers','tenant_settings','tenants','user_tenants','users']);
    IF v_remaining IS NOT NULL THEN
      RAISE EXCEPTION 'POST-DROP VERIFICATION FAILED: legacy tables remain: %', v_remaining;
    END IF;
  END
  $verify_after$;
  COMMIT;
  SELECT 'STAGE 5 COMPLETED (EXECUTE): 22 authorized public tables removed' AS status;
\else
  ROLLBACK;
  SELECT 'STAGE 5 COMPLETED (DRY_RUN): preconditions verified; no DROP sent' AS status;
\endif
