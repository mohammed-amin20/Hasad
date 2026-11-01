\set ON_ERROR_STOP on
CREATE OR REPLACE FUNCTION pg_temp.assert_true(ok boolean,label text) RETURNS void
LANGUAGE plpgsql AS $$ BEGIN
  IF NOT ok THEN RAISE EXCEPTION 'FAIL: %',label; END IF;
  RAISE NOTICE 'PASS: %',label;
END $$;

DO $jwt_rpc_tests$
DECLARE ctx hasad_api.company_context_dto; n integer;
BEGIN
  PERFORM pg_catalog.set_config('role','authenticated',true);
  PERFORM pg_catalog.set_config('request.jwt.claim.sub','',true);
  PERFORM pg_catalog.set_config('request.jwt.claims',
    '{"sub":"00000000-0000-0000-0000-000000000010","role":"authenticated"}',true);
  SELECT * INTO ctx FROM hasad_api.whoami();
  IF ctx.company_id <> '10000000-0000-0000-0000-000000000001'::uuid OR NOT ctx.is_owner THEN
    RAISE EXCEPTION 'FAIL: JWT owner context';
  END IF;
  SELECT count(*) INTO n FROM hasad_api.products_list();
  IF n<>1 THEN RAISE EXCEPTION 'FAIL: JWT owner products'; END IF;
  RAISE NOTICE 'PASS: authenticated owner whoami and products_list';

  PERFORM pg_catalog.set_config('request.jwt.claims',
    '{"sub":"00000000-0000-0000-0000-000000000001","role":"authenticated"}',true);
  SELECT count(*) INTO n FROM hasad_api.products_list();
  IF n<>1 OR EXISTS (SELECT 1 FROM hasad_api.products_list() p
    WHERE p.company_id<>'10000000-0000-0000-0000-000000000001'::uuid) THEN
    RAISE EXCEPTION 'FAIL: cross-tenant product isolation';
  END IF;
  RAISE NOTICE 'PASS: cross-tenant product isolation';

  PERFORM pg_catalog.set_config('request.jwt.claims','',true);
  PERFORM pg_catalog.set_config('request.jwt.claim.sub',
    '00000000-0000-0000-0000-000000000010',true);
  SELECT count(*) INTO n FROM hasad_api.products_list();
  IF n<>1 THEN RAISE EXCEPTION 'FAIL: legacy JWT subject setting'; END IF;
  RAISE NOTICE 'PASS: legacy PostgREST subject setting';

  PERFORM pg_catalog.set_config('request.jwt.claims','',true);
  PERFORM pg_catalog.set_config('request.jwt.claim.sub','',true);
  BEGIN PERFORM hasad_api.whoami(); RAISE EXCEPTION 'TEST_FAIL' USING ERRCODE='ZX001';
  EXCEPTION WHEN SQLSTATE '28000' THEN RAISE NOTICE 'PASS: missing subject denied'; END;
  BEGIN PERFORM hasad_api.products_list(); RAISE EXCEPTION 'TEST_FAIL' USING ERRCODE='ZX001';
  EXCEPTION WHEN SQLSTATE '28000' THEN RAISE NOTICE 'PASS: missing subject denied by products_list'; END;

  PERFORM pg_catalog.set_config('request.jwt.claims','not-json',true);
  BEGIN PERFORM hasad_api.whoami(); RAISE EXCEPTION 'TEST_FAIL' USING ERRCODE='ZX001';
  EXCEPTION WHEN SQLSTATE '28000' THEN RAISE NOTICE 'PASS: malformed claims JSON denied'; END;
  PERFORM pg_catalog.set_config('request.jwt.claims','{"sub":"not-a-uuid"}',true);
  BEGIN PERFORM hasad_api.products_list(); RAISE EXCEPTION 'TEST_FAIL' USING ERRCODE='ZX001';
  EXCEPTION WHEN SQLSTATE '28000' THEN RAISE NOTICE 'PASS: malformed subject denied'; END;
  PERFORM pg_catalog.set_config('request.jwt.claims','{"sub":""}',true);
  PERFORM pg_catalog.set_config('request.jwt.claim.sub','',true);
  BEGIN PERFORM hasad_api.whoami(); RAISE EXCEPTION 'TEST_FAIL' USING ERRCODE='ZX001';
  EXCEPTION WHEN SQLSTATE '28000' THEN RAISE NOTICE 'PASS: empty subject denied'; END;
  PERFORM pg_catalog.set_config('request.jwt.claims',
    '{"sub":"00000000-0000-0000-0000-000000000010"}',true);
  PERFORM pg_catalog.set_config('request.jwt.claim.sub',
    '00000000-0000-0000-0000-000000000001',true);
  BEGIN PERFORM hasad_api.whoami(); RAISE EXCEPTION 'TEST_FAIL' USING ERRCODE='ZX001';
  EXCEPTION WHEN SQLSTATE '28000' THEN RAISE NOTICE 'PASS: conflicting subject settings denied'; END;

  PERFORM pg_catalog.set_config('request.jwt.claims',
    '{"sub":"00000000-0000-0000-0000-000000000004","role":"authenticated"}',true);
  PERFORM pg_catalog.set_config('request.jwt.claim.sub','',true);
  BEGIN PERFORM hasad_api.products_list(); RAISE EXCEPTION 'TEST_FAIL' USING ERRCODE='ZX001';
  EXCEPTION WHEN SQLSTATE 'P0001' THEN RAISE NOTICE 'PASS: revoked membership denied'; END;
  PERFORM pg_catalog.set_config('request.jwt.claims',
    '{"sub":"00000000-0000-0000-0000-000000000006","role":"authenticated"}',true);
  BEGIN PERFORM hasad_api.products_list(); RAISE EXCEPTION 'TEST_FAIL' USING ERRCODE='ZX001';
  EXCEPTION WHEN SQLSTATE '42501' THEN RAISE NOTICE 'PASS: products.read default deny preserved'; END;
  PERFORM pg_catalog.set_config('request.jwt.claims',
    '{"sub":"00000000-0000-0000-0000-000000000008","role":"authenticated"}',true);
  BEGIN PERFORM hasad_api.products_list(); RAISE EXCEPTION 'TEST_FAIL' USING ERRCODE='ZX001';
  EXCEPTION WHEN SQLSTATE '42501' THEN RAISE NOTICE 'PASS: explicit deny override preserved'; END;

  PERFORM pg_catalog.set_config('role','hasad_rpc_owner',true);
  PERFORM pg_catalog.set_config('request.jwt.claims',
    '{"sub":"00000000-0000-0000-0000-000000000010","role":"authenticated"}',true);
  IF NOT hasad.has_permission('30000000-0000-0000-0000-000000000010',NULL,true,'products.read') THEN
    RAISE EXCEPTION 'FAIL: permission resolver owner precedence';
  END IF;
  PERFORM pg_catalog.set_config('request.jwt.claims',
    '{"sub":"00000000-0000-0000-0000-000000000008","role":"authenticated"}',true);
  IF hasad.has_permission('30000000-0000-0000-0000-000000000008',
      '20000000-0000-0000-0000-000000000001',false,'products.read') THEN
    RAISE EXCEPTION 'FAIL: permission resolver deny override';
  END IF;
  PERFORM pg_catalog.set_config('role','authenticated',true);
  RAISE NOTICE 'PASS: has_permission owner and deny precedence preserved';

  PERFORM pg_catalog.set_config('role','anon',true);
  PERFORM pg_catalog.set_config('request.jwt.claims','{"role":"anon"}',true);
  BEGIN PERFORM hasad_api.whoami(); RAISE EXCEPTION 'TEST_FAIL' USING ERRCODE='ZX001';
  EXCEPTION WHEN SQLSTATE '42501' THEN RAISE NOTICE 'PASS: anonymous whoami denied'; END;
  BEGIN PERFORM hasad_api.products_list(); RAISE EXCEPTION 'TEST_FAIL' USING ERRCODE='ZX001';
  EXCEPTION WHEN SQLSTATE '42501' THEN RAISE NOTICE 'PASS: anonymous products_list denied'; END;
  PERFORM pg_catalog.set_config('role',session_user,true);
END
$jwt_rpc_tests$;

SELECT pg_temp.assert_true(NOT pg_catalog.has_schema_privilege('hasad_rpc_owner','auth','USAGE'),
  'RPC owner has no auth schema USAGE');
SELECT pg_temp.assert_true(NOT pg_catalog.has_table_privilege('authenticated','auth.users','SELECT')
  AND NOT pg_catalog.has_table_privilege('anon','auth.users','SELECT'),
  'direct auth.users SELECT remains denied');
SELECT pg_temp.assert_true(NOT pg_catalog.has_function_privilege('authenticated','hasad.request_user_id()','EXECUTE')
  AND NOT pg_catalog.has_function_privilege('anon','hasad.request_user_id()','EXECUTE'),
  'JWT helper is not executable by clients');
SELECT pg_temp.assert_true(NOT pg_catalog.has_table_privilege('authenticated','hasad.products','SELECT')
  AND NOT pg_catalog.has_table_privilege('anon','hasad.products','SELECT'),
  'direct hasad table access remains denied');
SELECT pg_temp.assert_true((SELECT count(*)=47 AND count(*) FILTER
  (WHERE c.relrowsecurity AND c.relforcerowsecurity)=47
  FROM pg_catalog.pg_class c JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace
  WHERE n.nspname='hasad' AND c.relkind IN ('r','p')),
  '47 of 47 hasad tables retain FORCE RLS');
SELECT pg_temp.assert_true((SELECT count(*)=2 AND bool_and(p.pronargs=0)
  FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname='hasad_api' AND p.proname IN ('whoami','products_list')),
  'both RPC signatures remain argument-free');
SELECT pg_temp.assert_true(NOT pg_catalog.has_function_privilege('anon','hasad_api.whoami()','EXECUTE')
  AND NOT pg_catalog.has_function_privilege('anon','hasad_api.products_list()','EXECUTE'),
  'anonymous API execution remains denied');
SELECT pg_temp.assert_true(NOT EXISTS (
  SELECT 1 FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
  WHERE ((n.nspname='hasad_api' AND p.proname IN ('whoami','products_list'))
     OR (n.nspname='hasad' AND p.proname='has_permission'))
    AND p.prosrc LIKE '%auth.uid()%'
), 'all targeted function auth.uid dependencies removed');
SELECT pg_temp.assert_true((SELECT count(*)=7 FROM pg_catalog.pg_policy p
  JOIN pg_catalog.pg_class c ON c.oid=p.polrelid JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace
  WHERE n.nspname='hasad' AND c.relname IN ('company_memberships','companies','company_settings',
    'roles','role_permissions','user_permission_overrides','products')
    AND p.polcmd='r' AND 'hasad_rpc_owner'::pg_catalog.regrole=ANY(p.polroles)
    AND pg_catalog.pg_get_expr(p.polqual,p.polrelid) LIKE '%hasad.request_user_id()%'
    AND pg_catalog.pg_get_expr(p.polqual,p.polrelid) NOT LIKE '%auth.uid()%'),
  'all seven caller-scoped RLS policies use the private JWT helper');
