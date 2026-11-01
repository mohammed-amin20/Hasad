-- Local-only S3 posting assertions. Disposable PostgreSQL 17 harness only.
-- Fixture map (see s3_posting_harness_fixtures.sql):
--   c1  20000000-...-0001   c2  20000000-...-0002
--   owner c1 u1 10000000-...-0001 (is_owner)
--   poster c1 u2 10000000-...-0002 (role has sales.post)
--   denied c1 u3 10000000-...-0003 (role has no permission)
--   owner c2 u4 10000000-...-0004
--   party c1 4300...0001  party c2 4300...0002
--   product 4200...0001  warehouse 4100...0001
--   SI 4400...0001 (NULL prefix, pad 4)  JE 4400...0002 (prefix 'JE')
--   FY 4500...0001  period 4600...0001 (2026-10-01..2026-10-31, open)
--   accounts 4700...0001 AR, ...0002 revenue, ...0003 VAT, ...0004 COGS, ...0005 inventory
--   stock 10 units at moving average 7.2500
CREATE OR REPLACE FUNCTION pg_temp.assert_true(p_ok boolean, p_label text) RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
  IF p_ok IS NOT TRUE THEN RAISE EXCEPTION 'ASSERT_FAIL: %', p_label; END IF;
END $$;

CREATE OR REPLACE FUNCTION pg_temp.expect_state(p_sql text, p_state text, p_label text) RETURNS void
LANGUAGE plpgsql AS $$
DECLARE s text;
BEGIN
  BEGIN
    EXECUTE p_sql;
  EXCEPTION WHEN others THEN
    GET STACKED DIAGNOSTICS s = RETURNED_SQLSTATE;
    IF s <> p_state THEN
      RAISE EXCEPTION 'ASSERT_FAIL: % expected state %, got %', p_label, p_state, s;
    END IF;
    RETURN;
  END;
  RAISE EXCEPTION 'ASSERT_FAIL: % unexpectedly succeeded', p_label;
END $$;

CREATE OR REPLACE FUNCTION pg_temp.expect_raise(p_sql text, p_needle text, p_label text) RETURNS void
LANGUAGE plpgsql AS $$
DECLARE m text; d text;
BEGIN
  BEGIN
    EXECUTE p_sql;
  EXCEPTION WHEN others THEN
    GET STACKED DIAGNOSTICS m = MESSAGE_TEXT, d = PG_EXCEPTION_DETAIL;
    IF pg_catalog.strpos(m, p_needle) = 0
       AND pg_catalog.strpos(coalesce(d, ''), p_needle) = 0 THEN
      RAISE EXCEPTION 'ASSERT_FAIL: % expected [%], got [%] / [%]', p_label, p_needle, m, d;
    END IF;
    RETURN;
  END;
  RAISE EXCEPTION 'ASSERT_FAIL: % unexpectedly succeeded', p_label;
END $$;

-- ---------------------------------------------------------------- fixtures --
-- Drafts A and B are produced by the deployed S2 atomic draft operation so the
-- S3 candidate is verified against real draft rows, not hand-built ones.
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', '{"sub":"10000000-0000-0000-0000-000000000001"}', true);
SELECT hasad.save_sales_invoice_draft(
  '50000000-0000-0000-0000-000000000010',
  '20000000-0000-0000-0000-000000000001',
  '43000000-0000-0000-0000-000000000001',
  '2026-10-31', 'exclusive',
  '44000000-0000-0000-0000-000000000001',
  '45000000-0000-0000-0000-000000000001',
  '51000000-0000-0000-0000-000000000010',
  '[{"id":"52000000-0000-0000-0000-000000000010","line_no":1,"product_id":"42000000-0000-0000-0000-000000000001","warehouse_id":"41000000-0000-0000-0000-000000000001","qty":2,"unit_price":10.00,"discount_amount":0,"tax_rate":18.000}]'::jsonb);
SELECT hasad.save_sales_invoice_draft(
  '50000000-0000-0000-0000-000000000011',
  '20000000-0000-0000-0000-000000000001',
  '43000000-0000-0000-0000-000000000001',
  '2026-10-31', 'exclusive',
  '44000000-0000-0000-0000-000000000001',
  '45000000-0000-0000-0000-000000000001',
  '51000000-0000-0000-0000-000000000011',
  '[{"id":"52000000-0000-0000-0000-000000000011","line_no":1,"product_id":"42000000-0000-0000-0000-000000000001","warehouse_id":"41000000-0000-0000-0000-000000000001","qty":1,"unit_price":20.00,"discount_amount":0,"tax_rate":0}]'::jsonb);
RESET ROLE;
COMMIT;

BEGIN;
INSERT INTO hasad.sales_documents
  (id,company_id,doc_kind,status,party_id,doc_date,vat_mode,doc_type_id,
   fiscal_year_id,idempotency_key,net,tax,gross)
VALUES
  -- C: demand 11 > 10 on hand
  ('50000000-0000-0000-0000-000000000012','20000000-0000-0000-0000-000000000001','invoice','draft','43000000-0000-0000-0000-000000000001','2026-10-31','exclusive','44000000-0000-0000-0000-000000000001','45000000-0000-0000-0000-000000000001','51000000-0000-0000-0000-000000000012',11.00,0,11.00),
  -- D: server totals will not match recomputation after tampering below
  ('50000000-0000-0000-0000-000000000013','20000000-0000-0000-0000-000000000001','invoice','draft','43000000-0000-0000-0000-000000000001','2026-10-31','exclusive','44000000-0000-0000-0000-000000000001','45000000-0000-0000-0000-000000000001','51000000-0000-0000-0000-000000000013',9.00,0,9.00),
  -- E: 5% rate is not in the effective-dated catalogue
  ('50000000-0000-0000-0000-000000000014','20000000-0000-0000-0000-000000000001','invoice','draft','43000000-0000-0000-0000-000000000001','2026-10-31','exclusive','44000000-0000-0000-0000-000000000001','45000000-0000-0000-0000-000000000001','51000000-0000-0000-0000-000000000014',10.00,0.50,10.50),
  -- F: company 2 draft, service line, no company-2 accounting configured
  ('50000000-0000-0000-0000-000000000015','20000000-0000-0000-0000-000000000002','invoice','draft','43000000-0000-0000-0000-000000000002','2026-10-31','exclusive','44000000-0000-0000-0000-000000000003','45000000-0000-0000-0000-000000000002','51000000-0000-0000-0000-000000000015',10.00,0,10.00),
  -- G: date inside the fiscal year but outside every open period
  ('50000000-0000-0000-0000-000000000016','20000000-0000-0000-0000-000000000001','invoice','draft','43000000-0000-0000-0000-000000000001','2026-11-15','exclusive','44000000-0000-0000-0000-000000000001','45000000-0000-0000-0000-000000000001','51000000-0000-0000-0000-000000000016',10.00,0,10.00),
  -- I: zero-value invoice must be refused before any write
  ('50000000-0000-0000-0000-000000000017','20000000-0000-0000-0000-000000000001','invoice','draft','43000000-0000-0000-0000-000000000001','2026-10-31','exclusive','44000000-0000-0000-0000-000000000001','45000000-0000-0000-0000-000000000001','51000000-0000-0000-0000-000000000017',0,0,0),
  -- H: reserved for the two-session concurrency step in the runner
  ('50000000-0000-0000-0000-000000000018','20000000-0000-0000-0000-000000000001','invoice','draft','43000000-0000-0000-0000-000000000001','2026-10-31','exclusive','44000000-0000-0000-0000-000000000001','45000000-0000-0000-0000-000000000001','51000000-0000-0000-0000-000000000018',10.00,0,10.00);
INSERT INTO hasad.sales_document_lines
  (id,company_id,document_id,line_no,product_id,warehouse_id,qty,unit_price,
   discount_amount,tax_rate,net,tax,gross)
VALUES
  ('52000000-0000-0000-0000-000000000012','20000000-0000-0000-0000-000000000001','50000000-0000-0000-0000-000000000012',1,'42000000-0000-0000-0000-000000000001','41000000-0000-0000-0000-000000000001',11,1.00,0,0,11.00,0,11.00),
  ('52000000-0000-0000-0000-000000000013','20000000-0000-0000-0000-000000000001','50000000-0000-0000-0000-000000000013',1,'42000000-0000-0000-0000-000000000001','41000000-0000-0000-0000-000000000001',1,10.00,0,0,9.00,0,9.00),
  ('52000000-0000-0000-0000-000000000014','20000000-0000-0000-0000-000000000001','50000000-0000-0000-0000-000000000014',1,'42000000-0000-0000-0000-000000000001','41000000-0000-0000-0000-000000000001',1,10.00,0,5.000,10.00,0.50,10.50),
  ('52000000-0000-0000-0000-000000000015','20000000-0000-0000-0000-000000000002','50000000-0000-0000-0000-000000000015',1,NULL,NULL,1,10.00,0,0,10.00,0,10.00),
  ('52000000-0000-0000-0000-000000000016','20000000-0000-0000-0000-000000000001','50000000-0000-0000-0000-000000000016',1,'42000000-0000-0000-0000-000000000001','41000000-0000-0000-0000-000000000001',1,10.00,0,0,10.00,0,10.00),
  ('52000000-0000-0000-0000-000000000017','20000000-0000-0000-0000-000000000001','50000000-0000-0000-0000-000000000017',1,NULL,NULL,1,0,0,0,0,0,0),
  ('52000000-0000-0000-0000-000000000018','20000000-0000-0000-0000-000000000001','50000000-0000-0000-0000-000000000018',1,'42000000-0000-0000-0000-000000000001','41000000-0000-0000-0000-000000000001',1,10.00,0,0,10.00,0,10.00);
COMMIT;

SELECT pg_temp.assert_true((SELECT count(*)=9 FROM hasad.sales_documents WHERE status='draft'),'fixtures: nine drafts');
SELECT pg_temp.assert_true((SELECT count(*)=0 FROM hasad.doc_numbers),'fixtures: no counter yet');
SELECT pg_temp.assert_true((SELECT count(*)=0 FROM hasad.journal_entries),'fixtures: no journal yet');
SELECT pg_temp.assert_true((SELECT count(*)=0 FROM hasad.stock_movements),'fixtures: no movement yet');
SELECT pg_temp.assert_true((SELECT doc_no IS NULL FROM hasad.sales_documents WHERE id='50000000-0000-0000-0000-000000000010'),'fixtures: draft has no number');

-- --------------------------------------------- 1. accounting gate is closed --
BEGIN;
DELETE FROM hasad.module_account_map
WHERE company_id='20000000-0000-0000-0000-000000000001' AND account_role='AR_CONTROL';
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', '{"sub":"10000000-0000-0000-0000-000000000001"}', true);
SELECT pg_temp.expect_raise(
  $q$SELECT hasad.post_sales_invoice('20000000-0000-0000-0000-000000000001','50000000-0000-0000-0000-000000000010','51000000-0000-0000-0000-000000000010')$q$,
  'ACCOUNTING_PREREQUISITES_MISSING', 'missing sales mapping fails closed');
RESET ROLE;
SELECT pg_temp.assert_true(
  (SELECT status='draft' AND doc_no IS NULL FROM hasad.sales_documents WHERE id='50000000-0000-0000-0000-000000000010'),
  'gate: invoice untouched');
SELECT pg_temp.assert_true((SELECT count(*)=0 FROM hasad.doc_numbers),'gate: no number consumed');
SELECT pg_temp.assert_true((SELECT count(*)=0 FROM hasad.stock_movements),'gate: no movement written');
SELECT pg_temp.assert_true((SELECT count(*)=0 FROM hasad.journal_entries),'gate: no journal written');
ROLLBACK;

-- -------------------------------------------------- 2. authentication gates --
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', '', true);
SELECT pg_temp.expect_state(
  $q$SELECT hasad.post_sales_invoice('20000000-0000-0000-0000-000000000001','50000000-0000-0000-0000-000000000010','51000000-0000-0000-0000-000000000010')$q$,
  '28000', 'anonymous request rejected');
RESET ROLE;
COMMIT;

BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', '{"sub":"10000000-0000-0000-0000-000000000003"}', true);
SELECT pg_temp.expect_state(
  $q$SELECT hasad.post_sales_invoice('20000000-0000-0000-0000-000000000001','50000000-0000-0000-0000-000000000010','51000000-0000-0000-0000-000000000010')$q$,
  '42501', 'member without sales.post denied');
RESET ROLE;
COMMIT;

-- ------------------------------------------------- 3. tenant isolation ------
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', '{"sub":"10000000-0000-0000-0000-000000000002"}', true);
SELECT pg_temp.expect_state(
  $q$SELECT hasad.post_sales_invoice('20000000-0000-0000-0000-000000000002','50000000-0000-0000-0000-000000000015','51000000-0000-0000-0000-000000000015')$q$,
  '42501', 'company-1 member cannot post company-2 invoice');
RESET ROLE;
COMMIT;

BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', '{"sub":"10000000-0000-0000-0000-000000000004"}', true);
SELECT pg_temp.expect_raise(
  $q$SELECT hasad.post_sales_invoice('20000000-0000-0000-0000-000000000002','50000000-0000-0000-0000-000000000015','51000000-0000-0000-0000-000000000015')$q$,
  'ACCOUNTING_PREREQUISITES_MISSING', 'company-2 owner blocked by missing company-2 accounting');
RESET ROLE;
SELECT pg_temp.assert_true(
  (SELECT status='draft' AND doc_no IS NULL FROM hasad.sales_documents WHERE id='50000000-0000-0000-0000-000000000015'),
  'tenant: company-2 invoice untouched');
SELECT pg_temp.assert_true(
  (SELECT count(*)=0 FROM hasad.doc_numbers WHERE company_id='20000000-0000-0000-0000-000000000002'),
  'tenant: no company-2 number consumed');
COMMIT;

-- ------------------------------------------------ 4. pre-write validation ---
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', '{"sub":"10000000-0000-0000-0000-000000000002"}', true);
SELECT pg_temp.expect_raise(
  $q$SELECT hasad.post_sales_invoice('20000000-0000-0000-0000-000000000001','50000000-0000-0000-0000-000000000012','51000000-0000-0000-0000-000000000099')$q$,
  'IDEMPOTENCY_MISMATCH', 'wrong posting key rejected');
SELECT pg_temp.expect_raise(
  $q$SELECT hasad.post_sales_invoice('20000000-0000-0000-0000-000000000001','50000000-0000-0000-0000-000000000016','51000000-0000-0000-0000-000000000016')$q$,
  'open_fiscal_period', 'document date outside open period blocked');
SELECT pg_temp.expect_raise(
  $q$SELECT hasad.post_sales_invoice('20000000-0000-0000-0000-000000000001','50000000-0000-0000-0000-000000000017','51000000-0000-0000-0000-000000000017')$q$,
  'DOCUMENT_TOTAL_INVALID', 'zero-value invoice blocked');
SELECT pg_temp.expect_raise(
  $q$SELECT hasad.post_sales_invoice('20000000-0000-0000-0000-000000000001','50000000-0000-0000-0000-000000000013','51000000-0000-0000-0000-000000000013')$q$,
  'TOTALS_MISMATCH', 'tampered totals blocked');
SELECT pg_temp.expect_raise(
  $q$SELECT hasad.post_sales_invoice('20000000-0000-0000-0000-000000000001','50000000-0000-0000-0000-000000000014','51000000-0000-0000-0000-000000000014')$q$,
  'RATE_NOT_FOUND_FOR_DATE', 'uncatalogued tax rate blocked');
RESET ROLE;
SELECT pg_temp.assert_true((SELECT count(*)=0 FROM hasad.doc_numbers),'validation: no number consumed');
SELECT pg_temp.assert_true((SELECT count(*)=0 FROM hasad.stock_movements),'validation: no movement written');
SELECT pg_temp.assert_true((SELECT count(*)=0 FROM hasad.journal_entries),'validation: no journal written');
SELECT pg_temp.assert_true(
  (SELECT count(*)=5 FROM hasad.sales_documents WHERE id IN (
    '50000000-0000-0000-0000-000000000012','50000000-0000-0000-0000-000000000013',
    '50000000-0000-0000-0000-000000000014','50000000-0000-0000-0000-000000000016',
    '50000000-0000-0000-0000-000000000017') AND status='draft' AND doc_no IS NULL),
  'validation: refused invoices stay untouched drafts');
COMMIT;

-- ---------------------------------------------------- 5. successful posting --
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', '{"sub":"10000000-0000-0000-0000-000000000002"}', true);
SELECT set_config('hasad_test.post_result', hasad.post_sales_invoice(
  '20000000-0000-0000-0000-000000000001',
  '50000000-0000-0000-0000-000000000010',
  '51000000-0000-0000-0000-000000000010')::text, true);
RESET ROLE;

SELECT pg_temp.assert_true((current_setting('hasad_test.post_result')::jsonb->>'replayed')::boolean IS FALSE, 'post: not a replay');
SELECT pg_temp.assert_true(current_setting('hasad_test.post_result')::jsonb->>'doc_no' = 'SI-2026-0001', 'post: official invoice number');
SELECT pg_temp.assert_true(current_setting('hasad_test.post_result')::jsonb->>'journal_entry_no' = 'JE-2026-0001', 'post: journal entry number');
SELECT pg_temp.assert_true(current_setting('hasad_test.post_result')::jsonb->'document'->>'status' = 'posted', 'post: returned document posted');

SELECT pg_temp.assert_true(
  (SELECT status='posted' AND doc_no='SI-2026-0001' AND posted_at IS NOT NULL
     AND posted_by='10000000-0000-0000-0000-000000000002'
   FROM hasad.sales_documents WHERE id='50000000-0000-0000-0000-000000000010'),
  'post: invoice flipped once with number and actor');
SELECT pg_temp.assert_true(
  (SELECT qty=8 AND last_unit_cost=7.2500 FROM hasad.stock_levels
   WHERE company_id='20000000-0000-0000-0000-000000000001'
     AND product_id='42000000-0000-0000-0000-000000000001'
     AND warehouse_id='41000000-0000-0000-0000-000000000001'),
  'post: stock reduced, moving average unchanged');
SELECT pg_temp.assert_true(
  (SELECT count(*)=1 FROM hasad.stock_movements WHERE company_id='20000000-0000-0000-0000-000000000001'
     AND movement_type='sales_issue' AND direction='out' AND qty=2 AND unit_cost=7.2500
     AND value=14.50 AND seq=1 AND source_document_type='sales_invoice'
     AND source_document_id='50000000-0000-0000-0000-000000000010'
     AND journal_line_id IS NOT NULL),
  'post: one linked weighted-average issue movement');
SELECT pg_temp.assert_true(
  (SELECT count(*)=1 FROM hasad.journal_entries WHERE company_id='20000000-0000-0000-0000-000000000001'),
  'post: exactly one journal entry');
SELECT pg_temp.assert_true(
  (SELECT status='posted' AND entry_no='JE-2026-0001'
     AND period_id='46000000-0000-0000-0000-000000000001'
     AND entry_date='2026-10-31'
     AND idempotency_key='51000000-0000-0000-0000-000000000010'
     AND posted_by='10000000-0000-0000-0000-000000000002'
   FROM hasad.journal_entries WHERE company_id='20000000-0000-0000-0000-000000000001'),
  'post: journal entry posted, periodized and numbered');
SELECT pg_temp.assert_true(
  (SELECT count(*)=5 AND sum(debit)=38.10 AND sum(credit)=38.10
   FROM hasad.journal_lines WHERE company_id='20000000-0000-0000-0000-000000000001'),
  'post: five balanced journal legs');
SELECT pg_temp.assert_true(
  (SELECT debit=23.60 FROM hasad.journal_lines WHERE account_id='47000000-0000-0000-0000-000000000001'),
  'post: AR debit equals gross');
SELECT pg_temp.assert_true(
  (SELECT credit=20.00 FROM hasad.journal_lines WHERE account_id='47000000-0000-0000-0000-000000000002'),
  'post: revenue credit equals net');
SELECT pg_temp.assert_true(
  (SELECT credit=3.60 FROM hasad.journal_lines WHERE account_id='47000000-0000-0000-0000-000000000003'),
  'post: VAT credit equals tax');
SELECT pg_temp.assert_true(
  (SELECT debit=14.50 FROM hasad.journal_lines WHERE account_id='47000000-0000-0000-0000-000000000004')
  AND (SELECT credit=14.50 FROM hasad.journal_lines WHERE account_id='47000000-0000-0000-0000-000000000005'),
  'post: COGS equals inventory credit equals movement value');
SELECT pg_temp.assert_true(
  (SELECT count(*)=1 FROM hasad.journal_lines l
   WHERE l.account_id='47000000-0000-0000-0000-000000000001'
     AND l.party_id='43000000-0000-0000-0000-000000000001'),
  'post: AR leg carries the customer');
SELECT pg_temp.assert_true(
  (SELECT next_value=2 FROM hasad.doc_numbers
   WHERE document_type_id='44000000-0000-0000-0000-000000000001'
     AND fiscal_year_id='45000000-0000-0000-0000-000000000001'),
  'post: SI counter advanced exactly once');
SELECT pg_temp.assert_true(
  (SELECT next_value=2 FROM hasad.doc_numbers
   WHERE document_type_id='44000000-0000-0000-0000-000000000002'
     AND fiscal_year_id='45000000-0000-0000-0000-000000000001'),
  'post: JE counter advanced exactly once');
SELECT pg_temp.assert_true(
  (SELECT count(*)=1 FROM hasad.audit_log WHERE action='sale.invoice_posted'
     AND entity_id='50000000-0000-0000-0000-000000000010'),
  'post: posting audited once');
SELECT pg_temp.assert_true(
  (SELECT count(*)=1 FROM hasad.audit_log WHERE action='number.issued'
     AND entity_id='50000000-0000-0000-0000-000000000010'),
  'post: number issuance audited once');
SELECT pg_temp.assert_true(
  (SELECT count(*)=1 FROM hasad.audit_log WHERE action='stock.posted'
     AND details->>'source_document_id'='50000000-0000-0000-0000-000000000010'),
  'post: stock issue audited once');
COMMIT;

-- ---------------------------------------------- 6. replay and double posting --
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', '{"sub":"10000000-0000-0000-0000-000000000002"}', true);
SELECT set_config('hasad_test.post_result', hasad.post_sales_invoice(
  '20000000-0000-0000-0000-000000000001',
  '50000000-0000-0000-0000-000000000010',
  '51000000-0000-0000-0000-000000000010')::text, true);
SELECT pg_temp.expect_raise(
  $q$SELECT hasad.post_sales_invoice('20000000-0000-0000-0000-000000000001','50000000-0000-0000-0000-000000000010','51000000-0000-0000-0000-000000000098')$q$,
  'ALREADY_POSTED', 'posted invoice with a different key rejected');
RESET ROLE;
SELECT pg_temp.assert_true((current_setting('hasad_test.post_result')::jsonb->>'replayed')::boolean IS TRUE, 'replay: flagged as replay');
SELECT pg_temp.assert_true(current_setting('hasad_test.post_result')::jsonb->>'doc_no' = 'SI-2026-0001', 'replay: same official number');
SELECT pg_temp.assert_true(current_setting('hasad_test.post_result')::jsonb->>'journal_entry_no' = 'JE-2026-0001', 'replay: same journal number');
SELECT pg_temp.assert_true(
  (SELECT count(*)=1 FROM hasad.stock_movements WHERE company_id='20000000-0000-0000-0000-000000000001'),
  'replay: no extra movement');
SELECT pg_temp.assert_true(
  (SELECT count(*)=1 FROM hasad.journal_entries WHERE company_id='20000000-0000-0000-0000-000000000001'),
  'replay: no extra journal entry');
SELECT pg_temp.assert_true(
  (SELECT count(*)=1 FROM hasad.audit_log WHERE action='sale.invoice_posted'),
  'replay: no extra posting audit');
SELECT pg_temp.assert_true(
  (SELECT count(*)=2 FROM hasad.doc_numbers WHERE company_id='20000000-0000-0000-0000-000000000001'),
  'replay: counters untouched');
COMMIT;

-- ------------------------------------------------- 7. numbering uniqueness ---
BEGIN;
DELETE FROM hasad.tax_rates
WHERE company_id='20000000-0000-0000-0000-000000000001';
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', '{"sub":"10000000-0000-0000-0000-000000000001"}', true);
SELECT set_config('hasad_test.post_result', hasad.post_sales_invoice(
  '20000000-0000-0000-0000-000000000001',
  '50000000-0000-0000-0000-000000000011',
  '51000000-0000-0000-0000-000000000011')::text, true);
RESET ROLE;
SELECT pg_temp.assert_true(current_setting('hasad_test.post_result')::jsonb->>'doc_no' = 'SI-2026-0002', 'numbering: second invoice gets SI-2026-0002');
SELECT pg_temp.assert_true(current_setting('hasad_test.post_result')::jsonb->>'journal_entry_no' = 'JE-2026-0002', 'numbering: second journal gets JE-2026-0002');
SELECT pg_temp.assert_true(
  (SELECT count(*)=2 AND count(DISTINCT doc_no)=2
   FROM hasad.sales_documents WHERE company_id='20000000-0000-0000-0000-000000000001'
     AND doc_no IS NOT NULL),
  'numbering: official numbers are unique per company');
SELECT pg_temp.assert_true(
  (SELECT count(*)=2 FROM hasad.sales_documents WHERE company_id='20000000-0000-0000-0000-000000000001'
      AND doc_no IN ('SI-2026-0001','SI-2026-0002') AND status='posted'),
  'numbering: both invoices posted with contiguous numbers');
SELECT pg_temp.assert_true(
  (SELECT vat_enabled IS FALSE FROM hasad.company_settings
   WHERE company_id='20000000-0000-0000-0000-000000000001')
  AND (SELECT count(*)=0 FROM hasad.tax_rates
       WHERE company_id='20000000-0000-0000-0000-000000000001'),
  'VAT-disabled: zero-tax invoice posts without a tax-rate configuration');
SELECT pg_temp.assert_true(
  (SELECT qty=7 FROM hasad.stock_levels
   WHERE company_id='20000000-0000-0000-0000-000000000001'
     AND product_id='42000000-0000-0000-0000-000000000001'
     AND warehouse_id='41000000-0000-0000-0000-000000000001'),
  'stock: cumulative issue is 3 units');
SELECT pg_temp.assert_true(
  (SELECT count(*)=2 FROM hasad.stock_movements WHERE company_id='20000000-0000-0000-0000-000000000001'
     AND seq IN (1,2) AND direction='out'),
  'stock: per-product sequence stays unique');
SELECT pg_temp.assert_true(
  (SELECT sum(debit)=sum(credit) FROM hasad.journal_lines
   WHERE entry_id=(SELECT id FROM hasad.journal_entries
     WHERE idempotency_key='51000000-0000-0000-0000-000000000011')),
  'accounting: second journal entry balances');
COMMIT;

-- ------------------------------------------------ 8. insufficient stock ------
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', '{"sub":"10000000-0000-0000-0000-000000000002"}', true);
SELECT pg_temp.expect_raise(
  $q$SELECT hasad.post_sales_invoice('20000000-0000-0000-0000-000000000001','50000000-0000-0000-0000-000000000012','51000000-0000-0000-0000-000000000012')$q$,
  'STOCK_INSUFFICIENT', 'demand above availability rejected');
RESET ROLE;
SELECT pg_temp.assert_true(
  (SELECT status='draft' AND doc_no IS NULL FROM hasad.sales_documents WHERE id='50000000-0000-0000-0000-000000000012'),
  'stock: refused invoice untouched');
SELECT pg_temp.assert_true(
  (SELECT qty=7 FROM hasad.stock_levels
   WHERE company_id='20000000-0000-0000-0000-000000000001'
     AND product_id='42000000-0000-0000-0000-000000000001'
     AND warehouse_id='41000000-0000-0000-0000-000000000001'),
  'stock: quantity rolled back');
SELECT pg_temp.assert_true(
  (SELECT count(*)=2 FROM hasad.stock_movements WHERE company_id='20000000-0000-0000-0000-000000000001'),
  'stock: no movement left behind');
SELECT pg_temp.assert_true(
  (SELECT next_value=3 FROM hasad.doc_numbers
   WHERE document_type_id='44000000-0000-0000-0000-000000000001'
     AND fiscal_year_id='45000000-0000-0000-0000-000000000001'),
  'stock: failed post consumes no invoice number');
SELECT pg_temp.assert_true(
  (SELECT next_value=3 FROM hasad.doc_numbers
   WHERE document_type_id='44000000-0000-0000-0000-000000000002'
     AND fiscal_year_id='45000000-0000-0000-0000-000000000001'),
  'stock: failed post consumes no journal number');
SELECT pg_temp.assert_true(
  (SELECT count(*)=2 FROM hasad.journal_entries WHERE company_id='20000000-0000-0000-0000-000000000001'),
  'stock: no journal left behind');
COMMIT;

-- ------------------------------------- 9. tax catalogue is the only blocker --
BEGIN;
INSERT INTO hasad.tax_rates (id,company_id,code,rate,valid_from) VALUES
  ('49000000-0000-0000-0000-000000000002','20000000-0000-0000-0000-000000000001','TEST5',5.000,'2026-01-01');
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', '{"sub":"10000000-0000-0000-0000-000000000002"}', true);
SELECT set_config('hasad_test.post_result', hasad.post_sales_invoice(
  '20000000-0000-0000-0000-000000000001',
  '50000000-0000-0000-0000-000000000014',
  '51000000-0000-0000-0000-000000000014')::text, true);
RESET ROLE;
SELECT pg_temp.assert_true(current_setting('hasad_test.post_result')::jsonb->>'doc_no' = 'SI-2026-0003', 'rate: posting proceeds once the rate exists');
SELECT pg_temp.assert_true(current_setting('hasad_test.post_result')::jsonb->>'journal_entry_no' = 'JE-2026-0003', 'rate: journal numbering stays in sequence');
SELECT pg_temp.assert_true(
  (SELECT net=10.00 AND tax=0.50 AND gross=10.50 FROM hasad.sales_documents
   WHERE id='50000000-0000-0000-0000-000000000014'),
  'rate: invoice totals preserved');
SELECT pg_temp.assert_true(
  (SELECT credit=0.50 FROM hasad.journal_lines WHERE account_id='47000000-0000-0000-0000-000000000003'
     AND entry_id=(SELECT id FROM hasad.journal_entries
       WHERE idempotency_key='51000000-0000-0000-0000-000000000014')),
  'rate: VAT leg uses the catalogued rate');
COMMIT;

-- ------------------------------------- 10. audit trail completeness ----------
SELECT pg_temp.assert_true(
  (SELECT count(*)=3 FROM hasad.audit_log WHERE action='sale.invoice_posted'),
  'audit: one posting event per posted invoice');
SELECT pg_temp.assert_true(
  (SELECT count(*)=3 FROM hasad.audit_log WHERE action='number.issued'),
  'audit: one number event per posted invoice');
SELECT pg_temp.assert_true(
  (SELECT count(*)=3 FROM hasad.audit_log WHERE action='stock.posted'),
  'audit: one stock event per issued line');
SELECT pg_temp.assert_true(
  (SELECT bool_and(actor_user_id IN (
     '10000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000002'))
   FROM hasad.audit_log WHERE action IN ('sale.invoice_posted','number.issued','stock.posted')),
  'audit: actor always comes from the request context');
SELECT pg_temp.assert_true(
  (SELECT count(*)=6 FROM hasad.sales_documents WHERE status='draft'),
  'final: only the reserved drafts remain unposted');

SELECT 'PASS: S3 sales posting atomic harness' AS result;
