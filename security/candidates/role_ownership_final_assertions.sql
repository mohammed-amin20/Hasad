CREATE OR REPLACE FUNCTION pg_temp.assert_true(ok boolean, label text) RETURNS void
LANGUAGE plpgsql AS $$ BEGIN
  IF NOT ok THEN RAISE EXCEPTION 'FAIL: %', label; END IF;
  RAISE NOTICE 'PASS: %', label;
END $$;

SELECT pg_temp.assert_true((SELECT NOT rolsuper AND rolbypassrls AND rolcreaterole AND NOT rolinherit
  FROM pg_roles WHERE rolname='migration_executor'),
  'test executor mirrors DEV: non-superuser BYPASSRLS CREATEROLE and NOINHERIT');
SELECT pg_temp.assert_true((SELECT NOT rolcanlogin AND NOT rolsuper AND NOT rolbypassrls
  AND NOT rolcreaterole AND NOT rolcreatedb AND NOT rolinherit
  FROM pg_roles WHERE rolname='hasad_rpc_owner'),
  'final RPC owner remains restricted');
SELECT pg_temp.assert_true(NOT EXISTS (
  SELECT 1 FROM pg_auth_members m
  WHERE m.roleid='hasad_rpc_owner'::regrole OR m.member='hasad_rpc_owner'::regrole),
  'no role-membership edges remain for RPC owner');
SELECT pg_temp.assert_true(NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='hasad_owner_bootstrap'),
  'disposable CREATEROLE bootstrap role was removed before commit');
SELECT pg_temp.assert_true(EXISTS (
  SELECT 1 FROM pg_auth_members m
  WHERE m.roleid='executor_existing_role'::regrole
    AND m.member='migration_executor'::regrole
    AND m.set_option AND NOT m.inherit_option AND NOT m.admin_option),
  'executor pre-existing membership is preserved unchanged');
SELECT pg_temp.assert_true((SELECT count(*)=1 FROM pg_auth_members m
  WHERE m.member='migration_executor'::regrole),
  'temporary owner membership was removed without changing executor memberships');
SELECT pg_temp.assert_true((SELECT count(*)=3 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
  JOIN pg_roles r ON r.oid=p.proowner
  WHERE r.rolname='hasad_rpc_owner' AND (n.nspname='hasad_api' OR (n.nspname='hasad' AND p.proname='has_permission'))),
  'all three intended functions are owned by restricted RPC owner');
