-- Hasad ERP V2 C1/C2 local disposable PoC — test-only surface and fixtures
-- Target: disposable local PostgreSQL database only. Never run on DEV.
--
-- This file is NOT a V2 migration. It creates:
--   1. deterministic, non-production fixtures;
--   2. a test-only RPC surface in hasad_api owned by a locked non-superuser;
--   3. owner-only read policies for that locked role, because the deployed
--      tables have FORCE RLS and no application policies;
--   4. a test-only audit helper and append-only audit table in the poc schema.
--
-- Application roles receive no table grants and no policy. The only grants are
-- EXECUTE on the four test RPCs.

\set ON_ERROR_STOP on

BEGIN;

CREATE SCHEMA poc;

CREATE TABLE poc.notes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES hasad.companies(id) ON DELETE RESTRICT,
  note text NOT NULL,
  created_by uuid NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE poc.audit_log (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  company_id uuid NOT NULL REFERENCES hasad.companies(id) ON DELETE RESTRICT,
  actor_user_id uuid NOT NULL,
  action text NOT NULL,
  entity text NOT NULL,
  entity_id uuid NULL,
  details jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE FUNCTION poc.reject_audit_mutation()
RETURNS trigger
LANGUAGE plpgsql
AS $fn$
BEGIN
  RAISE EXCEPTION 'AUDIT_APPEND_ONLY';
END;
$fn$;

CREATE TRIGGER audit_log_no_update_delete
BEFORE UPDATE OR DELETE ON poc.audit_log
FOR EACH ROW EXECUTE FUNCTION poc.reject_audit_mutation();

CREATE FUNCTION poc.assert(p_condition boolean, p_message text)
RETURNS void
LANGUAGE plpgsql
AS $fn$
BEGIN
  IF p_condition IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'FAIL: %', p_message;
  END IF;
END;
$fn$;

-- ---------------------------------------------------------------- fixtures
INSERT INTO auth.users (id, email, email_confirmed_at) VALUES
  ('00000000-0000-0000-0000-000000000001', 'owner-a@example.test', now()),
  ('00000000-0000-0000-0000-000000000002', 'member-a@example.test', now()),
  ('00000000-0000-0000-0000-000000000003', 'suspended-a@example.test', now()),
  ('00000000-0000-0000-0000-000000000004', 'revoked-a@example.test', now()),
  ('00000000-0000-0000-0000-000000000005', 'admin-a@example.test', now()),
  ('00000000-0000-0000-0000-000000000006', 'sales-a@example.test', now()),
  ('00000000-0000-0000-0000-000000000007', 'warehouse-a@example.test', now()),
  ('00000000-0000-0000-0000-000000000008', 'owner-b@example.test', now());

INSERT INTO hasad.user_profiles (id, display_name) VALUES
  ('00000000-0000-0000-0000-000000000001', 'Owner A'),
  ('00000000-0000-0000-0000-000000000002', 'Member A'),
  ('00000000-0000-0000-0000-000000000003', 'Suspended A'),
  ('00000000-0000-0000-0000-000000000004', 'Revoked A'),
  ('00000000-0000-0000-0000-000000000005', 'Admin A'),
  ('00000000-0000-0000-0000-000000000006', 'Sales A'),
  ('00000000-0000-0000-0000-000000000007', 'Warehouse A'),
  ('00000000-0000-0000-0000-000000000008', 'Owner B');

INSERT INTO hasad.companies (id, created_by, status) VALUES
  ('10000000-0000-0000-0000-000000000001',
   '00000000-0000-0000-0000-000000000001', 'active'),
  ('20000000-0000-0000-0000-000000000001',
   '00000000-0000-0000-0000-000000000008', 'active');

INSERT INTO hasad.roles (id, company_id, code, is_system) VALUES
  ('a1000000-0000-0000-0000-000000000001',
   '10000000-0000-0000-0000-000000000001', 'admin', true),
  ('a1000000-0000-0000-0000-000000000002',
   '10000000-0000-0000-0000-000000000001', 'accountant', true),
  ('a1000000-0000-0000-0000-000000000003',
   '10000000-0000-0000-0000-000000000001', 'sales', true),
  ('a1000000-0000-0000-0000-000000000004',
   '10000000-0000-0000-0000-000000000001', 'warehouse', true),
  ('b1000000-0000-0000-0000-000000000001',
   '20000000-0000-0000-0000-000000000001', 'admin', true);

INSERT INTO hasad.company_memberships
  (id, company_id, user_id, role_id, is_owner, status, invited_by, revoked_at)
VALUES
  ('c1000000-0000-0000-0000-000000000001',
   '10000000-0000-0000-0000-000000000001',
   '00000000-0000-0000-0000-000000000001', NULL, true, 'active', NULL, NULL),
  ('c1000000-0000-0000-0000-000000000002',
   '10000000-0000-0000-0000-000000000001',
   '00000000-0000-0000-0000-000000000002',
   'a1000000-0000-0000-0000-000000000002', false, 'active', NULL, NULL),
  ('c1000000-0000-0000-0000-000000000003',
   '10000000-0000-0000-0000-000000000001',
   '00000000-0000-0000-0000-000000000003',
   'a1000000-0000-0000-0000-000000000002', false, 'suspended', NULL, NULL),
  ('c1000000-0000-0000-0000-000000000004',
   '10000000-0000-0000-0000-000000000001',
   '00000000-0000-0000-0000-000000000004',
   'a1000000-0000-0000-0000-000000000002', false, 'revoked', NULL, now()),
  ('c1000000-0000-0000-0000-000000000005',
   '10000000-0000-0000-0000-000000000001',
   '00000000-0000-0000-0000-000000000005',
   'a1000000-0000-0000-0000-000000000001', false, 'active', NULL, NULL),
  ('c1000000-0000-0000-0000-000000000006',
   '10000000-0000-0000-0000-000000000001',
   '00000000-0000-0000-0000-000000000006',
   'a1000000-0000-0000-0000-000000000003', false, 'active', NULL, NULL),
  ('c1000000-0000-0000-0000-000000000007',
   '10000000-0000-0000-0000-000000000001',
   '00000000-0000-0000-0000-000000000007',
   'a1000000-0000-0000-0000-000000000004', false, 'active', NULL, NULL),
  ('c1000000-0000-0000-0000-000000000008',
   '20000000-0000-0000-0000-000000000001',
   '00000000-0000-0000-0000-000000000008', NULL, true, 'active', NULL, NULL);

INSERT INTO hasad.role_permissions (role_id, permission_code)
SELECT 'a1000000-0000-0000-0000-000000000001', code
FROM hasad.permissions
WHERE code <> 'fiscal.close';

INSERT INTO hasad.role_permissions (role_id, permission_code) VALUES
  ('a1000000-0000-0000-0000-000000000002', 'journals.post'),
  ('a1000000-0000-0000-0000-000000000002', 'reports.view'),
  ('a1000000-0000-0000-0000-000000000002', 'cash.post'),
  ('a1000000-0000-0000-0000-000000000003', 'sales.create'),
  ('a1000000-0000-0000-0000-000000000003', 'sales.post'),
  ('a1000000-0000-0000-0000-000000000003', 'sales.reverse'),
  ('a1000000-0000-0000-0000-000000000003', 'parties.manage'),
  ('a1000000-0000-0000-0000-000000000004', 'inventory.manage'),
  ('a1000000-0000-0000-0000-000000000004', 'inventory.post');

INSERT INTO hasad.user_permission_overrides
  (membership_id, permission_code, effect)
VALUES
  ('c1000000-0000-0000-0000-000000000001', 'journals.post', 'deny'),
  ('c1000000-0000-0000-0000-000000000002', 'journals.post', 'deny'),
  ('c1000000-0000-0000-0000-000000000002', 'reports.export', 'allow'),
  ('c1000000-0000-0000-0000-000000000005', 'fiscal.close', 'allow'),
  ('c1000000-0000-0000-0000-000000000006', 'cash.post', 'allow'),
  ('c1000000-0000-0000-0000-000000000007', 'inventory.adjust', 'allow');

-- ------------------------------------------------------- test-only resolver
CREATE FUNCTION hasad.has_permission(
  p_company_id uuid,
  p_permission_code text
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
SET search_path = pg_catalog, pg_temp
AS $fn$
DECLARE
  v_uid uuid := auth.uid();
  v_membership_id uuid;
  v_status text;
  v_is_owner boolean;
  v_role_code text;
  v_effect text;
  v_has_role_grant boolean;
BEGIN
  IF v_uid IS NULL OR p_company_id IS NULL OR p_permission_code IS NULL THEN
    RETURN false;
  END IF;

  SELECT m.id, m.status, m.is_owner, r.code
    INTO v_membership_id, v_status, v_is_owner, v_role_code
  FROM hasad.company_memberships m
  LEFT JOIN hasad.roles r ON r.id = m.role_id
  WHERE m.user_id = v_uid AND m.company_id = p_company_id;

  IF NOT FOUND OR v_status <> 'active' THEN
    RETURN false;
  END IF;

  IF v_is_owner THEN
    RETURN true;
  END IF;

  IF p_permission_code = 'fiscal.close' THEN
    RETURN false;
  END IF;

  SELECT o.effect
    INTO v_effect
  FROM hasad.user_permission_overrides o
  WHERE o.membership_id = v_membership_id
    AND o.permission_code = p_permission_code;

  IF v_effect = 'deny' THEN
    RETURN false;
  END IF;

  IF p_permission_code = 'inventory.adjust' THEN
    RETURN COALESCE(v_role_code = 'admin', false);
  END IF;

  IF p_permission_code = 'cash.post' AND v_role_code = 'sales' THEN
    RETURN false;
  END IF;

  SELECT EXISTS (
    SELECT 1
    FROM hasad.role_permissions rp
    WHERE rp.role_id = (
      SELECT m.role_id
      FROM hasad.company_memberships m
      WHERE m.id = v_membership_id
    )
    AND rp.permission_code = p_permission_code
  ) INTO v_has_role_grant;

  IF v_has_role_grant THEN
    RETURN true;
  END IF;

  IF v_effect = 'allow' THEN
    RETURN true;
  END IF;

  RETURN false;
END;
$fn$;

-- ---------------------------------------------------------- test-only RPCs
CREATE FUNCTION hasad_api.poc_has_permission(
  p_company_id uuid,
  p_permission_code text
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
SET search_path = pg_catalog, pg_temp
AS $fn$
BEGIN
  RETURN hasad.has_permission(p_company_id, p_permission_code);
END;
$fn$;

CREATE FUNCTION hasad_api.poc_get_my_company()
RETURNS TABLE(company_id uuid, status text)
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
SET search_path = pg_catalog, pg_temp
AS $fn$
DECLARE
  v_company_id uuid;
BEGIN
  SELECT m.company_id
    INTO v_company_id
  FROM hasad.company_memberships m
  WHERE m.user_id = auth.uid()
    AND m.status = 'active';

  IF v_company_id IS NULL THEN
    RAISE EXCEPTION 'NO_ACTIVE_MEMBERSHIP';
  END IF;

  RETURN QUERY
  SELECT c.id, c.status
  FROM hasad.companies c
  WHERE c.id = v_company_id;
END;
$fn$;

CREATE FUNCTION hasad_api.poc_get_company(p_company_id uuid)
RETURNS TABLE(company_id uuid, status text)
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
SET search_path = pg_catalog, pg_temp
AS $fn$
BEGIN
  IF NOT hasad.has_permission(p_company_id, 'reports.view') THEN
    RAISE EXCEPTION 'DENIED';
  END IF;

  RETURN QUERY
  SELECT c.id, c.status
  FROM hasad.companies c
  WHERE c.id = p_company_id;
END;
$fn$;

CREATE FUNCTION hasad_api.poc_add_note(
  p_company_id uuid,
  p_note text
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $fn$
DECLARE
  v_id uuid;
BEGIN
  IF NOT hasad.has_permission(p_company_id, 'company.settings') THEN
    RAISE EXCEPTION 'DENIED';
  END IF;

  INSERT INTO poc.notes (company_id, note, created_by)
  VALUES (p_company_id, p_note, auth.uid())
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$fn$;

CREATE FUNCTION hasad_api.poc_audit_write(
  p_company_id uuid,
  p_action text,
  p_entity text,
  p_entity_id uuid,
  p_details jsonb
)
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $fn$
DECLARE
  v_id bigint;
  v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'DENIED';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM hasad.company_memberships m
    WHERE m.user_id = v_uid
      AND m.company_id = p_company_id
      AND m.status = 'active'
  ) THEN
    RAISE EXCEPTION 'DENIED';
  END IF;

  INSERT INTO poc.audit_log
    (company_id, actor_user_id, action, entity, entity_id, details)
  VALUES
    (p_company_id, v_uid, p_action, p_entity, p_entity_id,
     COALESCE(p_details, '{}'::jsonb))
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$fn$;

-- ------------------------------------------- owner-only RLS for the test role
CREATE POLICY poc_owner_select_user_profiles
  ON hasad.user_profiles FOR SELECT TO hasad_poc_owner USING (true);
CREATE POLICY poc_owner_select_companies
  ON hasad.companies FOR SELECT TO hasad_poc_owner USING (true);
CREATE POLICY poc_owner_select_roles
  ON hasad.roles FOR SELECT TO hasad_poc_owner USING (true);
CREATE POLICY poc_owner_select_memberships
  ON hasad.company_memberships FOR SELECT TO hasad_poc_owner USING (true);
CREATE POLICY poc_owner_select_permissions
  ON hasad.permissions FOR SELECT TO hasad_poc_owner USING (true);
CREATE POLICY poc_owner_select_role_permissions
  ON hasad.role_permissions FOR SELECT TO hasad_poc_owner USING (true);
CREATE POLICY poc_owner_select_overrides
  ON hasad.user_permission_overrides FOR SELECT TO hasad_poc_owner USING (true);

-- ------------------------------------------------------------ ownership/ACL
ALTER FUNCTION hasad.has_permission(uuid, text)
  OWNER TO hasad_poc_owner;
ALTER FUNCTION hasad_api.poc_has_permission(uuid, text)
  OWNER TO hasad_poc_owner;
ALTER FUNCTION hasad_api.poc_get_my_company()
  OWNER TO hasad_poc_owner;
ALTER FUNCTION hasad_api.poc_get_company(uuid)
  OWNER TO hasad_poc_owner;
ALTER FUNCTION hasad_api.poc_add_note(uuid, text)
  OWNER TO hasad_poc_owner;
ALTER FUNCTION hasad_api.poc_audit_write(uuid, text, text, uuid, jsonb)
  OWNER TO hasad_poc_owner;

GRANT USAGE ON SCHEMA hasad TO hasad_poc_owner;
GRANT USAGE ON SCHEMA hasad_api TO hasad_poc_owner;
GRANT USAGE ON SCHEMA poc TO hasad_poc_owner;
GRANT SELECT ON ALL TABLES IN SCHEMA hasad TO hasad_poc_owner;
GRANT SELECT, INSERT ON poc.notes TO hasad_poc_owner;
-- RETURNING the generated audit id requires SELECT on that column; this
-- remains available only to the locked helper owner, never to application
-- roles.
GRANT INSERT, SELECT (id) ON poc.audit_log TO hasad_poc_owner;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA poc TO hasad_poc_owner;

REVOKE ALL ON SCHEMA hasad FROM PUBLIC, anon, authenticated;
REVOKE ALL ON SCHEMA hasad_api FROM PUBLIC, anon;
REVOKE ALL ON SCHEMA poc FROM PUBLIC, anon, authenticated;
REVOKE ALL ON ALL TABLES IN SCHEMA hasad FROM PUBLIC, anon, authenticated;
REVOKE ALL ON ALL TABLES IN SCHEMA poc FROM PUBLIC, anon, authenticated;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA hasad FROM PUBLIC, anon, authenticated;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA hasad_api FROM PUBLIC, anon, authenticated;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA auth FROM PUBLIC, anon, authenticated;

GRANT USAGE ON SCHEMA hasad_api TO authenticated;
GRANT EXECUTE ON FUNCTION hasad_api.poc_has_permission(uuid, text)
  TO authenticated;
GRANT EXECUTE ON FUNCTION hasad_api.poc_get_my_company()
  TO authenticated;
GRANT EXECUTE ON FUNCTION hasad_api.poc_get_company(uuid)
  TO authenticated;
GRANT EXECUTE ON FUNCTION hasad_api.poc_add_note(uuid, text)
  TO authenticated;
GRANT EXECUTE ON FUNCTION hasad_api.poc_audit_write(uuid, text, text, uuid, jsonb)
  TO authenticated;

-- The auth helpers must remain callable by the locked owner and by the test
-- roles only; they are not part of the application surface.
GRANT EXECUTE ON FUNCTION auth.uid() TO hasad_poc_owner, authenticated, anon;
GRANT EXECUTE ON FUNCTION auth.jwt() TO hasad_poc_owner, authenticated, anon;

-- Hostile objects used only to prove the pinned search_path.
CREATE FUNCTION public.has_permission(uuid, text)
RETURNS boolean
LANGUAGE sql
AS $fn$ SELECT true; $fn$;

CREATE TABLE public.companies (id uuid, status text);
INSERT INTO public.companies VALUES
  ('99999999-9999-9999-9999-999999999999', 'hostile');

COMMIT;
