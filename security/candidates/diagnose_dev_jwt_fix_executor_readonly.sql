-- Read-only catalog preflight for the JWT identity candidate.
-- Emits only privilege booleans, object names/signatures, and counts.
WITH executor AS (
  SELECT r.oid, r.rolsuper,
    pg_catalog.has_schema_privilege(current_user,'hasad','USAGE') AS hasad_usage,
    pg_catalog.has_schema_privilege(current_user,'hasad','CREATE') AS hasad_create,
    pg_catalog.has_schema_privilege(current_user,'hasad_api','USAGE') AS api_usage,
    pg_catalog.has_schema_privilege(current_user,'hasad_api','CREATE') AS api_create,
    pg_catalog.pg_has_role(current_user,'hasad_rpc_owner','MEMBER') AS member_rpc_owner,
    pg_catalog.pg_has_role(current_user,'hasad_rpc_owner','USAGE') AS use_rpc_owner,
    r.rolname
  FROM pg_catalog.pg_roles r WHERE r.rolname=current_user
), rpc AS (
  SELECT p.oid, p.proname, pg_catalog.pg_get_function_identity_arguments(p.oid) AS identity_args,
    pg_catalog.pg_get_function_result(p.oid) AS result_type,
    pg_catalog.pg_get_userbyid(p.proowner) AS owner_name, p.prosecdef,
    p.prosrc LIKE '%auth.uid()%' AS source_mentions_auth_uid,
    pg_catalog.has_function_privilege(current_user,p.oid,'EXECUTE') AS executor_execute,
    pg_catalog.has_function_privilege('authenticated',p.oid,'EXECUTE') AS authenticated_execute,
    pg_catalog.has_function_privilege('anon',p.oid,'EXECUTE') AS anon_execute,
    pg_catalog.pg_has_role(current_user,p.proowner,'USAGE') AS executor_can_act_as_owner,
    pg_catalog.has_schema_privilege(current_user,'hasad_api','CREATE') AS executor_schema_create
  FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname='hasad_api' AND p.proname IN ('whoami','products_list')
), resolver AS (
  SELECT p.oid,p.prosrc LIKE '%auth.uid()%' AS source_mentions_auth_uid,
    pg_catalog.pg_get_userbyid(p.proowner) AS owner_name,p.prosecdef
  FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname='hasad' AND p.proname='has_permission'
    AND p.proargtypes='2950 2950 16 25'::pg_catalog.oidvector
), target_policies AS (
  SELECT p.polname,c.relname AS table_name,
    pg_catalog.pg_get_userbyid(c.relowner) AS table_owner,
    pg_catalog.pg_has_role(current_user,c.relowner,'USAGE') AS executor_can_act_as_table_owner,
    pg_catalog.pg_get_expr(p.polqual,p.polrelid) LIKE '%auth.uid()%'
      OR pg_catalog.pg_get_expr(p.polwithcheck,p.polrelid) LIKE '%auth.uid()%' AS mentions_auth_uid,
    'hasad_rpc_owner'::pg_catalog.regrole=ANY(p.polroles) AS applies_to_rpc_owner,
    p.polcmd::text AS command
  FROM pg_catalog.pg_policy p JOIN pg_catalog.pg_class c ON c.oid=p.polrelid
  JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace
  WHERE n.nspname='hasad' AND c.relname IN ('company_memberships','companies',
    'company_settings','roles','role_permissions','user_permission_overrides','products')
    AND (pg_catalog.pg_get_expr(p.polqual,p.polrelid) LIKE '%auth.uid()%'
      OR pg_catalog.pg_get_expr(p.polwithcheck,p.polrelid) LIKE '%auth.uid()%')
), schema_acl AS (
  SELECT n.nspowner,
    (n.nspowner=(SELECT oid FROM executor)) AS executor_owns_hasad,
    EXISTS (
      SELECT 1 FROM pg_catalog.aclexplode(COALESCE(n.nspacl,
        pg_catalog.acldefault('n',n.nspowner))) a
      WHERE a.privilege_type='CREATE' AND a.is_grantable
        AND (a.grantee=0 OR pg_catalog.pg_has_role((SELECT oid FROM executor),a.grantee,'USAGE'))
    ) AS executor_has_create_grant_option
  FROM pg_catalog.pg_namespace n WHERE n.nspname='hasad'
), table_state AS (
  SELECT count(*) AS total_tables,
    count(*) FILTER (WHERE c.relrowsecurity AND c.relforcerowsecurity) AS force_rls_tables,
    bool_or(pg_catalog.has_table_privilege('anon',c.oid,'SELECT') OR
      pg_catalog.has_table_privilege('authenticated',c.oid,'SELECT')) AS client_has_hasad_select
  FROM pg_catalog.pg_class c JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace
  WHERE n.nspname='hasad' AND c.relkind IN ('r','p')
), helper_state AS (
  SELECT pg_catalog.to_regprocedure('hasad.request_user_id()') IS NOT NULL AS helper_exists,
    pg_catalog.has_schema_privilege('hasad_rpc_owner','hasad','CREATE') AS rpc_owner_hasad_create,
    pg_catalog.has_schema_privilege('hasad_rpc_owner','auth','USAGE') AS rpc_owner_auth_usage,
    pg_catalog.has_table_privilege('hasad_rpc_owner','auth.users','SELECT') AS rpc_owner_auth_users_select,
    CASE WHEN pg_catalog.to_regprocedure('hasad.request_user_id()') IS NULL THEN false
      ELSE pg_catalog.has_function_privilege('anon','hasad.request_user_id()','EXECUTE') END AS anon_helper_execute,
    CASE WHEN pg_catalog.to_regprocedure('hasad.request_user_id()') IS NULL THEN false
      ELSE pg_catalog.has_function_privilege('authenticated','hasad.request_user_id()','EXECUTE') END AS authenticated_helper_execute
)
SELECT pg_catalog.jsonb_build_object(
  'executor', pg_catalog.jsonb_build_object(
    'is_superuser',(SELECT rolsuper FROM executor),
    'hasad_usage',(SELECT hasad_usage FROM executor),
    'hasad_create',(SELECT hasad_create FROM executor),
    'hasad_api_usage',(SELECT api_usage FROM executor),
    'hasad_api_create',(SELECT api_create FROM executor),
    'member_hasad_rpc_owner',(SELECT member_rpc_owner FROM executor),
    'can_act_as_hasad_rpc_owner',(SELECT use_rpc_owner FROM executor),
    'owns_hasad_schema',(SELECT executor_owns_hasad FROM schema_acl),
    'hasad_create_grant_option',(SELECT executor_has_create_grant_option FROM schema_acl),
    'can_replace_both_rpcs',(SELECT count(*)=2 AND bool_and(
      owner_name='hasad_rpc_owner' AND prosecdef AND executor_can_act_as_owner AND executor_schema_create)
      FROM rpc),
    'can_transfer_helper_owner',(SELECT rolsuper OR member_rpc_owner FROM executor)
      AND ((SELECT rolsuper FROM executor) OR (SELECT executor_owns_hasad OR executor_has_create_grant_option FROM schema_acl)),
    'can_temporary_create_grant_and_revoke',(SELECT rolsuper FROM executor)
      OR (SELECT executor_owns_hasad OR executor_has_create_grant_option FROM schema_acl)
  ),
  'rpcs',(SELECT COALESCE(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
      'name',proname,'identity_arguments',identity_args,'result_type',result_type,
      'owner',owner_name,'security_definer',prosecdef,'authenticated_execute',authenticated_execute,
      'anon_execute',anon_execute,'executor_can_act_as_owner',executor_can_act_as_owner,
      'executor_schema_create',executor_schema_create,'source_mentions_auth_uid',source_mentions_auth_uid)
      ORDER BY proname),'[]'::jsonb) FROM rpc),
  'resolver',(SELECT COALESCE(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
      'owner',owner_name,'security_definer',prosecdef,'source_mentions_auth_uid',source_mentions_auth_uid)),
      '[]'::jsonb) FROM resolver),
  'policies',(SELECT COALESCE(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
      'table',table_name,'policy',polname,'command',command,'applies_to_rpc_owner',applies_to_rpc_owner,
      'mentions_auth_uid',mentions_auth_uid,'executor_can_act_as_table_owner',executor_can_act_as_table_owner)
      ORDER BY table_name,polname),'[]'::jsonb) FROM target_policies),
  'policy_counts',pg_catalog.jsonb_build_object(
    'target_policies',(SELECT count(*) FROM target_policies),
    'owner_policies',(SELECT count(*) FROM target_policies WHERE applies_to_rpc_owner),
    'auth_uid_policies',(SELECT count(*) FROM target_policies WHERE applies_to_rpc_owner AND mentions_auth_uid),
    'alterable_auth_uid_policies',(SELECT count(*) FROM target_policies WHERE applies_to_rpc_owner
      AND mentions_auth_uid AND executor_can_act_as_table_owner)),
  'table_security',pg_catalog.jsonb_build_object(
    'table_count',(SELECT total_tables FROM table_state),
    'force_rls_count',(SELECT force_rls_tables FROM table_state),
    'client_has_hasad_select',COALESCE((SELECT client_has_hasad_select FROM table_state),false)),
  'helper_boundary',pg_catalog.jsonb_build_object(
    'exists',(SELECT helper_exists FROM helper_state),
    'rpc_owner_auth_usage',(SELECT rpc_owner_auth_usage FROM helper_state),
    'rpc_owner_auth_users_select',(SELECT rpc_owner_auth_users_select FROM helper_state),
    'rpc_owner_hasad_create',(SELECT rpc_owner_hasad_create FROM helper_state),
    'anon_execute',COALESCE((SELECT anon_helper_execute FROM helper_state),false),
    'authenticated_execute',COALESCE((SELECT authenticated_helper_execute FROM helper_state),false)),
  'exact_candidate_executor_preflight',
    (SELECT rolsuper OR (hasad_usage AND hasad_create AND api_usage AND api_create
      AND member_rpc_owner) FROM executor)
    AND ((SELECT rolsuper FROM executor) OR
      (SELECT executor_owns_hasad OR executor_has_create_grant_option FROM schema_acl))
    AND (SELECT count(*)=2 AND bool_and(owner_name='hasad_rpc_owner' AND prosecdef
      AND executor_can_act_as_owner AND executor_schema_create) FROM rpc)
    AND (SELECT count(*)=7 AND count(*) FILTER (WHERE applies_to_rpc_owner AND mentions_auth_uid
      AND executor_can_act_as_table_owner)=7 FROM target_policies)
    AND (SELECT count(*)=1 AND bool_and(owner_name='hasad_rpc_owner' AND NOT prosecdef)
      FROM resolver)
    AND (SELECT total_tables=47 AND force_rls_tables=47 AND NOT COALESCE(client_has_hasad_select,false) FROM table_state)
    AND (SELECT NOT helper_exists AND NOT rpc_owner_auth_usage AND NOT rpc_owner_auth_users_select
      AND NOT rpc_owner_hasad_create AND NOT anon_helper_execute AND NOT authenticated_helper_execute FROM helper_state)
) AS jwt_fix_executor_preflight;
