CREATE OR REPLACE FUNCTION pg_temp.assert_true(p_ok boolean, p_label text) RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
  IF p_ok IS NOT TRUE THEN RAISE EXCEPTION 'ASSERT_FAIL: %', p_label; END IF;
END $$;

-- The FY/period are local fixture data only. They exercise the allocator's
-- selected-fiscal-year path; no system-clock year is used.
INSERT INTO hasad.fiscal_years (id, company_id, start_date, end_date, status) VALUES
  ('45000000-0000-0000-0000-000000000103', '20000000-0000-0000-0000-000000000001',
   DATE '2027-01-01', DATE '2027-12-31', 'open');
INSERT INTO hasad.fiscal_periods
  (id, company_id, fiscal_year_id, period_no, start_date, end_date, status)
VALUES
  ('46000000-0000-0000-0000-000000000103', '20000000-0000-0000-0000-000000000001',
   '45000000-0000-0000-0000-000000000103', 1, DATE '2027-01-01', DATE '2027-01-31', 'open');
INSERT INTO hasad.sales_documents
  (id, company_id, doc_kind, status, party_id, doc_date, vat_mode, doc_type_id,
   fiscal_year_id, idempotency_key, net, tax, gross)
VALUES
  ('50000000-0000-0000-0000-000000000101', '20000000-0000-0000-0000-000000000001',
   'invoice', 'draft', '43000000-0000-0000-0000-000000000001', DATE '2026-10-31',
   'exclusive', '44000000-0000-0000-0000-000000000001',
   '45000000-0000-0000-0000-000000000001', '51000000-0000-0000-0000-000000000101', 10, 0, 10),
  ('50000000-0000-0000-0000-000000000102', '20000000-0000-0000-0000-000000000001',
   'invoice', 'draft', '43000000-0000-0000-0000-000000000001', DATE '2027-01-15',
   'exclusive', '44000000-0000-0000-0000-000000000001',
   '45000000-0000-0000-0000-000000000103', '51000000-0000-0000-0000-000000000102', 10, 0, 10);
INSERT INTO hasad.sales_document_lines
  (id, company_id, document_id, line_no, qty, unit_price, discount_amount, tax_rate, net, tax, gross)
VALUES
  ('52000000-0000-0000-0000-000000000101', '20000000-0000-0000-0000-000000000001',
   '50000000-0000-0000-0000-000000000101', 1, 1, 10, 0, 0, 10, 0, 10),
  ('52000000-0000-0000-0000-000000000102', '20000000-0000-0000-0000-000000000001',
   '50000000-0000-0000-0000-000000000102', 1, 1, 10, 0, 0, 10, 0, 10);

BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', '{"sub":"10000000-0000-0000-0000-000000000002"}', true);
SELECT set_config('hasad_test.post_2026', hasad.post_sales_invoice(
  '20000000-0000-0000-0000-000000000001',
  '50000000-0000-0000-0000-000000000101',
  '51000000-0000-0000-0000-000000000101')::text, true);
SELECT set_config('hasad_test.post_2027', hasad.post_sales_invoice(
  '20000000-0000-0000-0000-000000000001',
  '50000000-0000-0000-0000-000000000102',
  '51000000-0000-0000-0000-000000000102')::text, true);
RESET ROLE;
SELECT pg_temp.assert_true(
  current_setting('hasad_test.post_2026')::jsonb->>'doc_no' = 'SI-2026-0001'
  AND current_setting('hasad_test.post_2026')::jsonb->>'journal_entry_no' = 'JE-2026-0001',
  'numbering: 2026 uses the selected fiscal year, not the server clock');
SELECT pg_temp.assert_true(
  current_setting('hasad_test.post_2027')::jsonb->>'doc_no' = 'SI-2027-0001'
  AND current_setting('hasad_test.post_2027')::jsonb->>'journal_entry_no' = 'JE-2027-0001',
  'numbering: 2027 counter resets and embeds the selected fiscal year');
SELECT pg_temp.assert_true(
  (SELECT count(*) = 2 AND count(DISTINCT doc_no) = 2
   FROM hasad.sales_documents
   WHERE id IN ('50000000-0000-0000-0000-000000000101',
                '50000000-0000-0000-0000-000000000102')),
  'numbering: annual reset does not duplicate company official document numbers');
SELECT pg_temp.assert_true(
  (SELECT next_value = 2 FROM hasad.doc_numbers
   WHERE company_id = '20000000-0000-0000-0000-000000000001'
     AND document_type_id = '44000000-0000-0000-0000-000000000001'
     AND fiscal_year_id = '45000000-0000-0000-0000-000000000001'),
  'numbering: 2026 counter is isolated');
SELECT pg_temp.assert_true(
  (SELECT next_value = 2 FROM hasad.doc_numbers
   WHERE company_id = '20000000-0000-0000-0000-000000000001'
     AND document_type_id = '44000000-0000-0000-0000-000000000001'
     AND fiscal_year_id = '45000000-0000-0000-0000-000000000103'),
  'numbering: 2027 counter is isolated');
COMMIT;

SELECT 'PASS: S3 accounting configuration yearly numbering harness' AS result;
