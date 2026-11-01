CREATE OR REPLACE FUNCTION pg_temp.assert_true(p_ok boolean, p_label text) RETURNS void
LANGUAGE plpgsql AS $$ BEGIN IF p_ok IS NOT TRUE THEN RAISE EXCEPTION 'ASSERT_FAIL: %', p_label; END IF; END $$;

SELECT pg_temp.assert_true(
  (SELECT format_prefix='LEGACY' FROM hasad.document_types WHERE id='44000000-0000-0000-0000-000000000401'),
  'rollback: conflicting prefix is never overwritten');
SELECT pg_temp.assert_true((SELECT count(*)=0 FROM hasad.fiscal_periods WHERE company_id='20000000-0000-0000-0000-000000000401'),'rollback: no period');
SELECT pg_temp.assert_true((SELECT count(*)=0 FROM hasad.doc_numbers WHERE company_id='20000000-0000-0000-0000-000000000401'),'rollback: no counter');
SELECT pg_temp.assert_true((SELECT count(*)=0 FROM hasad.journal_entries WHERE company_id='20000000-0000-0000-0000-000000000401'),'rollback: no journal');
SELECT 'PASS: S3 SI prefix rollback harness' AS result;
