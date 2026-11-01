-- Hasad ERP V2 / Unit S3 — REVIEW ONLY, NOT DEPLOYED.
--
-- Owner/accountant-approved Abo Amen starter accounts and sales mappings only.
-- It creates no journal entry, fiscal period, tax rate, document type, number,
-- invoice, stock row, accounting balance or other financial transaction.
--
-- Approved account contract (all parent_id NULL; name_en remains NULL/default):
--   1100 | الذمم المدينة التجارية             | asset     | AR_CONTROL
--   1200 | مخزون البضاعة                      | asset     | INVENTORY_CONTROL
--   2100 | ضريبة القيمة المضافة – مخرجات      | liability | VAT_OUTPUT
--   4100 | إيرادات المبيعات                   | revenue   | SALES_REVENUE
--   5100 | تكلفة البضاعة المباعة              | expense   | COGS
--
-- VAT_OUTPUT is an approved accounting mapping only. This candidate never
-- changes company_settings.vat_enabled and never inserts a tax_rates row.

BEGIN;
SET LOCAL search_path = pg_catalog, pg_temp;

DO $preflight$
DECLARE v_missing text; v_bad text; v_privileges text; v_can_bypass_rls boolean;
BEGIN
  SELECT string_agg(name, ', ' ORDER BY name) INTO v_missing
  FROM (VALUES
    ('companies'),('company_settings'),('accounts'),('module_account_map'),
    ('fiscal_years'),('fiscal_periods'),('document_types'),('tax_rates'),
    ('doc_numbers'),('sales_documents'),('stock_levels'),('stock_movements'),
    ('journal_entries'),('journal_lines')
  ) required(name)
  WHERE pg_catalog.to_regclass('hasad.' || name) IS NULL;
  IF v_missing IS NOT NULL THEN
    RAISE EXCEPTION 'PREFLIGHT_MISSING_TABLES: %', v_missing;
  END IF;
  SELECT rolsuper OR rolbypassrls INTO v_can_bypass_rls
  FROM pg_catalog.pg_roles
  WHERE rolname = current_user;
  IF coalesce(v_can_bypass_rls, false) IS NOT TRUE THEN
    RAISE EXCEPTION 'PREFLIGHT_RLS_BYPASS_REQUIRED';
  END IF;
  IF NOT pg_catalog.has_schema_privilege(current_user, 'hasad', 'USAGE') THEN
    RAISE EXCEPTION 'PREFLIGHT_HASAD_SCHEMA_USAGE_REQUIRED';
  END IF;
  SELECT string_agg(relation_name || ':' || privilege_type, ', ' ORDER BY relation_name, privilege_type)
  INTO v_privileges
  FROM (VALUES
    ('companies','SELECT'),('company_settings','SELECT'),
    ('accounts','SELECT'),('accounts','INSERT'),
    ('module_account_map','SELECT'),('module_account_map','INSERT'),
    ('fiscal_years','SELECT'),('fiscal_periods','SELECT'),
    ('document_types','SELECT'),('tax_rates','SELECT'),('doc_numbers','SELECT'),
    ('sales_documents','SELECT'),('stock_levels','SELECT'),('stock_movements','SELECT'),
    ('journal_entries','SELECT'),('journal_lines','SELECT')
  ) required_privilege(relation_name, privilege_type)
  WHERE NOT pg_catalog.has_table_privilege(
    current_user, 'hasad.' || relation_name, privilege_type
  );
  IF v_privileges IS NOT NULL THEN
    RAISE EXCEPTION 'PREFLIGHT_TABLE_PRIVILEGES_MISSING: %', v_privileges;
  END IF;
  IF NOT pg_catalog.has_function_privilege(
    current_user, 'pg_catalog.gen_random_uuid()', 'EXECUTE'
  ) THEN
    RAISE EXCEPTION 'PREFLIGHT_UUID_GENERATOR_EXECUTE_REQUIRED';
  END IF;
  SELECT string_agg(c.relname, ', ' ORDER BY c.relname) INTO v_bad
  FROM pg_catalog.pg_class c
  JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'hasad'
    AND c.relname IN ('accounts','module_account_map')
    AND (NOT c.relrowsecurity OR NOT c.relforcerowsecurity);
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'PREFLIGHT_FORCE_RLS_MISSING: %', v_bad;
  END IF;
END
$preflight$;

DO $configure$
DECLARE
  v_company_ids uuid[];
  v_company_count integer;
  v_company_id uuid;
  v_item record;
  v_account_id uuid;
  v_existing_name text;
  v_existing_type text;
  v_existing_parent uuid;
  v_existing_active boolean;
  v_existing_mapping uuid;
  v_sales_docs_before bigint;
  v_stock_levels_before bigint;
  v_stock_movements_before bigint;
  v_journal_entries_before bigint;
  v_journal_lines_before bigint;
  v_tax_rates_before bigint;
  v_periods_before bigint;
  v_doc_numbers_before bigint;
BEGIN
  SELECT array_agg(DISTINCT cs.company_id ORDER BY cs.company_id),
         count(DISTINCT cs.company_id)
  INTO v_company_ids, v_company_count
  FROM hasad.company_settings cs
  JOIN hasad.companies c ON c.id = cs.company_id AND c.status = 'active'
  WHERE lower(btrim(coalesce(cs.name_ar, ''))) IN (lower('أبو أمين'), lower('Abo Amen'))
     OR lower(btrim(coalesce(cs.name_en, ''))) IN (lower('أبو أمين'), lower('Abo Amen'))
     OR lower(btrim(coalesce(cs.display_name, ''))) IN (lower('أبو أمين'), lower('Abo Amen'));
  IF v_company_count IS DISTINCT FROM 1 THEN
    RAISE EXCEPTION 'ABO_AMEN_COMPANY_SELECTOR_NOT_UNIQUE: matched % active companies',
      coalesce(v_company_count, 0);
  END IF;
  v_company_id := v_company_ids[1];

  SELECT count(*) INTO v_sales_docs_before FROM hasad.sales_documents WHERE company_id = v_company_id;
  SELECT count(*) INTO v_stock_levels_before FROM hasad.stock_levels WHERE company_id = v_company_id;
  SELECT count(*) INTO v_stock_movements_before FROM hasad.stock_movements WHERE company_id = v_company_id;
  SELECT count(*) INTO v_journal_entries_before FROM hasad.journal_entries WHERE company_id = v_company_id;
  SELECT count(*) INTO v_journal_lines_before FROM hasad.journal_lines WHERE company_id = v_company_id;
  SELECT count(*) INTO v_tax_rates_before FROM hasad.tax_rates WHERE company_id = v_company_id;
  SELECT count(*) INTO v_periods_before FROM hasad.fiscal_periods WHERE company_id = v_company_id;
  SELECT count(*) INTO v_doc_numbers_before FROM hasad.doc_numbers WHERE company_id = v_company_id;

  FOR v_item IN
    SELECT * FROM (VALUES
      ('1100'::text, 'الذمم المدينة التجارية'::text, 'asset'::text, 'AR_CONTROL'::text),
      ('1200'::text, 'مخزون البضاعة'::text, 'asset'::text, 'INVENTORY_CONTROL'::text),
      ('2100'::text, 'ضريبة القيمة المضافة – مخرجات'::text, 'liability'::text, 'VAT_OUTPUT'::text),
      ('4100'::text, 'إيرادات المبيعات'::text, 'revenue'::text, 'SALES_REVENUE'::text),
      ('5100'::text, 'تكلفة البضاعة المباعة'::text, 'expense'::text, 'COGS'::text)
    ) approved(code, name_ar, account_type, account_role)
    ORDER BY code
  LOOP
    v_account_id := NULL;
    SELECT id, name_ar, account_type, parent_id, is_active
    INTO v_account_id, v_existing_name, v_existing_type, v_existing_parent, v_existing_active
    FROM hasad.accounts
    WHERE company_id = v_company_id AND code = v_item.code;
    IF v_account_id IS NULL THEN
      INSERT INTO hasad.accounts
        (id, company_id, code, name_ar, account_type, parent_id, is_active)
      VALUES
        (pg_catalog.gen_random_uuid(), v_company_id, v_item.code, v_item.name_ar,
         v_item.account_type, NULL, true)
      RETURNING id INTO v_account_id;
    ELSIF v_existing_name <> v_item.name_ar
       OR v_existing_type <> v_item.account_type
       OR v_existing_parent IS NOT NULL
       OR v_existing_active IS NOT TRUE THEN
      RAISE EXCEPTION 'ACCOUNT_CONFLICT: code %', v_item.code;
    END IF;

    v_existing_mapping := NULL;
    SELECT account_id INTO v_existing_mapping
    FROM hasad.module_account_map
    WHERE company_id = v_company_id
      AND module = 'sales'
      AND account_role = v_item.account_role;
    IF v_existing_mapping IS NULL THEN
      INSERT INTO hasad.module_account_map
        (id, company_id, module, account_role, account_id)
      VALUES
        (pg_catalog.gen_random_uuid(), v_company_id, 'sales',
         v_item.account_role, v_account_id);
    ELSIF v_existing_mapping <> v_account_id THEN
      RAISE EXCEPTION 'ACCOUNT_MAPPING_CONFLICT: role %', v_item.account_role;
    END IF;
  END LOOP;

  IF (SELECT count(*) FROM hasad.accounts
      WHERE company_id = v_company_id
        AND code IN ('1100','1200','2100','4100','5100')) <> 5
     OR (SELECT count(*) FROM hasad.module_account_map
         WHERE company_id = v_company_id AND module = 'sales'
           AND account_role IN ('AR_CONTROL','INVENTORY_CONTROL','VAT_OUTPUT','SALES_REVENUE','COGS')) <> 5 THEN
    RAISE EXCEPTION 'POSTFLIGHT_APPROVED_CHART_INCOMPLETE';
  END IF;

  IF (SELECT count(*) FROM hasad.sales_documents WHERE company_id = v_company_id) <> v_sales_docs_before
     OR (SELECT count(*) FROM hasad.stock_levels WHERE company_id = v_company_id) <> v_stock_levels_before
     OR (SELECT count(*) FROM hasad.stock_movements WHERE company_id = v_company_id) <> v_stock_movements_before
     OR (SELECT count(*) FROM hasad.journal_entries WHERE company_id = v_company_id) <> v_journal_entries_before
     OR (SELECT count(*) FROM hasad.journal_lines WHERE company_id = v_company_id) <> v_journal_lines_before
     OR (SELECT count(*) FROM hasad.tax_rates WHERE company_id = v_company_id) <> v_tax_rates_before
     OR (SELECT count(*) FROM hasad.fiscal_periods WHERE company_id = v_company_id) <> v_periods_before
     OR (SELECT count(*) FROM hasad.doc_numbers WHERE company_id = v_company_id) <> v_doc_numbers_before THEN
    RAISE EXCEPTION 'POSTFLIGHT_FORBIDDEN_NON_CHART_WRITE';
  END IF;
END
$configure$;

COMMIT;
