\set ON_ERROR_STOP on
DO $$ DECLARE n integer; schemas text[]; setting text; BEGIN
  SELECT count(*) INTO n FROM pg_class WHERE oid IN (
   'hasad.user_profiles'::regclass,'hasad.companies'::regclass,'hasad.roles'::regclass,
   'hasad.company_memberships'::regclass,'hasad.company_settings'::regclass,
   'hasad.permissions'::regclass,'hasad.role_permissions'::regclass,
   'hasad.user_permission_overrides'::regclass,'hasad.products'::regclass)
   AND relrowsecurity AND relforcerowsecurity;
  IF n <> 9 THEN RAISE EXCEPTION 'ASSERT_FORCE_RLS_FAILED'; END IF;
  IF (SELECT rolsuper OR rolbypassrls FROM pg_roles WHERE rolname='hasad_rpc_owner') THEN
    RAISE EXCEPTION 'ASSERT_RPC_OWNER_BYPASS_FAILED';
  END IF;
  IF (SELECT r.rolname='hasad_rpc_owner' FROM pg_class c JOIN pg_roles r ON r.oid=c.relowner
      WHERE c.oid='hasad.products'::regclass) THEN RAISE EXCEPTION 'ASSERT_TABLE_OWNERSHIP_FAILED'; END IF;
  IF EXISTS (
    SELECT 1 FROM pg_class c JOIN pg_namespace ns ON ns.oid=c.relnamespace
    CROSS JOIN LATERAL aclexplode(COALESCE(c.relacl,acldefault('r',c.relowner))) a
    WHERE ns.nspname='hasad' AND c.relkind IN ('r','p')
      AND a.grantee IN ('authenticated'::regrole,'anon'::regrole)
      AND a.privilege_type IN ('SELECT','INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER')) THEN
    RAISE EXCEPTION 'ASSERT_DIRECT_TABLE_GRANTS_FAILED';
  END IF;
  IF has_function_privilege('anon','hasad_api.whoami()','EXECUTE')
     OR has_function_privilege('anon','hasad_api.products_list()','EXECUTE') THEN
    RAISE EXCEPTION 'ASSERT_ANON_EXECUTE_FAILED';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_proc p
    CROSS JOIN LATERAL aclexplode(COALESCE(p.proacl,acldefault('f',p.proowner))) a
    WHERE p.oid IN ('hasad_api.whoami()'::regprocedure,'hasad_api.products_list()'::regprocedure)
      AND a.grantee=0 AND a.privilege_type='EXECUTE') THEN
    RAISE EXCEPTION 'ASSERT_PUBLIC_EXECUTE_FAILED';
  END IF;
  SELECT regexp_replace(cfg.config, '^pgrst.db_schemas=', '') INTO setting
    FROM pg_db_role_setting s JOIN pg_roles r ON r.oid=s.setrole
    CROSS JOIN LATERAL unnest(s.setconfig) AS cfg(config)
    WHERE r.rolname='authenticator' AND cfg.config LIKE 'pgrst.db_schemas=%' LIMIT 1;
  schemas := string_to_array(trim(both '"' from trim(both '''' from setting)),',');
  IF schemas IS NULL OR NOT ('hasad_api'=ANY(schemas)) OR 'hasad'=ANY(schemas) THEN
    RAISE EXCEPTION 'ASSERT_POSTGREST_SCHEMA_EXPOSURE_FAILED';
  END IF;
END $$;
SELECT 'PASS: FORCE RLS, constrained owner, no direct table grants, anon/PUBLIC denial, PostgREST schema exposure';

DO $$ BEGIN
  BEGIN
    INSERT INTO hasad.company_memberships(id,company_id,user_id,role_id,is_owner,status,revoked_at)
      SELECT '30000000-0000-0000-0000-000000000099',
       '10000000-0000-0000-0000-000000000002',user_id,
       '20000000-0000-0000-0000-000000000002',false,'active',null
      FROM hasad.company_memberships WHERE id='30000000-0000-0000-0000-000000000001';
    RAISE EXCEPTION 'ASSERT_MULTIPLE_MEMBERSHIP_ACCEPTED';
  EXCEPTION WHEN unique_violation THEN NULL;
  END;
END $$;
SELECT 'PASS: UNIQUE(user_id) rejects a second company membership';
