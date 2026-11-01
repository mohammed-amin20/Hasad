CREATE OR REPLACE FUNCTION pg_temp.assert_true(p_ok boolean, p_label text) RETURNS void LANGUAGE plpgsql AS $$ BEGIN IF p_ok IS NOT TRUE THEN RAISE EXCEPTION 'ASSERT_FAIL: %',p_label; END IF; END $$;
CREATE OR REPLACE FUNCTION pg_temp.expect_state(p_sql text,p_state text,p_label text) RETURNS void LANGUAGE plpgsql AS $$ DECLARE s text; BEGIN BEGIN EXECUTE p_sql; EXCEPTION WHEN others THEN GET STACKED DIAGNOSTICS s=RETURNED_SQLSTATE; IF s<>p_state THEN RAISE EXCEPTION 'ASSERT_FAIL: % expected %, got %',p_label,p_state,s; END IF; RETURN; END; RAISE EXCEPTION 'ASSERT_FAIL: % unexpectedly succeeded',p_label; END $$;

BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000001"}',true);
SELECT hasad.save_sales_invoice_draft('50000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001','43000000-0000-0000-0000-000000000001','2026-10-31','exclusive','44000000-0000-0000-0000-000000000001','45000000-0000-0000-0000-000000000001','51000000-0000-0000-0000-000000000001','[{"id":"52000000-0000-0000-0000-000000000001","line_no":1,"product_id":"42000000-0000-0000-0000-000000000001","warehouse_id":"41000000-0000-0000-0000-000000000001","qty":2,"unit_price":10.00,"discount_amount":1.00,"tax_rate":18.000}]'::jsonb);
RESET ROLE;
SELECT pg_temp.assert_true((SELECT status='draft' AND net=19.00 AND tax=3.42 AND gross=22.42 FROM hasad.sales_documents WHERE id='50000000-0000-0000-0000-000000000001'),'owner creates calculated draft');
SELECT pg_temp.assert_true((SELECT count(*)=1 FROM hasad.sales_document_lines WHERE document_id='50000000-0000-0000-0000-000000000001'),'atomic draft creates one line');
SELECT pg_temp.assert_true((SELECT count(*)=0 FROM hasad.stock_levels) AND (SELECT count(*)=0 FROM hasad.stock_movements),'draft has no stock effect');
SELECT pg_temp.assert_true((SELECT count(*)=1 FROM hasad.audit_log WHERE entity_id='50000000-0000-0000-0000-000000000001' AND action='sale.draft_created'),'draft creation audited once');
COMMIT;

BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000001"}',true);
SELECT pg_temp.assert_true((SELECT count(*)=1 FROM hasad.sales_documents WHERE company_id='20000000-0000-0000-0000-000000000001'),'tenant-scoped authenticated draft read works');
RESET ROLE;
COMMIT;

BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000002"}',true);
SELECT hasad.save_sales_invoice_draft('50000000-0000-0000-0000-000000000002','20000000-0000-0000-0000-000000000001','43000000-0000-0000-0000-000000000001','2026-10-31','inclusive','44000000-0000-0000-0000-000000000001','45000000-0000-0000-0000-000000000001','51000000-0000-0000-0000-000000000002','[{"id":"52000000-0000-0000-0000-000000000002","line_no":1,"product_id":"42000000-0000-0000-0000-000000000001","warehouse_id":"41000000-0000-0000-0000-000000000001","qty":1,"unit_price":118.00,"discount_amount":0,"tax_rate":18.000}]'::jsonb);
RESET ROLE;
SELECT pg_temp.assert_true((SELECT net=100.00 AND tax=18.00 AND gross=118.00 FROM hasad.sales_documents WHERE id='50000000-0000-0000-0000-000000000002'),'sales.create role creates inclusive draft');
COMMIT;

BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000003"}',true);
SELECT pg_temp.expect_state($q$SELECT hasad.save_sales_invoice_draft('50000000-0000-0000-0000-000000000003','20000000-0000-0000-0000-000000000001','43000000-0000-0000-0000-000000000001','2026-10-31','exclusive','44000000-0000-0000-0000-000000000001','45000000-0000-0000-0000-000000000001','51000000-0000-0000-0000-000000000003','[]'::jsonb)$q$,'42501','user without sales.create denied');
RESET ROLE;
COMMIT;

BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000001"}',true);
SELECT pg_temp.expect_state($q$SELECT hasad.save_sales_invoice_draft('50000000-0000-0000-0000-000000000004','20000000-0000-0000-0000-000000000001','43000000-0000-0000-0000-000000000002','2026-10-31','exclusive','44000000-0000-0000-0000-000000000001','45000000-0000-0000-0000-000000000001','51000000-0000-0000-0000-000000000004','[{"id":"52000000-0000-0000-0000-000000000004","line_no":1,"qty":1,"unit_price":1,"discount_amount":0,"tax_rate":0}]'::jsonb)$q$,'23514','cross-company party denied');
RESET ROLE;
SELECT pg_temp.assert_true((SELECT count(*)=0 FROM hasad.sales_documents WHERE id='50000000-0000-0000-0000-000000000004'),'failed request rolls back header');
COMMIT;

BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000001"}',true);
SELECT pg_temp.expect_state($q$SELECT hasad.save_sales_invoice_draft('50000000-0000-0000-0000-000000000005','20000000-0000-0000-0000-000000000001','43000000-0000-0000-0000-000000000001','2027-01-01','exclusive','44000000-0000-0000-0000-000000000001','45000000-0000-0000-0000-000000000001','51000000-0000-0000-0000-000000000005','[{"id":"52000000-0000-0000-0000-000000000005","line_no":1,"qty":1,"unit_price":1,"discount_amount":0,"tax_rate":0}]'::jsonb)$q$,'23514','document date outside fiscal year denied');
RESET ROLE;
SELECT pg_temp.assert_true((SELECT count(*)=0 FROM hasad.sales_documents WHERE id='50000000-0000-0000-0000-000000000005'),'out-of-year request rolls back header');
COMMIT;

SELECT 'PASS: S2 sales draft atomic harness' AS result;
