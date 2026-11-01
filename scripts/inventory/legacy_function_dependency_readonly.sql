-- =====================================================================
-- Hasad ERP V2 - READ-ONLY DIAGNOSTIC: Stage 4 dependency blocker
-- =====================================================================
-- Target : Supabase DEV project sxasnunzspkuwbxiddqd (owner-executed only)
-- Status : PREPARED - READ ONLY - NO DDL / DML / DEPLOY
-- Why    : 04_drop_functions.sql EXECUTE failed with
--          "cannot drop function get_my_tenant_id() because other objects
--           depend on it" -> storage.objects policies:
--             tenant_isolated_pdf_select / _insert / _delete
--          The Stage 4 pg_depend preflight only resolved dependents whose
--          classid was pg_class or pg_proc, and then discarded every row
--          whose namespace could not be resolved (fail-open). pg_policy
--          dependents were therefore invisible.
--
-- Proves : (S2) whether all 33 legacy functions still exist after the
--               failed transaction, and that Stage 1-3 state was restored
--          (S3) the exact surviving function identities and ownership
--          (S4) EVERY reverse dependency, by catalog class, fail-closed
--          (S5) storage.objects policy metadata (no expressions)
--          (S6) a single verdict for Stage 4 readiness
--
-- Hides  : policy expressions, bucket/object paths, function source,
--          cron command payloads, credentials, table row data.
--          Policy expressions are never selected; only booleans derived
--          from them are reported.
--
-- Safety : one explicit BEGIN TRANSACTION READ ONLY / ROLLBACK pair,
--          server-side fail-closed read-only guard, ON_ERROR_STOP=1,
--          statement timeout, psql meta-commands limited to \set/\echo.
--          Exit with ROLLBACK: no database state is changed.
-- =====================================================================

\set ON_ERROR_STOP on

SET default_transaction_read_only = on;
SET statement_timeout = '60s';
SET idle_in_transaction_session_timeout = '120s';

BEGIN TRANSACTION READ ONLY;

-- ---------------------------------------------------------------------
-- Fail-closed read-only guard
-- ---------------------------------------------------------------------
DO $hasad_s4_guard$
BEGIN
  IF current_setting('transaction_read_only') <> 'on' THEN
    RAISE EXCEPTION 'FAIL-CLOSED: transaction_read_only = %, expected on',
      current_setting('transaction_read_only');
  END IF;
  IF current_setting('default_transaction_read_only') <> 'on' THEN
    RAISE EXCEPTION 'FAIL-CLOSED: default_transaction_read_only = %, expected on',
      current_setting('default_transaction_read_only');
  END IF;
END
$hasad_s4_guard$;

-- ---------------------------------------------------------------------
-- S1. Run context
-- ---------------------------------------------------------------------
\echo '==== S1. RUN CONTEXT ===='
SELECT current_database()                       AS database_name,
       current_user                             AS connected_role,
       current_setting('transaction_read_only') AS transaction_read_only,
       current_setting('server_version')        AS server_version,
       clock_timestamp()                        AS captured_at;

-- ---------------------------------------------------------------------
-- S2. Post-failure state: did the failed EXECUTE leave anything behind?
--     Expected: 33 functions, 22 tables, RLS on 22, 0 legacy public
--     policies, 0 non-internal triggers on those tables.
-- ---------------------------------------------------------------------
\echo '==== S2. POST-FAILURE STATE RECONCILIATION ===='
SELECT
  (SELECT count(*)
     FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.proname = ANY (ARRAY[
        '_fire_reminder','add_employee_movement','adjust_inventory','create_account',
        'create_journal_entry','create_purchase_invoice','create_sale_invoice',
        'get_balance_sheet','get_chart_of_accounts','get_dashboard_summary',
        'get_employee_entitlement','get_income_statement','get_journal_entries',
        'get_ledger','get_my_role','get_my_tenant_id','get_my_user',
        'get_party_statement','get_trial_balance','get_user_tenants',
        'next_invoice_no','next_journal_no','pay_salary','record_payment',
        'register_tenant','seed_chart_of_accounts','seed_tenant_settings',
        'send_due_reminders','send_reminder_now','send_reminders_to_all',
        'set_master_tenant','settle_supplier','switch_tenant'])) AS legacy_functions_present,
  (SELECT count(*)
     FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public' AND c.relkind IN ('r','p')
      AND c.relname = ANY (ARRAY[
        'accounts','commission_dues','customers','employee_movements','employees',
        'expenses','invoice_counters','invoice_items','invoices','journal_entries',
        'journal_entry_lines','payments','processed_requests','products','reminder_log',
        'salaries','stock_moves','suppliers','tenant_settings','tenants',
        'user_tenants','users'])) AS legacy_tables_present,
  (SELECT count(*)
     FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public' AND c.relkind IN ('r','p') AND c.relrowsecurity
      AND c.relname = ANY (ARRAY[
        'accounts','commission_dues','customers','employee_movements','employees',
        'expenses','invoice_counters','invoice_items','invoices','journal_entries',
        'journal_entry_lines','payments','processed_requests','products','reminder_log',
        'salaries','stock_moves','suppliers','tenant_settings','tenants',
        'user_tenants','users'])) AS legacy_tables_with_rls_enabled,
  (SELECT count(*)
     FROM pg_policy po
     JOIN pg_class c ON c.oid = po.polrelid
     JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public'
      AND c.relname = ANY (ARRAY[
        'accounts','commission_dues','customers','employee_movements','employees',
        'expenses','invoice_counters','invoice_items','invoices','journal_entries',
        'journal_entry_lines','payments','processed_requests','products','reminder_log',
        'salaries','stock_moves','suppliers','tenant_settings','tenants',
        'user_tenants','users'])) AS legacy_public_policies_present,
  (SELECT count(*)
     FROM pg_trigger t
     JOIN pg_class c ON c.oid = t.tgrelid
     JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public' AND NOT t.tgisinternal
      AND c.relname = ANY (ARRAY[
        'accounts','commission_dues','customers','employee_movements','employees',
        'expenses','invoice_counters','invoice_items','invoices','journal_entries',
        'journal_entry_lines','payments','processed_requests','products','reminder_log',
        'salaries','stock_moves','suppliers','tenant_settings','tenants',
        'user_tenants','users'])) AS legacy_triggers_present;

-- S2b. Cron state (Stage 1). Guarded: cron.job may be absent.
\echo '---- S2b. CRON STATE (Stage 1 intact?) ----'
DO $hasad_s4_cron$
DECLARE
  v_rows int;
BEGIN
  IF to_regclass('cron.job') IS NULL THEN
    RAISE NOTICE 'cron_job_table_present=false';
    RAISE NOTICE 'cron_job5_state=UNRESOLVED (cron.job NOT_PRESENT)';
    RETURN;
  END IF;

  RAISE NOTICE 'cron_job_table_present=true';
  SELECT count(*) INTO v_rows FROM cron.job WHERE jobid = 5;
  RAISE NOTICE 'cron_job5_rows=%', v_rows;

  IF v_rows = 0 THEN
    RAISE NOTICE 'cron_job5_state=ABSENT (Stage 1 intact)';
  ELSE
    RAISE NOTICE 'cron_job5_state=PRESENT (Stage 1 incomplete, or job recreated)';
  END IF;
END
$hasad_s4_cron$;

-- ---------------------------------------------------------------------
-- S3. The 33 legacy functions: identity, owner, SECURITY DEFINER,
--     extension membership. Signatures printed for owner confirmation;
--     the diagnostic matches by name so an unexpected overload is visible.
-- ---------------------------------------------------------------------
\echo '==== S3. LEGACY FUNCTION SET (expect 33 rows) ===='
SELECT n.nspname||'.'||p.proname||'('||pg_get_function_identity_arguments(p.oid)||')' AS function_identity,
       pg_get_userbyid(p.proowner) AS owner,
       p.prosecdef                 AS security_definer,
       p.prokind::text             AS kind,
       EXISTS (SELECT 1
                 FROM pg_depend d
                WHERE d.classid = 'pg_proc'::regclass
                  AND d.objid = p.oid
                  AND d.deptype = 'e') AS extension_owned
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname = ANY (ARRAY[
    '_fire_reminder','add_employee_movement','adjust_inventory','create_account',
    'create_journal_entry','create_purchase_invoice','create_sale_invoice',
    'get_balance_sheet','get_chart_of_accounts','get_dashboard_summary',
    'get_employee_entitlement','get_income_statement','get_journal_entries',
    'get_ledger','get_my_role','get_my_tenant_id','get_my_user',
    'get_party_statement','get_trial_balance','get_user_tenants',
    'next_invoice_no','next_journal_no','pay_salary','record_payment',
    'register_tenant','seed_chart_of_accounts','seed_tenant_settings',
    'send_due_reminders','send_reminder_now','send_reminders_to_all',
    'set_master_tenant','settle_supplier','switch_tenant'])
ORDER BY p.proname, pg_get_function_identity_arguments(p.oid);

-- ---------------------------------------------------------------------
-- S4. Blocker matrix: EVERY reverse dependency for the 33 functions,
--     resolved by catalog class via pg_depend.classid::regclass.
--     Fail-closed policy: only same-scope objects are ALLOWed
--     (the 33 functions themselves; the 22 legacy tables as relkind='r').
--     Every other class -- including any class this query cannot resolve
--     -- is a BLOCKER. Nothing is filtered out of the result set.
-- ---------------------------------------------------------------------
\echo '==== S4. REVERSE DEPENDENCIES BY CATALOG CLASS (fail-closed) ===='
WITH legacy AS (
  SELECT p.oid,
         n.nspname||'.'||p.proname||'('||pg_get_function_identity_arguments(p.oid)||')' AS fn_identity
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND p.proname = ANY (ARRAY[
      '_fire_reminder','add_employee_movement','adjust_inventory','create_account',
      'create_journal_entry','create_purchase_invoice','create_sale_invoice',
      'get_balance_sheet','get_chart_of_accounts','get_dashboard_summary',
      'get_employee_entitlement','get_income_statement','get_journal_entries',
      'get_ledger','get_my_role','get_my_tenant_id','get_my_user',
      'get_party_statement','get_trial_balance','get_user_tenants',
      'next_invoice_no','next_journal_no','pay_salary','record_payment',
      'register_tenant','seed_chart_of_accounts','seed_tenant_settings',
      'send_due_reminders','send_reminder_now','send_reminders_to_all',
      'set_master_tenant','settle_supplier','switch_tenant'])
),
dep AS (
  SELECT d.classid,
         d.objid,
         d.deptype::text AS deptype,
         l.fn_identity
  FROM pg_depend d
  JOIN legacy l
    ON l.oid = d.refobjid
   AND d.refclassid = 'pg_proc'::regclass
  WHERE d.deptype <> 'p'   -- pins never reference user functions
),
resolved AS (
  SELECT dep.fn_identity,
         dep.classid,
         dep.objid,
         dep.deptype,
         c.relnamespace AS c_nsp,
         c.relname      AS c_name,
         c.relkind      AS c_kind,
         CASE dep.classid::regclass::text
           WHEN 'pg_class' THEN
             COALESCE(c.relnamespace::regnamespace::text, '?')||'.'||
             COALESCE(c.relname, '?')||' (relkind='||COALESCE(c.relkind::text, '?')||')'
           WHEN 'pg_proc' THEN
             COALESCE(pr.pronamespace::regnamespace::text, '?')||'.'||COALESCE(pr.proname, '?')
           WHEN 'pg_policy' THEN
             'policy "'||COALESCE(pol.polname, '?')||'" on '||
             COALESCE(pol.polrelid::regclass::text, '?')
           WHEN 'pg_trigger' THEN
             'trigger "'||COALESCE(tg.tgname, '?')||'" on '||
             COALESCE(tg.tgrelid::regclass::text, '?')
           WHEN 'pg_rewrite' THEN
             'rule "'||COALESCE(rw.rulename, '?')||'" on '||
             COALESCE(rw.ev_class::regclass::text, '?')
           WHEN 'pg_constraint' THEN
             'constraint "'||COALESCE(con.conname, '?')||'"'
           WHEN 'pg_attrdef' THEN
             'column default on '||COALESCE(ad.adrelid::regclass::text, '?')
           WHEN 'pg_type' THEN
             'type '||COALESCE(ty.typnamespace::regnamespace::text, '?')||'.'||
             COALESCE(ty.typname, '?')
           WHEN 'pg_operator' THEN
             'operator '||COALESCE(op.oprname, '?')
           WHEN 'pg_extension' THEN
             'extension '||COALESCE(ext.extname, '?')
           WHEN 'pg_ts_config' THEN
             'text search config '||COALESCE(tsc.cfgname, '?')
           WHEN 'pg_ts_dict' THEN
             'text search dictionary '||COALESCE(tsd.dictname, '?')
           WHEN 'pg_statistic_ext' THEN
             'extended statistics '||COALESCE(se.stxname, '?')
           ELSE
             'UNMAPPED CLASS '||dep.classid::regclass::text||' (objid='||dep.objid::text||')'
         END AS dependent_object
  FROM dep
  LEFT JOIN pg_class         c   ON dep.classid = 'pg_class'::regclass         AND c.oid   = dep.objid
  LEFT JOIN pg_proc          pr  ON dep.classid = 'pg_proc'::regclass          AND pr.oid  = dep.objid
  LEFT JOIN pg_policy        pol ON dep.classid = 'pg_policy'::regclass        AND pol.oid = dep.objid
  LEFT JOIN pg_trigger       tg  ON dep.classid = 'pg_trigger'::regclass       AND tg.oid  = dep.objid
  LEFT JOIN pg_rewrite       rw  ON dep.classid = 'pg_rewrite'::regclass       AND rw.oid  = dep.objid
  LEFT JOIN pg_constraint    con ON dep.classid = 'pg_constraint'::regclass    AND con.oid = dep.objid
  LEFT JOIN pg_attrdef       ad  ON dep.classid = 'pg_attrdef'::regclass       AND ad.oid  = dep.objid
  LEFT JOIN pg_type          ty  ON dep.classid = 'pg_type'::regclass          AND ty.oid  = dep.objid
  LEFT JOIN pg_operator      op  ON dep.classid = 'pg_operator'::regclass      AND op.oid  = dep.objid
  LEFT JOIN pg_extension     ext ON dep.classid = 'pg_extension'::regclass     AND ext.oid = dep.objid
  LEFT JOIN pg_ts_config     tsc ON dep.classid = 'pg_ts_config'::regclass     AND tsc.oid = dep.objid
  LEFT JOIN pg_ts_dict       tsd ON dep.classid = 'pg_ts_dict'::regclass       AND tsd.oid = dep.objid
  LEFT JOIN pg_statistic_ext se  ON dep.classid = 'pg_statistic_ext'::regclass AND se.oid  = dep.objid
)
SELECT r.fn_identity              AS depended_on_function,
       r.classid::regclass::text  AS dependent_catalog,
       r.deptype                  AS deptype,
       r.dependent_object         AS dependent_object,
       CASE
         WHEN r.dependent_object LIKE 'UNMAPPED%'
              THEN 'BLOCKER_UNMAPPED_CLASS'
         WHEN r.classid = 'pg_policy'::regclass
              THEN 'BLOCKER_POLICY_OUTSIDE_CLEANUP_SCOPE'
         WHEN r.classid = 'pg_proc'::regclass
              AND EXISTS (SELECT 1 FROM legacy l2 WHERE l2.oid = r.objid)
              THEN 'ALLOW_SAME_SCOPE_FUNCTION'
         WHEN r.classid = 'pg_class'::regclass
              AND r.c_nsp = 'public'::regnamespace
              AND r.c_kind = 'r'
              AND r.c_name = ANY (ARRAY[
                'accounts','commission_dues','customers','employee_movements','employees',
                'expenses','invoice_counters','invoice_items','invoices','journal_entries',
                'journal_entry_lines','payments','processed_requests','products','reminder_log',
                'salaries','stock_moves','suppliers','tenant_settings','tenants',
                'user_tenants','users'])
              THEN 'ALLOW_SAME_SCOPE_TABLE'
         ELSE 'BLOCKER'
       END AS classification
FROM resolved r
ORDER BY 5 DESC, 1, 2;   -- column 5 = classification: BLOCKER* first

-- ---------------------------------------------------------------------
-- S5. storage.objects policies: metadata only, NO expressions.
--     Answers: which policies block Stage 4, what they are attached to,
--     whether the catalog links them to a legacy V1 function, and whether
--     they are extension-owned (they are not expected to be).
--     Authorship is NOT decidable from pg_policy (no owner, no created_at).
-- ---------------------------------------------------------------------
\echo '==== S5. storage.objects POLICIES (metadata only) ===='
SELECT po.polname                                  AS policy_name,
       po.polrelid::regclass::text                 AS on_relation,
       CASE po.polcmd
         WHEN 'r' THEN 'SELECT'
         WHEN 'a' THEN 'INSERT'
         WHEN 'w' THEN 'UPDATE'
         WHEN 'd' THEN 'DELETE'
         WHEN '*' THEN 'ALL'
         ELSE po.polcmd::text
       END                                         AS command,
       po.polpermissive                            AS permissive,
       COALESCE((SELECT string_agg(
                          CASE WHEN r = 0 THEN 'PUBLIC' ELSE pg_get_userbyid(r) END,
                          ', ' ORDER BY CASE WHEN r = 0 THEN 'PUBLIC' ELSE pg_get_userbyid(r) END)
                   FROM unnest(po.polroles) AS r), '(none)') AS applies_to_roles,
       (po.polqual IS NOT NULL)                    AS has_using_expression,
       (po.polwithcheck IS NOT NULL)               AS has_with_check_expression,
       (COALESCE(pg_get_expr(po.polqual, po.polrelid), '') LIKE '%get_my_tenant_id%'
        OR COALESCE(pg_get_expr(po.polwithcheck, po.polrelid), '') LIKE '%get_my_tenant_id%')
                                                   AS expr_refs_get_my_tenant_id,
       COALESCE((SELECT string_agg(
                          DISTINCT p2.pronamespace::regnamespace::text||'.'||p2.proname||
                                   '('||pg_get_function_identity_arguments(p2.oid)||')',
                          '; ')
                   FROM pg_depend d
                   JOIN pg_proc p2
                     ON p2.oid = d.refobjid
                    AND d.refclassid = 'pg_proc'::regclass
                  WHERE d.classid = 'pg_policy'::regclass
                    AND d.objid = po.oid), '(none)') AS catalog_linked_functions,
       EXISTS (SELECT 1
                 FROM pg_depend d
                WHERE d.classid = 'pg_policy'::regclass
                  AND d.objid = po.oid
                  AND d.deptype = 'e')             AS extension_owned,
       pg_get_userbyid(pc.relowner)                AS table_owner
FROM pg_policy po
JOIN pg_class pc     ON pc.oid = po.polrelid
JOIN pg_namespace pn ON pn.oid = pc.relnamespace
WHERE pn.nspname = 'storage'
  AND pc.relname = 'objects'
ORDER BY po.polname;

-- ---------------------------------------------------------------------
-- S6. Verdict
-- ---------------------------------------------------------------------
\echo '==== S6. VERDICT ===='
DO $hasad_s4_verdict$
DECLARE
  v_names text[] := ARRAY[
    '_fire_reminder','add_employee_movement','adjust_inventory','create_account',
    'create_journal_entry','create_purchase_invoice','create_sale_invoice',
    'get_balance_sheet','get_chart_of_accounts','get_dashboard_summary',
    'get_employee_entitlement','get_income_statement','get_journal_entries',
    'get_ledger','get_my_role','get_my_tenant_id','get_my_user',
    'get_party_statement','get_trial_balance','get_user_tenants',
    'next_invoice_no','next_journal_no','pay_salary','record_payment',
    'register_tenant','seed_chart_of_accounts','seed_tenant_settings',
    'send_due_reminders','send_reminder_now','send_reminders_to_all',
    'set_master_tenant','settle_supplier','switch_tenant'];
  v_present int;
  v_missing text;
  v_overloaded text;
  v_blockers int;
  v_blocker_classes text;
  v_storage_policies int;
  v_linked int;
  v_linked_names text;
BEGIN
  SELECT count(*) INTO v_present
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND p.proname = ANY (v_names);

  SELECT string_agg(x, ', ' ORDER BY x) INTO v_missing
  FROM unnest(v_names) x
  WHERE NOT EXISTS (
    SELECT 1 FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = x);

  SELECT string_agg(proname||'='||cnt, ', ' ORDER BY proname) INTO v_overloaded
  FROM (SELECT p.proname, count(*) AS cnt
          FROM pg_proc p
          JOIN pg_namespace n ON n.oid = p.pronamespace
         WHERE n.nspname = 'public' AND p.proname = ANY (v_names)
         GROUP BY p.proname
        HAVING count(*) > 1) s;

  SELECT count(*),
         string_agg(DISTINCT d.classid::regclass::text, ', ')
    INTO v_blockers, v_blocker_classes
  FROM pg_depend d
  JOIN pg_proc p1 ON p1.oid = d.refobjid AND d.refclassid = 'pg_proc'::regclass
  JOIN pg_namespace n1 ON n1.oid = p1.pronamespace
  WHERE n1.nspname = 'public'
    AND p1.proname = ANY (v_names)
    AND d.deptype <> 'p'
    AND NOT (d.classid = 'pg_proc'::regclass AND d.objid IN (
          SELECT p2.oid FROM pg_proc p2
          JOIN pg_namespace n2 ON n2.oid = p2.pronamespace
          WHERE n2.nspname = 'public' AND p2.proname = ANY (v_names)))
    AND NOT (d.classid = 'pg_class'::regclass AND d.objid IN (
          SELECT c.oid FROM pg_class c
          JOIN pg_namespace n ON n.oid = c.relnamespace
          WHERE n.nspname = 'public' AND c.relkind = 'r'
            AND c.relname = ANY (ARRAY[
              'accounts','commission_dues','customers','employee_movements','employees',
              'expenses','invoice_counters','invoice_items','invoices','journal_entries',
              'journal_entry_lines','payments','processed_requests','products','reminder_log',
              'salaries','stock_moves','suppliers','tenant_settings','tenants',
              'user_tenants','users'])));

  SELECT count(*) INTO v_storage_policies
  FROM pg_policy po
  JOIN pg_class pc ON pc.oid = po.polrelid
  JOIN pg_namespace pn ON pn.oid = pc.relnamespace
  WHERE pn.nspname = 'storage' AND pc.relname = 'objects';

  SELECT count(*), string_agg(po.polname, ', ' ORDER BY po.polname)
    INTO v_linked, v_linked_names
  FROM pg_policy po
  JOIN pg_class pc ON pc.oid = po.polrelid
  JOIN pg_namespace pn ON pn.oid = pc.relnamespace
  WHERE pn.nspname = 'storage' AND pc.relname = 'objects'
    AND EXISTS (
      SELECT 1 FROM pg_depend d
      JOIN pg_proc p2 ON p2.oid = d.refobjid AND d.refclassid = 'pg_proc'::regclass
      JOIN pg_namespace n2 ON n2.oid = p2.pronamespace
      WHERE d.classid = 'pg_policy'::regclass AND d.objid = po.oid
        AND n2.nspname = 'public' AND p2.proname = ANY (v_names));

  RAISE NOTICE 'legacy_functions_present=%/33', v_present;
  RAISE NOTICE 'legacy_functions_missing=%', COALESCE(v_missing, '(none)');
  RAISE NOTICE 'legacy_overloaded_names=%', COALESCE(v_overloaded, '(none)');
  RAISE NOTICE 'blocking_dependents=%', v_blockers;
  RAISE NOTICE 'blocking_catalog_classes=%', COALESCE(v_blocker_classes, '(none)');
  RAISE NOTICE 'storage_objects_policy_count=%', v_storage_policies;
  RAISE NOTICE 'storage_objects_policies_linked_to_legacy=% (names: %)',
    v_linked, COALESCE(v_linked_names, '(none)');

  IF v_present <> 33 OR v_overloaded IS NOT NULL THEN
    RAISE NOTICE 'verdict=STATE_MISMATCH - expected exactly 33 non-overloaded legacy identities';
  ELSIF v_blockers > 0 THEN
    RAISE NOTICE 'verdict=BLOCKED - live dependents remain (not failed-transaction residue)';
  ELSE
    RAISE NOTICE 'verdict=READY_FOR_DRY_RUN - no catalog blockers remain';
  END IF;

  RAISE NOTICE 'caveat=pg_depend cannot see PL/pgSQL bodies, cron command text, client code or Edge Functions';
  RAISE NOTICE 'caveat=policy authorship is not provable from catalogs (pg_policy has no owner/created_at)';
END
$hasad_s4_verdict$;

ROLLBACK;
\echo ''
\echo 'ROLLBACK COMPLETE - NO DATABASE STATE WAS CHANGED'
