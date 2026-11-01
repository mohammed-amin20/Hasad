CREATE OR REPLACE FUNCTION pg_temp.assert_true(ok boolean, label text) RETURNS void
LANGUAGE plpgsql AS $$ BEGIN
  IF NOT ok THEN RAISE EXCEPTION 'FAIL: %',label; END IF;
  RAISE NOTICE 'PASS: %',label;
END $$;

SELECT pg_temp.assert_true((SELECT count(*)=1 FROM hasad.user_profiles), 'one selected Auth user received a profile');
SELECT pg_temp.assert_true((SELECT count(*)=1 FROM hasad.companies), 'one company created');
SELECT pg_temp.assert_true((SELECT count(*)=1 FROM hasad.company_settings), 'one minimum company settings row created');
SELECT pg_temp.assert_true((SELECT count(*)=1 FROM hasad.roles), 'one explicit owner role created');
SELECT pg_temp.assert_true((SELECT count(*)=1 FROM hasad.company_memberships WHERE is_owner AND status='active'), 'one active owner membership created');
SELECT pg_temp.assert_true((SELECT count(*)=1 FROM hasad.audit_log WHERE action='company.created' AND entity_type='company'), 'one company-created audit event recorded');
SELECT pg_temp.assert_true((SELECT count(*)=0 FROM hasad.role_permissions WHERE permission_code='products.read'), 'no products.read role assignment created');
SELECT pg_temp.assert_true((SELECT count(*)=0 FROM hasad.user_permission_overrides WHERE permission_code='products.read'), 'no products.read user override created');
SELECT pg_temp.assert_true((SELECT count(*)=0 FROM hasad.user_profiles WHERE id='00000000-0000-0000-0000-000000000002'::uuid), 'unselected Auth user received no profile');
SELECT pg_temp.assert_true((SELECT count(*)=0 FROM hasad.company_memberships WHERE user_id='00000000-0000-0000-0000-000000000002'::uuid), 'unselected Auth user received no membership');
SELECT pg_temp.assert_true((SELECT count(*)=9 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='hasad' AND c.relkind='r' AND c.relrowsecurity AND c.relforcerowsecurity), 'all harness hasad tables retain FORCE RLS');
