-- REVIEW ONLY. Intended for a separately approved DEV privilege change.
-- One DO statement: the CLI prepares exactly one SQL statement, and PostgreSQL
-- rolls the grant back if any postflight assertion raises an exception.
DO $hasad_auth_usage$
DECLARE
  v_role pg_roles%ROWTYPE;
  v_tables integer;
  v_unprotected integer;
BEGIN
  -- Fail closed unless the restricted RPC owner and the intended pre-fix state
  -- still match the reviewed state.
  IF NOT EXISTS (
    SELECT 1 FROM pg_roles r WHERE r.rolname = 'hasad_rpc_owner'
      AND NOT r.rolcanlogin AND NOT r.rolsuper AND NOT r.rolbypassrls
      AND NOT r.rolinherit
  ) THEN
    RAISE EXCEPTION 'FAIL-CLOSED: restricted RPC owner role state changed';
  END IF;
  SELECT * INTO v_role FROM pg_roles WHERE rolname = 'hasad_rpc_owner';
  IF NOT FOUND OR v_role.rolcanlogin OR v_role.rolsuper OR v_role.rolbypassrls
     OR v_role.rolinherit THEN
    RAISE EXCEPTION 'FAIL-CLOSED: restricted RPC owner role state mismatch';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_namespace WHERE nspname = 'auth') THEN
    RAISE EXCEPTION 'FAIL-CLOSED: auth schema is missing';
  END IF;
  IF has_table_privilege('hasad_rpc_owner', 'auth.users', 'SELECT')
     OR has_table_privilege('anon', 'auth.users', 'SELECT')
     OR has_table_privilege('authenticated', 'auth.users', 'SELECT') THEN
    RAISE EXCEPTION 'FAIL-CLOSED: direct auth.users SELECT boundary mismatch';
  END IF;
  IF has_schema_privilege('hasad_rpc_owner', 'auth', 'USAGE') THEN
    RAISE EXCEPTION 'FAIL-CLOSED: proposed privilege already exists';
  END IF;

  -- This is the only mutation in the candidate.
  EXECUTE 'GRANT USAGE ON SCHEMA auth TO hasad_rpc_owner';

  -- Verify the single grant and all reviewed security boundaries before this
  -- DO statement can commit.
  IF NOT EXISTS (
    SELECT 1 FROM pg_roles r WHERE r.rolname = 'hasad_rpc_owner'
      AND NOT r.rolcanlogin AND NOT r.rolsuper AND NOT r.rolbypassrls
      AND NOT r.rolinherit
  ) THEN
    RAISE EXCEPTION 'FAIL-CLOSED: restricted RPC owner role state changed';
  END IF;
  IF NOT has_schema_privilege('hasad_rpc_owner', 'auth', 'USAGE') THEN
    RAISE EXCEPTION 'FAIL-CLOSED: required auth schema privilege missing';
  END IF;
  IF has_table_privilege('hasad_rpc_owner', 'auth.users', 'SELECT')
     OR has_table_privilege('anon', 'auth.users', 'SELECT')
     OR has_table_privilege('authenticated', 'auth.users', 'SELECT') THEN
    RAISE EXCEPTION 'FAIL-CLOSED: direct auth.users SELECT boundary changed';
  END IF;
  IF NOT has_function_privilege('hasad_rpc_owner', 'auth.uid()', 'EXECUTE') THEN
    RAISE EXCEPTION 'FAIL-CLOSED: auth.uid execute privilege changed';
  END IF;
  IF has_function_privilege('anon', 'hasad_api.whoami()', 'EXECUTE')
     OR has_function_privilege('anon', 'hasad_api.products_list()', 'EXECUTE') THEN
    RAISE EXCEPTION 'FAIL-CLOSED: anonymous RPC execute boundary mismatch';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    JOIN pg_roles r ON r.oid = p.proowner
    WHERE n.nspname = 'hasad_api' AND p.proname = 'whoami'
      AND r.rolname = 'hasad_rpc_owner' AND p.prosecdef
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    JOIN pg_roles r ON r.oid = p.proowner
    WHERE n.nspname = 'hasad_api' AND p.proname = 'products_list'
      AND r.rolname = 'hasad_rpc_owner' AND p.prosecdef
  ) THEN
    RAISE EXCEPTION 'FAIL-CLOSED: API RPC owner/security mode mismatch';
  END IF;
  SELECT count(*), count(*) FILTER (WHERE NOT c.relrowsecurity OR NOT c.relforcerowsecurity)
    INTO v_tables, v_unprotected
  FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'hasad' AND c.relkind IN ('r', 'p');
  IF v_tables = 0 OR v_unprotected <> 0 THEN
    RAISE EXCEPTION 'FAIL-CLOSED: hasad table RLS boundary mismatch';
  END IF;
END
$hasad_auth_usage$;

-- Read-only verification to run separately after approved application:
-- SELECT has_schema_privilege('hasad_rpc_owner', 'auth', 'USAGE') AS rpc_owner_auth_usage,
--        has_function_privilege('hasad_rpc_owner', 'auth.uid()', 'EXECUTE') AS rpc_owner_uid_execute,
--        has_table_privilege('hasad_rpc_owner', 'auth.users', 'SELECT') AS rpc_owner_auth_users_select,
--        (SELECT count(*) = 47 AND bool_and(c.relrowsecurity AND c.relforcerowsecurity)
--           FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
--          WHERE n.nspname = 'hasad' AND c.relkind IN ('r', 'p')) AS all_hasad_tables_force_rls;
