-- Hasad ERP V2 / S2 — DEV REVIEW-ONLY configuration candidate, NOT DEPLOYED
-- Scope: one existing active Abo Amen company; one FY and one sales-invoice
-- document type. No company/auth/member/customer/product/warehouse change, no
-- fiscal periods, doc_numbers, invoice, stock, policy, privilege, or role write.
BEGIN;

DO $preflight$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM (VALUES ('company_settings'),('companies'),('fiscal_years'),
                 ('document_types'),('doc_numbers'),('fiscal_periods')) q(name)
    WHERE pg_catalog.to_regclass('hasad.' || q.name) IS NULL
  ) THEN
    RAISE EXCEPTION 'PREFLIGHT_MISSING_REFERENCE_TABLE';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_roles
    WHERE rolname=current_user AND (rolsuper OR rolbypassrls)
  ) THEN
    RAISE EXCEPTION 'PREFLIGHT_EXECUTOR_CANNOT_SAFELY_WRITE_FORCE_RLS_TABLES';
  END IF;
  IF EXISTS (
    SELECT 1
    FROM pg_catalog.pg_class c JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace
    WHERE n.nspname='hasad'
      AND c.relname IN ('company_settings','fiscal_years','document_types','doc_numbers','fiscal_periods')
      AND (NOT c.relrowsecurity OR NOT c.relforcerowsecurity)
  ) THEN
    RAISE EXCEPTION 'PREFLIGHT_FORCE_RLS';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_proc p
    JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname IN ('pg_catalog','public','extensions')
      AND p.proname='gen_random_uuid' AND p.pronargs=0
  ) THEN
    RAISE EXCEPTION 'PREFLIGHT_UUID_GENERATOR_MISSING';
  END IF;
END
$preflight$;

DO $configure$
DECLARE
  v_company_ids uuid[];
  v_company_count integer;
  v_company_id uuid;
  v_year hasad.fiscal_years%ROWTYPE;
  v_type hasad.document_types%ROWTYPE;
  v_doc_numbers_before integer;
  v_periods_before integer;
BEGIN
  SELECT array_agg(DISTINCT cs.company_id), count(DISTINCT cs.company_id)
  INTO v_company_ids, v_company_count
  FROM hasad.company_settings cs
  JOIN hasad.companies c ON c.id=cs.company_id AND c.status='active'
  WHERE lower(btrim(coalesce(cs.name_ar,''))) IN (lower('أبو أمين'),lower('Abo Amen'))
     OR lower(btrim(coalesce(cs.name_en,''))) IN (lower('أبو أمين'),lower('Abo Amen'))
     OR lower(btrim(coalesce(cs.display_name,''))) IN (lower('أبو أمين'),lower('Abo Amen'));

  IF v_company_count IS DISTINCT FROM 1 THEN
    RAISE EXCEPTION 'ABO_AMEN_COMPANY_SELECTOR_NOT_UNIQUE: matched % active companies',coalesce(v_company_count,0);
  END IF;
  v_company_id:=v_company_ids[1];

  SELECT count(*) INTO v_doc_numbers_before FROM hasad.doc_numbers WHERE company_id=v_company_id;
  SELECT count(*) INTO v_periods_before FROM hasad.fiscal_periods WHERE company_id=v_company_id;

  SELECT * INTO v_year
  FROM hasad.fiscal_years
  WHERE company_id=v_company_id AND start_date=DATE '2026-01-01'
  FOR UPDATE;
  IF FOUND THEN
    IF v_year.end_date<>DATE '2026-12-31' OR v_year.status<>'open'
       OR v_year.reopen_count<>0 OR v_year.closed_at IS NOT NULL
       OR v_year.closed_by IS NOT NULL OR v_year.reopened_at IS NOT NULL
       OR v_year.reopened_by IS NOT NULL THEN
      RAISE EXCEPTION 'FISCAL_YEAR_CONFLICT';
    END IF;
  ELSE
    INSERT INTO hasad.fiscal_years
      (id,company_id,start_date,end_date,status,reopen_count)
    VALUES
      (pg_catalog.gen_random_uuid(),v_company_id,DATE '2026-01-01',DATE '2026-12-31','open',0);
  END IF;

  SELECT * INTO v_type
  FROM hasad.document_types
  WHERE company_id=v_company_id AND code='SI'
  FOR UPDATE;
  IF FOUND THEN
    IF v_type.name_ar<>'فاتورة مبيعات' OR v_type.issuance<>'posting'
       OR NOT v_type.is_active OR v_type.pad_length<>4
       OR v_type.format_prefix IS NOT NULL THEN
      RAISE EXCEPTION 'SALES_INVOICE_DOCUMENT_TYPE_CONFLICT';
    END IF;
  ELSE
    INSERT INTO hasad.document_types
      (id,company_id,code,name_ar,issuance,format_prefix,is_active)
    VALUES
      (pg_catalog.gen_random_uuid(),v_company_id,'SI','فاتورة مبيعات','posting',NULL,true);
  END IF;

  IF (SELECT count(*) FROM hasad.doc_numbers WHERE company_id=v_company_id)<>v_doc_numbers_before
     OR (SELECT count(*) FROM hasad.fiscal_periods WHERE company_id=v_company_id)<>v_periods_before THEN
    RAISE EXCEPTION 'REFERENCE_CONFIG_SCOPE_VIOLATION';
  END IF;
END
$configure$;

DO $postflight$
DECLARE v_company_id uuid;
BEGIN
  SELECT cs.company_id INTO v_company_id
  FROM hasad.company_settings cs JOIN hasad.companies c ON c.id=cs.company_id AND c.status='active'
  WHERE lower(btrim(coalesce(cs.name_ar,''))) IN (lower('أبو أمين'),lower('Abo Amen'))
     OR lower(btrim(coalesce(cs.name_en,''))) IN (lower('أبو أمين'),lower('Abo Amen'))
     OR lower(btrim(coalesce(cs.display_name,''))) IN (lower('أبو أمين'),lower('Abo Amen'));
  IF NOT EXISTS (SELECT 1 FROM hasad.fiscal_years WHERE company_id=v_company_id AND start_date=DATE '2026-01-01' AND end_date=DATE '2026-12-31' AND status='open' AND reopen_count=0) THEN
    RAISE EXCEPTION 'POSTFLIGHT_FISCAL_YEAR_MISSING';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM hasad.document_types WHERE company_id=v_company_id AND code='SI' AND name_ar='فاتورة مبيعات' AND issuance='posting' AND is_active AND pad_length=4 AND format_prefix IS NULL) THEN
    RAISE EXCEPTION 'POSTFLIGHT_DOCUMENT_TYPE_MISSING';
  END IF;
END
$postflight$;
COMMIT;
