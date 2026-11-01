-- One SELECT only. Catalog metadata; no business or Auth rows are queried.
SELECT jsonb_build_object(
  'rpc_owner_auth_schema_usage', has_schema_privilege('hasad_rpc_owner', 'auth', 'USAGE'),
  'rpc_owner_auth_uid_execute', has_function_privilege('hasad_rpc_owner', 'auth.uid()', 'EXECUTE'),
  'rpc_owner_auth_users_select', has_table_privilege('hasad_rpc_owner', 'auth.users', 'SELECT'),
  'anon_auth_users_select', has_table_privilege('anon', 'auth.users', 'SELECT'),
  'authenticated_auth_users_select', has_table_privilege('authenticated', 'auth.users', 'SELECT'),
  'anon_auth_schema_usage', has_schema_privilege('anon', 'auth', 'USAGE'),
  'authenticated_auth_schema_usage', has_schema_privilege('authenticated', 'auth', 'USAGE'),
  'rpc_owner_role', (
    SELECT jsonb_build_object(
      'exists', true,
      'login', rolcanlogin,
      'superuser', rolsuper,
      'bypass_rls', rolbypassrls,
      'inherit', rolinherit
    ) FROM pg_roles WHERE rolname = 'hasad_rpc_owner'
  ),
  'api_rpcs', COALESCE((
    SELECT jsonb_agg(jsonb_build_object(
      'name', p.proname,
      'owner', pg_get_userbyid(p.proowner),
      'security_definer', p.prosecdef,
      'authenticated_execute', has_function_privilege('authenticated', p.oid, 'EXECUTE'),
      'anon_execute', has_function_privilege('anon', p.oid, 'EXECUTE')
    ) ORDER BY p.proname)
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'hasad_api'
      AND p.proname IN ('whoami', 'products_list')
  ), '[]'::jsonb),
  'hasad_rls', COALESCE((
    SELECT jsonb_agg(jsonb_build_object(
      'table', c.relname,
      'rls_enabled', c.relrowsecurity,
      'force_rls', c.relforcerowsecurity,
      'policy_count', (SELECT count(*) FROM pg_policy pol WHERE pol.polrelid = c.oid)
    ) ORDER BY c.relname)
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'hasad' AND c.relkind IN ('r', 'p')
  ), '[]'::jsonb)
) AS rpc_privilege_verification;
