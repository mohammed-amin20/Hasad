-- Hasad ERP V2 / Unit S3 — READ-ONLY DEV PREFLIGHT, NO DEPLOYMENT.
-- Target: Supabase DEV project sxasnunzspkuwbxiddqd (Hasad-erp-dev).
--
-- This file only runs SELECT and system-catalog reads. It contains no DDL/DML,
-- no CREATE/ALTER/DROP/GRANT/REVOKE, no function execution that writes, and no
-- credentials. Run it in the DEV SQL editor only under a separate, explicit
-- read-only authorization.
--
-- It reports one row per check: PASS / FAIL with actionable JSON diagnostics.
-- A missing Abo Amen company, SI row, JE row, period, account or mapping can
-- never produce PASS: every target-scoped check also requires the selector to
-- match exactly one active company.

WITH
abo_matches AS (
  SELECT DISTINCT cs.company_id
  FROM hasad.company_settings cs
  JOIN hasad.companies c ON c.id = cs.company_id AND c.status = 'active'
  WHERE lower(btrim(coalesce(cs.name_ar, ''))) IN (lower('أبو أمين'), lower('Abo Amen'))
     OR lower(btrim(coalesce(cs.name_en, ''))) IN (lower('أبو أمين'), lower('Abo Amen'))
     OR lower(btrim(coalesce(cs.display_name, ''))) IN (lower('أبو أمين'), lower('Abo Amen'))
),
target AS (
  SELECT CASE WHEN count(*) = 1 THEN (array_agg(company_id))[1] END AS company_id,
         count(*) AS match_count
  FROM abo_matches
),
executor AS (
  SELECT r.rolname,
         r.rolsuper,
         r.rolcreaterole,
         r.rolbypassrls,
         pg_catalog.has_schema_privilege(current_user, 'hasad', 'USAGE') AS hasad_usage,
         pg_catalog.has_schema_privilege(current_user, 'hasad', 'CREATE') AS hasad_create,
         pg_catalog.has_function_privilege(
           current_user, 'pg_catalog.gen_random_uuid()', 'EXECUTE'
         ) AS uuid_execute
  FROM pg_catalog.pg_roles r
  WHERE r.rolname = current_user
),
required_tables(relation_name) AS (
  VALUES
    ('sales_documents'),('sales_document_lines'),('parties'),('products'),
    ('warehouses'),('document_types'),('fiscal_years'),('fiscal_periods'),
    ('accounts'),('module_account_map'),('tax_rates'),('doc_numbers'),
    ('journal_entries'),('journal_lines'),('stock_levels'),('stock_movements'),
    ('companies'),('company_memberships'),('roles'),('permissions'),
    ('role_permissions'),('user_permission_overrides'),('audit_log'),
    ('company_settings')
),
missing_tables AS (
  SELECT rt.relation_name
  FROM required_tables rt
  WHERE pg_catalog.to_regclass('hasad.' || rt.relation_name) IS NULL
),
required_columns(relation_name, column_name) AS (
  VALUES
    ('companies','id'),('companies','status'),
    ('company_settings','company_id'),('company_settings','name_ar'),
    ('company_settings','name_en'),('company_settings','display_name'),
    ('company_settings','vat_enabled'),
    ('company_memberships','id'),('company_memberships','company_id'),
    ('company_memberships','user_id'),('company_memberships','role_id'),
    ('company_memberships','is_owner'),('company_memberships','status'),
    ('roles','id'),('roles','company_id'),
    ('permissions','code'),('permissions','module'),
    ('role_permissions','role_id'),('role_permissions','permission_code'),
    ('user_permission_overrides','membership_id'),
    ('user_permission_overrides','permission_code'),
    ('user_permission_overrides','effect'),
    ('parties','id'),('parties','company_id'),('parties','is_customer'),
    ('parties','is_active'),
    ('products','id'),('products','company_id'),('products','track_inventory'),
    ('products','is_active'),
    ('warehouses','id'),('warehouses','company_id'),('warehouses','is_active'),
    ('document_types','id'),('document_types','company_id'),
    ('document_types','code'),('document_types','name_ar'),
    ('document_types','issuance'),('document_types','format_prefix'),
    ('document_types','pad_length'),('document_types','is_active'),
    ('fiscal_years','id'),('fiscal_years','company_id'),
    ('fiscal_years','start_date'),('fiscal_years','end_date'),
    ('fiscal_years','status'),
    ('fiscal_periods','id'),('fiscal_periods','company_id'),
    ('fiscal_periods','fiscal_year_id'),('fiscal_periods','period_no'),
    ('fiscal_periods','start_date'),('fiscal_periods','end_date'),
    ('fiscal_periods','status'),
    ('accounts','id'),('accounts','company_id'),('accounts','code'),
    ('accounts','account_type'),('accounts','is_active'),
    ('module_account_map','id'),('module_account_map','company_id'),
    ('module_account_map','module'),('module_account_map','account_role'),
    ('module_account_map','account_id'),
    ('tax_rates','id'),('tax_rates','company_id'),('tax_rates','code'),
    ('tax_rates','rate'),('tax_rates','valid_from'),('tax_rates','valid_to'),
    ('tax_rates','is_active'),
    ('doc_numbers','company_id'),('doc_numbers','document_type_id'),
    ('doc_numbers','fiscal_year_id'),('doc_numbers','next_value'),
    ('sales_documents','id'),('sales_documents','company_id'),
    ('sales_documents','doc_kind'),('sales_documents','status'),
    ('sales_documents','party_id'),('sales_documents','doc_date'),
    ('sales_documents','vat_mode'),('sales_documents','doc_type_id'),
    ('sales_documents','fiscal_year_id'),('sales_documents','doc_no'),
    ('sales_documents','original_document_id'),
    ('sales_documents','idempotency_key'),('sales_documents','net'),
    ('sales_documents','tax'),('sales_documents','gross'),
    ('sales_documents','posted_at'),('sales_documents','posted_by'),
    ('sales_document_lines','id'),('sales_document_lines','company_id'),
    ('sales_document_lines','document_id'),('sales_document_lines','line_no'),
    ('sales_document_lines','product_id'),('sales_document_lines','warehouse_id'),
    ('sales_document_lines','qty'),('sales_document_lines','unit_price'),
    ('sales_document_lines','discount_amount'),('sales_document_lines','tax_rate'),
    ('sales_document_lines','net'),('sales_document_lines','tax'),
    ('sales_document_lines','gross'),('sales_document_lines','order_line_id'),
    ('sales_document_lines','original_line_id'),
    ('stock_levels','company_id'),('stock_levels','product_id'),
    ('stock_levels','warehouse_id'),('stock_levels','qty'),
    ('stock_levels','last_unit_cost'),
    ('stock_movements','id'),('stock_movements','company_id'),
    ('stock_movements','product_id'),('stock_movements','warehouse_id'),
    ('stock_movements','movement_type'),('stock_movements','direction'),
    ('stock_movements','qty'),('stock_movements','unit_cost'),
    ('stock_movements','value'),('stock_movements','seq'),
    ('stock_movements','source_document_type'),
    ('stock_movements','source_document_id'),
    ('stock_movements','journal_line_id'),('stock_movements','posted_at'),
    ('journal_entries','id'),('journal_entries','company_id'),
    ('journal_entries','fiscal_year_id'),('journal_entries','period_id'),
    ('journal_entries','entry_date'),('journal_entries','entry_kind'),
    ('journal_entries','status'),('journal_entries','entry_no'),
    ('journal_entries','reversal_of_id'),('journal_entries','idempotency_key'),
    ('journal_entries','posted_at'),('journal_entries','posted_by'),
    ('journal_entries','reason'),
    ('journal_lines','id'),('journal_lines','company_id'),
    ('journal_lines','entry_id'),('journal_lines','line_no'),
    ('journal_lines','account_id'),('journal_lines','party_id'),
    ('journal_lines','debit'),('journal_lines','credit'),
    ('journal_lines','description'),
    ('audit_log','id'),('audit_log','company_id'),('audit_log','actor_user_id'),
    ('audit_log','action'),('audit_log','entity_type'),
    ('audit_log','entity_id'),('audit_log','details')
),
missing_columns AS (
  SELECT rc.relation_name, rc.column_name
  FROM required_columns rc
  LEFT JOIN pg_catalog.pg_attribute a
    ON a.attrelid = pg_catalog.to_regclass('hasad.' || rc.relation_name)
   AND a.attname = rc.column_name
   AND a.attnum > 0
   AND NOT a.attisdropped
  WHERE a.attname IS NULL
),
required_indexes(index_name) AS (
  VALUES
    ('accounts_company_code_key'),
    ('doc_numbers_pkey'),
    ('document_types_company_code_key'),
    ('fiscal_periods_year_period_no_key'),
    ('journal_entries_company_entry_no_key'),
    ('journal_entries_company_idempotency_key_key'),
    ('module_account_map_company_module_role_key'),
    ('sales_documents_company_doc_no_key'),
    ('sales_documents_company_idempotency_key_key'),
    ('stock_levels_pkey'),
    ('stock_movements_product_seq_key')
),
missing_indexes AS (
  SELECT ri.index_name
  FROM required_indexes ri
  WHERE NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_class ic
    JOIN pg_catalog.pg_namespace n ON n.oid = ic.relnamespace
    JOIN pg_catalog.pg_index i ON i.indexrelid = ic.oid
    WHERE n.nspname = 'hasad'
      AND ic.relname = ri.index_name
      AND i.indisunique
      AND i.indisvalid
  )
),
table_state AS (
  SELECT rt.relation_name,
         c.oid IS NOT NULL AS table_exists,
         coalesce(c.relrowsecurity, false) AS rls_enabled,
         coalesce(c.relforcerowsecurity, false) AS force_rls,
         pg_catalog.pg_get_userbyid(c.relowner) AS table_owner
  FROM required_tables rt
  LEFT JOIN pg_catalog.pg_class c
    ON c.oid = pg_catalog.to_regclass('hasad.' || rt.relation_name)
),
s3_function_names(proname) AS (
  VALUES
    ('sales_posting_actor_id'),
    ('sales_posting_allowed'),
    ('allocate_document_number'),
    ('post_sales_invoice')
),
existing_s3_functions AS (
  SELECT p.oid::regprocedure::text AS signature
  FROM pg_catalog.pg_proc p
  JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'hasad'
    AND p.proname IN (SELECT proname FROM s3_function_names)
),
s3_policy_names(policy_name) AS (
  VALUES
    ('hasad_sales_poster_memberships_read'),
    ('hasad_sales_poster_companies_read'),
    ('hasad_sales_poster_roles_read'),
    ('hasad_sales_poster_permissions_read'),
    ('hasad_sales_poster_role_permissions_read'),
    ('hasad_sales_poster_overrides_read'),
    ('hasad_sales_poster_parties_read'),
    ('hasad_sales_poster_products_read'),
    ('hasad_sales_poster_warehouses_read'),
    ('hasad_sales_poster_document_types_read'),
    ('hasad_sales_poster_fiscal_years_read'),
    ('hasad_sales_poster_fiscal_periods_read'),
    ('hasad_sales_poster_accounts_read'),
    ('hasad_sales_poster_module_map_read'),
    ('hasad_sales_poster_tax_rates_read'),
    ('hasad_sales_poster_doc_numbers_all'),
    ('hasad_sales_poster_documents_read'),
    ('hasad_sales_poster_documents_update'),
    ('hasad_sales_poster_lines_read'),
    ('hasad_sales_poster_stock_levels_read'),
    ('hasad_sales_poster_stock_levels_update'),
    ('hasad_sales_poster_stock_movements_read'),
    ('hasad_sales_poster_stock_movements_insert'),
    ('hasad_sales_poster_journal_entries_read'),
    ('hasad_sales_poster_journal_entries_insert'),
    ('hasad_sales_poster_journal_lines_read'),
    ('hasad_sales_poster_journal_lines_insert'),
    ('hasad_sales_poster_audit_insert')
),
existing_s3_policies AS (
  SELECT pol.polname AS policy_name, c.relname AS table_name
  FROM pg_catalog.pg_policy pol
  JOIN pg_catalog.pg_class c ON c.oid = pol.polrelid
  JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'hasad'
    AND pol.polname IN (SELECT policy_name FROM s3_policy_names)
),
poster_role AS (
  SELECT r.rolname, r.rolcanlogin, r.rolinherit, r.rolsuper, r.rolcreatedb,
         r.rolcreaterole, r.rolreplication, r.rolbypassrls
  FROM pg_catalog.pg_roles r
  WHERE r.rolname = 'hasad_sales_poster'
),
poster_client_membership AS (
  SELECT member.rolname
  FROM pg_catalog.pg_auth_members m
  JOIN pg_catalog.pg_roles granted ON granted.oid = m.roleid
  JOIN pg_catalog.pg_roles member ON member.oid = m.member
  WHERE granted.rolname = 'hasad_sales_poster'
    AND member.rolname IN ('authenticated', 'anon')
),
poster_set_option AS (
  SELECT CASE
           WHEN EXISTS (SELECT 1 FROM pg_catalog.pg_roles WHERE rolname = 'hasad_sales_poster')
           THEN pg_catalog.pg_has_role(current_user, 'hasad_sales_poster', 'SET')
           ELSE false
         END AS has_set
),
fy AS (
  SELECT count(*) AS row_count,
         count(*) FILTER (WHERE fy.status = 'open') AS open_count,
         coalesce(jsonb_agg(jsonb_build_object(
           'id', fy.id, 'start_date', fy.start_date,
           'end_date', fy.end_date, 'status', fy.status
         ) ORDER BY fy.start_date), '[]'::jsonb) AS rows
  FROM hasad.fiscal_years fy
  CROSS JOIN target t
  WHERE t.company_id IS NOT NULL
    AND fy.company_id = t.company_id
    AND fy.start_date = DATE '2026-01-01'
    AND fy.end_date = DATE '2026-12-31'
),
si AS (
  SELECT count(*) AS row_count,
         count(*) FILTER (
           WHERE dt.is_active
             AND dt.issuance = 'posting'
             AND dt.name_ar = 'فاتورة مبيعات'
             AND dt.format_prefix = 'SI'
             AND dt.pad_length = 4
         ) AS valid_count,
         coalesce(jsonb_agg(jsonb_build_object(
           'id', dt.id, 'name_ar', dt.name_ar, 'issuance', dt.issuance,
           'format_prefix', dt.format_prefix, 'pad_length', dt.pad_length,
           'is_active', dt.is_active
         ) ORDER BY dt.id), '[]'::jsonb) AS rows
  FROM hasad.document_types dt
  CROSS JOIN target t
  WHERE t.company_id IS NOT NULL
    AND dt.company_id = t.company_id
    AND dt.code = 'SI'
),
je AS (
  SELECT count(*) AS row_count,
         count(*) FILTER (
           WHERE dt.is_active
             AND dt.issuance = 'posting'
             AND dt.name_ar = 'قيد يومية'
             AND dt.format_prefix = 'JE'
             AND dt.pad_length = 4
         ) AS valid_count,
         coalesce(jsonb_agg(jsonb_build_object(
           'id', dt.id, 'name_ar', dt.name_ar, 'issuance', dt.issuance,
           'format_prefix', dt.format_prefix, 'pad_length', dt.pad_length,
           'is_active', dt.is_active
         ) ORDER BY dt.id), '[]'::jsonb) AS rows
  FROM hasad.document_types dt
  CROSS JOIN target t
  WHERE t.company_id IS NOT NULL
    AND dt.company_id = t.company_id
    AND dt.code = 'JE'
),
periods AS (
  SELECT count(*) AS row_count,
         count(*) FILTER (WHERE fp.status = 'open') AS open_count,
         count(*) FILTER (
           WHERE fp.status = 'open' AND fp.period_no = 10
         ) AS october_open_count,
         count(*) FILTER (WHERE fp.period_no NOT BETWEEN 1 AND 12) AS bad_period_no_count,
         count(*) FILTER (
           WHERE fp.period_no NOT BETWEEN 1 AND 12
              OR fp.start_date <> (
                   DATE '2026-01-01'
                   + ((fp.period_no - 1) * INTERVAL '1 month')
                 )::date
              OR fp.end_date <> (
                   DATE '2026-01-01'
                   + ((fp.period_no - 1) * INTERVAL '1 month')
                   + INTERVAL '1 month - 1 day'
                 )::date
         ) AS bad_date_count,
         coalesce(jsonb_agg(jsonb_build_object(
           'period_no', fp.period_no, 'start_date', fp.start_date,
           'end_date', fp.end_date, 'status', fp.status
         ) ORDER BY fp.period_no), '[]'::jsonb) AS rows
  FROM hasad.fiscal_periods fp
  JOIN hasad.fiscal_years fy
    ON fy.id = fp.fiscal_year_id AND fy.company_id = fp.company_id
  CROSS JOIN target t
  WHERE t.company_id IS NOT NULL
    AND fp.company_id = t.company_id
    AND fy.start_date = DATE '2026-01-01'
    AND fy.end_date = DATE '2026-12-31'
),
approved_accounts(code, name_ar, account_type, account_role) AS (
  VALUES
    ('1100', 'الذمم المدينة التجارية', 'asset', 'AR_CONTROL'),
    ('1200', 'مخزون البضاعة', 'asset', 'INVENTORY_CONTROL'),
    ('2100', 'ضريبة القيمة المضافة – مخرجات', 'liability', 'VAT_OUTPUT'),
    ('4100', 'إيرادات المبيعات', 'revenue', 'SALES_REVENUE'),
    ('5100', 'تكلفة البضاعة المباعة', 'expense', 'COGS')
),
account_report AS (
  SELECT aa.code,
         aa.name_ar AS approved_name_ar,
         aa.account_type AS approved_type,
         aa.account_role,
         a.id AS existing_account_id,
         a.name_ar AS existing_name_ar,
         a.account_type AS existing_type,
         a.parent_id,
         a.is_active
  FROM approved_accounts aa
  CROSS JOIN target t
  LEFT JOIN hasad.accounts a
    ON t.company_id IS NOT NULL
   AND a.company_id = t.company_id
   AND a.code = aa.code
),
mapping_report AS (
  SELECT aa.account_role,
         aa.code AS expected_code,
         m.account_id,
         a.code AS mapped_code
  FROM approved_accounts aa
  CROSS JOIN target t
  LEFT JOIN hasad.module_account_map m
    ON t.company_id IS NOT NULL
   AND m.company_id = t.company_id
   AND m.module = 'sales'
   AND m.account_role = aa.account_role
  LEFT JOIN hasad.accounts a
    ON t.company_id IS NOT NULL
   AND a.company_id = t.company_id
   AND a.id = m.account_id
),
vat AS (
  SELECT cs.vat_enabled
  FROM hasad.company_settings cs
  CROSS JOIN target t
  WHERE t.company_id IS NOT NULL
    AND cs.company_id = t.company_id
),
tax AS (
  SELECT count(*) AS row_count
  FROM hasad.tax_rates tr
  CROSS JOIN target t
  WHERE t.company_id IS NOT NULL
    AND tr.company_id = t.company_id
),
counters AS (
  SELECT count(*) AS row_count,
         coalesce(jsonb_agg(jsonb_build_object(
           'document_type_code', dt.code,
           'fiscal_year_start', fy.start_date,
           'next_value', dn.next_value
         ) ORDER BY dt.code), '[]'::jsonb) AS rows
  FROM hasad.doc_numbers dn
  JOIN hasad.document_types dt
    ON dt.id = dn.document_type_id AND dt.company_id = dn.company_id
  JOIN hasad.fiscal_years fy
    ON fy.id = dn.fiscal_year_id AND fy.company_id = dn.company_id
  CROSS JOIN target t
  WHERE t.company_id IS NOT NULL
    AND dn.company_id = t.company_id
),
s2 AS (
  SELECT
    pg_catalog.to_regprocedure(
      'hasad.save_sales_invoice_draft(uuid,uuid,uuid,date,text,uuid,uuid,uuid,jsonb)'
    ) IS NOT NULL AS rpc_exists,
    pg_catalog.to_regprocedure(
      'hasad.sales_request_actor_user_id()'
    ) IS NOT NULL AS actor_helper_exists,
    pg_catalog.to_regprocedure(
      'hasad.sales_draft_allowed(uuid)'
    ) IS NOT NULL AS allowed_helper_exists,
    EXISTS (
      SELECT 1 FROM pg_catalog.pg_roles WHERE rolname = 'hasad_sales_draft_writer'
    ) AS writer_role_exists,
    EXISTS (
      SELECT 1 FROM hasad.permissions
      WHERE code = 'sales.create' AND module = 'sales'
    ) AS create_permission_exists,
    CASE
      WHEN pg_catalog.to_regprocedure(
        'hasad.save_sales_invoice_draft(uuid,uuid,uuid,date,text,uuid,uuid,uuid,jsonb)'
      ) IS NULL THEN false
      ELSE pg_catalog.has_function_privilege(
        'authenticated',
        'hasad.save_sales_invoice_draft(uuid,uuid,uuid,date,text,uuid,uuid,uuid,jsonb)',
        'EXECUTE'
      )
    END AS authenticated_execute
),
inventory_api AS (
  SELECT pg_catalog.to_regprocedure(
    'hasad.post_stock_issue(uuid,uuid,uuid,uuid,numeric)'
  ) IS NOT NULL AS function_present
),
posting_actor AS (
  SELECT count(*) AS eligible_memberships
  FROM hasad.company_memberships cm
  CROSS JOIN target t
  WHERE t.company_id IS NOT NULL
    AND cm.company_id = t.company_id
    AND cm.status = 'active'
    AND (
      cm.is_owner
      OR EXISTS (
        SELECT 1 FROM hasad.user_permission_overrides uo
        WHERE uo.membership_id = cm.id
          AND uo.permission_code = 'sales.post'
          AND uo.effect = 'allow'
      )
      OR (
        NOT EXISTS (
          SELECT 1 FROM hasad.user_permission_overrides uo
          WHERE uo.membership_id = cm.id
            AND uo.permission_code = 'sales.post'
            AND uo.effect = 'deny'
        )
        AND EXISTS (
          SELECT 1
          FROM hasad.role_permissions rp
          JOIN hasad.roles r
            ON r.id = rp.role_id AND r.company_id = cm.company_id
          WHERE rp.role_id = cm.role_id
            AND rp.permission_code = 'sales.post'
        )
      )
    )
),
posted_integrity AS (
  SELECT
    (
      SELECT count(*) FROM hasad.sales_documents sd
      CROSS JOIN target t
      WHERE t.company_id IS NOT NULL
        AND sd.company_id = t.company_id
        AND sd.status = 'posted'
    ) AS posted_invoices,
    (
      SELECT count(*) FROM hasad.sales_documents sd
      CROSS JOIN target t
      WHERE t.company_id IS NOT NULL
        AND sd.company_id = t.company_id
        AND sd.status = 'draft'
    ) AS draft_invoices,
    (
      SELECT count(*) FROM hasad.sales_documents sd
      CROSS JOIN target t
      WHERE t.company_id IS NOT NULL
        AND sd.company_id = t.company_id
        AND sd.status = 'posted'
        AND (sd.doc_no IS NULL OR sd.posted_at IS NULL OR sd.posted_by IS NULL)
    ) AS invalid_posted_invoices,
    (
      SELECT count(*) FROM hasad.journal_entries je
      CROSS JOIN target t
      WHERE t.company_id IS NOT NULL
        AND je.company_id = t.company_id
        AND je.status = 'posted'
        AND (je.entry_no IS NULL OR je.posted_at IS NULL OR je.posted_by IS NULL)
    ) AS invalid_posted_entries,
    (
      SELECT count(*) FROM hasad.stock_movements sm
      CROSS JOIN target t
      WHERE t.company_id IS NOT NULL
        AND sm.company_id = t.company_id
    ) AS stock_movements
),
checks AS (
  SELECT 1 AS check_no,
         'ABO_AMEN_COMPANY_SELECTOR' AS check_name,
         CASE WHEN (SELECT match_count FROM target) = 1 THEN 'PASS' ELSE 'FAIL' END AS status,
         jsonb_build_object(
           'matched_active_companies', (SELECT match_count FROM target),
           'expected', 1,
           'action', 'Make exactly one active company match name_ar/name_en/display_name Abu Amen; do not deploy against an ambiguous selector.'
         ) AS detail

  UNION ALL
  SELECT 2,
         'EXECUTOR_ROLE_ADMIN_CAPABILITY',
         CASE WHEN (SELECT rolsuper OR rolcreaterole FROM executor) THEN 'PASS' ELSE 'FAIL' END,
         jsonb_build_object(
           'current_user', (SELECT rolname FROM executor),
           'rolsuper', (SELECT rolsuper FROM executor),
           'rolcreaterole', (SELECT rolcreaterole FROM executor),
           'rolbypassrls', (SELECT rolbypassrls FROM executor),
           'action', 'Install the candidate with a role that is SUPERUSER or CREATEROLE, as the verified DEV executor is.'
         )

  UNION ALL
  SELECT 3,
         'EXECUTOR_HASAD_SCHEMA_ACCESS',
         CASE WHEN (SELECT hasad_usage AND hasad_create FROM executor) THEN 'PASS' ELSE 'FAIL' END,
         jsonb_build_object(
           'hasad_usage', (SELECT hasad_usage FROM executor),
           'hasad_create', (SELECT hasad_create FROM executor),
           'action', 'Grant USAGE and CREATE on schema hasad to the deployment executor.'
         )

  UNION ALL
  SELECT 4,
         'EXECUTOR_UUID_FUNCTION',
         CASE WHEN (SELECT uuid_execute FROM executor) THEN 'PASS' ELSE 'FAIL' END,
         jsonb_build_object(
           'gen_random_uuid_execute', (SELECT uuid_execute FROM executor),
           'action', 'The candidate uses pg_catalog.gen_random_uuid(); ensure EXECUTE is available.'
         )

  UNION ALL
  SELECT 5,
         'REQUIRED_TABLES_EXIST',
         CASE WHEN NOT EXISTS (SELECT 1 FROM missing_tables) THEN 'PASS' ELSE 'FAIL' END,
         jsonb_build_object(
           'missing_tables', (
             SELECT coalesce(jsonb_agg(relation_name ORDER BY relation_name), '[]'::jsonb)
             FROM missing_tables
           ),
           'action', 'Apply the approved V2 migrations before deploying S3.'
         )

  UNION ALL
  SELECT 6,
         'REQUIRED_COLUMNS_EXIST',
         CASE WHEN NOT EXISTS (SELECT 1 FROM missing_columns) THEN 'PASS' ELSE 'FAIL' END,
         jsonb_build_object(
           'missing_columns', (
             SELECT coalesce(jsonb_agg(jsonb_build_object(
               'table', relation_name, 'column', column_name
             ) ORDER BY relation_name, column_name), '[]'::jsonb)
             FROM missing_columns
           ),
           'action', 'A schema/version mismatch exists; reconcile migrations before deployment.'
         )

  UNION ALL
  SELECT 7,
         'REQUIRED_KEYS_AND_UNIQUE_INDEXES',
         CASE WHEN NOT EXISTS (SELECT 1 FROM missing_indexes) THEN 'PASS' ELSE 'FAIL' END,
         jsonb_build_object(
           'missing_indexes', (
             SELECT coalesce(jsonb_agg(index_name ORDER BY index_name), '[]'::jsonb)
             FROM missing_indexes
           ),
           'action', 'Numbering and idempotency depend on these unique indexes; restore them before deployment.'
         )

  UNION ALL
  SELECT 8,
         'RLS_AND_FORCE_RLS_ENABLED',
         CASE WHEN NOT EXISTS (
                SELECT 1 FROM table_state WHERE NOT rls_enabled OR NOT force_rls
              ) THEN 'PASS' ELSE 'FAIL' END,
         jsonb_build_object(
           'bad_tables', (
             SELECT coalesce(jsonb_agg(jsonb_build_object(
               'table', relation_name, 'rls_enabled', rls_enabled, 'force_rls', force_rls
             ) ORDER BY relation_name) FILTER (WHERE NOT rls_enabled OR NOT force_rls), '[]'::jsonb)
             FROM table_state
           ),
           'action', 'Re-enable ROW LEVEL SECURITY and FORCE ROW LEVEL SECURITY; never weaken RLS to deploy.'
         )

  UNION ALL
  SELECT 9,
         'TABLE_OWNERSHIP_MATCHES_EXECUTOR',
         CASE WHEN NOT EXISTS (
                SELECT 1 FROM table_state
                WHERE table_owner IS DISTINCT FROM current_user
              ) THEN 'PASS' ELSE 'FAIL' END,
         jsonb_build_object(
           'current_user', (SELECT rolname FROM executor),
           'bad_tables', (
             SELECT coalesce(jsonb_agg(jsonb_build_object(
               'table', relation_name, 'owner', table_owner
             ) ORDER BY relation_name) FILTER (WHERE table_owner IS DISTINCT FROM current_user), '[]'::jsonb)
             FROM table_state
           ),
           'action', 'The candidate grants column privileges and creates policies; every target table must be owned by the executing role.'
         )

  UNION ALL
  SELECT 10,
         'SALES_POST_PERMISSION_PRESENT',
         CASE WHEN EXISTS (
                SELECT 1 FROM hasad.permissions
                WHERE code = 'sales.post' AND module = 'sales'
              ) THEN 'PASS' ELSE 'FAIL' END,
         jsonb_build_object(
           'action', 'Seed or restore permissions code=sales.post, module=sales.'
         )

  UNION ALL
  SELECT 11,
         'NO_S3_FUNCTION_CONFLICT',
         CASE WHEN NOT EXISTS (SELECT 1 FROM existing_s3_functions) THEN 'PASS' ELSE 'FAIL' END,
         jsonb_build_object(
           'existing_signatures', (
             SELECT coalesce(jsonb_agg(signature ORDER BY signature), '[]'::jsonb)
             FROM existing_s3_functions
           ),
           'action', 'A full or partial S3 installation already exists; review/drop only under a separate authorized change before re-running the candidate.'
         )

  UNION ALL
  SELECT 12,
         'NO_S3_POLICY_NAME_CONFLICT',
         CASE WHEN NOT EXISTS (SELECT 1 FROM existing_s3_policies) THEN 'PASS' ELSE 'FAIL' END,
         jsonb_build_object(
           'existing_policies', (
             SELECT coalesce(jsonb_agg(jsonb_build_object(
               'policy', policy_name, 'table', table_name
             ) ORDER BY policy_name), '[]'::jsonb)
             FROM existing_s3_policies
           ),
           'action', 'Candidate policy names must be free; a partial S3 install would make CREATE POLICY fail.'
         )

  UNION ALL
  SELECT 13,
         'POSTER_ROLE_SAFE_AND_INSTALLABLE',
         CASE
           WHEN NOT EXISTS (SELECT 1 FROM poster_role) THEN
             CASE WHEN (SELECT rolsuper OR rolcreaterole FROM executor) THEN 'PASS' ELSE 'FAIL' END
           WHEN EXISTS (
             SELECT 1 FROM poster_role
             WHERE rolcanlogin OR rolinherit OR rolsuper OR rolcreatedb
                OR rolcreaterole OR rolreplication OR rolbypassrls
           ) THEN 'FAIL'
           WHEN EXISTS (SELECT 1 FROM poster_client_membership) THEN 'FAIL'
           WHEN (SELECT has_set FROM poster_set_option) THEN 'PASS'
           WHEN (SELECT rolsuper OR rolcreaterole FROM executor) THEN 'PASS'
           ELSE 'FAIL'
         END,
         jsonb_build_object(
           'role_exists', (SELECT count(*) FROM poster_role) > 0,
           'safe_attributes', NOT EXISTS (
             SELECT 1 FROM poster_role
             WHERE rolcanlogin OR rolinherit OR rolsuper OR rolcreatedb
                OR rolcreaterole OR rolreplication OR rolbypassrls
           ),
           'client_memberships', (
             SELECT coalesce(jsonb_agg(rolname ORDER BY rolname), '[]'::jsonb)
             FROM poster_client_membership
           ),
           'current_user_has_set', (SELECT has_set FROM poster_set_option),
           'executor_can_create_or_admin', (SELECT rolsuper OR rolcreaterole FROM executor),
           'action', 'Recreate hasad_sales_poster as NOLOGIN NOINHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS and keep it out of anon/authenticated.'
         )

  UNION ALL
  SELECT 14,
         'CLIENT_ROLES_PRESENT',
         CASE WHEN (
                SELECT count(*) FROM pg_catalog.pg_roles
                WHERE rolname IN ('anon', 'authenticated')
              ) = 2 THEN 'PASS' ELSE 'FAIL' END,
         jsonb_build_object(
           'missing_roles', (
             SELECT coalesce(jsonb_agg(required_name ORDER BY required_name), '[]'::jsonb)
             FROM (VALUES ('anon'), ('authenticated')) req(required_name)
             WHERE NOT EXISTS (
               SELECT 1 FROM pg_catalog.pg_roles r WHERE r.rolname = req.required_name
             )
           ),
           'action', 'Supabase client roles must exist before GRANT/REVOKE statements are applied.'
         )

  UNION ALL
  SELECT 15,
         'FY_2026_OPEN',
         CASE WHEN (SELECT match_count FROM target) = 1
                AND (SELECT row_count = 1 AND open_count = 1 FROM fy)
              THEN 'PASS' ELSE 'FAIL' END,
         jsonb_build_object(
           'matched_count', (SELECT row_count FROM fy),
           'open_count', (SELECT open_count FROM fy),
           'rows', (SELECT rows FROM fy),
           'action', 'Keep exactly one open FY 2026-01-01..2026-12-31 for Abo Amen.'
         )

  UNION ALL
  SELECT 16,
         'SI_DOCUMENT_TYPE_CONTRACT',
         CASE WHEN (SELECT match_count FROM target) = 1
                AND (SELECT row_count = 1 AND valid_count = 1 FROM si)
              THEN 'PASS' ELSE 'FAIL' END,
         jsonb_build_object(
           'row_count', (SELECT row_count FROM si),
           'valid_count', (SELECT valid_count FROM si),
           'rows', (SELECT rows FROM si),
           'expected', 'code=SI, active, issuance=posting, name_ar=فاتورة مبيعات, format_prefix=SI, pad_length=4',
           'action', 'Fix the existing SI row; the S3 candidate refuses an empty/non-SI prefix and never creates a second SI row.'
         )

  UNION ALL
  SELECT 17,
         'JE_DOCUMENT_TYPE_CONTRACT',
         CASE WHEN (SELECT match_count FROM target) = 1
                AND (SELECT row_count = 1 AND valid_count = 1 FROM je)
              THEN 'PASS' ELSE 'FAIL' END,
         jsonb_build_object(
           'row_count', (SELECT row_count FROM je),
           'valid_count', (SELECT valid_count FROM je),
           'rows', (SELECT rows FROM je),
           'expected', 'code=JE, active, issuance=posting, name_ar=قيد يومية, format_prefix=JE, pad_length=4',
           'action', 'Deploy/repair the JE document type before asking for S3 deployment.'
         )

  UNION ALL
  SELECT 18,
         'FISCAL_PERIODS_OCTOBER_ONLY',
         CASE WHEN (SELECT match_count FROM target) = 1
                AND (SELECT row_count = 12
                            AND open_count = 1
                            AND october_open_count = 1
                            AND bad_period_no_count = 0
                            AND bad_date_count = 0
                     FROM periods)
              THEN 'PASS' ELSE 'FAIL' END,
         jsonb_build_object(
           'row_count', (SELECT row_count FROM periods),
           'open_count', (SELECT open_count FROM periods),
           'october_open_count', (SELECT october_open_count FROM periods),
           'bad_period_no_count', (SELECT bad_period_no_count FROM periods),
           'bad_date_count', (SELECT bad_date_count FROM periods),
           'rows', (SELECT rows FROM periods),
           'action', 'Expect 12 calendar periods for FY 2026 with only period 10 (October 2026) open.'
         )

  UNION ALL
  SELECT 19,
         'APPROVED_ACCOUNTS_CONTRACT',
         CASE WHEN (SELECT match_count FROM target) = 1
                AND (
                  SELECT count(*) FROM account_report
                  WHERE existing_account_id IS NOT NULL
                    AND existing_name_ar = approved_name_ar
                    AND existing_type = approved_type
                    AND parent_id IS NULL
                    AND is_active
                ) = 5
              THEN 'PASS' ELSE 'FAIL' END,
         jsonb_build_object(
           'accounts', (
             SELECT coalesce(jsonb_agg(jsonb_build_object(
               'code', code,
               'approved_name_ar', approved_name_ar,
               'existing_name_ar', existing_name_ar,
               'approved_type', approved_type,
               'existing_type', existing_type,
               'parent_id', parent_id,
               'is_active', is_active,
               'ok', existing_account_id IS NOT NULL
                     AND existing_name_ar = approved_name_ar
                     AND existing_type = approved_type
                     AND parent_id IS NULL
                     AND is_active
             ) ORDER BY code), '[]'::jsonb)
             FROM account_report
           ),
           'action', 'Reconcile the five approved accounts: 1100, 1200, 2100, 4100, 5100 with parent_id NULL and active=true.'
         )

  UNION ALL
  SELECT 20,
         'APPROVED_SALES_MAPPINGS_CONTRACT',
         CASE WHEN (SELECT match_count FROM target) = 1
                AND (
                  SELECT count(*) FROM mapping_report
                  WHERE mapped_code = expected_code
                ) = 5
              THEN 'PASS' ELSE 'FAIL' END,
         jsonb_build_object(
           'mappings', (
             SELECT coalesce(jsonb_agg(jsonb_build_object(
               'account_role', account_role,
               'expected_code', expected_code,
               'mapped_account_id', account_id,
               'mapped_code', mapped_code,
               'ok', mapped_code = expected_code
             ) ORDER BY account_role), '[]'::jsonb)
             FROM mapping_report
           ),
           'action', 'Map sales AR_CONTROL->1100, INVENTORY_CONTROL->1200, VAT_OUTPUT->2100, SALES_REVENUE->4100, COGS->5100.'
         )

  UNION ALL
  SELECT 21,
         'VAT_DISABLED',
         CASE WHEN (SELECT vat_enabled FROM vat) IS FALSE THEN 'PASS' ELSE 'FAIL' END,
         jsonb_build_object(
           'vat_enabled', (SELECT vat_enabled FROM vat),
           'action', 'Keep VAT disabled for this deployment; enabling VAT requires D-023 and an effective-dated rate.'
         )

  UNION ALL
  SELECT 22,
         'NO_TAX_RATES_EXPECTED',
         CASE WHEN (SELECT match_count FROM target) = 1
                AND (SELECT row_count FROM tax) = 0
              THEN 'PASS' ELSE 'FAIL' END,
         jsonb_build_object(
           'tax_rate_rows', (SELECT row_count FROM tax),
           'vat_decision', 'D-023 remains OPEN',
           'action', 'Zero-tax invoices post without tax_rates; any taxable invoice requires an approved effective-dated rate.'
         )

  UNION ALL
  SELECT 23,
         'NO_PREEXISTING_NUMBER_COUNTERS',
         CASE WHEN (SELECT match_count FROM target) = 1
                AND (SELECT row_count FROM counters) = 0
              THEN 'PASS' ELSE 'FAIL' END,
         jsonb_build_object(
           'counters', (SELECT rows FROM counters),
           'action', 'Review any existing counter manually; S3 numbering must start from the approved SI-YYYY/JE-YYYY baseline.'
         )

  UNION ALL
  SELECT 24,
         'S2_DRAFT_RPC_AVAILABLE',
         CASE WHEN (
                SELECT rpc_exists
                   AND actor_helper_exists
                   AND allowed_helper_exists
                   AND writer_role_exists
                   AND create_permission_exists
                   AND authenticated_execute
                FROM s2
              ) THEN 'PASS' ELSE 'FAIL' END,
         (SELECT to_jsonb(s) FROM s2 s) || jsonb_build_object(
           'action', 'The S2 draft RPC must remain available; S3 does not replace it.'
         )

  UNION ALL
  SELECT 25,
         'S3_INVENTORY_DEPENDENCIES',
         CASE WHEN (SELECT count(*) FROM missing_columns WHERE relation_name IN (
                     'sales_document_lines','products','warehouses','stock_levels',
                     'stock_movements','journal_lines','journal_entries'
                   )) = 0
                AND NOT EXISTS (
                  SELECT 1 FROM missing_tables
                  WHERE relation_name IN (
                    'sales_document_lines','products','warehouses','stock_levels',
                    'stock_movements','journal_lines','journal_entries'
                  )
                )
              THEN 'PASS' ELSE 'FAIL' END,
         jsonb_build_object(
           'post_stock_issue_present', (SELECT function_present FROM inventory_api),
           's3_invokes_post_stock_issue', false,
           'note', 'S3 re-implements the issue contract in its own transaction; the required dependency is the stock table/key schema, not the function.',
           'action', 'No S3 blocker when post_stock_issue is absent; verify stock tables/keys instead.'
         )

  UNION ALL
  SELECT 26,
         'POSTING_ACTOR_PRESENT',
         CASE WHEN (SELECT match_count FROM target) = 1
                AND (SELECT eligible_memberships FROM posting_actor) > 0
              THEN 'PASS' ELSE 'FAIL' END,
         jsonb_build_object(
           'eligible_active_memberships', (SELECT eligible_memberships FROM posting_actor),
           'action', 'At least one active Abo Amen member must be owner or hold sales.post; otherwise the DEV posting test cannot authenticate.'
         )

  UNION ALL
  SELECT 27,
         'EXISTING_POSTED_RECORDS_INTEGRITY',
         CASE WHEN (SELECT match_count FROM target) = 1
                AND (SELECT invalid_posted_invoices = 0 AND invalid_posted_entries = 0 FROM posted_integrity)
              THEN 'PASS' ELSE 'FAIL' END,
         (SELECT to_jsonb(p) FROM posted_integrity p) || jsonb_build_object(
           'action', 'Any posted invoice/journal without its official number/audit fields is an unexpected pre-existing conflict; review before deployment.'
         )
)
SELECT check_no,
       check_name,
       status,
       detail
FROM checks
UNION ALL
SELECT 999,
       'OVERALL',
       CASE WHEN bool_and(status = 'PASS') THEN 'PASS' ELSE 'FAIL' END,
       jsonb_build_object(
         'checks', count(*),
         'failed_checks', coalesce(
           jsonb_agg(check_name ORDER BY check_no) FILTER (WHERE status = 'FAIL'),
           '[]'::jsonb
         )
       )
FROM checks
ORDER BY check_no;
