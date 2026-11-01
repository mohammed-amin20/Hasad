-- REVIEW ONLY. Not an approved or deployable migration.
-- Uses company_settings.display_name, falling back to name_ar; companies has no name column.
-- products.read is proposed and is not seeded or granted here.
CREATE SCHEMA IF NOT EXISTS hasad_api;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_roles WHERE rolname = 'hasad_rpc_owner') THEN
    CREATE ROLE hasad_rpc_owner NOLOGIN NOSUPERUSER NOBYPASSRLS;
  END IF;
END $$;
GRANT USAGE ON SCHEMA hasad, auth, hasad_api TO hasad_rpc_owner;
GRANT CREATE ON SCHEMA hasad_api TO hasad_rpc_owner;
GRANT EXECUTE ON FUNCTION auth.uid() TO hasad_rpc_owner;
GRANT SELECT ON hasad.company_memberships, hasad.companies, hasad.company_settings,
  hasad.roles, hasad.permissions, hasad.role_permissions,
  hasad.user_permission_overrides, hasad.products TO hasad_rpc_owner;

-- Caller-scoped SELECT policies for this RPC owner only; no application-role table grants.
CREATE POLICY candidate_rpc_memberships ON hasad.company_memberships
  FOR SELECT TO hasad_rpc_owner USING (user_id = auth.uid() AND status = 'active');
CREATE POLICY candidate_rpc_companies ON hasad.companies
  FOR SELECT TO hasad_rpc_owner USING (EXISTS (
    SELECT 1 FROM hasad.company_memberships cm
    WHERE cm.company_id = companies.id AND cm.user_id = auth.uid() AND cm.status = 'active'));
CREATE POLICY candidate_rpc_company_settings ON hasad.company_settings
  FOR SELECT TO hasad_rpc_owner USING (EXISTS (
    SELECT 1 FROM hasad.company_memberships cm
    JOIN hasad.companies c ON c.id = cm.company_id AND c.status = 'active'
    WHERE cm.company_id = company_settings.company_id
      AND cm.user_id = auth.uid() AND cm.status = 'active'));
CREATE POLICY candidate_rpc_roles ON hasad.roles
  FOR SELECT TO hasad_rpc_owner USING (EXISTS (
    SELECT 1 FROM hasad.company_memberships cm
    WHERE cm.company_id = roles.company_id AND cm.user_id = auth.uid() AND cm.status = 'active'));
CREATE POLICY candidate_rpc_permission ON hasad.permissions
  FOR SELECT TO hasad_rpc_owner USING (code = 'products.read');
CREATE POLICY candidate_rpc_role_permissions ON hasad.role_permissions
  FOR SELECT TO hasad_rpc_owner USING (EXISTS (
    SELECT 1 FROM hasad.company_memberships cm
    WHERE cm.role_id = role_permissions.role_id
      AND cm.user_id = auth.uid() AND cm.status = 'active'));
CREATE POLICY candidate_rpc_overrides ON hasad.user_permission_overrides
  FOR SELECT TO hasad_rpc_owner USING (EXISTS (
    SELECT 1 FROM hasad.company_memberships cm
    WHERE cm.id = user_permission_overrides.membership_id
      AND cm.user_id = auth.uid() AND cm.status = 'active'));
CREATE POLICY candidate_rpc_products ON hasad.products
  FOR SELECT TO hasad_rpc_owner USING (EXISTS (
    SELECT 1 FROM hasad.company_memberships cm
    JOIN hasad.companies c ON c.id = cm.company_id AND c.status = 'active'
    WHERE cm.company_id = products.company_id
      AND cm.user_id = auth.uid() AND cm.status = 'active'));
CREATE TYPE hasad_api.company_context_dto AS (
  company_id uuid, company_name text, is_owner boolean, role_code text
);
CREATE TYPE hasad_api.product_dto AS (
  id uuid, company_id uuid, code text, name_ar text, name_en text,
  barcode text, category_id uuid, base_uom_id uuid,
  track_inventory boolean, is_active boolean
);

-- Dedicated NOLOGIN, NOBYPASSRLS owner. Must not own hasad tables.
-- Exact SELECT grants and caller-scoped RLS policies above restrict this owner
-- to the rows needed by these two functions; application roles get no table grants.
CREATE OR REPLACE FUNCTION hasad_api.whoami()
RETURNS hasad_api.company_context_dto
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = pg_catalog
AS $$
DECLARE v_uid uuid; v_ctx hasad_api.company_context_dto; v_memberships integer;
BEGIN
  v_uid := auth.uid();
  IF v_uid IS NULL THEN RAISE EXCEPTION 'UNAUTHORIZED' USING ERRCODE = '28000'; END IF;
  SELECT count(*) INTO v_memberships FROM hasad.company_memberships cm
   WHERE cm.user_id = v_uid AND cm.status = 'active';
  IF v_memberships > 1 THEN RAISE EXCEPTION 'MULTIPLE_MEMBERSHIPS' USING ERRCODE = '42501'; END IF;
  SELECT cm.company_id, COALESCE(cs.display_name, cs.name_ar), cm.is_owner, r.code
    INTO v_ctx.company_id, v_ctx.company_name, v_ctx.is_owner, v_ctx.role_code
  FROM hasad.company_memberships cm
  JOIN hasad.companies c ON c.id = cm.company_id
  LEFT JOIN hasad.company_settings cs ON cs.company_id = c.id
  LEFT JOIN hasad.roles r ON r.id = cm.role_id AND r.company_id = cm.company_id
  WHERE cm.user_id = v_uid AND cm.status = 'active' AND c.status = 'active';
  IF NOT FOUND THEN RAISE EXCEPTION 'NO_MEMBERSHIP' USING ERRCODE = 'P0001'; END IF;
  RETURN v_ctx;
END;
$$;

CREATE OR REPLACE FUNCTION hasad_api.products_list()
RETURNS SETOF hasad_api.product_dto
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = pg_catalog
AS $$
DECLARE v_uid uuid; v_company_id uuid; v_membership_id uuid; v_role_id uuid;
        v_memberships integer;
        v_is_owner boolean; v_effect text; v_role_allow boolean;
BEGIN
  v_uid := auth.uid();
  IF v_uid IS NULL THEN RAISE EXCEPTION 'UNAUTHORIZED' USING ERRCODE = '28000'; END IF;
  SELECT count(*) INTO v_memberships FROM hasad.company_memberships cm
   WHERE cm.user_id = v_uid AND cm.status = 'active';
  IF v_memberships > 1 THEN RAISE EXCEPTION 'MULTIPLE_MEMBERSHIPS' USING ERRCODE = '42501'; END IF;
  SELECT cm.company_id, cm.id, cm.role_id, cm.is_owner
    INTO v_company_id, v_membership_id, v_role_id, v_is_owner
  FROM hasad.company_memberships cm
  JOIN hasad.companies c ON c.id = cm.company_id
  WHERE cm.user_id = v_uid AND cm.status = 'active' AND c.status = 'active';
  IF NOT FOUND THEN RAISE EXCEPTION 'NO_MEMBERSHIP' USING ERRCODE = 'P0001'; END IF;
  SELECT o.effect INTO v_effect FROM hasad.user_permission_overrides o
   WHERE o.membership_id = v_membership_id AND o.permission_code = 'products.read';
  SELECT EXISTS (SELECT 1 FROM hasad.role_permissions rp
                  WHERE rp.role_id = v_role_id AND rp.permission_code = 'products.read')
    INTO v_role_allow;
  -- Resolver precedence: owner, explicit deny, explicit allow, role grant, default deny.
  IF NOT v_is_owner AND (v_effect = 'deny' OR
      (v_effect IS DISTINCT FROM 'allow' AND NOT COALESCE(v_role_allow, false))) THEN
    RAISE EXCEPTION 'DENIED' USING ERRCODE = '42501';
  END IF;
  RETURN QUERY SELECT p.id, p.company_id, p.code, p.name_ar, p.name_en,
      p.barcode, p.category_id, p.base_uom_id, p.track_inventory, p.is_active
    FROM hasad.products p WHERE p.company_id = v_company_id ORDER BY p.code;
END;
$$;

REVOKE ALL ON FUNCTION hasad_api.whoami() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION hasad_api.products_list() FROM PUBLIC, anon;
ALTER FUNCTION hasad_api.whoami() OWNER TO hasad_rpc_owner;
ALTER FUNCTION hasad_api.products_list() OWNER TO hasad_rpc_owner;
REVOKE CREATE ON SCHEMA hasad_api FROM hasad_rpc_owner;
-- EXECUTE grants intentionally omitted pending approval.
