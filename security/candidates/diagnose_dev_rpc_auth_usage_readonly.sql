-- Read-only catalog diagnostic for the failed grant attempt.
-- Does not read business rows, Auth rows, credentials, or user identifiers.
WITH role_state AS (
  SELECT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'hasad_rpc_owner') AS role_exists,
    EXISTS (
    SELECT 1 FROM pg_roles r WHERE r.rolname = 'hasad_rpc_owner'
      AND NOT r.rolcanlogin AND NOT r.rolsuper AND NOT r.rolbypassrls
      AND NOT r.rolinherit
  ) AS restricted_role_ok
), auth_uid_state AS (
  SELECT to_regprocedure('auth.uid()') IS NOT NULL AS function_exists
), executor_state AS (
  SELECT
    r.rolsuper AS executor_is_superuser,
    n.nspowner = r.oid AS executor_is_auth_schema_owner,
    pg_has_role(current_user, n.nspowner, 'USAGE') AS executor_in_auth_schema_owner_role,
    EXISTS (
      SELECT 1
      FROM aclexplode(COALESCE(n.nspacl, acldefault('n', n.nspowner))) acl
      WHERE acl.privilege_type = 'USAGE'
        AND acl.is_grantable
        AND (acl.grantee = 0 OR pg_has_role(current_user, acl.grantee, 'USAGE'))
    ) AS executor_has_auth_usage_grant_option
  FROM pg_roles r CROSS JOIN pg_namespace n
  WHERE r.rolname = current_user AND n.nspname = 'auth'
), candidate_executor_state AS (
  SELECT
    r.rolsuper AS executor_is_superuser,
    pg_catalog.has_schema_privilege(current_user,'hasad','CREATE') AS hasad_schema_create,
    pg_catalog.has_schema_privilege(current_user,'hasad_api','CREATE') AS api_schema_create,
    pg_catalog.pg_has_role(current_user,'hasad_rpc_owner','MEMBER') AS can_assign_helper_owner,
    EXISTS (
      SELECT 1 FROM pg_catalog.pg_namespace ns
      WHERE ns.nspname='hasad'
        AND (ns.nspowner=r.oid OR EXISTS (
          SELECT 1 FROM pg_catalog.aclexplode(COALESCE(ns.nspacl,pg_catalog.acldefault('n',ns.nspowner))) acl
          WHERE acl.privilege_type='CREATE' AND acl.is_grantable
            AND (acl.grantee=0 OR pg_catalog.pg_has_role(current_user,acl.grantee,'USAGE'))
        ))
    ) AS can_grant_and_revoke_helper_create,
    NOT EXISTS (
      SELECT 1 FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace ns ON ns.oid=p.pronamespace
      WHERE ns.nspname='hasad_api' AND p.proname IN ('whoami','products_list') AND p.pronargs=0
        AND (p.proowner <> 'hasad_rpc_owner'::pg_catalog.regrole OR NOT p.prosecdef
          OR NOT pg_catalog.pg_has_role(current_user,p.proowner,'USAGE'))
    ) AND pg_catalog.has_schema_privilege(current_user,'hasad_api','CREATE') AS can_replace_api_functions,
    NOT EXISTS (
      SELECT 1 FROM pg_catalog.pg_policy p JOIN pg_catalog.pg_class c ON c.oid=p.polrelid
      JOIN pg_catalog.pg_namespace ns ON ns.oid=c.relnamespace
      WHERE ns.nspname='hasad' AND c.relname IN ('company_memberships','companies','company_settings',
        'roles','role_permissions','user_permission_overrides','products')
        AND p.polcmd='r' AND 'hasad_rpc_owner'::pg_catalog.regrole=ANY(p.polroles)
        AND pg_catalog.pg_get_expr(p.polqual,p.polrelid) LIKE '%auth.uid()%'
        AND NOT pg_catalog.pg_has_role(current_user,c.relowner,'USAGE')
    ) AS can_alter_auth_uid_policies
  FROM pg_catalog.pg_roles r WHERE r.rolname=current_user
), rpc_state AS (
  SELECT
    count(*) AS rpc_count,
    count(*) FILTER (WHERE p.proname = 'whoami'
      AND pg_get_userbyid(p.proowner) = 'hasad_rpc_owner' AND p.prosecdef) AS whoami_ok,
    count(*) FILTER (WHERE p.proname = 'products_list'
      AND pg_get_userbyid(p.proowner) = 'hasad_rpc_owner' AND p.prosecdef) AS products_list_ok,
    bool_or(has_function_privilege('anon', p.oid, 'EXECUTE')) AS anon_execute_any
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'hasad_api' AND p.proname IN ('whoami', 'products_list')
), rls_state AS (
  SELECT count(*) AS table_count,
    count(*) FILTER (WHERE c.relrowsecurity AND c.relforcerowsecurity) AS force_rls_count,
    count(*) FILTER (WHERE NOT c.relrowsecurity OR NOT c.relforcerowsecurity) AS unprotected_count
  FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'hasad' AND c.relkind IN ('r', 'p')
), auth_users_state AS (
  SELECT to_regclass('auth.users') IS NOT NULL AS table_exists,
    CASE WHEN to_regclass('auth.users') IS NULL OR NOT (SELECT role_exists FROM role_state) THEN NULL
      ELSE has_table_privilege('hasad_rpc_owner', 'auth.users', 'SELECT') END AS owner_select,
    CASE WHEN to_regclass('auth.users') IS NULL THEN NULL
      ELSE has_table_privilege('anon', 'auth.users', 'SELECT') END AS anon_select,
    CASE WHEN to_regclass('auth.users') IS NULL THEN NULL
      ELSE has_table_privilege('authenticated', 'auth.users', 'SELECT') END AS authenticated_select
), identity_dependency_state AS (
  SELECT
    count(*) FILTER (WHERE ns.nspname='hasad_api' AND p.proname IN ('whoami','products_list')
      AND p.pronargs=0 AND p.prosrc LIKE '%auth.uid()%') AS api_auth_uid_count,
    count(*) FILTER (WHERE ns.nspname='hasad' AND p.proname='has_permission'
      AND p.proargtypes='2950 2950 16 25'::pg_catalog.oidvector
      AND p.prosrc LIKE '%auth.uid()%') AS resolver_auth_uid_count
  FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace ns ON ns.oid=p.pronamespace
), policy_identity_state AS (
  SELECT count(*) AS auth_uid_policy_count
  FROM pg_catalog.pg_policy p JOIN pg_catalog.pg_class c ON c.oid=p.polrelid
  JOIN pg_catalog.pg_namespace ns ON ns.oid=c.relnamespace
  WHERE ns.nspname='hasad' AND c.relname IN ('company_memberships','companies','company_settings',
    'roles','role_permissions','user_permission_overrides','products')
    AND p.polcmd='r' AND 'hasad_rpc_owner'::pg_catalog.regrole=ANY(p.polroles)
    AND pg_catalog.pg_get_expr(p.polqual,p.polrelid) LIKE '%auth.uid()%'
), candidate_state AS (
  SELECT
    (SELECT api_auth_uid_count FROM identity_dependency_state)=2
      AND (SELECT auth_uid_policy_count FROM policy_identity_state)=7
      AND (SELECT resolver_auth_uid_count FROM identity_dependency_state) IN (0,1)
      AND (SELECT count(*) FROM pg_catalog.pg_class c JOIN pg_catalog.pg_namespace ns ON ns.oid=c.relnamespace
        WHERE ns.nspname='hasad' AND c.relkind IN ('r','p'))=47
      AND (SELECT count(*) FROM pg_catalog.pg_class c JOIN pg_catalog.pg_namespace ns ON ns.oid=c.relnamespace
        WHERE ns.nspname='hasad' AND c.relkind IN ('r','p') AND c.relrowsecurity AND c.relforcerowsecurity)=47
      AND NOT pg_catalog.has_schema_privilege('hasad_rpc_owner','auth','USAGE')
      AND NOT EXISTS (SELECT 1 FROM pg_catalog.pg_roles WHERE rolname='hasad_rpc_owner'
        AND (rolcanlogin OR rolsuper OR rolbypassrls OR rolinherit))
      AND (SELECT executor_is_superuser OR (hasad_schema_create AND api_schema_create
        AND can_assign_helper_owner AND can_grant_and_revoke_helper_create
        AND can_replace_api_functions AND can_alter_auth_uid_policies)
        FROM candidate_executor_state) AS candidate_executor_preconditions
)
SELECT jsonb_build_object(
  'executor_authority', jsonb_build_object(
    'executor_is_superuser', COALESCE((SELECT executor_is_superuser FROM executor_state), false),
    'executor_is_auth_schema_owner', COALESCE((SELECT executor_is_auth_schema_owner FROM executor_state), false),
    'executor_in_auth_schema_owner_role', COALESCE((SELECT executor_in_auth_schema_owner_role FROM executor_state), false),
    'executor_has_auth_usage_grant_option', COALESCE((SELECT executor_has_auth_usage_grant_option FROM executor_state), false),
    'executor_can_grant_auth_usage', COALESCE((SELECT executor_is_superuser OR executor_is_auth_schema_owner
      OR executor_has_auth_usage_grant_option FROM executor_state), false)
  ),
  'jwt_claim_fix_preflight', jsonb_build_object(
    'executor_can_apply_candidate', COALESCE((SELECT candidate_executor_preconditions FROM candidate_state),false),
    'api_auth_uid_reference_count', (SELECT api_auth_uid_count FROM identity_dependency_state),
    'permission_resolver_auth_uid_reference_count', (SELECT resolver_auth_uid_count FROM identity_dependency_state),
    'rpc_owner_auth_uid_policy_count', (SELECT auth_uid_policy_count FROM policy_identity_state),
    'hasad_force_rls_count', (SELECT count(*) FROM pg_catalog.pg_class c
      JOIN pg_catalog.pg_namespace ns ON ns.oid=c.relnamespace
      WHERE ns.nspname='hasad' AND c.relkind IN ('r','p') AND c.relrowsecurity AND c.relforcerowsecurity)
  ),
  'current_state', jsonb_build_object(
    'auth_schema_exists', EXISTS (SELECT 1 FROM pg_namespace WHERE nspname = 'auth'),
    'rpc_owner_auth_schema_usage', CASE WHEN (SELECT role_exists FROM role_state)
      AND EXISTS (SELECT 1 FROM pg_namespace WHERE nspname = 'auth')
      THEN has_schema_privilege('hasad_rpc_owner', 'auth', 'USAGE') ELSE false END,
    'rpc_owner_auth_uid_execute', CASE WHEN (SELECT role_exists FROM role_state)
      AND (SELECT function_exists FROM auth_uid_state)
      THEN has_function_privilege('hasad_rpc_owner', 'auth.uid()', 'EXECUTE') ELSE false END,
    'rpc_owner_role_restricted', (SELECT restricted_role_ok FROM role_state),
    'auth_users_table_exists', (SELECT table_exists FROM auth_users_state),
    'rpc_owner_auth_users_select', (SELECT owner_select FROM auth_users_state),
    'anon_auth_users_select', (SELECT anon_select FROM auth_users_state),
    'authenticated_auth_users_select', (SELECT authenticated_select FROM auth_users_state),
    'api_rpc_count', (SELECT rpc_count FROM rpc_state),
    'whoami_owner_security_definer_ok', (SELECT whoami_ok = 1 FROM rpc_state),
    'products_list_owner_security_definer_ok', (SELECT products_list_ok = 1 FROM rpc_state),
    'anon_api_execute_any', COALESCE((SELECT anon_execute_any FROM rpc_state), false),
    'hasad_table_count', (SELECT table_count FROM rls_state),
    'hasad_force_rls_count', (SELECT force_rls_count FROM rls_state),
    'hasad_unprotected_count', (SELECT unprotected_count FROM rls_state)
  ),
  'candidate_assertion_status', jsonb_build_object(
    'preflight_role_state', (SELECT restricted_role_ok FROM role_state),
    'preflight_auth_schema_exists', EXISTS (SELECT 1 FROM pg_namespace WHERE nspname = 'auth'),
    'preflight_auth_users_select_denied', (SELECT table_exists AND owner_select = false
      AND anon_select = false AND authenticated_select = false FROM auth_users_state),
    'preflight_expected_grant_absent', CASE WHEN (SELECT role_exists FROM role_state)
      AND EXISTS (SELECT 1 FROM pg_namespace WHERE nspname = 'auth')
      THEN NOT has_schema_privilege('hasad_rpc_owner', 'auth', 'USAGE') ELSE false END,
    'postflight_auth_uid_execute', CASE WHEN (SELECT role_exists FROM role_state)
      AND (SELECT function_exists FROM auth_uid_state)
      THEN has_function_privilege('hasad_rpc_owner', 'auth.uid()', 'EXECUTE') ELSE false END,
    'postflight_anon_rpc_denied', NOT COALESCE((SELECT anon_execute_any FROM rpc_state), false),
    'postflight_rpc_ownership_and_mode', (SELECT rpc_count = 2 AND whoami_ok = 1 AND products_list_ok = 1 FROM rpc_state),
    'postflight_force_rls_preserved', (SELECT table_count > 0 AND unprotected_count = 0 FROM rls_state)
  )
) AS rpc_auth_usage_diagnostic;
