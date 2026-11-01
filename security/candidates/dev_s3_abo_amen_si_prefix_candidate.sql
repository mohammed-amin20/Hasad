-- Hasad ERP V2 / Unit S3 — REVIEW ONLY, NOT DEPLOYED.
-- Updates only the existing Abo Amen SI document type's format_prefix to SI.
-- It creates no document type, fiscal period, counter, tax row, invoice, stock
-- movement, journal entry, account, mapping, or financial balance.

BEGIN;
SET LOCAL search_path = pg_catalog, pg_temp;

DO $preflight$
DECLARE v_missing text; v_bad text; v_privileges text; v_can_bypass_rls boolean;
BEGIN
  SELECT string_agg(name, ', ' ORDER BY name) INTO v_missing
  FROM (VALUES
    ('companies'),('company_settings'),('document_types'),('fiscal_periods'),
    ('doc_numbers'),('tax_rates'),('sales_documents'),('stock_levels'),
    ('stock_movements'),('journal_entries'),('journal_lines')
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
    ('document_types','SELECT'),('document_types','UPDATE'),
    ('fiscal_periods','SELECT'),('doc_numbers','SELECT'),('tax_rates','SELECT'),
    ('sales_documents','SELECT'),('stock_levels','SELECT'),('stock_movements','SELECT'),
    ('journal_entries','SELECT'),('journal_lines','SELECT')
  ) required_privilege(relation_name, privilege_type)
  WHERE NOT pg_catalog.has_table_privilege(current_user, 'hasad.' || relation_name, privilege_type);
  IF v_privileges IS NOT NULL THEN
    RAISE EXCEPTION 'PREFLIGHT_TABLE_PRIVILEGES_MISSING: %', v_privileges;
  END IF;
  SELECT string_agg(c.relname, ', ' ORDER BY c.relname) INTO v_bad
  FROM pg_catalog.pg_class c
  JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname='hasad' AND c.relname='document_types'
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
  v_si_count integer;
  v_si hasad.document_types%ROWTYPE;
  v_vat_enabled_before boolean;
  v_periods_before bigint;
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
  JOIN hasad.companies c ON c.id=cs.company_id AND c.status='active'
  WHERE lower(btrim(coalesce(cs.name_ar,''))) IN (lower('أبو أمين'),lower('Abo Amen'))
     OR lower(btrim(coalesce(cs.name_en,''))) IN (lower('أبو أمين'),lower('Abo Amen'))
     OR lower(btrim(coalesce(cs.display_name,''))) IN (lower('أبو أمين'),lower('Abo Amen'));
  IF v_company_count IS DISTINCT FROM 1 THEN
    RAISE EXCEPTION 'ABO_AMEN_COMPANY_SELECTOR_NOT_UNIQUE: matched % active companies',
      coalesce(v_company_count,0);
  END IF;
  v_company_id := v_company_ids[1];

  SELECT count(*) INTO v_si_count
  FROM hasad.document_types WHERE company_id=v_company_id AND code='SI';
  IF v_si_count <> 1 THEN
    RAISE EXCEPTION 'PREFLIGHT_SI_DOCUMENT_TYPE_NOT_EXACTLY_ONE: found %', v_si_count;
  END IF;
  SELECT * INTO v_si
  FROM hasad.document_types WHERE company_id=v_company_id AND code='SI';
  IF v_si.name_ar <> 'فاتورة مبيعات'
     OR v_si.issuance <> 'posting'
     OR v_si.is_active IS NOT TRUE
     OR v_si.pad_length <> 4 THEN
    RAISE EXCEPTION 'SI_DOCUMENT_TYPE_CONTRACT_CONFLICT';
  END IF;
  IF v_si.format_prefix IS NOT NULL
     AND btrim(v_si.format_prefix) <> ''
     AND v_si.format_prefix <> 'SI' THEN
    RAISE EXCEPTION 'SI_PREFIX_CONFLICT: %', v_si.format_prefix;
  END IF;

  SELECT vat_enabled INTO v_vat_enabled_before FROM hasad.company_settings WHERE company_id=v_company_id;
  SELECT count(*) INTO v_periods_before FROM hasad.fiscal_periods WHERE company_id=v_company_id;
  SELECT count(*) INTO v_doc_numbers_before FROM hasad.doc_numbers WHERE company_id=v_company_id;
  SELECT count(*) INTO v_tax_rates_before FROM hasad.tax_rates WHERE company_id=v_company_id;
  SELECT count(*) INTO v_sales_docs_before FROM hasad.sales_documents WHERE company_id=v_company_id;
  SELECT count(*) INTO v_stock_levels_before FROM hasad.stock_levels WHERE company_id=v_company_id;
  SELECT count(*) INTO v_stock_movements_before FROM hasad.stock_movements WHERE company_id=v_company_id;
  SELECT count(*) INTO v_journal_entries_before FROM hasad.journal_entries WHERE company_id=v_company_id;
  SELECT count(*) INTO v_journal_lines_before FROM hasad.journal_lines WHERE company_id=v_company_id;

  IF v_si.format_prefix IS NULL OR btrim(v_si.format_prefix) = '' THEN
    UPDATE hasad.document_types
    SET format_prefix='SI'
    WHERE id=v_si.id AND company_id=v_company_id
      AND (format_prefix IS NULL OR btrim(format_prefix) = '');
  END IF;

  IF (SELECT vat_enabled FROM hasad.company_settings WHERE company_id=v_company_id)
       IS DISTINCT FROM v_vat_enabled_before
     OR (SELECT count(*) FROM hasad.fiscal_periods WHERE company_id=v_company_id) <> v_periods_before
     OR (SELECT count(*) FROM hasad.doc_numbers WHERE company_id=v_company_id) <> v_doc_numbers_before
     OR (SELECT count(*) FROM hasad.tax_rates WHERE company_id=v_company_id) <> v_tax_rates_before
     OR (SELECT count(*) FROM hasad.sales_documents WHERE company_id=v_company_id) <> v_sales_docs_before
     OR (SELECT count(*) FROM hasad.stock_levels WHERE company_id=v_company_id) <> v_stock_levels_before
     OR (SELECT count(*) FROM hasad.stock_movements WHERE company_id=v_company_id) <> v_stock_movements_before
     OR (SELECT count(*) FROM hasad.journal_entries WHERE company_id=v_company_id) <> v_journal_entries_before
     OR (SELECT count(*) FROM hasad.journal_lines WHERE company_id=v_company_id) <> v_journal_lines_before THEN
    RAISE EXCEPTION 'POSTFLIGHT_FORBIDDEN_SIDE_EFFECT';
  END IF;
END
$configure$;

COMMIT;
NOTIFY pgrst, 'reload schema';
