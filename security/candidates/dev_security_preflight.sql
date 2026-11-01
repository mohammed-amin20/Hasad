-- READ ONLY. Catalog/permission metadata only; never selects employee, Auth, or business rows.
SELECT jsonb_build_object(
  'target', jsonb_build_object(
    'database', current_database(), 'query_role', current_user,
    'server_version', current_setting('server_version')),
  'schemas', (
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
      'name',n.nspname,'owner',pg_get_userbyid(n.nspowner),
      'authenticated_usage',has_schema_privilege('authenticated',n.oid,'USAGE'),
      'anon_usage',has_schema_privilege('anon',n.oid,'USAGE')
    ) ORDER BY n.nspname),'[]'::jsonb)
    FROM pg_namespace n WHERE n.nspname IN ('hasad','hasad_api')),
  'application_roles', (
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
      'name',rolname,'superuser',rolsuper,'inherit',rolinherit,
      'create_role',rolcreaterole,'create_db',rolcreatedb,
      'login',rolcanlogin,'bypass_rls',rolbypassrls
    ) ORDER BY rolname),'[]'::jsonb)
    FROM pg_roles WHERE rolname IN ('postgres','authenticator','anon','authenticated','service_role','hasad_rpc_owner')),
  'application_role_memberships', (
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
      'member',member_role.rolname,'granted_role',granted_role.rolname,
      'admin_option',m.admin_option,'inherit_option',m.inherit_option
    ) ORDER BY member_role.rolname,granted_role.rolname),'[]'::jsonb)
    FROM pg_auth_members m
    JOIN pg_roles member_role ON member_role.oid=m.member
    JOIN pg_roles granted_role ON granted_role.oid=m.roleid
    WHERE member_role.rolname IN ('anon','authenticated','hasad_rpc_owner')
       OR granted_role.rolname IN ('anon','authenticated','hasad_rpc_owner')),
  'tables_rls', (
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
      'table',c.relname,'owner',pg_get_userbyid(c.relowner),
      'rls',c.relrowsecurity,'force_rls',c.relforcerowsecurity
    ) ORDER BY c.relname),'[]'::jsonb)
    FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
    WHERE n.nspname='hasad' AND c.relkind IN ('r','p')),
  'api_relations', (
    SELECT COALESCE(jsonb_agg(c.relname ORDER BY c.relname),'[]'::jsonb)
    FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
    WHERE n.nspname='hasad_api' AND c.relkind IN ('r','p','v','m','S')),
  'api_contract_columns', (
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
      'table',c.table_name,'column',c.column_name,'type',c.data_type,'nullable',c.is_nullable
    ) ORDER BY c.table_name,c.ordinal_position),'[]'::jsonb)
    FROM information_schema.columns c
    WHERE c.table_schema='hasad' AND c.table_name IN (
      'companies','company_settings','company_memberships','roles','permissions',
      'role_permissions','user_permission_overrides','products')),
  'api_contract_constraints', (
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
      'table',c.relname,'name',con.conname,'type',con.contype,'definition',pg_get_constraintdef(con.oid)
    ) ORDER BY c.relname,con.conname),'[]'::jsonb)
    FROM pg_constraint con JOIN pg_class c ON c.oid=con.conrelid
    JOIN pg_namespace n ON n.oid=c.relnamespace
    WHERE n.nspname='hasad' AND c.relname IN (
      'companies','company_settings','company_memberships','roles','permissions',
      'role_permissions','user_permission_overrides','products')),
  'application_table_grants', (
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
      'schema',n.nspname,'object',c.relname,
      'grantee',CASE WHEN a.grantee=0 THEN 'PUBLIC' ELSE r.rolname END,
      'privilege',a.privilege_type,'grantable',a.is_grantable
    ) ORDER BY n.nspname,c.relname,grantee,a.privilege_type),'[]'::jsonb)
    FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
    CROSS JOIN LATERAL aclexplode(COALESCE(c.relacl,acldefault((CASE WHEN c.relkind='S' THEN 'S' ELSE 'r' END)::"char",c.relowner))) a
    LEFT JOIN pg_roles r ON r.oid=a.grantee
    WHERE n.nspname IN ('hasad','hasad_api')
      AND (a.grantee=0 OR r.rolname IN ('anon','authenticated','service_role','hasad_rpc_owner'))),
  'policies', (
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
      'table',tablename,'name',policyname,'mode',permissive,'roles',roles,
      'command',cmd,'using',qual,'check',with_check
    ) ORDER BY tablename,policyname),'[]'::jsonb)
    FROM pg_policies WHERE schemaname='hasad'),
  'functions', (
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
      'schema',n.nspname,'name',p.proname,
      'arguments',pg_get_function_identity_arguments(p.oid),
      'result',pg_get_function_result(p.oid),'security_definer',p.prosecdef,
      'owner',pg_get_userbyid(p.proowner),'settings',p.proconfig,
      'authenticated_execute',has_function_privilege('authenticated',p.oid,'EXECUTE'),
      'anon_execute',has_function_privilege('anon',p.oid,'EXECUTE'),
      'public_execute',EXISTS(SELECT 1 FROM aclexplode(COALESCE(p.proacl,acldefault('f',p.proowner))) x WHERE x.grantee=0 AND x.privilege_type='EXECUTE')
    ) ORDER BY n.nspname,p.proname),'[]'::jsonb)
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname IN ('hasad_api','hasad')),
  'api_named_types', (
    SELECT COALESCE(jsonb_agg(t.typname ORDER BY t.typname),'[]'::jsonb)
    FROM pg_type t JOIN pg_namespace n ON n.oid=t.typnamespace
    WHERE n.nspname='hasad_api' AND t.typrelid=0 AND t.typtype IN ('c','d','e','r','m')),
  'postgrest_schema_settings', (
    SELECT COALESCE(jsonb_agg(jsonb_build_object('role',role_name,'setting',setting) ORDER BY role_name,setting),'[]'::jsonb) FROM (
      SELECT r.rolname AS role_name,cfg.setting FROM pg_roles r
      CROSS JOIN LATERAL unnest(COALESCE(r.rolconfig,ARRAY[]::text[])) cfg(setting)
      WHERE cfg.setting LIKE 'pgrst.db_schemas=%'
      UNION
      SELECT COALESCE(r.rolname,'DATABASE') AS role_name,cfg.setting
      FROM pg_db_role_setting s LEFT JOIN pg_roles r ON r.oid=s.setrole
      CROSS JOIN LATERAL unnest(s.setconfig) cfg(setting)
      WHERE cfg.setting LIKE 'pgrst.db_schemas=%'
    ) settings),
  'products_read_catalogue', (
    SELECT COALESCE(jsonb_agg(jsonb_build_object('code',code,'module',module,'description',description)),'[]'::jsonb)
    FROM hasad.permissions WHERE code='products.read'),
  'products_read_role_mappings', (
    SELECT COALESCE(jsonb_agg(jsonb_build_object('role_code',role_code,'mapping_count',mapping_count) ORDER BY role_code),'[]'::jsonb)
    FROM (
      SELECT r.code AS role_code,count(*) AS mapping_count
      FROM hasad.role_permissions rp JOIN hasad.permissions p ON p.code=rp.permission_code
      JOIN hasad.roles r ON r.id=rp.role_id WHERE p.code='products.read' GROUP BY r.code
    ) mappings),
  'products_read_override_counts', (
    SELECT COALESCE(jsonb_agg(jsonb_build_object('effect',effect,'count',override_count) ORDER BY effect),'[]'::jsonb)
    FROM (
      SELECT effect,count(*) AS override_count FROM hasad.user_permission_overrides
      WHERE permission_code='products.read' GROUP BY effect
    ) overrides),
  'migration_versions', (
    SELECT COALESCE(jsonb_agg(version ORDER BY version),'[]'::jsonb) FROM supabase_migrations.schema_migrations)
) AS dev_security_baseline;
