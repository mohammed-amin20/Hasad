CREATE OR REPLACE FUNCTION pg_temp.assert_true(p_ok boolean, p_label text) RETURNS void
LANGUAGE plpgsql AS $$ BEGIN IF p_ok IS NOT TRUE THEN RAISE EXCEPTION 'ASSERT_FAIL: %', p_label; END IF; END $$;

SELECT pg_temp.assert_true(
  (SELECT count(*)=0 FROM hasad.fiscal_periods WHERE company_id='20000000-0000-0000-0000-000000000301'),
  'rollback: no fiscal period survived JE conflict');
SELECT pg_temp.assert_true(
  (SELECT count(*)=0 FROM hasad.doc_numbers WHERE company_id='20000000-0000-0000-0000-000000000301'),
  'rollback: no counter side effect');
SELECT pg_temp.assert_true(
  (SELECT vat_enabled IS FALSE FROM hasad.company_settings WHERE company_id='20000000-0000-0000-0000-000000000301'),
  'rollback: VAT setting unchanged');
SELECT 'PASS: S3 JE and fiscal-period rollback harness' AS result;
