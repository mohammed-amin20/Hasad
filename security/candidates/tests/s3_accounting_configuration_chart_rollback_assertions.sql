CREATE OR REPLACE FUNCTION pg_temp.assert_true(p_ok boolean, p_label text) RETURNS void
LANGUAGE plpgsql AS $$ BEGIN IF p_ok IS NOT TRUE THEN RAISE EXCEPTION 'ASSERT_FAIL: %', p_label; END IF; END $$;

SELECT pg_temp.assert_true(
  (SELECT count(*) = 0 FROM hasad.accounts
   WHERE company_id='20000000-0000-0000-0000-000000000201' AND code='1100'),
  'rollback: first inserted account did not survive a later conflict');
SELECT pg_temp.assert_true(
  (SELECT count(*) = 0 FROM hasad.module_account_map
   WHERE company_id='20000000-0000-0000-0000-000000000201' AND account_role='AR_CONTROL'),
  'rollback: first inserted mapping did not survive a later conflict');
SELECT pg_temp.assert_true(
  (SELECT count(*) = 0 FROM hasad.sales_documents WHERE company_id='20000000-0000-0000-0000-000000000201'),
  'rollback: no invoice side effect');
SELECT pg_temp.assert_true(
  (SELECT count(*) = 0 FROM hasad.stock_movements WHERE company_id='20000000-0000-0000-0000-000000000201'),
  'rollback: no stock side effect');
SELECT pg_temp.assert_true(
  (SELECT count(*) = 0 FROM hasad.journal_entries WHERE company_id='20000000-0000-0000-0000-000000000201'),
  'rollback: no journal side effect');
