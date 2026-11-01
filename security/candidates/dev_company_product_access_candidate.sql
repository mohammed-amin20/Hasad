-- FOR OWNER REVIEW ONLY. Not deployed; not in supabase/migrations.
-- Target snapshot: DEV sxasnunzspkuwbxiddqd, observed 2026-10-28.
-- Adds only the locked RPC owner, caller-scoped owner policies/grants, one
-- products.read catalogue code, a private resolver, and two client RPCs.
-- It assigns no permissions to roles automatically.
-- PostgREST exposed-schema configuration is separate. DEV owner confirmed
-- hasad_api is exposed and hasad is excluded; this SQL does not change settings.

BEGIN;

DO $preflight$
DECLARE v_count integer;
BEGIN
  IF to_regnamespace('hasad') IS NULL OR to_regnamespace('hasad_api') IS NULL THEN
    RAISE EXCEPTION 'PREFLIGHT_SCHEMA_MISSING';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname='hasad_rpc_owner') THEN
    RAISE EXCEPTION 'PREFLIGHT_RPC_OWNER_ALREADY_EXISTS';
  END IF;
  SELECT count(*) INTO v_count
  FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
  WHERE n.nspname='hasad'
    AND c.relname IN ('company_memberships','companies','company_settings','roles',
      'permissions','role_permissions','user_permission_overrides','products')
    AND c.relkind IN ('r','p') AND c.relrowsecurity AND c.relforcerowsecurity;
  IF v_count <> 8 THEN RAISE EXCEPTION 'PREFLIGHT_REQUIRED_RLS_TABLES_CHANGED'; END IF;
  IF EXISTS (
    SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
    WHERE n.nspname='hasad' AND c.relkind IN ('r','p')
      AND (has_table_privilege('authenticated',c.oid,'SELECT')
        OR has_table_privilege('authenticated',c.oid,'INSERT')
        OR has_table_privilege('authenticated',c.oid,'UPDATE')
        OR has_table_privilege('authenticated',c.oid,'DELETE')
        OR has_table_privilege('authenticated',c.oid,'TRUNCATE')
        OR has_table_privilege('authenticated',c.oid,'REFERENCES')
        OR has_table_privilege('authenticated',c.oid,'TRIGGER')
        OR has_table_privilege('anon',c.oid,'SELECT')
        OR has_table_privilege('anon',c.oid,'INSERT')
        OR has_table_privilege('anon',c.oid,'UPDATE')
        OR has_table_privilege('anon',c.oid,'DELETE')
        OR has_table_privilege('anon',c.oid,'TRUNCATE')
        OR has_table_privilege('anon',c.oid,'REFERENCES')
        OR has_table_privilege('anon',c.oid,'TRIGGER'))) OR EXISTS (
    SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
    CROSS JOIN LATERAL aclexplode(COALESCE(c.relacl,acldefault('r',c.relowner))) a
    WHERE n.nspname='hasad' AND c.relkind IN ('r','p') AND a.grantee=0
      AND a.privilege_type IN ('SELECT','INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER')) THEN
    RAISE EXCEPTION 'PREFLIGHT_DIRECT_TABLE_PRIVILEGES_CHANGED';
  END IF;
  IF has_schema_privilege('authenticated','hasad','USAGE')
     OR has_schema_privilege('anon','hasad','USAGE')
     OR has_schema_privilege('authenticated','hasad_api','CREATE')
     OR has_schema_privilege('anon','hasad_api','CREATE')
     OR EXISTS (SELECT 1 FROM pg_namespace ns
       CROSS JOIN LATERAL aclexplode(COALESCE(ns.nspacl,acldefault('n',ns.nspowner))) a
       WHERE ns.nspname IN ('hasad','hasad_api') AND a.grantee=0
         AND a.privilege_type IN ('USAGE','CREATE')) THEN
    RAISE EXCEPTION 'PREFLIGHT_CLIENT_SCHEMA_PRIVILEGES_CHANGED';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname IN ('hasad','hasad_api')) THEN
    RAISE EXCEPTION 'PREFLIGHT_FUNCTIONS_ALREADY_EXIST';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='hasad') THEN
    RAISE EXCEPTION 'PREFLIGHT_RLS_POLICIES_CHANGED';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
    WHERE n.nspname='hasad_api' AND c.relkind IN ('r','p','v','m','S')) THEN
    RAISE EXCEPTION 'PREFLIGHT_API_RELATIONS_ALREADY_EXIST';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_type t JOIN pg_namespace n ON n.oid=t.typnamespace
    WHERE n.nspname='hasad_api' AND t.typrelid=0 AND t.typtype IN ('c','d','e','r','m')) THEN
    RAISE EXCEPTION 'PREFLIGHT_API_TYPES_ALREADY_EXIST';
  END IF;
END
$preflight$;

-- Proposed catalogue definition. ON CONFLICT preserves any existing record; the
-- assertion prevents silently accepting a code attached to a different module.
INSERT INTO hasad.permissions(code,module,description)
VALUES ('products.read','products','Read products for the caller''s active company')
ON CONFLICT (code) DO NOTHING;
DO $permission$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM hasad.permissions WHERE code='products.read' AND module='products') THEN
    RAISE EXCEPTION 'PRODUCTS_READ_CATALOGUE_CONFLICT';
  END IF;
END
$permission$;

CREATE ROLE hasad_rpc_owner
  NOLOGIN NOINHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE NOBYPASSRLS;
GRANT USAGE ON SCHEMA hasad, auth, hasad_api TO hasad_rpc_owner;
GRANT CREATE ON SCHEMA hasad_api TO hasad_rpc_owner;
GRANT EXECUTE ON FUNCTION auth.uid() TO hasad_rpc_owner;
GRANT SELECT ON hasad.company_memberships, hasad.companies, hasad.company_settings,
  hasad.roles, hasad.permissions, hasad.role_permissions,
  hasad.user_permission_overrides, hasad.products TO hasad_rpc_owner;

-- Each policy is limited to the authenticated caller's active membership and
-- active company. FORCE RLS remains enabled and is asserted again in preflight.
CREATE POLICY hasad_rpc_owner_memberships ON hasad.company_memberships
  FOR SELECT TO hasad_rpc_owner
  USING (user_id=auth.uid() AND status='active');
CREATE POLICY hasad_rpc_owner_companies ON hasad.companies
  FOR SELECT TO hasad_rpc_owner
  USING (status='active' AND EXISTS (
    SELECT 1 FROM hasad.company_memberships cm
    WHERE cm.company_id=companies.id AND cm.user_id=auth.uid() AND cm.status='active'));
CREATE POLICY hasad_rpc_owner_company_settings ON hasad.company_settings
  FOR SELECT TO hasad_rpc_owner
  USING (EXISTS (
    SELECT 1 FROM hasad.company_memberships cm
    JOIN hasad.companies c ON c.id=cm.company_id AND c.status='active'
    WHERE cm.company_id=company_settings.company_id
      AND cm.user_id=auth.uid() AND cm.status='active'));
CREATE POLICY hasad_rpc_owner_roles ON hasad.roles
  FOR SELECT TO hasad_rpc_owner
  USING (EXISTS (
    SELECT 1 FROM hasad.company_memberships cm
    JOIN hasad.companies c ON c.id=cm.company_id AND c.status='active'
    WHERE cm.company_id=roles.company_id AND cm.user_id=auth.uid() AND cm.status='active'));
CREATE POLICY hasad_rpc_owner_products_permission ON hasad.permissions
  FOR SELECT TO hasad_rpc_owner USING (code='products.read');
CREATE POLICY hasad_rpc_owner_role_permissions ON hasad.role_permissions
  FOR SELECT TO hasad_rpc_owner
  USING (EXISTS (
    SELECT 1 FROM hasad.company_memberships cm
    JOIN hasad.companies c ON c.id=cm.company_id AND c.status='active'
    WHERE cm.role_id=role_permissions.role_id
      AND cm.user_id=auth.uid() AND cm.status='active'));
CREATE POLICY hasad_rpc_owner_overrides ON hasad.user_permission_overrides
  FOR SELECT TO hasad_rpc_owner
  USING (EXISTS (
    SELECT 1 FROM hasad.company_memberships cm
    JOIN hasad.companies c ON c.id=cm.company_id AND c.status='active'
    WHERE cm.id=user_permission_overrides.membership_id
      AND cm.user_id=auth.uid() AND cm.status='active'));
CREATE POLICY hasad_rpc_owner_products ON hasad.products
  FOR SELECT TO hasad_rpc_owner
  USING (EXISTS (
    SELECT 1 FROM hasad.company_memberships cm
    JOIN hasad.companies c ON c.id=cm.company_id AND c.status='active'
    WHERE cm.company_id=products.company_id
      AND cm.user_id=auth.uid() AND cm.status='active'));

CREATE TYPE hasad_api.company_context_dto AS (
  company_id uuid, company_name text, is_owner boolean, role_code text
);
CREATE TYPE hasad_api.product_dto AS (
  id uuid, company_id uuid, code text, name_ar text, name_en text,
  barcode text, category_id uuid, base_uom_id uuid,
  track_inventory boolean, is_active boolean
);
-- Composite return types are usable by the authenticated RPC caller only.
REVOKE ALL ON TYPE hasad_api.company_context_dto, hasad_api.product_dto
  FROM PUBLIC, anon, authenticated;
GRANT USAGE ON TYPE hasad_api.company_context_dto, hasad_api.product_dto TO authenticated;

-- Private canonical resolver. Precedence follows the approved owner rule:
-- owner ignores overrides; otherwise deny override, allow override, role, default deny.
CREATE OR REPLACE FUNCTION hasad.has_permission(
  p_membership_id uuid, p_role_id uuid, p_is_owner boolean, p_permission_code text
) RETURNS boolean
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path=pg_catalog,pg_temp
AS $$
  SELECT CASE
    WHEN p_is_owner THEN true
    WHEN EXISTS (SELECT 1 FROM hasad.user_permission_overrides o
      WHERE o.membership_id=p_membership_id AND o.permission_code=p_permission_code AND o.effect='deny')
      THEN false
    WHEN EXISTS (SELECT 1 FROM hasad.user_permission_overrides o
      WHERE o.membership_id=p_membership_id AND o.permission_code=p_permission_code AND o.effect='allow')
      THEN true
    ELSE EXISTS (SELECT 1 FROM hasad.role_permissions rp
      WHERE rp.role_id=p_role_id AND rp.permission_code=p_permission_code)
  END
$$;

CREATE OR REPLACE FUNCTION hasad_api.whoami()
RETURNS hasad_api.company_context_dto
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path=pg_catalog,pg_temp
AS $$
DECLARE v_uid uuid; v_ctx hasad_api.company_context_dto; v_active_count integer;
BEGIN
  v_uid := auth.uid();
  IF v_uid IS NULL THEN RAISE EXCEPTION 'UNAUTHORIZED' USING ERRCODE='28000'; END IF;
  SELECT count(*) INTO v_active_count FROM hasad.company_memberships cm
  WHERE cm.user_id=v_uid AND cm.status='active';
  IF v_active_count>1 THEN RAISE EXCEPTION 'MULTIPLE_MEMBERSHIPS' USING ERRCODE='42501'; END IF;
  SELECT cm.company_id,COALESCE(cs.display_name,cs.name_ar),cm.is_owner,r.code
    INTO v_ctx.company_id,v_ctx.company_name,v_ctx.is_owner,v_ctx.role_code
  FROM hasad.company_memberships cm
  JOIN hasad.companies c ON c.id=cm.company_id AND c.status='active'
  LEFT JOIN hasad.company_settings cs ON cs.company_id=c.id
  LEFT JOIN hasad.roles r ON r.id=cm.role_id AND r.company_id=cm.company_id
  WHERE cm.user_id=v_uid AND cm.status='active';
  IF NOT FOUND THEN RAISE EXCEPTION 'NO_MEMBERSHIP' USING ERRCODE='P0001'; END IF;
  RETURN v_ctx;
END
$$;

CREATE OR REPLACE FUNCTION hasad_api.products_list()
RETURNS SETOF hasad_api.product_dto
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path=pg_catalog,pg_temp
AS $$
DECLARE v_uid uuid; v_company_id uuid; v_membership_id uuid;
        v_role_id uuid; v_is_owner boolean; v_active_count integer;
BEGIN
  v_uid := auth.uid();
  IF v_uid IS NULL THEN RAISE EXCEPTION 'UNAUTHORIZED' USING ERRCODE='28000'; END IF;
  SELECT count(*) INTO v_active_count FROM hasad.company_memberships cm
  WHERE cm.user_id=v_uid AND cm.status='active';
  IF v_active_count>1 THEN RAISE EXCEPTION 'MULTIPLE_MEMBERSHIPS' USING ERRCODE='42501'; END IF;
  SELECT cm.company_id,cm.id,cm.role_id,cm.is_owner
    INTO v_company_id,v_membership_id,v_role_id,v_is_owner
  FROM hasad.company_memberships cm
  JOIN hasad.companies c ON c.id=cm.company_id AND c.status='active'
  WHERE cm.user_id=v_uid AND cm.status='active';
  IF NOT FOUND THEN RAISE EXCEPTION 'NO_MEMBERSHIP' USING ERRCODE='P0001'; END IF;
  IF NOT hasad.has_permission(v_membership_id,v_role_id,v_is_owner,'products.read') THEN
    RAISE EXCEPTION 'DENIED' USING ERRCODE='42501';
  END IF;
  RETURN QUERY SELECT p.id,p.company_id,p.code,p.name_ar,p.name_en,
      p.barcode,p.category_id,p.base_uom_id,p.track_inventory,p.is_active
  FROM hasad.products p
  WHERE p.company_id=v_company_id
  ORDER BY p.code;
END
$$;

REVOKE ALL ON FUNCTION hasad.has_permission(uuid,uuid,boolean,text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION hasad_api.whoami() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION hasad_api.products_list() FROM PUBLIC, anon;
GRANT CREATE ON SCHEMA hasad TO hasad_rpc_owner;
ALTER FUNCTION hasad.has_permission(uuid,uuid,boolean,text) OWNER TO hasad_rpc_owner;
ALTER FUNCTION hasad_api.whoami() OWNER TO hasad_rpc_owner;
ALTER FUNCTION hasad_api.products_list() OWNER TO hasad_rpc_owner;
REVOKE CREATE ON SCHEMA hasad,hasad_api FROM hasad_rpc_owner;

REVOKE ALL ON SCHEMA hasad_api FROM PUBLIC, anon;
GRANT USAGE ON SCHEMA hasad_api TO authenticated;
GRANT EXECUTE ON FUNCTION hasad_api.whoami() TO authenticated;
GRANT EXECUTE ON FUNCTION hasad_api.products_list() TO authenticated;

COMMIT;

-- DEV's exposed-schema list is configured separately and already excludes
-- hasad while exposing hasad_api; this candidate makes no PostgREST change.
