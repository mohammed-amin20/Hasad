CREATE OR REPLACE FUNCTION pg_temp.assert_true(p_ok boolean, p_label text) RETURNS void
LANGUAGE plpgsql AS $$ BEGIN IF p_ok IS NOT TRUE THEN RAISE EXCEPTION 'ASSERT_FAIL: %', p_label; END IF; END $$;

SELECT pg_temp.assert_true(
  (SELECT count(*) = 12 FROM hasad.fiscal_periods
   WHERE company_id='20000000-0000-0000-0000-000000000301'
     AND fiscal_year_id='45000000-0000-0000-0000-000000000301'),
  'periods: exactly twelve FY-2026 calendar months');
SELECT pg_temp.assert_true(
  (SELECT count(*) = 1 FROM hasad.fiscal_periods
   WHERE fiscal_year_id='45000000-0000-0000-0000-000000000301'
     AND period_no=10 AND start_date=DATE '2026-10-01'
     AND end_date=DATE '2026-10-31' AND status='open'),
  'periods: proposed October test period is the only open period');
SELECT pg_temp.assert_true(
  (SELECT count(*) = 11 FROM hasad.fiscal_periods
   WHERE fiscal_year_id='45000000-0000-0000-0000-000000000301' AND status='closed'),
  'periods: every non-selected month is closed');
SELECT pg_temp.assert_true(
  (SELECT count(*) = 1 FROM hasad.document_types
   WHERE company_id='20000000-0000-0000-0000-000000000301'
     AND code='JE' AND name_ar='قيد يومية' AND issuance='posting'
     AND format_prefix='JE' AND pad_length=4 AND is_active),
  'JE: exact active journal document type');
SELECT pg_temp.assert_true(
  (SELECT vat_enabled IS FALSE FROM hasad.company_settings WHERE company_id='20000000-0000-0000-0000-000000000301'),
  'VAT: setting unchanged');
SELECT pg_temp.assert_true(
  (SELECT count(*)=0 FROM hasad.tax_rates WHERE company_id='20000000-0000-0000-0000-000000000301'),
  'VAT: no tax rate inserted');
SELECT pg_temp.assert_true(
  (SELECT count(*)=0 FROM hasad.doc_numbers WHERE company_id='20000000-0000-0000-0000-000000000301'),
  'numbers: no counter issued');
SELECT pg_temp.assert_true(
  (SELECT count(*)=0 FROM hasad.sales_documents WHERE company_id='20000000-0000-0000-0000-000000000301'),
  'sales: no invoice side effect');
SELECT pg_temp.assert_true(
  (SELECT count(*)=0 FROM hasad.stock_movements WHERE company_id='20000000-0000-0000-0000-000000000301'),
  'inventory: no movement side effect');
SELECT pg_temp.assert_true(
  (SELECT count(*)=0 FROM hasad.journal_entries WHERE company_id='20000000-0000-0000-0000-000000000301'),
  'accounting: no journal entry side effect');
SELECT pg_temp.assert_true(
  (SELECT count(*)=0 FROM hasad.fiscal_periods WHERE company_id='20000000-0000-0000-0000-000000000302')
  AND (SELECT count(*)=0 FROM hasad.document_types WHERE company_id='20000000-0000-0000-0000-000000000302' AND code='JE'),
  'tenant: other company is untouched');
SELECT 'PASS: S3 JE and fiscal-period harness' AS result;
