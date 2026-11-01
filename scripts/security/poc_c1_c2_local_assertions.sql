-- Hasad ERP V2 C1/C2 local disposable PoC — structural assertions
-- Target: the disposable local test database only. Never run on DEV.

\set ON_ERROR_STOP on

SELECT poc.assert(
  (SELECT count(*)
   FROM pg_class c
   JOIN pg_namespace n ON n.oid = c.relnamespace
   WHERE n.nspname = 'hasad'
     AND c.relkind IN ('r', 'p')
     AND c.relname IN (
       'user_profiles', 'companies', 'roles', 'company_memberships',
       'permissions', 'role_permissions', 'user_permission_overrides'
     )
     AND c.relrowsecurity AND c.relforcerowsecurity) = 7,
  'all 7 V2 tables must have ENABLE + FORCE RLS'
);

SELECT poc.assert(
  (SELECT count(*)
   FROM pg_constraint con
   WHERE con.contype = 'f'
     AND con.conrelid IN (
       'hasad.role_permissions'::regclass,
       'hasad.user_permission_overrides'::regclass
     )
     AND con.confdeltype = 'r') = 4,
  'exactly 4 restrictive permission-foundation FKs'
);

SELECT poc.assert(
  (SELECT count(*) FROM hasad.permissions) = 37,
  'exactly 37 catalogue rows'
);

SELECT poc.assert(
  NOT EXISTS (
    SELECT 1
    FROM information_schema.role_table_grants
    WHERE table_schema IN ('hasad', 'poc')
      AND grantee IN ('anon', 'authenticated')
  ),
  'no direct table grants to anon or authenticated'
);

SELECT poc.assert(
  NOT EXISTS (
    SELECT 1
    FROM pg_policies
    WHERE schemaname IN ('hasad', 'poc')
      AND roles && ARRAY['anon', 'authenticated', 'public']::name[]
  ),
  'no RLS policy targets anon, authenticated, or public'
);

SELECT poc.assert(
  NOT has_schema_privilege('authenticated', 'hasad', 'USAGE'),
  'authenticated has no USAGE on the private hasad schema'
);

SELECT poc.assert(
  has_schema_privilege('authenticated', 'hasad_api', 'USAGE'),
  'authenticated has USAGE on hasad_api'
);

SELECT poc.assert(
  NOT has_schema_privilege('anon', 'hasad_api', 'USAGE'),
  'anon has no USAGE on hasad_api'
);

SELECT poc.assert(
  NOT has_function_privilege(
    'authenticated', 'hasad.has_permission(uuid,text)', 'EXECUTE'
  ),
  'authenticated cannot execute the internal resolver'
);

SELECT poc.assert(
  NOT has_function_privilege(
    'anon', 'hasad_api.poc_get_my_company()', 'EXECUTE'
  ),
  'anon cannot execute the test RPC'
);

SELECT poc.assert(
  has_function_privilege(
    'authenticated', 'hasad_api.poc_get_my_company()', 'EXECUTE'
  ),
  'authenticated can execute the test RPC'
);

SELECT poc.assert(
  (SELECT NOT rolsuper AND NOT rolbypassrls AND NOT rolcreaterole AND NOT rolcreatedb
   FROM pg_roles
   WHERE rolname = 'hasad_poc_owner'),
  'hasad_poc_owner is a locked non-superuser role'
);

SELECT poc.assert(
  (SELECT count(*)
   FROM pg_proc p
   JOIN pg_namespace n ON n.oid = p.pronamespace
   JOIN pg_roles r ON r.oid = p.proowner
   WHERE n.nspname = 'hasad_api'
     AND p.proname LIKE 'poc_%'
     AND p.prosecdef
     AND r.rolname = 'hasad_poc_owner'
     AND p.proconfig @> ARRAY['search_path=pg_catalog, pg_temp']) = 5,
  'all 5 test RPCs are SECURITY DEFINER, locked-owner, pinned search_path'
);

SELECT poc.assert(
  (SELECT p.prosecdef AND r.rolname = 'hasad_poc_owner'
          AND p.proconfig @> ARRAY['search_path=pg_catalog, pg_temp']
   FROM pg_proc p
   JOIN pg_namespace n ON n.oid = p.pronamespace
   JOIN pg_roles r ON r.oid = p.proowner
   WHERE n.nspname = 'hasad'
     AND p.proname = 'has_permission'),
  'internal resolver is SECURITY DEFINER, locked-owner, pinned search_path'
);

SELECT poc.assert(
  NOT EXISTS (
    SELECT 1
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    CROSS JOIN LATERAL aclexplode(
      COALESCE(p.proacl, acldefault('f', p.proowner))
    ) a
    WHERE n.nspname = 'hasad_api'
      AND a.grantee = 0
      AND a.privilege_type = 'EXECUTE'
  ),
  'no PUBLIC EXECUTE grant on hasad_api functions'
);

SELECT poc.assert(
  EXISTS (
    SELECT 1
    FROM pg_trigger
    WHERE tgrelid = 'poc.audit_log'::regclass
      AND tgname = 'audit_log_no_update_delete'
      AND NOT tgisinternal
  ),
  'audit append-only trigger exists'
);
