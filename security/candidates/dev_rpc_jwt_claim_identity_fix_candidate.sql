-- REVIEW ONLY. Forward-only replacement for the auth.uid() schema-USAGE dependency.
-- Execute only through an approved, single-statement Supabase SQL transport.
-- PostgREST validates the JWT and sets request.jwt.claims (and, on legacy
-- configurations, request.jwt.claim.sub) transaction-locally. HTTP callers do
-- not supply these database settings as RPC arguments. A direct SQL session
-- with database credentials can set custom GUCs itself; such a session is a
-- trusted database principal, not an untrusted PostgREST caller. The helper is
-- private, has no client EXECUTE grant, and the exposed RPCs have no user-id input.
DO $rpc_claim_identity_fix$
DECLARE
  v_role oid;
  v_owner oid;
  v_schema_owner oid;
  v_superuser boolean;
  v_create_grant boolean;
  v_table_count integer;
  v_force_count integer;
  v_policy_count integer;
  v_exec_count integer;
  v_expected_exec_count integer;
  v_permission_uses_auth_uid boolean;
  v_fn record;
  v_pol record;
  v_definition text;
  v_source text;
  v_expr text;
BEGIN
  SELECT oid, rolsuper INTO v_role, v_superuser
  FROM pg_catalog.pg_roles WHERE rolname = current_user;
  IF v_role IS NULL THEN RAISE EXCEPTION 'PREFLIGHT_EXECUTOR_ROLE_MISSING'; END IF;

  SELECT oid INTO v_owner FROM pg_catalog.pg_roles WHERE rolname = 'hasad_rpc_owner'
    AND NOT rolcanlogin AND NOT rolsuper AND NOT rolbypassrls AND NOT rolinherit;
  IF v_owner IS NULL THEN RAISE EXCEPTION 'PREFLIGHT_RPC_OWNER_ROLE_STATE'; END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_namespace WHERE nspname='hasad')
     OR NOT pg_catalog.has_schema_privilege(current_user,'hasad','USAGE') THEN
    RAISE EXCEPTION 'PREFLIGHT_PRIVATE_SCHEMA';
  END IF;
  IF pg_catalog.to_regprocedure('hasad.request_user_id()') IS NOT NULL THEN
    RAISE EXCEPTION 'PREFLIGHT_HELPER_ALREADY_EXISTS';
  END IF;
  IF pg_catalog.has_schema_privilege('hasad_rpc_owner','auth','USAGE') THEN
    RAISE EXCEPTION 'PREFLIGHT_AUTH_SCHEMA_USAGE_ALREADY_PRESENT';
  END IF;
  IF pg_catalog.has_schema_privilege('hasad_rpc_owner','hasad','CREATE') THEN
    RAISE EXCEPTION 'PREFLIGHT_RPC_OWNER_ALREADY_HAS_SCHEMA_CREATE';
  END IF;

  -- The linked executor must be able to replace all owned routines and alter
  -- the relevant table policies. Require proof before any DDL is attempted.
  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_proc p
    JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='hasad_api' AND p.proname='whoami' AND p.pronargs=0
      AND p.prosecdef AND p.proowner=v_owner
      AND (v_superuser OR pg_catalog.pg_has_role(v_role,p.proowner,'USAGE'))
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_proc p
    JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='hasad_api' AND p.proname='products_list' AND p.pronargs=0
      AND p.prosecdef AND p.proowner=v_owner
      AND (v_superuser OR pg_catalog.pg_has_role(v_role,p.proowner,'USAGE'))
  ) THEN
    RAISE EXCEPTION 'PREFLIGHT_RPC_REPLACEMENT_AUTHORITY';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_proc p
    JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='hasad' AND p.proname='has_permission'
      AND p.proargtypes='2950 2950 16 25'::pg_catalog.oidvector
      AND NOT p.prosecdef AND p.proowner=v_owner
  ) THEN
    RAISE EXCEPTION 'PREFLIGHT_PERMISSION_RESOLVER';
  END IF;
  SELECT p.prosrc LIKE '%auth.uid()%' INTO v_permission_uses_auth_uid
  FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname='hasad' AND p.proname='has_permission'
    AND p.proargtypes='2950 2950 16 25'::pg_catalog.oidvector;
  v_expected_exec_count := 2 + CASE WHEN v_permission_uses_auth_uid THEN 1 ELSE 0 END;
  IF NOT v_superuser AND NOT pg_catalog.has_schema_privilege(current_user,'hasad','CREATE') THEN
    RAISE EXCEPTION 'PREFLIGHT_PRIVATE_SCHEMA_CREATE_AUTHORITY';
  END IF;
  IF NOT v_superuser AND NOT pg_catalog.has_schema_privilege(current_user,'hasad_api','CREATE') THEN
    RAISE EXCEPTION 'PREFLIGHT_API_SCHEMA_REPLACEMENT_AUTHORITY';
  END IF;
  IF NOT v_superuser AND NOT pg_catalog.pg_has_role(v_role,v_owner,'MEMBER') THEN
    RAISE EXCEPTION 'PREFLIGHT_RPC_OWNER_TRANSFER_AUTHORITY';
  END IF;
  SELECT n.nspowner INTO v_schema_owner FROM pg_catalog.pg_namespace n WHERE n.nspname='hasad';
  SELECT (v_schema_owner=v_role) OR EXISTS (
    SELECT 1 FROM pg_catalog.aclexplode(COALESCE(n.nspacl,pg_catalog.acldefault('n',n.nspowner))) a
    WHERE a.privilege_type='CREATE' AND a.is_grantable
      AND (a.grantee=0 OR pg_catalog.pg_has_role(v_role,a.grantee,'USAGE'))
  ) INTO v_create_grant FROM pg_catalog.pg_namespace n WHERE n.nspname='hasad';
  IF NOT v_superuser AND NOT v_create_grant THEN
    RAISE EXCEPTION 'PREFLIGHT_HELPER_OWNER_TRANSFER_AUTHORITY';
  END IF;

  SELECT count(*), count(*) FILTER (WHERE c.relrowsecurity AND c.relforcerowsecurity)
    INTO v_table_count,v_force_count
  FROM pg_catalog.pg_class c JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace
  WHERE n.nspname='hasad' AND c.relkind IN ('r','p');
  IF v_table_count <> 47 OR v_force_count <> 47 THEN
    RAISE EXCEPTION 'PREFLIGHT_FORCE_RLS_COUNT';
  END IF;
  IF pg_catalog.has_table_privilege('anon','hasad.products','SELECT')
     OR pg_catalog.has_table_privilege('authenticated','hasad.products','SELECT')
     OR pg_catalog.has_table_privilege('hasad_rpc_owner','auth.users','SELECT')
     OR pg_catalog.has_table_privilege('anon','auth.users','SELECT')
     OR pg_catalog.has_table_privilege('authenticated','auth.users','SELECT') THEN
    RAISE EXCEPTION 'PREFLIGHT_DIRECT_TABLE_BOUNDARY';
  END IF;
  IF pg_catalog.has_function_privilege('anon','hasad_api.whoami()','EXECUTE')
     OR pg_catalog.has_function_privilege('anon','hasad_api.products_list()','EXECUTE') THEN
    RAISE EXCEPTION 'PREFLIGHT_ANON_RPC_BOUNDARY';
  END IF;

  -- All caller-scoped policies that read Auth identity must be replaceable by
  -- this executor; exact target set is fail-closed against schema drift.
  SELECT count(*) INTO v_policy_count
  FROM pg_catalog.pg_policy p
  JOIN pg_catalog.pg_class c ON c.oid=p.polrelid
  JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace
  WHERE n.nspname='hasad'
    AND c.relname IN ('company_memberships','companies','company_settings','roles',
      'role_permissions','user_permission_overrides','products')
    AND p.polcmd='r' AND p.polwithcheck IS NULL AND v_owner=ANY(p.polroles)
    AND pg_catalog.pg_get_expr(p.polqual,p.polrelid) LIKE '%auth.uid()%';
  IF v_policy_count <> 7 THEN RAISE EXCEPTION 'PREFLIGHT_AUTH_UID_POLICY_SET'; END IF;
  IF NOT v_superuser AND EXISTS (
    SELECT 1 FROM pg_catalog.pg_policy p
    JOIN pg_catalog.pg_class c ON c.oid=p.polrelid
    JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace
    WHERE n.nspname='hasad'
      AND c.relname IN ('company_memberships','companies','company_settings','roles',
        'role_permissions','user_permission_overrides','products')
      AND p.polcmd='r' AND p.polwithcheck IS NULL AND v_owner=ANY(p.polroles)
      AND pg_catalog.pg_get_expr(p.polqual,p.polrelid) LIKE '%auth.uid()%'
      AND NOT pg_catalog.pg_has_role(v_role,c.relowner,'USAGE')
  ) THEN
    RAISE EXCEPTION 'PREFLIGHT_POLICY_REPLACEMENT_AUTHORITY';
  END IF;

  -- Create helper with the invoking executor's rights. Ownership is transferred
  -- below only after the limited CREATE grant is made and then revoked.
  EXECUTE $helper$
    CREATE FUNCTION hasad.request_user_id() RETURNS uuid
    LANGUAGE plpgsql STABLE SECURITY INVOKER
    SET search_path = pg_catalog
    AS $body$
    DECLARE
      v_legacy_sub text;
      v_claims_text text;
      v_claims jsonb;
      v_json_sub text;
    BEGIN
      v_legacy_sub := NULLIF(pg_catalog.current_setting('request.jwt.claim.sub', true), '');
      v_claims_text := NULLIF(pg_catalog.current_setting('request.jwt.claims', true), '');
      IF v_claims_text IS NOT NULL THEN
        BEGIN
          v_claims := v_claims_text::jsonb;
        EXCEPTION WHEN others THEN
          RAISE EXCEPTION 'UNAUTHORIZED' USING ERRCODE='28000';
        END;
        IF pg_catalog.jsonb_typeof(v_claims) IS DISTINCT FROM 'object' THEN
          RAISE EXCEPTION 'UNAUTHORIZED' USING ERRCODE='28000';
        END IF;
        IF v_claims ? 'sub' THEN
          IF pg_catalog.jsonb_typeof(v_claims->'sub') IS DISTINCT FROM 'string' THEN
            RAISE EXCEPTION 'UNAUTHORIZED' USING ERRCODE='28000';
          END IF;
          v_json_sub := v_claims->>'sub';
        END IF;
      END IF;
      IF v_legacy_sub IS NOT NULL AND v_json_sub IS NOT NULL
         AND v_legacy_sub <> v_json_sub THEN
        RAISE EXCEPTION 'UNAUTHORIZED' USING ERRCODE='28000';
      END IF;
      v_json_sub := COALESCE(v_legacy_sub,v_json_sub);
      IF v_json_sub IS NULL OR pg_catalog.btrim(v_json_sub) = '' THEN
        RETURN NULL;
      END IF;
      IF v_json_sub !~ '^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$' THEN
        RAISE EXCEPTION 'UNAUTHORIZED' USING ERRCODE='28000';
      END IF;
      RETURN v_json_sub::uuid;
    END
    $body$
  $helper$;

  -- Rebuild only function source containing the exact auth.uid() call. Using
  -- pg_get_functiondef preserves the deployed function signatures, attributes,
  -- security mode, owner and grants under CREATE OR REPLACE semantics.
  FOR v_fn IN
    SELECT p.oid,p.prosrc,n.nspname,p.proname
    FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
    WHERE (n.nspname='hasad_api' AND p.proname IN ('whoami','products_list') AND p.pronargs=0)
       OR (n.nspname='hasad' AND p.proname='has_permission'
           AND p.proargtypes='2950 2950 16 25'::pg_catalog.oidvector)
  LOOP
    IF v_fn.prosrc LIKE '%auth.uid()%' THEN
      v_definition := pg_catalog.pg_get_functiondef(v_fn.oid);
      v_definition := pg_catalog.replace(v_definition,'auth.uid()','hasad.request_user_id()');
      IF v_definition LIKE '%auth.uid()%' THEN
        RAISE EXCEPTION 'PREFLIGHT_UNREPLACED_FUNCTION_IDENTITY_CALL';
      END IF;
      EXECUTE v_definition;
      v_exec_count := COALESCE(v_exec_count,0)+1;
    END IF;
  END LOOP;
  IF v_exec_count <> v_expected_exec_count THEN RAISE EXCEPTION 'PREFLIGHT_AUTH_UID_FUNCTION_SET'; END IF;

  FOR v_pol IN
    SELECT p.polname,c.relname,p.polrelid,p.polqual,p.polwithcheck
    FROM pg_catalog.pg_policy p
    JOIN pg_catalog.pg_class c ON c.oid=p.polrelid
    JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace
    WHERE n.nspname='hasad'
      AND c.relname IN ('company_memberships','companies','company_settings','roles',
        'role_permissions','user_permission_overrides','products')
      AND p.polcmd='r' AND p.polwithcheck IS NULL AND v_owner=ANY(p.polroles)
      AND pg_catalog.pg_get_expr(p.polqual,p.polrelid) LIKE '%auth.uid()%'
  LOOP
    v_expr := pg_catalog.replace(pg_catalog.pg_get_expr(v_pol.polqual,
      v_pol.polrelid),
      'auth.uid()','hasad.request_user_id()');
    IF v_expr IS NULL OR v_expr LIKE '%auth.uid()%' THEN
      RAISE EXCEPTION 'PREFLIGHT_POLICY_EXPRESSION_REWRITE';
    END IF;
    EXECUTE pg_catalog.format('ALTER POLICY %I ON hasad.%I USING (%s)',
      v_pol.polname,v_pol.relname,v_expr);
  END LOOP;

  -- The executor must be able to grant CREATE on its private schema. It is
  -- temporary and transaction-local in effect: the same block revokes it.
  EXECUTE 'GRANT CREATE ON SCHEMA hasad TO hasad_rpc_owner';
  EXECUTE 'REVOKE ALL ON FUNCTION hasad.request_user_id() FROM PUBLIC, anon, authenticated';
  EXECUTE 'GRANT EXECUTE ON FUNCTION hasad.request_user_id() TO hasad_rpc_owner';
  EXECUTE 'ALTER FUNCTION hasad.request_user_id() OWNER TO hasad_rpc_owner';
  EXECUTE 'REVOKE CREATE ON SCHEMA hasad FROM hasad_rpc_owner';

  -- Fail closed if any auth.uid dependency remains in the targeted functions or policies.
  IF EXISTS (
    SELECT 1 FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
    WHERE ((n.nspname='hasad_api' AND p.proname IN ('whoami','products_list') AND p.pronargs=0)
       OR (n.nspname='hasad' AND p.proname='has_permission'
           AND p.proargtypes='2950 2950 16 25'::pg_catalog.oidvector))
      AND p.prosrc LIKE '%auth.uid()%'
  ) THEN RAISE EXCEPTION 'POSTCHECK_FUNCTION_AUTH_UID_REMAINS'; END IF;
  IF EXISTS (
    SELECT 1 FROM pg_catalog.pg_policy p
    JOIN pg_catalog.pg_class c ON c.oid=p.polrelid
    JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace
    WHERE n.nspname='hasad'
      AND c.relname IN ('company_memberships','companies','company_settings','roles',
        'role_permissions','user_permission_overrides','products')
      AND v_owner=ANY(p.polroles)
      AND (pg_catalog.pg_get_expr(p.polqual,p.polrelid) LIKE '%auth.uid()%'
        OR pg_catalog.pg_get_expr(p.polwithcheck,p.polrelid) LIKE '%auth.uid()%')
  ) THEN RAISE EXCEPTION 'POSTCHECK_POLICY_AUTH_UID_REMAINS'; END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='hasad' AND p.proname='request_user_id' AND p.pronargs=0
      AND p.proowner=(SELECT oid FROM pg_catalog.pg_roles WHERE rolname='hasad_rpc_owner')
      AND NOT p.prosecdef AND p.proconfig @> ARRAY['search_path=pg_catalog']
      AND pg_catalog.has_function_privilege('hasad_rpc_owner',p.oid,'EXECUTE')
      AND NOT pg_catalog.has_function_privilege('anon',p.oid,'EXECUTE')
      AND NOT pg_catalog.has_function_privilege('authenticated',p.oid,'EXECUTE')
  ) THEN RAISE EXCEPTION 'POSTCHECK_HELPER_BOUNDARY'; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_namespace WHERE nspname='hasad'
      AND NOT pg_catalog.has_schema_privilege('hasad_rpc_owner','hasad','CREATE')) THEN
    RAISE EXCEPTION 'POSTCHECK_RPC_OWNER_CREATE_REVOKED';
  END IF;
  IF NOT pg_catalog.has_function_privilege('hasad_rpc_owner','auth.uid()','EXECUTE')
     OR pg_catalog.has_schema_privilege('hasad_rpc_owner','auth','USAGE') THEN
    RAISE EXCEPTION 'POSTCHECK_AUTH_BOUNDARY';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='hasad_api' AND p.proname='whoami' AND p.pronargs=0
      AND p.prorettype='hasad_api.company_context_dto'::pg_catalog.regtype
      AND p.prosecdef AND p.proowner=v_owner
      AND pg_catalog.has_function_privilege('authenticated',p.oid,'EXECUTE')
      AND NOT pg_catalog.has_function_privilege('anon',p.oid,'EXECUTE')
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='hasad_api' AND p.proname='products_list' AND p.pronargs=0
      AND p.prorettype='hasad_api.product_dto'::pg_catalog.regtype AND p.proretset
      AND p.prosecdef AND p.proowner=v_owner
      AND pg_catalog.has_function_privilege('authenticated',p.oid,'EXECUTE')
      AND NOT pg_catalog.has_function_privilege('anon',p.oid,'EXECUTE')
  ) THEN RAISE EXCEPTION 'POSTCHECK_RPC_CONTRACT'; END IF;
  IF EXISTS (
    SELECT 1 FROM pg_catalog.pg_class c JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace
    WHERE n.nspname='hasad' AND c.relkind IN ('r','p')
      AND (pg_catalog.has_table_privilege('anon',c.oid,'SELECT')
        OR pg_catalog.has_table_privilege('authenticated',c.oid,'SELECT'))
  ) THEN RAISE EXCEPTION 'POSTCHECK_CLIENT_TABLE_BOUNDARY'; END IF;
  IF EXISTS (
    SELECT 1 FROM pg_catalog.pg_class c JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace
    WHERE n.nspname='hasad' AND c.relkind IN ('r','p')
      AND (NOT c.relrowsecurity OR NOT c.relforcerowsecurity)
  ) OR (SELECT count(*) FROM pg_catalog.pg_class c
        JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace
        WHERE n.nspname='hasad' AND c.relkind IN ('r','p')) <> 47 THEN
    RAISE EXCEPTION 'POSTCHECK_FORCE_RLS';
  END IF;
END
$rpc_claim_identity_fix$;
