-- Hasad ERP V2 / Unit S3 — REVIEW ONLY, LOCAL VALIDATION ONLY, NOT DEPLOYED.
--
-- Configures no account balances, no VAT rate, no invoice, no stock row and no
-- document counter. It may only, after separate owner/accountant selection:
--   * map already-existing active accounts identified by code;
--   * create the twelve calendar-month periods for the existing FY 2026, with
--     the explicitly selected period number(s) open and all others closed;
--   * set an existing NULL SI prefix to SI; and
--   * create an exactly configured JE document type when absent.
--
-- Required session settings (the candidate fails before any write if absent):
--   hasad_s3_config.open_period_nos  JSON array, e.g. '[10]'
--   hasad_s3_config.ar_control_code
--   hasad_s3_config.sales_revenue_code
--   hasad_s3_config.cogs_code
--   hasad_s3_config.inventory_control_code
-- Optional only when VAT is owner-approved/configured:
--   hasad_s3_config.vat_output_code
--
-- Account codes are deliberately NOT embedded here. Selection is an owner and
-- accountant decision; this file never creates an account or invents an ID.
-- `vat_enabled = false` is not treated as a legal exemption and is not changed.

BEGIN;
SET LOCAL search_path = pg_catalog, pg_temp;

DO $preflight$
DECLARE
  v_missing text;
  v_bad text;
BEGIN
  SELECT string_agg(name, ', ' ORDER BY name) INTO v_missing
  FROM (VALUES
    ('companies'),('company_settings'),('accounts'),('module_account_map'),
    ('fiscal_years'),('fiscal_periods'),('document_types'),('doc_numbers'),
    ('tax_rates')
  ) required(name)
  WHERE pg_catalog.to_regclass('hasad.' || name) IS NULL;
  IF v_missing IS NOT NULL THEN
    RAISE EXCEPTION 'PREFLIGHT_MISSING_TABLES: %', v_missing;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_roles WHERE rolname = current_user AND rolsuper
  ) THEN
    RAISE EXCEPTION 'PREFLIGHT_SUPERUSER_REQUIRED';
  END IF;

  SELECT string_agg(c.relname, ', ' ORDER BY c.relname) INTO v_bad
  FROM pg_catalog.pg_class c
  JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'hasad'
    AND c.relname IN (
      'companies','company_settings','accounts','module_account_map',
      'fiscal_years','fiscal_periods','document_types','doc_numbers','tax_rates'
    )
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
  v_vat_enabled boolean;
  v_fiscal_year hasad.fiscal_years%ROWTYPE;
  v_si hasad.document_types%ROWTYPE;
  v_je hasad.document_types%ROWTYPE;
  v_open_periods smallint[];
  v_period_no smallint;
  v_period_start date;
  v_period_end date;
  v_expected_status text;
  v_existing_period hasad.fiscal_periods%ROWTYPE;
  v_ar_code text;
  v_revenue_code text;
  v_cogs_code text;
  v_inventory_code text;
  v_vat_code text;
  v_role text;
  v_account_code text;
  v_expected_type text;
  v_account_id uuid;
  v_existing_mapping uuid;
  v_doc_numbers_before bigint;
  v_tax_rates_before bigint;
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

  SELECT vat_enabled INTO v_vat_enabled
  FROM hasad.company_settings
  WHERE company_id = v_company_id;

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
     OR EXISTS (
       SELECT 1 FROM unnest(v_open_periods) period_no
       WHERE period_no NOT BETWEEN 1 AND 12
     )
     OR (SELECT count(*) <> count(DISTINCT period_no)
         FROM unnest(v_open_periods) period_no) THEN
    RAISE EXCEPTION 'OWNER_OPEN_PERIOD_SELECTION_INVALID';
  END IF;

  v_ar_code := nullif(btrim(current_setting('hasad_s3_config.ar_control_code', true)), '');
  v_revenue_code := nullif(btrim(current_setting('hasad_s3_config.sales_revenue_code', true)), '');
  v_cogs_code := nullif(btrim(current_setting('hasad_s3_config.cogs_code', true)), '');
  v_inventory_code := nullif(btrim(current_setting('hasad_s3_config.inventory_control_code', true)), '');
  v_vat_code := nullif(btrim(current_setting('hasad_s3_config.vat_output_code', true)), '');
  IF v_ar_code IS NULL OR v_revenue_code IS NULL
     OR v_cogs_code IS NULL OR v_inventory_code IS NULL THEN
    RAISE EXCEPTION 'OWNER_ACCOUNT_SELECTION_REQUIRED';
  END IF;
  IF v_vat_enabled AND v_vat_code IS NULL THEN
    RAISE EXCEPTION 'OWNER_VAT_OUTPUT_ACCOUNT_SELECTION_REQUIRED';
  END IF;

  SELECT count(*) INTO v_doc_numbers_before
  FROM hasad.doc_numbers WHERE company_id = v_company_id;
  SELECT count(*) INTO v_tax_rates_before
  FROM hasad.tax_rates WHERE company_id = v_company_id;

  -- Calendar-month structure follows the approved Jan–Dec / monthly design.
  -- Opening any period is still an explicit runtime owner decision above.
  FOR v_period_no IN 1..12 LOOP
    v_period_start := make_date(extract(year FROM v_fiscal_year.start_date)::integer, v_period_no, 1);
    v_period_end := (v_period_start + interval '1 month - 1 day')::date;
    v_expected_status := CASE
      WHEN v_period_no = ANY (v_open_periods) THEN 'open' ELSE 'closed'
    END;

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

  -- No account is created. Each selected code must identify one active account
  -- of the expected proposed classification before its role can be mapped.
  FOR v_role, v_account_code, v_expected_type IN
    SELECT role_name, account_code, account_type
    FROM (VALUES
      ('AR_CONTROL'::text, v_ar_code, 'asset'::text),
      ('SALES_REVENUE'::text, v_revenue_code, 'revenue'::text),
      ('COGS'::text, v_cogs_code, 'expense'::text),
      ('INVENTORY_CONTROL'::text, v_inventory_code, 'asset'::text),
      ('VAT_OUTPUT'::text, v_vat_code, 'liability'::text)
    ) selected(role_name, account_code, account_type)
    WHERE account_code IS NOT NULL
  LOOP
    v_account_id := NULL;
    SELECT id INTO v_account_id
    FROM hasad.accounts
    WHERE company_id = v_company_id
      AND code = v_account_code
      AND account_type = v_expected_type
      AND is_active;
    IF v_account_id IS NULL THEN
      RAISE EXCEPTION 'PREFLIGHT_REQUIRED_ACTIVE_ACCOUNT_NOT_FOUND: role %, code %, expected type %',
        v_role, v_account_code, v_expected_type;
    END IF;

    v_existing_mapping := NULL;
    SELECT account_id INTO v_existing_mapping
    FROM hasad.module_account_map
    WHERE company_id = v_company_id AND module = 'sales' AND account_role = v_role;
    IF v_existing_mapping IS NULL THEN
      INSERT INTO hasad.module_account_map
        (id, company_id, module, account_role, account_id)
      VALUES
        (pg_catalog.gen_random_uuid(), v_company_id, 'sales', v_role, v_account_id);
    ELSIF v_existing_mapping <> v_account_id THEN
      RAISE EXCEPTION 'ACCOUNT_MAPPING_CONFLICT: role %', v_role;
    END IF;
  END LOOP;

  SELECT * INTO v_si
  FROM hasad.document_types
  WHERE company_id = v_company_id AND code = 'SI';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'PREFLIGHT_SI_DOCUMENT_TYPE_MISSING';
  END IF;
  IF v_si.name_ar <> 'فاتورة مبيعات'
     OR v_si.issuance <> 'posting'
     OR NOT v_si.is_active
     OR v_si.pad_length <> 4
     OR (v_si.format_prefix IS NOT NULL AND v_si.format_prefix <> 'SI') THEN
    RAISE EXCEPTION 'SI_DOCUMENT_TYPE_CONFLICT';
  END IF;
  IF v_si.format_prefix IS NULL THEN
    UPDATE hasad.document_types
    SET format_prefix = 'SI'
    WHERE id = v_si.id AND company_id = v_company_id AND format_prefix IS NULL;
  END IF;

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

  IF (SELECT count(*) FROM hasad.doc_numbers WHERE company_id = v_company_id) <> v_doc_numbers_before
     OR (SELECT count(*) FROM hasad.tax_rates WHERE company_id = v_company_id) <> v_tax_rates_before THEN
    RAISE EXCEPTION 'POSTFLIGHT_FORBIDDEN_NUMBER_OR_TAX_WRITE';
  END IF;
END
$configure$;

COMMIT;
NOTIFY pgrst, 'reload schema';
