CREATE OR REPLACE FUNCTION pg_temp.assert_true(p_ok boolean, p_label text) RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
  IF p_ok IS NOT TRUE THEN RAISE EXCEPTION 'ASSERT_FAIL: %', p_label; END IF;
END $$;

SELECT pg_temp.assert_true(
  (SELECT count(*) = 0 FROM hasad.module_account_map
   WHERE company_id = '20000000-0000-0000-0000-000000000101'),
  'rollback: no account mapping survived JE conflict');
SELECT pg_temp.assert_true(
  (SELECT count(*) = 0 FROM hasad.fiscal_periods
   WHERE company_id = '20000000-0000-0000-0000-000000000101'),
  'rollback: no fiscal period survived JE conflict');
SELECT pg_temp.assert_true(
  (SELECT format_prefix IS NULL FROM hasad.document_types
   WHERE id = '44000000-0000-0000-0000-000000000101'),
  'rollback: SI prefix was not partially updated');
SELECT pg_temp.assert_true(
  (SELECT count(*) = 0 FROM hasad.doc_numbers
   WHERE company_id = '20000000-0000-0000-0000-000000000101'),
  'rollback: no document counter exists');
SELECT pg_temp.assert_true(
  (SELECT count(*) = 0 FROM hasad.tax_rates
   WHERE company_id = '20000000-0000-0000-0000-000000000101'),
  'rollback: no tax row exists');
SELECT 'PASS: S3 accounting configuration rollback harness' AS result;
