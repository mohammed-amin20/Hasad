\set ON_ERROR_STOP on
DO $$
BEGIN
  IF has_schema_privilege('hasad_rpc_owner', 'auth', 'USAGE') THEN
    RAISE EXCEPTION 'FAIL: auth schema usage already exists before proposed grant';
  END IF;
  IF NOT has_function_privilege('hasad_rpc_owner', 'auth.uid()', 'EXECUTE') THEN
    RAISE EXCEPTION 'FAIL: restricted owner lacks auth.uid execute';
  END IF;
  IF NOT has_schema_privilege('anon', 'auth', 'USAGE')
     OR NOT has_schema_privilege('authenticated', 'auth', 'USAGE') THEN
    RAISE EXCEPTION 'FAIL: expected client auth schema usage fixture is missing';
  END IF;
  IF NOT has_function_privilege('anon', 'auth.uid()', 'EXECUTE')
     OR NOT has_function_privilege('authenticated', 'auth.uid()', 'EXECUTE') THEN
    RAISE EXCEPTION 'FAIL: expected client auth.uid execute fixture is missing';
  END IF;
  IF has_table_privilege('anon', 'auth.users', 'SELECT')
     OR has_table_privilege('authenticated', 'auth.users', 'SELECT') THEN
    RAISE EXCEPTION 'FAIL: unexpected direct client auth.users SELECT';
  END IF;
  IF has_table_privilege('hasad_rpc_owner', 'auth.users', 'SELECT') THEN
    RAISE EXCEPTION 'FAIL: unexpected direct auth table privilege';
  END IF;
  PERFORM set_config('role','authenticated',true);
  PERFORM set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',true);
  BEGIN
    PERFORM hasad_api.whoami();
    RAISE EXCEPTION 'FAIL: whoami succeeded without auth schema usage';
  EXCEPTION WHEN SQLSTATE '42501' THEN
    RAISE NOTICE 'PASS: whoami denied before proposed grant (42501)';
  END;
  BEGIN
    PERFORM hasad_api.products_list();
    RAISE EXCEPTION 'FAIL: products_list succeeded without auth schema usage';
  EXCEPTION WHEN SQLSTATE '42501' THEN
    RAISE NOTICE 'PASS: products_list denied before proposed grant (42501)';
  END;
END $$;
