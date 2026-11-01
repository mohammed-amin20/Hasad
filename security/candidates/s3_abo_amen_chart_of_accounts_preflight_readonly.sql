-- Hasad ERP V2 / Unit S3 — READ ONLY preflight for the approved chart candidate.
-- No DDL/DML. Execute on DEV only under separate read-only authorization.
WITH
executor AS (
  SELECT rolname, rolsuper, rolbypassrls
  FROM pg_catalog.pg_roles
  WHERE rolname = current_user
),
abo_matches AS (
  SELECT cs.company_id
  FROM hasad.company_settings cs
  JOIN hasad.companies c ON c.id = cs.company_id
  WHERE c.status = 'active'
    AND (
      lower(btrim(coalesce(cs.name_ar, ''))) IN (lower('أبو أمين'), lower('Abo Amen'))
      OR lower(btrim(coalesce(cs.name_en, ''))) IN (lower('أبو أمين'), lower('Abo Amen'))
      OR lower(btrim(coalesce(cs.display_name, ''))) IN (lower('أبو أمين'), lower('Abo Amen'))
    )
),
required_privileges(relation_name, privilege_type) AS (
  VALUES
    ('companies','SELECT'),('company_settings','SELECT'),
    ('accounts','SELECT'),('accounts','INSERT'),
    ('module_account_map','SELECT'),('module_account_map','INSERT'),
    ('fiscal_years','SELECT'),('fiscal_periods','SELECT'),
    ('document_types','SELECT'),('tax_rates','SELECT'),('doc_numbers','SELECT'),
    ('sales_documents','SELECT'),('stock_levels','SELECT'),('stock_movements','SELECT'),
    ('journal_entries','SELECT'),('journal_lines','SELECT')
),
table_report AS (
  SELECT
    rp.relation_name,
    rp.privilege_type,
    pg_catalog.has_table_privilege(current_user, 'hasad.' || rp.relation_name, rp.privilege_type) AS granted,
    pg_catalog.pg_get_userbyid(c.relowner) AS table_owner,
    c.relrowsecurity AS rls_enabled,
    c.relforcerowsecurity AS force_rls
  FROM required_privileges rp
  JOIN pg_catalog.pg_class c ON c.oid = pg_catalog.to_regclass('hasad.' || rp.relation_name)
),
approved_accounts(code, name_ar, account_type, account_role) AS (
  VALUES
    ('1100','الذمم المدينة التجارية','asset','AR_CONTROL'),
    ('1200','مخزون البضاعة','asset','INVENTORY_CONTROL'),
    ('2100','ضريبة القيمة المضافة – مخرجات','liability','VAT_OUTPUT'),
    ('4100','إيرادات المبيعات','revenue','SALES_REVENUE'),
    ('5100','تكلفة البضاعة المباعة','expense','COGS')
),
target AS (
  SELECT company_id FROM abo_matches
),
account_report AS (
  SELECT aa.code, aa.name_ar, aa.account_type, aa.account_role,
         a.id AS existing_account_id, a.name_ar AS existing_name_ar,
         a.account_type AS existing_type, a.parent_id, a.is_active,
         m.account_id AS mapped_account_id
  FROM approved_accounts aa
  LEFT JOIN target t ON true
  LEFT JOIN hasad.accounts a ON a.company_id = t.company_id AND a.code = aa.code
  LEFT JOIN hasad.module_account_map m
    ON m.company_id = t.company_id AND m.module = 'sales' AND m.account_role = aa.account_role
)
SELECT jsonb_build_object(
  'executor', jsonb_build_object(
    'current_user', current_user,
    'rolsuper', (SELECT rolsuper FROM executor),
    'rolbypassrls', (SELECT rolbypassrls FROM executor),
    'hasad_usage', pg_catalog.has_schema_privilege(current_user, 'hasad', 'USAGE'),
    'uuid_execute', pg_catalog.has_function_privilege(current_user, 'pg_catalog.gen_random_uuid()', 'EXECUTE')
  ),
  'abo_amen_active_match_count', (SELECT count(*) FROM abo_matches),
  'table_privileges_and_rls', (
    SELECT jsonb_agg(jsonb_build_object(
      'table', relation_name, 'privilege', privilege_type, 'granted', granted,
      'owner', table_owner, 'rls_enabled', rls_enabled, 'force_rls', force_rls
    ) ORDER BY relation_name, privilege_type)
    FROM table_report
  ),
  'approved_account_conflict_review', (
    SELECT jsonb_agg(jsonb_build_object(
      'code', code, 'approved_name_ar', name_ar, 'approved_type', account_type,
      'role', account_role, 'existing_account_id', existing_account_id,
      'existing_name_ar', existing_name_ar, 'existing_type', existing_type,
      'existing_parent_id', parent_id, 'existing_is_active', is_active,
      'existing_mapped_account_id', mapped_account_id
    ) ORDER BY code)
    FROM account_report
  )
) AS s3_abo_amen_chart_preflight;
