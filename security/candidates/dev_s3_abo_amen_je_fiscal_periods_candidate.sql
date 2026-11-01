-- Hasad ERP V2 / Unit S3 — REVIEW ONLY, NOT DEPLOYED.
--
-- Creates/verifies only the Abo Amen FY-2026 calendar-month periods and the JE
-- document type. It never creates accounts/mappings, tax rates, counters,
-- invoices, stock movements, journal entries, or accounting balances.
--
-- Required runtime setting: hasad_s3_config.open_period_nos (JSON array).
-- Proposed first posting-test selection only: '[10]' (October 2026 open,
-- January–September and November–December closed). This is NOT an approved
-- business setting until the owner separately authorizes a DEV execution.

BEGIN;
SET LOCAL search_path = pg_catalog, pg_temp;

DO $preflight$
DECLARE v_missing text; v_bad text; v_privileges text; v_can_bypass_rls boolean;
BEGIN
  SELECT string_agg(name, ', ' ORDER BY name) INTO v_missing
  FROM (VALUES
    ('companies'),('company_settings'),('fiscal_years'),('fiscal_periods'),
    ('document_types'),('tax_rates'),('doc_numbers'),('sales_documents'),
    ('stock_levels'),('stock_movements'),('journal_entries'),('journal_lines')
  ) required(name)
  WHERE pg_catalog.to_regclass('hasad.' || name) IS NULL;
  IF v_missing IS NOT NULL THEN
    RAISE EXCEPTION 'PREFLIGHT_MISSING_TABLES: %', v_missing;
  END IF;

  SELECT rolsuper OR rolbypassrls INTO v_can_bypass_rls
  FROM pg_catalog.pg_roles WHERE rolname = current_user;
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
    ('fiscal_years','SELECT'),('fiscal_periods','SELECT'),('fiscal_periods','INSERT'),
    ('document_types','SELECT'),('document_types','INSERT'),
    ('tax_rates','SELECT'),('doc_numbers','SELECT'),('sales_documents','SELECT'),
    ('stock_levels','SELECT'),('stock_movements','SELECT'),
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
    AND c.relname IN ('fiscal_years','fiscal_periods','document_types')
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
  v_vat_enabled_before boolean;
  v_fiscal_year hasad.fiscal_years%ROWTYPE;
  v_je hasad.document_types%ROWTYPE;
  v_open_periods smallint[];
  v_period_no smallint;
  v_period_start date;
  v_period_end date;
  v_expected_status text;
  v_existing_period hasad.fiscal_periods%ROWTYPE;
  v_doc_numbers_before bigint;
  v_tax_rates_before bigint;
  v_sales_docs_before bigint;
  v_stock_levels_before bigint;
  v_stock_movements_before bigint;
  v_journal_entries_before bigint;
  v_journal_lines_before bigint;
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

  SELECT vat_enabled INTO v_vat_enabled_before
  FROM hasad.company_settings WHERE company_id = v_company_id;
  SELECT * INTO v_fiscal_year
  FROM hasad.fiscal_years
  WHERE company_id = v_company_id
    AND start_date = DATE '2026-01-01'
    AND end_date = DATE '2026-12-31'
    AND status = 'open';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'PREFLIGHT_OPEN_FY_2026_MISSING';
  END IF;

  IF current_setting('hasad_s3_config.open_period_nos', true) IS NULL THEN
    RAISE EXCEPTION 'OWNER_OPEN_PERIOD_SELECTION_REQUIRED';
  END IF;
  BEGIN
    SELECT array_agg(value::smallint ORDER BY value::smallint)
    INTO v_open_periods
    FROM jsonb_array_elements_text(
      current_setting('hasad_s3_config.open_period_nos', true)::jsonb
    ) periods(value);
  EXCEPTION WHEN others THEN
    RAISE EXCEPTION 'OWNER_OPEN_PERIOD_SELECTION_INVALID';
  END;
  IF coalesce(array_length(v_open_periods, 1), 0) = 0
     OR EXISTS (SELECT 1 FROM unnest(v_open_periods) period_no WHERE period_no NOT BETWEEN 1 AND 12)
     OR (SELECT count(*) <> count(DISTINCT period_no) FROM unnest(v_open_periods) period_no) THEN
    RAISE EXCEPTION 'OWNER_OPEN_PERIOD_SELECTION_INVALID';
  END IF;

  SELECT count(*) INTO v_doc_numbers_before FROM hasad.doc_numbers WHERE company_id = v_company_id;
  SELECT count(*) INTO v_tax_rates_before FROM hasad.tax_rates WHERE company_id = v_company_id;
  SELECT count(*) INTO v_sales_docs_before FROM hasad.sales_documents WHERE company_id = v_company_id;
  SELECT count(*) INTO v_stock_levels_before FROM hasad.stock_levels WHERE company_id = v_company_id;
  SELECT count(*) INTO v_stock_movements_before FROM hasad.stock_movements WHERE company_id = v_company_id;
  SELECT count(*) INTO v_journal_entries_before FROM hasad.journal_entries WHERE company_id = v_company_id;
  SELECT count(*) INTO v_journal_lines_before FROM hasad.journal_lines WHERE company_id = v_company_id;

  FOR v_period_no IN 1..12 LOOP
    v_period_start := make_date(extract(year FROM v_fiscal_year.start_date)::integer, v_period_no, 1);
    v_period_end := (v_period_start + interval '1 month - 1 day')::date;
    v_expected_status := CASE WHEN v_period_no = ANY (v_open_periods) THEN 'open' ELSE 'closed' END;
    SELECT * INTO v_existing_period
    FROM hasad.fiscal_periods
    WHERE company_id = v_company_id
      AND fiscal_year_id = v_fiscal_year.id
      AND period_no = v_period_no;
    IF FOUND THEN
      IF v_existing_period.start_date <> v_period_start
         OR v_existing_period.end_date <> v_period_end
         OR v_existing_period.status <> v_expected_status THEN
        RAISE EXCEPTION 'FISCAL_PERIOD_CONFLICT: period %', v_period_no;
      END IF;
    ELSE
      INSERT INTO hasad.fiscal_periods
        (id, company_id, fiscal_year_id, period_no, start_date, end_date, status)
      VALUES
        (pg_catalog.gen_random_uuid(), v_company_id, v_fiscal_year.id,
         v_period_no, v_period_start, v_period_end, v_expected_status);
    END IF;
  END LOOP;

  SELECT * INTO v_je
  FROM hasad.document_types
  WHERE company_id = v_company_id AND code = 'JE';
  IF FOUND THEN
    IF v_je.name_ar <> 'قيد يومية'
       OR v_je.issuance <> 'posting'
       OR v_je.format_prefix <> 'JE'
       OR v_je.pad_length <> 4
       OR NOT v_je.is_active THEN
      RAISE EXCEPTION 'JE_DOCUMENT_TYPE_CONFLICT';
    END IF;
  ELSE
    INSERT INTO hasad.document_types
      (id, company_id, code, name_ar, issuance, format_prefix, pad_length, is_active)
    VALUES
      (pg_catalog.gen_random_uuid(), v_company_id, 'JE', 'قيد يومية',
       'posting', 'JE', 4, true);
  END IF;

  IF (SELECT vat_enabled FROM hasad.company_settings WHERE company_id = v_company_id)
       IS DISTINCT FROM v_vat_enabled_before
     OR (SELECT count(*) FROM hasad.doc_numbers WHERE company_id = v_company_id) <> v_doc_numbers_before
     OR (SELECT count(*) FROM hasad.tax_rates WHERE company_id = v_company_id) <> v_tax_rates_before
     OR (SELECT count(*) FROM hasad.sales_documents WHERE company_id = v_company_id) <> v_sales_docs_before
     OR (SELECT count(*) FROM hasad.stock_levels WHERE company_id = v_company_id) <> v_stock_levels_before
     OR (SELECT count(*) FROM hasad.stock_movements WHERE company_id = v_company_id) <> v_stock_movements_before
     OR (SELECT count(*) FROM hasad.journal_entries WHERE company_id = v_company_id) <> v_journal_entries_before
     OR (SELECT count(*) FROM hasad.journal_lines WHERE company_id = v_company_id) <> v_journal_lines_before THEN
    RAISE EXCEPTION 'POSTFLIGHT_FORBIDDEN_SIDE_EFFECT';
  END IF;
END
$configure$;

COMMIT;
NOTIFY pgrst, 'reload schema';
