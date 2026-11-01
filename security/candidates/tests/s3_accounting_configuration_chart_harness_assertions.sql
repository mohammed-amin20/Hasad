CREATE OR REPLACE FUNCTION pg_temp.assert_true(p_ok boolean, p_label text) RETURNS void
LANGUAGE plpgsql AS $$ BEGIN IF p_ok IS NOT TRUE THEN RAISE EXCEPTION 'ASSERT_FAIL: %', p_label; END IF; END $$;

SELECT pg_temp.assert_true(
  (SELECT count(*) = 5 FROM hasad.accounts WHERE company_id='20000000-0000-0000-0000-000000000201'),
  'chart: exactly five Abo Amen accounts exist');
SELECT pg_temp.assert_true(
  (SELECT count(*) = 5 FROM hasad.module_account_map
   WHERE company_id='20000000-0000-0000-0000-000000000201' AND module='sales'),
  'chart: exactly five sales mappings exist');
SELECT pg_temp.assert_true(
  (SELECT count(*) = 5 FROM hasad.accounts
   WHERE company_id='20000000-0000-0000-0000-000000000201'
     AND parent_id IS NULL AND is_active
     AND (code,name_ar,account_type) IN (
       ('1100','الذمم المدينة التجارية','asset'),
       ('1200','مخزون البضاعة','asset'),
       ('2100','ضريبة القيمة المضافة – مخرجات','liability'),
       ('4100','إيرادات المبيعات','revenue'),
       ('5100','تكلفة البضاعة المباعة','expense'))),
  'chart: all approved code/name/type values are exact');
SELECT pg_temp.assert_true(
  (SELECT count(*) = 5 FROM hasad.module_account_map m
   JOIN hasad.accounts a ON a.company_id=m.company_id AND a.id=m.account_id
   WHERE m.company_id='20000000-0000-0000-0000-000000000201' AND m.module='sales'
     AND (m.account_role,a.code) IN (
       ('AR_CONTROL','1100'),('INVENTORY_CONTROL','1200'),('VAT_OUTPUT','2100'),
       ('SALES_REVENUE','4100'),('COGS','5100'))),
  'chart: every sales role maps to its exact approved account');
SELECT pg_temp.assert_true(
  (SELECT count(*) = 1 FROM hasad.accounts WHERE company_id='20000000-0000-0000-0000-000000000202'),
  'chart: other-company account is untouched');
SELECT pg_temp.assert_true(
  (SELECT vat_enabled IS FALSE FROM hasad.company_settings WHERE company_id='20000000-0000-0000-0000-000000000201'),
  'chart: VAT setting is unchanged');
SELECT pg_temp.assert_true(
  (SELECT count(*) = 0 FROM hasad.tax_rates WHERE company_id='20000000-0000-0000-0000-000000000201'),
  'chart: no tax rate exists');
SELECT pg_temp.assert_true(
  (SELECT count(*) = 0 FROM hasad.fiscal_periods WHERE company_id='20000000-0000-0000-0000-000000000201'),
  'chart: no fiscal period side effect');
SELECT pg_temp.assert_true(
  (SELECT count(*) = 0 FROM hasad.doc_numbers WHERE company_id='20000000-0000-0000-0000-000000000201'),
  'chart: no document number side effect');
SELECT pg_temp.assert_true(
  (SELECT count(*) = 0 FROM hasad.sales_documents WHERE company_id='20000000-0000-0000-0000-000000000201'),
  'chart: no invoice side effect');
SELECT pg_temp.assert_true(
  (SELECT count(*) = 0 FROM hasad.stock_levels WHERE company_id='20000000-0000-0000-0000-000000000201'),
  'chart: no stock-level side effect');
SELECT pg_temp.assert_true(
  (SELECT count(*) = 0 FROM hasad.stock_movements WHERE company_id='20000000-0000-0000-0000-000000000201'),
  'chart: no stock-movement side effect');
SELECT pg_temp.assert_true(
  (SELECT count(*) = 0 FROM hasad.journal_entries WHERE company_id='20000000-0000-0000-0000-000000000201'),
  'chart: no journal side effect');
SELECT 'PASS: S3 approved chart harness' AS result;
