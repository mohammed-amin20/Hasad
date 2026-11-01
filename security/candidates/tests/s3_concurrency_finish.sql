-- Local-only S3 concurrency step 3 of 3.
-- The row lock is released; one normal retry may now post the reserved draft.
CREATE OR REPLACE FUNCTION pg_temp.assert_true(p_ok boolean, p_label text) RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
  IF p_ok IS NOT TRUE THEN RAISE EXCEPTION 'ASSERT_FAIL: %', p_label; END IF;
END $$;

BEGIN;
SELECT pg_temp.assert_true(
  (SELECT status='draft' AND doc_no IS NULL FROM hasad.sales_documents
   WHERE id='50000000-0000-0000-0000-000000000018'),
  'concurrency: timed-out attempt left no partial posting');
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', '{"sub":"10000000-0000-0000-0000-000000000002"}', true);
SELECT set_config('hasad_test.post_result', hasad.post_sales_invoice(
  '20000000-0000-0000-0000-000000000001',
  '50000000-0000-0000-0000-000000000018',
  '51000000-0000-0000-0000-000000000018')::text, true);
RESET ROLE;
SELECT pg_temp.assert_true(
  current_setting('hasad_test.post_result')::jsonb->>'doc_no' = 'SI-2026-0004',
  'concurrency: only the later retry receives the next invoice number');
SELECT pg_temp.assert_true(
  current_setting('hasad_test.post_result')::jsonb->>'journal_entry_no' = 'JE-2026-0004',
  'concurrency: only the later retry receives the next journal number');
SELECT pg_temp.assert_true(
  (SELECT status='posted' AND doc_no='SI-2026-0004' FROM hasad.sales_documents
   WHERE id='50000000-0000-0000-0000-000000000018'),
  'concurrency: reserved invoice posted exactly once');
SELECT pg_temp.assert_true(
  (SELECT count(*)=1 FROM hasad.stock_movements
   WHERE source_document_id='50000000-0000-0000-0000-000000000018'),
  'concurrency: exactly one movement exists');
SELECT pg_temp.assert_true(
  (SELECT count(*)=1 FROM hasad.journal_entries
   WHERE idempotency_key='51000000-0000-0000-0000-000000000018'),
  'concurrency: exactly one journal entry exists');
SELECT pg_temp.assert_true(
  (SELECT qty=5 FROM hasad.stock_levels
   WHERE company_id='20000000-0000-0000-0000-000000000001'
     AND product_id='42000000-0000-0000-0000-000000000001'
     AND warehouse_id='41000000-0000-0000-0000-000000000001'),
  'concurrency: stock is decremented once after the successful retry');
SELECT pg_temp.assert_true(
  (SELECT next_value=5 FROM hasad.doc_numbers
   WHERE document_type_id='44000000-0000-0000-0000-000000000001'
     AND fiscal_year_id='45000000-0000-0000-0000-000000000001'),
  'concurrency: invoice counter advanced only by the retry');
SELECT pg_temp.assert_true(
  (SELECT next_value=5 FROM hasad.doc_numbers
   WHERE document_type_id='44000000-0000-0000-0000-000000000002'
     AND fiscal_year_id='45000000-0000-0000-0000-000000000001'),
  'concurrency: journal counter advanced only by the retry');
COMMIT;

SELECT 'PASS: S3 sales posting concurrency harness' AS result;
