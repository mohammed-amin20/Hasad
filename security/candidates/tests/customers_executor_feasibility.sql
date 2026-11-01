-- Local-only feasibility probe for the installed-executor assumption.
--
-- Hosted DEV evidence: the executor is not superuser; it cannot grant USAGE on
-- schema `auth` to hasad_rpc_owner and cannot alter/replace restricted-owner
-- RPCs. The corrected design avoids all of that by creating its own role.
--
-- This probe proves, with a NON-SUPERUSER executor that only has CREATEROLE:
--   1. it can create a locked writer role;
--   2. it can explicitly grant itself SET OPTION on that new role, which
--      ALTER ... OWNER TO requires on PostgreSQL 17;
--   3. it can transfer function ownership to the new role;
--   4. it still CANNOT transfer ownership to a role it did not create, which
--      is the exact hosted blocker the design routes around.
SET client_min_messages = warning;

CREATE ROLE harness_executor NOLOGIN CREATEROLE;
CREATE SCHEMA hasad_probe AUTHORIZATION harness_executor;
CREATE ROLE harness_foreign NOLOGIN;

SET ROLE harness_executor;

CREATE ROLE harness_writer
  NOLOGIN NOINHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS;

DO $before_set_check$
BEGIN
  IF pg_catalog.pg_has_role(current_user, 'harness_writer', 'SET') THEN
    RAISE EXCEPTION 'ASSERT_FAIL: new writer role unexpectedly has SET privilege before explicit grant';
  END IF;
END
$before_set_check$;

GRANT harness_writer TO CURRENT_USER WITH SET OPTION;

DO $setcheck$
BEGIN
  IF NOT pg_catalog.pg_has_role(current_user, 'harness_writer', 'SET') THEN
    RAISE EXCEPTION 'ASSERT_FAIL: executor lacks SET privilege on self-created writer role';
  END IF;
  IF NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_auth_members m
    JOIN pg_catalog.pg_roles granted ON granted.oid = m.roleid
    JOIN pg_catalog.pg_roles member ON member.oid = m.member
    WHERE granted.rolname = 'harness_writer'
      AND member.rolname = current_user
      AND m.set_option
  ) THEN
    RAISE EXCEPTION 'ASSERT_FAIL: writer membership lacks direct SET OPTION';
  END IF;
END
$setcheck$;

CREATE FUNCTION hasad_probe.f() RETURNS integer
LANGUAGE sql AS 'SELECT 1';

CREATE FUNCTION hasad_probe.g() RETURNS integer
LANGUAGE sql AS 'SELECT 2';

GRANT CREATE ON SCHEMA hasad_probe TO harness_writer;
ALTER FUNCTION hasad_probe.f() OWNER TO harness_writer;
REVOKE CREATE ON SCHEMA hasad_probe FROM harness_writer;

DO $probe$
DECLARE
  v_state text;
BEGIN
  BEGIN
    ALTER FUNCTION hasad_probe.g() OWNER TO harness_foreign;
    RAISE EXCEPTION 'ASSERT_FAIL: non-member ownership transfer unexpectedly allowed';
  EXCEPTION WHEN insufficient_privilege THEN
    NULL;
  WHEN others THEN
    GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE;
    RAISE EXCEPTION 'ASSERT_FAIL: expected 42501, got % - %', v_state, SQLERRM;
  END;
END
$probe$;

RESET ROLE;

DO $probecheck$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_proc p
    JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
    JOIN pg_catalog.pg_roles r ON r.oid = p.proowner
    WHERE n.nspname = 'hasad_probe'
      AND p.proname = 'f'
      AND r.rolname = 'harness_writer'
  ) THEN
    RAISE EXCEPTION 'ASSERT_FAIL: ownership transfer to a self-created role failed';
  END IF;

  IF EXISTS (
    SELECT 1 FROM pg_catalog.pg_roles
    WHERE rolname = 'harness_executor'
      AND (rolsuper OR rolbypassrls)
  ) THEN
    RAISE EXCEPTION 'ASSERT_FAIL: feasibility probe executor is not representative';
  END IF;

  IF pg_catalog.has_schema_privilege('harness_writer', 'hasad_probe', 'CREATE') THEN
    RAISE EXCEPTION 'ASSERT_FAIL: writer role retained schema CREATE';
  END IF;
END
$probecheck$;

-- Cleanup: the disposable database is removed anyway, but leave no probe roles.
DROP SCHEMA hasad_probe CASCADE;
DROP ROLE harness_writer;
DROP ROLE harness_foreign;
DROP ROLE harness_executor;

SELECT 'PASS: non-superuser CREATEROLE executor feasibility probe' AS result;
