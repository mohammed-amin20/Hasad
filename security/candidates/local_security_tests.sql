\set ON_ERROR_STOP on
CREATE OR REPLACE FUNCTION pg_temp.assert_true(ok boolean, label text) RETURNS void
LANGUAGE plpgsql AS $$ BEGIN
 IF NOT ok THEN RAISE EXCEPTION 'FAIL: %',label; END IF;
 RAISE NOTICE 'PASS: %',label;
END $$;

DO $$ DECLARE n integer; s text; ctx hasad_api.company_context_dto; BEGIN
  -- Authenticated company A: company_name mapping and authorized product.
  PERFORM set_config('role','authenticated',true);
  PERFORM set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',true);
  SELECT * INTO ctx FROM hasad_api.whoami();
  IF ctx.company_id <> '10000000-0000-0000-0000-000000000001'::uuid OR ctx.company_name <> 'Company A'
    THEN RAISE EXCEPTION 'FAIL: company A context/name'; END IF;
  SELECT count(*) INTO n FROM hasad_api.products_list();
  IF n <> 1 THEN RAISE EXCEPTION 'FAIL: company A products'; END IF;
  RAISE NOTICE 'PASS: authorized company A and company_name mapping';

  -- Company B sees its own product and not A.
  PERFORM set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000002',true);
  SELECT count(*) INTO n FROM hasad_api.products_list();
  IF n <> 1 OR EXISTS (SELECT 1 FROM hasad_api.products_list() p WHERE p.company_id <> '10000000-0000-0000-0000-000000000002'::uuid)
    THEN RAISE EXCEPTION 'FAIL: company B / cross-company isolation'; END IF;
  RAISE NOTICE 'PASS: authorized company B and cross-company isolation';

  -- Missing and revoked membership.
  PERFORM set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000003',true);
  BEGIN PERFORM hasad_api.whoami(); RAISE EXCEPTION 'FAIL: missing membership accepted' USING ERRCODE='Z0001';
    EXCEPTION WHEN SQLSTATE 'P0001' THEN RAISE NOTICE 'PASS: missing membership denied'; END;
  PERFORM set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000004',true);
  BEGIN PERFORM hasad_api.products_list(); RAISE EXCEPTION 'FAIL: revoked membership accepted' USING ERRCODE='Z0001';
    EXCEPTION WHEN SQLSTATE 'P0001' THEN RAISE NOTICE 'PASS: revoked membership denied'; END;
  -- Suspended company has active membership but is denied.
  PERFORM set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000005',true);
  BEGIN PERFORM hasad_api.whoami(); RAISE EXCEPTION 'FAIL: suspended company accepted' USING ERRCODE='Z0001';
    EXCEPTION WHEN SQLSTATE 'P0001' THEN RAISE NOTICE 'PASS: suspended company denied'; END;

  -- Permission resolution: default deny, role grant, deny override, allow override.
  PERFORM set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000006',true);
  BEGIN PERFORM hasad_api.products_list(); RAISE EXCEPTION 'FAIL: missing products.read accepted';
    EXCEPTION WHEN SQLSTATE '42501' THEN RAISE NOTICE 'PASS: missing products.read denied'; END;
  PERFORM set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000007',true);
  SELECT count(*) INTO n FROM hasad_api.products_list();
  IF n <> 1 THEN RAISE EXCEPTION 'FAIL: role permission'; END IF;
  RAISE NOTICE 'PASS: role permission allow';
  PERFORM set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000008',true);
  BEGIN PERFORM hasad_api.products_list(); RAISE EXCEPTION 'FAIL: deny override ignored';
    EXCEPTION WHEN SQLSTATE '42501' THEN RAISE NOTICE 'PASS: deny override precedence'; END;
  PERFORM set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000009',true);
  SELECT count(*) INTO n FROM hasad_api.products_list();
  IF n <> 1 THEN RAISE EXCEPTION 'FAIL: allow override'; END IF;
  RAISE NOTICE 'PASS: allow override';
  PERFORM set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000010',true);
  SELECT * INTO ctx FROM hasad_api.whoami();
  IF ctx.company_id <> '10000000-0000-0000-0000-000000000001'::uuid
     OR NOT ctx.is_owner THEN RAISE EXCEPTION 'FAIL: owner company context'; END IF;
  RAISE NOTICE 'PASS: authorized owner reaches company context';
  SELECT count(*) INTO n FROM hasad_api.products_list();
  IF n <> 1 THEN RAISE EXCEPTION 'FAIL: owner precedence'; END IF;
  RAISE NOTICE 'PASS: owner permission precedence';
  PERFORM set_config('role',session_user,true);
END $$;

-- No direct hasad table grants; anon and PUBLIC cannot execute RPCs.
SELECT pg_temp.assert_true(NOT has_table_privilege('authenticated','hasad.products','SELECT'), 'authenticated direct-table denial');
SELECT pg_temp.assert_true(NOT has_table_privilege('anon','hasad.products','SELECT'), 'anon direct-table denial');
SELECT pg_temp.assert_true(NOT EXISTS (
 SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
 CROSS JOIN LATERAL aclexplode(COALESCE(c.relacl,acldefault('r',c.relowner))) a
 WHERE n.nspname='hasad' AND c.relkind IN ('r','p')
   AND a.grantee IN ('authenticated'::regrole,'anon'::regrole)
   AND a.privilege_type IN ('SELECT','INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER')),
 'no direct privileges on any hasad table for authenticated or anon');
SELECT pg_temp.assert_true(NOT has_function_privilege('anon','hasad_api.whoami()','EXECUTE'), 'anonymous RPC denial');
SELECT pg_temp.assert_true(NOT has_function_privilege('anon','hasad_api.products_list()','EXECUTE'), 'anonymous products RPC denial');
SELECT pg_temp.assert_true(has_schema_privilege('hasad_rpc_owner','auth','USAGE'), 'restricted RPC owner auth schema usage');
SELECT pg_temp.assert_true(has_schema_privilege('anon','auth','USAGE') AND has_schema_privilege('authenticated','auth','USAGE'), 'client auth schema usage preserved');
SELECT pg_temp.assert_true(has_function_privilege('anon','auth.uid()','EXECUTE') AND has_function_privilege('authenticated','auth.uid()','EXECUTE'), 'client auth.uid execute preserved');
SELECT pg_temp.assert_true(NOT has_table_privilege('anon','auth.users','SELECT') AND NOT has_table_privilege('authenticated','auth.users','SELECT'), 'client auth.users SELECT denied');
SELECT pg_temp.assert_true(NOT has_table_privilege('hasad_rpc_owner','auth.users','SELECT'), 'no auth table grant to RPC owner');
SELECT pg_temp.assert_true((SELECT count(*)=9 FROM pg_class WHERE oid IN (
 'hasad.user_profiles'::regclass,'hasad.companies'::regclass,'hasad.roles'::regclass,
 'hasad.company_memberships'::regclass,'hasad.company_settings'::regclass,
 'hasad.permissions'::regclass,'hasad.role_permissions'::regclass,
 'hasad.user_permission_overrides'::regclass,'hasad.products'::regclass)
 AND relrowsecurity AND relforcerowsecurity), 'FORCE RLS enabled on every harness table');
SELECT pg_temp.assert_true(NOT (SELECT rolbypassrls OR rolsuper FROM pg_roles WHERE rolname='hasad_rpc_owner'), 'RPC owner is not RLS bypass');
SELECT pg_temp.assert_true((SELECT r.rolname <> 'hasad_rpc_owner' FROM pg_class c JOIN pg_roles r ON r.oid=c.relowner WHERE c.oid='hasad.products'::regclass), 'RPC owner does not own hasad tables');

-- Reproduce the live unique-membership invariant as a negative test.
DO $$ BEGIN
 BEGIN
  INSERT INTO hasad.company_memberships(id,company_id,user_id,role_id,is_owner,status) VALUES
   ('30000000-0000-0000-0000-000000000099','10000000-0000-0000-0000-000000000002',
    '00000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000002',false,'active');
  RAISE EXCEPTION 'FAIL: multiple membership accepted';
 EXCEPTION WHEN unique_violation THEN RAISE NOTICE 'PASS: multiple membership rejected by UNIQUE(user_id)'; END;
END $$;
