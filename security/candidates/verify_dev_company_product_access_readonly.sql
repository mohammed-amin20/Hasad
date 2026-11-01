-- READ ONLY post-deployment catalog verification. Does not read business rows.
DO $verify$
DECLARE expected text[] := ARRAY[
  'hasad_rpc_owner_memberships','hasad_rpc_owner_companies',
  'hasad_rpc_owner_company_settings','hasad_rpc_owner_roles',
  'hasad_rpc_owner_products_permission','hasad_rpc_owner_role_permissions',
  'hasad_rpc_owner_overrides','hasad_rpc_owner_products'];
        n integer;
BEGIN
  IF EXISTS (SELECT 1 FROM pg_class c JOIN pg_namespace s ON s.oid=c.relnamespace
    WHERE s.nspname='hasad' AND c.relkind IN ('r','p')
      AND (NOT c.relrowsecurity OR NOT c.relforcerowsecurity)) THEN
    RAISE EXCEPTION 'FAIL: hasad table lacks FORCE RLS';
  END IF;
  RAISE NOTICE 'PASS: all hasad tables retain ENABLE and FORCE RLS';

  IF EXISTS (SELECT 1 FROM pg_class c JOIN pg_namespace s ON s.oid=c.relnamespace
    WHERE s.nspname='hasad' AND c.relkind IN ('r','p') AND
      (has_table_privilege('anon',c.oid,'SELECT') OR has_table_privilege('anon',c.oid,'INSERT') OR
       has_table_privilege('anon',c.oid,'UPDATE') OR has_table_privilege('anon',c.oid,'DELETE') OR
       has_table_privilege('anon',c.oid,'TRUNCATE') OR has_table_privilege('anon',c.oid,'REFERENCES') OR has_table_privilege('anon',c.oid,'TRIGGER') OR
       has_table_privilege('authenticated',c.oid,'SELECT') OR has_table_privilege('authenticated',c.oid,'INSERT') OR
       has_table_privilege('authenticated',c.oid,'UPDATE') OR has_table_privilege('authenticated',c.oid,'DELETE') OR
       has_table_privilege('authenticated',c.oid,'TRUNCATE') OR has_table_privilege('authenticated',c.oid,'REFERENCES') OR has_table_privilege('authenticated',c.oid,'TRIGGER')))
    OR EXISTS (SELECT 1 FROM pg_class c JOIN pg_namespace s ON s.oid=c.relnamespace
      CROSS JOIN LATERAL aclexplode(COALESCE(c.relacl,acldefault('r',c.relowner))) a
      WHERE s.nspname='hasad' AND c.relkind IN ('r','p') AND a.grantee=0
        AND a.privilege_type IN ('SELECT','INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER')) THEN
    RAISE EXCEPTION 'FAIL: direct hasad table privilege exists for client/PUBLIC';
  END IF;
  RAISE NOTICE 'PASS: anon, authenticated, and PUBLIC have no direct hasad table access';

  IF has_schema_privilege('authenticated','hasad','USAGE')
     OR has_schema_privilege('anon','hasad','USAGE')
     OR has_schema_privilege('anon','hasad_api','USAGE')
     OR NOT has_schema_privilege('authenticated','hasad_api','USAGE')
     OR has_schema_privilege('authenticated','hasad_api','CREATE')
     OR has_schema_privilege('anon','hasad_api','CREATE')
     OR has_schema_privilege('hasad_rpc_owner','hasad','CREATE')
     OR has_schema_privilege('hasad_rpc_owner','hasad_api','CREATE') THEN
    RAISE EXCEPTION 'FAIL: unexpected client/owner schema privilege';
  END IF;
  RAISE NOTICE 'PASS: private schema remains inaccessible; API has no anon USAGE or lingering CREATE';

  SELECT count(*) INTO n FROM pg_roles WHERE rolname='hasad_rpc_owner'
    AND NOT rolcanlogin AND NOT rolsuper AND NOT rolbypassrls AND NOT rolcreatedb
    AND NOT rolcreaterole AND NOT rolinherit;
  IF n<>1 THEN RAISE EXCEPTION 'FAIL: restricted execution owner attributes'; END IF;
  IF EXISTS (SELECT 1 FROM pg_class c JOIN pg_namespace s ON s.oid=c.relnamespace
    WHERE s.nspname='hasad' AND c.relkind IN ('r','p') AND pg_get_userbyid(c.relowner)='hasad_rpc_owner') THEN
    RAISE EXCEPTION 'FAIL: execution owner owns hasad table';
  END IF;
  RAISE NOTICE 'PASS: restricted NOLOGIN/NOBYPASSRLS owner owns no hasad tables';

  IF (SELECT count(*) FROM pg_policies WHERE schemaname='hasad')<>cardinality(expected)
    OR EXISTS (SELECT 1 FROM unnest(expected) x(name)
      WHERE NOT EXISTS (SELECT 1 FROM pg_policies p WHERE p.schemaname='hasad' AND p.policyname=x.name)) THEN
    RAISE EXCEPTION 'FAIL: expected RLS policy set differs';
  END IF;
  RAISE NOTICE 'PASS: exactly eight candidate policies exist';

  IF (SELECT count(*) FROM pg_proc p JOIN pg_namespace s ON s.oid=p.pronamespace WHERE s.nspname='hasad_api')<>2
    OR NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace s ON s.oid=p.pronamespace WHERE s.nspname='hasad_api' AND p.proname='whoami' AND p.pronargs=0 AND p.prosecdef AND pg_get_userbyid(p.proowner)='hasad_rpc_owner' AND p.proconfig @> ARRAY['search_path=pg_catalog, pg_temp'])
    OR NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace s ON s.oid=p.pronamespace WHERE s.nspname='hasad_api' AND p.proname='products_list' AND p.pronargs=0 AND p.prosecdef AND pg_get_userbyid(p.proowner)='hasad_rpc_owner' AND p.proconfig @> ARRAY['search_path=pg_catalog, pg_temp'])
    OR NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace s ON s.oid=p.pronamespace WHERE s.nspname='hasad' AND p.proname='has_permission' AND NOT p.prosecdef AND pg_get_userbyid(p.proowner)='hasad_rpc_owner' AND p.proconfig @> ARRAY['search_path=pg_catalog, pg_temp']) THEN
    RAISE EXCEPTION 'FAIL: API/internal function definition, owner, or search_path differs';
  END IF;
  RAISE NOTICE 'PASS: exact two SECURITY DEFINER RPCs and private SECURITY INVOKER resolver verified';

  IF EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace s ON s.oid=p.pronamespace
    CROSS JOIN LATERAL aclexplode(COALESCE(p.proacl,acldefault('f',p.proowner))) a
    WHERE (s.nspname='hasad_api' AND p.proname IN ('whoami','products_list'))
      AND a.privilege_type='EXECUTE' AND a.grantee NOT IN (p.proowner,'authenticated'::regrole))
    OR EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace s ON s.oid=p.pronamespace
      WHERE s.nspname='hasad_api' AND p.proname IN ('whoami','products_list')
        AND NOT has_function_privilege('authenticated',p.oid,'EXECUTE')) THEN
    RAISE EXCEPTION 'FAIL: API function EXECUTE ACL differs';
  END IF;
  RAISE NOTICE 'PASS: only function owner and authenticated have RPC EXECUTE; authenticated can execute both';

  IF EXISTS (SELECT 1 FROM pg_type t JOIN pg_namespace s ON s.oid=t.typnamespace
    CROSS JOIN LATERAL aclexplode(COALESCE(t.typacl,acldefault('T',t.typowner))) a
    WHERE s.nspname='hasad_api' AND t.typname IN ('company_context_dto','product_dto')
      AND a.privilege_type='USAGE' AND a.grantee NOT IN (t.typowner,'authenticated'::regrole))
    OR EXISTS (SELECT 1 FROM pg_type t JOIN pg_namespace s ON s.oid=t.typnamespace
      WHERE s.nspname='hasad_api' AND t.typname IN ('company_context_dto','product_dto')
        AND NOT has_type_privilege('authenticated',t.oid,'USAGE')) THEN
    RAISE EXCEPTION 'FAIL: API type USAGE ACL differs';
  END IF;
  RAISE NOTICE 'PASS: return types usable by authenticated only (besides owner)';

  IF NOT EXISTS (SELECT 1 FROM hasad.permissions WHERE code='products.read' AND module='products')
    OR EXISTS (SELECT 1 FROM hasad.role_permissions WHERE permission_code='products.read')
    OR EXISTS (SELECT 1 FROM hasad.user_permission_overrides WHERE permission_code='products.read') THEN
    RAISE EXCEPTION 'FAIL: products.read missing or assigned';
  END IF;
  RAISE NOTICE 'PASS: products.read catalogue exists with no role or user assignments';
END
$verify$;
