CREATE OR REPLACE FUNCTION pg_temp.assert_true(ok boolean, label text) RETURNS void
LANGUAGE plpgsql AS $$ BEGIN
  IF NOT ok THEN RAISE EXCEPTION 'FAIL: %', label; END IF;
  RAISE NOTICE 'PASS: %', label;
END $$;

SELECT pg_temp.assert_true(NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='hasad_rpc_owner'),
  'original-candidate failure rolled back created RPC owner');
SELECT pg_temp.assert_true(NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname IN ('hasad','hasad_api')),
  'original-candidate failure rolled back functions');
SELECT pg_temp.assert_true(NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='hasad'),
  'original-candidate failure rolled back policies');
SELECT pg_temp.assert_true(NOT EXISTS (SELECT 1 FROM hasad.permissions WHERE code='products.read'),
  'original-candidate failure rolled back permission catalogue insert');
