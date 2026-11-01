CREATE OR REPLACE FUNCTION pg_temp.assert_true(p_ok boolean, p_label text) RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
  IF p_ok IS NOT TRUE THEN RAISE EXCEPTION 'ASSERT_FAIL: %', p_label; END IF;
END $$;

SELECT pg_temp.assert_true(
  (SELECT count(*) = 5 FROM hasad.accounts
   WHERE company_id = '20000000-0000-0000-0000-000000000101'),
  'configuration: no account was created');
SELECT pg_temp.assert_true(
  (SELECT count(*) = 4 FROM hasad.module_account_map
   WHERE company_id = '20000000-0000-0000-0000-000000000101' AND module = 'sales'),
  'configuration: exactly four non-VAT mappings were created');
SELECT pg_temp.assert_true(
  (SELECT count(*) = 1 FROM hasad.module_account_map
   WHERE company_id = '20000000-0000-0000-0000-000000000101'
     AND module = 'sales' AND account_role = 'AR_CONTROL'
     AND account_id = '47000000-0000-0000-0000-000000000101'),
  'configuration: AR mapping uses the selected active asset account');
SELECT pg_temp.assert_true(
  (SELECT count(*) = 1 FROM hasad.module_account_map
   WHERE company_id = '20000000-0000-0000-0000-000000000101'
     AND module = 'sales' AND account_role = 'SALES_REVENUE'
     AND account_id = '47000000-0000-0000-0000-000000000102'),
  'configuration: revenue mapping uses the selected active revenue account');
SELECT pg_temp.assert_true(
  (SELECT count(*) = 1 FROM hasad.module_account_map
   WHERE company_id = '20000000-0000-0000-0000-000000000101'
     AND module = 'sales' AND account_role = 'COGS'
     AND account_id = '47000000-0000-0000-0000-000000000103'),
  'configuration: COGS mapping uses the selected active expense account');
SELECT pg_temp.assert_true(
  (SELECT count(*) = 1 FROM hasad.module_account_map
   WHERE company_id = '20000000-0000-0000-0000-000000000101'
     AND module = 'sales' AND account_role = 'INVENTORY_CONTROL'
     AND account_id = '47000000-0000-0000-0000-000000000104'),
  'configuration: inventory mapping uses the selected active asset account');
SELECT pg_temp.assert_true(
  (SELECT count(*) = 0 FROM hasad.module_account_map
   WHERE company_id = '20000000-0000-0000-0000-000000000101'
     AND module = 'sales' AND account_role = 'VAT_OUTPUT'),
  'configuration: VAT mapping stays absent while VAT is not configured');
SELECT pg_temp.assert_true(
  (SELECT count(*) = 12 FROM hasad.fiscal_periods
   WHERE company_id = '20000000-0000-0000-0000-000000000101'
     AND fiscal_year_id = '45000000-0000-0000-0000-000000000101'),
  'configuration: all twelve calendar months exist');
SELECT pg_temp.assert_true(
  (SELECT count(*) = 1 FROM hasad.fiscal_periods
   WHERE fiscal_year_id = '45000000-0000-0000-0000-000000000101'
     AND period_no = 10 AND start_date = DATE '2026-10-01'
     AND end_date = DATE '2026-10-31' AND status = 'open'),
  'configuration: owner-selected October is the only open test period');
SELECT pg_temp.assert_true(
  (SELECT count(*) = 11 FROM hasad.fiscal_periods
   WHERE fiscal_year_id = '45000000-0000-0000-0000-000000000101' AND status = 'closed'),
  'configuration: unselected periods are closed');
SELECT pg_temp.assert_true(
  (SELECT format_prefix = 'SI' AND pad_length = 4 AND issuance = 'posting' AND is_active
   FROM hasad.document_types WHERE id = '44000000-0000-0000-0000-000000000101'),
  'configuration: SI is compatible with SI-YYYY-0001');
SELECT pg_temp.assert_true(
  (SELECT count(*) = 1 FROM hasad.document_types
   WHERE company_id = '20000000-0000-0000-0000-000000000101'
     AND code = 'JE' AND name_ar = 'قيد يومية' AND issuance = 'posting'
     AND format_prefix = 'JE' AND pad_length = 4 AND is_active),
  'configuration: JE is exact and active');
SELECT pg_temp.assert_true(
  (SELECT count(*) = 0 FROM hasad.doc_numbers
   WHERE company_id = '20000000-0000-0000-0000-000000000101'),
  'configuration: no document number is issued or reserved');
SELECT pg_temp.assert_true(
  (SELECT vat_enabled IS FALSE FROM hasad.company_settings
   WHERE company_id = '20000000-0000-0000-0000-000000000101'),
  'configuration: VAT setting remains unchanged');
SELECT pg_temp.assert_true(
  (SELECT count(*) = 0 FROM hasad.tax_rates
   WHERE company_id = '20000000-0000-0000-0000-000000000101'),
  'configuration: no tax rate is created');
SELECT 'PASS: S3 accounting configuration harness' AS result;
