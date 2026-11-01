-- HASAD V2 — CANDIDATE (NOT APPROVED FOR DEPLOYMENT)
-- Purpose: minimal secure RPCs for whoami/company context and product listing
-- Scope: hasad_api schema only; no direct grants to hasad tables; no policies/RPC grants to clients
-- Security: derive auth.uid() server-side; enforce active membership + active company; one-company-per-user (D-003)
-- Notes:
--   - All hasad tables remain private with RLS ENABLE+FORCE and no application grants/policies
--   - Prefer SECURITY INVOKER with enumerated privileges. If not feasible due to private-table privileges,
--     use a narrowly scoped SECURITY DEFINER with a dedicated non-superuser/non-BYPASSRLS role and pinned search_path.
--   - No service_role usage; no direct table access for authenticated.
--   - Permission gating: prefer existing approved permission (see catalogue). If none, gate behind explicit approved code only.

BEGIN;

-- Create API schema if missing (reserved; review separately)
CREATE SCHEMA IF NOT EXISTS hasad_api;

-- Helper types for DTOs (explicit shape)
CREATE TYPE hasad_api.company_context_dto AS (
  company_id uuid,
  company_name text,
  is_owner boolean,
  role_code text
);

CREATE TYPE hasad_api.product_dto AS (
  id uuid,
  company_id uuid,
  code text,
  name_ar text,
  name_en text,
  barcode text,
  category_id uuid,
  base_uom_id uuid,
  track_inventory boolean,
  is_active boolean
);

-- Example SECURITY INVOKER skeleton (may require underlying SELECT privileges)
-- COMMENT: This skeleton is for review only. Do not EXECUTE GRANT without approved PoC.
CREATE OR REPLACE FUNCTION hasad_api.whoami()
RETURNS hasad_api.company_context_dto
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = pg_catalog, public, hasad
AS $$
DECLARE
  v_uid uuid;
  v_ctx hasad_api.company_context_dto;
BEGIN
  v_uid := auth.uid();
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'UNAUTHORIZED' USING ERRCODE = '28000';
  END IF;

  SELECT cm.company_id,
         COALESCE(cs.display_name, cs.name_ar),
         cm.is_owner,
         r.code
    INTO v_ctx.company_id, v_ctx.company_name, v_ctx.is_owner, v_ctx.role_code
  FROM hasad.company_memberships cm
  JOIN hasad.companies c ON c.id = cm.company_id
  LEFT JOIN hasad.company_settings cs ON cs.company_id = c.id
  LEFT JOIN hasad.roles r ON r.id = cm.role_id AND r.company_id = cm.company_id
  WHERE cm.user_id = (SELECT up.id FROM hasad.user_profiles up WHERE up.id = v_uid)
    AND cm.status = 'active'
    AND c.status = 'active'
  ORDER BY cm.created_at NULLS LAST
  LIMIT 1;

  IF v_ctx.company_id IS NULL THEN
    RAISE EXCEPTION 'NO_MEMBERSHIP' USING ERRCODE = 'P0001';
  END IF;

  -- NOTE: one-company-per-user enforced by UNIQUE(user_id) on company_memberships
  RETURN v_ctx;
EXCEPTION
  WHEN NO_DATA_FOUND THEN
    RAISE EXCEPTION 'NO_MEMBERSHIP' USING ERRCODE = 'P0001';
  WHEN TOO_MANY_ROWS THEN
    -- Should not happen due to UNIQUE(user_id); treat as denial if somehow occurs
    RAISE EXCEPTION 'DENIED' USING ERRCODE = '42501';
END;
$$;

-- Product listing: minimal fields only
CREATE OR REPLACE FUNCTION hasad_api.products_list()
RETURNS SETOF hasad_api.product_dto
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = pg_catalog, public, hasad
AS $$
DECLARE
  v_uid uuid;
  v_company_id uuid;
BEGIN
  v_uid := auth.uid();
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'UNAUTHORIZED' USING ERRCODE = '28000';
  END IF;

  -- Derive company from active membership (never trust client)
  SELECT cm.company_id
    INTO v_company_id
  FROM hasad.company_memberships cm
  JOIN hasad.companies c ON c.id = cm.company_id
  WHERE cm.user_id = (SELECT up.id FROM hasad.user_profiles up WHERE up.id = v_uid)
    AND cm.status = 'active'
    AND c.status = 'active'
  ORDER BY cm.created_at NULLS LAST
  LIMIT 1;

  IF v_company_id IS NULL THEN
    RAISE EXCEPTION 'NO_MEMBERSHIP' USING ERRCODE = 'P0001';
  END IF;

  -- Permission check placeholder (map to approved code). Do not assume 'products.read' exists.
  -- Example: require has_permission or role mapping; implementation depends on approved contract.
  -- IF NOT has_permission(v_uid, v_company_id, 'products.read') THEN RAISE EXCEPTION 'DENIED' USING ERRCODE='42501'; END IF;

  RETURN QUERY
  SELECT p.id,
         p.company_id,
         p.code,
         p.name_ar,
         p.name_en,
         p.barcode,
         p.category_id,
         p.base_uom_id,
         p.track_inventory,
         p.is_active
  FROM hasad.products p
  WHERE p.company_id = v_company_id
  ORDER BY p.code;
END;
$$;

-- DO NOT GRANT: EXECUTE must only be granted after PoC approval and with anon denied
-- REVOKE ALL ON FUNCTION hasad_api.whoami() FROM PUBLIC;
-- REVOKE ALL ON FUNCTION hasad_api.products_list() FROM PUBLIC;
-- GRANT EXECUTE ON FUNCTION hasad_api.whoami() TO authenticated;
-- GRANT EXECUTE ON FUNCTION hasad_api.products_list() TO authenticated;

COMMIT;
