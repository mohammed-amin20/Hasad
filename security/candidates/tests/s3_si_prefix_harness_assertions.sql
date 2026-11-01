CREATE OR REPLACE FUNCTION pg_temp.assert_true(p_ok boolean, p_label text) RETURNS void
LANGUAGE plpgsql AS $$ BEGIN IF p_ok IS NOT TRUE THEN RAISE EXCEPTION 'ASSERT_FAIL: %', p_label; END IF; END $$;

SELECT pg_temp.assert_true(
  (SELECT format_prefix='SI' AND code='SI' AND name_ar='فاتورة مبيعات'
     AND issuance='posting' AND pad_length=4 AND is_active
   FROM hasad.document_types WHERE id='44000000-0000-0000-0000-000000000401'),
  'SI: NULL prefix becomes SI and every other SI field is preserved');
SELECT pg_temp.assert_true(
  (SELECT format_prefix='OTHER' FROM hasad.document_types
   WHERE id='44000000-0000-0000-0000-000000000402'),
  'tenant: another company SI prefix is untouched');
SELECT pg_temp.assert_true(
  (SELECT vat_enabled IS FALSE FROM hasad.company_settings WHERE company_id='20000000-0000-0000-0000-000000000401'),
  'VAT: setting unchanged');
SELECT pg_temp.assert_true((SELECT count(*)=0 FROM hasad.fiscal_periods WHERE company_id='20000000-0000-0000-0000-000000000401'),'side effect: no period');
SELECT pg_temp.assert_true((SELECT count(*)=0 FROM hasad.doc_numbers WHERE company_id='20000000-0000-0000-0000-000000000401'),'side effect: no counter');
SELECT pg_temp.assert_true((SELECT count(*)=0 FROM hasad.tax_rates WHERE company_id='20000000-0000-0000-0000-000000000401'),'side effect: no tax');
SELECT pg_temp.assert_true((SELECT count(*)=0 FROM hasad.sales_documents WHERE company_id='20000000-0000-0000-0000-000000000401'),'side effect: no invoice');
SELECT pg_temp.assert_true((SELECT count(*)=0 FROM hasad.stock_movements WHERE company_id='20000000-0000-0000-0000-000000000401'),'side effect: no movement');
SELECT pg_temp.assert_true((SELECT count(*)=0 FROM hasad.journal_entries WHERE company_id='20000000-0000-0000-0000-000000000401'),'side effect: no journal');
SELECT 'PASS: S3 SI prefix harness' AS result;
