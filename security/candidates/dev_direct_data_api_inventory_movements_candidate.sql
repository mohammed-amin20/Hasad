-- REVIEW ONLY / NOT DEPLOYED / DEV ONLY.
-- Unit D: atomic stock receipts, issues, and transfers for Hasad V2.
-- Uses the owner-approved DEV direct Data API surface in exposed schema `hasad`.
--
-- Security design:
--   * Authenticated clients get READ-ONLY access to stock_movements.
--   * Stock quantities are written only by three SECURITY DEFINER functions.
--   * The function owner is a dedicated NOLOGIN / NOINHERIT / NOSUPERUSER /
--     NOCREATEDB / NOCREATEROLE / NOBYPASSRLS role. It is never `postgres`
--     and `authenticated` is not a member of it.
--   * The owner receives narrow column-level grants plus permissive RLS
--     policies scoped to that role only. FORCE RLS stays enabled everywhere.
--   * The actor identity comes from `request.jwt.claims`, avoiding the
--     documented auth-schema USAGE blocker without weakening auth.
--   * Every function pins search_path to pg_catalog, pg_temp and fully
--     schema-qualifies every relation.
--   * Duplicate submissions are rejected before any balance change by
--     client-supplied movement UUIDs (idempotency keys).
--   * Concurrent posting for the same product is serialized with a
--     transaction-scoped advisory lock, protecting the per-product `seq`
--     and preventing concurrent overselling.
--
-- The preflight below rechecks all eleven referenced tables, FORCE RLS, executor
-- ownership/CREATEROLE, direct-client write grants, anon access, and existing
-- function names on the target immediately before any candidate DDL.
--
-- NOT APPLIED. Costing policy is owner-approved; separate deployment
-- authorization and successful hosted DEV preflight are still required.

BEGIN;

DO $preflight$
DECLARE
  v_problem text;
BEGIN
  IF EXISTS (
    SELECT 1
    FROM pg_catalog.pg_class c
    JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'hasad'
      AND c.relname IN (
        'stock_movements', 'stock_levels', 'warehouses', 'products',
        'company_memberships', 'companies', 'roles', 'permissions',
        'role_permissions', 'user_permission_overrides', 'audit_log'
      )
      AND (NOT c.relrowsecurity OR NOT c.relforcerowsecurity)
  ) THEN
    RAISE EXCEPTION 'PREFLIGHT_FORCE_RLS';
  END IF;

  SELECT string_agg(c.relname, ', ' ORDER BY c.relname)
  INTO v_problem
  FROM pg_catalog.pg_class c
  JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'hasad'
    AND c.relname IN (
      'stock_movements', 'stock_levels', 'warehouses', 'products',
      'company_memberships', 'companies', 'roles', 'permissions',
      'role_permissions', 'user_permission_overrides', 'audit_log'
    )
    AND pg_catalog.pg_get_userbyid(c.relowner) <> current_user;
  IF v_problem IS NOT NULL THEN
    RAISE EXCEPTION 'PREFLIGHT_OWNERSHIP: %', v_problem;
  END IF;

  IF pg_catalog.has_schema_privilege('anon', 'hasad', 'USAGE')
     OR pg_catalog.has_table_privilege('anon', 'hasad.stock_movements', 'SELECT,INSERT,UPDATE,DELETE')
     OR pg_catalog.has_table_privilege('anon', 'hasad.stock_levels', 'SELECT,INSERT,UPDATE,DELETE')
     OR pg_catalog.has_any_column_privilege('anon', 'hasad.stock_movements', 'SELECT,INSERT,UPDATE')
     OR pg_catalog.has_any_column_privilege('anon', 'hasad.stock_levels', 'SELECT,INSERT,UPDATE') THEN
    RAISE EXCEPTION 'PREFLIGHT_ANON_ACCESS';
  END IF;

  IF pg_catalog.has_table_privilege('authenticated', 'hasad.stock_movements', 'INSERT,UPDATE,DELETE')
     OR pg_catalog.has_table_privilege('authenticated', 'hasad.stock_levels', 'INSERT,UPDATE,DELETE')
     OR pg_catalog.has_any_column_privilege('authenticated', 'hasad.stock_movements', 'INSERT,UPDATE')
     OR pg_catalog.has_any_column_privilege('authenticated', 'hasad.stock_levels', 'INSERT,UPDATE') THEN
    RAISE EXCEPTION 'PREFLIGHT_AUTHENTICATED_DIRECT_WRITE';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_roles
    WHERE rolname = current_user
      AND (rolsuper OR rolcreaterole)
  ) THEN
    RAISE EXCEPTION 'PREFLIGHT_NO_CREATEROLE';
  END IF;

  IF NOT pg_catalog.has_schema_privilege(current_user, 'hasad', 'CREATE') THEN
    RAISE EXCEPTION 'PREFLIGHT_NO_SCHEMA_CREATE';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM pg_catalog.pg_proc p
    JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'hasad'
      AND p.proname IN (
        'inventory_post_allowed', 'post_stock_receipt',
        'post_stock_issue', 'post_stock_transfer'
      )
  ) THEN
    RAISE EXCEPTION 'PREFLIGHT_POSTING_FUNCTION_ALREADY_EXISTS';
  END IF;
END
$preflight$;

-- Dedicated locked owner for stock posting only.
DO $rolesetup$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_roles WHERE rolname = 'hasad_inventory_poster'
  ) THEN
    CREATE ROLE hasad_inventory_poster
      NOLOGIN
      NOINHERIT
      NOSUPERUSER
      NOCREATEDB
      NOCREATEROLE
      NOREPLICATION
      NOBYPASSRLS;
  END IF;

  IF EXISTS (
    SELECT 1
    FROM pg_catalog.pg_roles
    WHERE rolname = 'hasad_inventory_poster'
      AND (
        rolcanlogin OR rolsuper OR rolcreatedb OR rolcreaterole
        OR rolreplication OR rolbypassrls
      )
  ) THEN
    RAISE EXCEPTION 'PREFLIGHT_POSTER_ROLE_UNSAFE';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM pg_catalog.pg_auth_members m
    JOIN pg_catalog.pg_roles granted ON granted.oid = m.roleid
    JOIN pg_catalog.pg_roles member ON member.oid = m.member
    WHERE granted.rolname = 'hasad_inventory_poster'
      AND member.rolname IN ('authenticated', 'anon')
  ) THEN
    RAISE EXCEPTION 'PREFLIGHT_POSTER_ROLE_GRANTED_TO_CLIENT';
  END IF;

  -- Allows the executor to alter function ownership and audit/repair later.
  -- The executor already owns the tables and is BYPASSRLS, so this does not
  -- widen the effective security boundary for application clients.
  EXECUTE pg_catalog.format(
    'GRANT hasad_inventory_poster TO %I', current_user
  );
END
$rolesetup$;

GRANT USAGE ON SCHEMA hasad TO hasad_inventory_poster;
GRANT USAGE ON SCHEMA hasad TO authenticated;

GRANT SELECT (id, company_id, user_id, role_id, is_owner, status)
  ON hasad.company_memberships TO hasad_inventory_poster;
GRANT SELECT (id, status)
  ON hasad.companies TO hasad_inventory_poster;
GRANT SELECT (id, company_id)
  ON hasad.roles TO hasad_inventory_poster;
GRANT SELECT (code, module)
  ON hasad.permissions TO hasad_inventory_poster;
GRANT SELECT (role_id, permission_code)
  ON hasad.role_permissions TO hasad_inventory_poster;
GRANT SELECT (membership_id, permission_code, effect)
  ON hasad.user_permission_overrides TO hasad_inventory_poster;
GRANT SELECT (id, company_id, is_active, track_inventory)
  ON hasad.products TO hasad_inventory_poster;
GRANT SELECT (id, company_id, is_active)
  ON hasad.warehouses TO hasad_inventory_poster;

GRANT SELECT (company_id, product_id, warehouse_id, qty, last_unit_cost),
      INSERT (company_id, product_id, warehouse_id, qty, last_unit_cost)
  ON hasad.stock_levels TO hasad_inventory_poster;

-- Table-level UPDATE is required for SELECT ... FOR UPDATE row locking.
-- This privilege belongs only to the NOLOGIN poster role; authenticated
-- still has no INSERT/UPDATE access to stock_levels.
GRANT UPDATE ON hasad.stock_levels TO hasad_inventory_poster;

GRANT SELECT (
        id, company_id, product_id, warehouse_id, movement_type, direction,
        qty, unit_cost, value, seq, source_document_type, source_document_id,
        journal_line_id, posted_at
      ),
      INSERT (
        id, company_id, product_id, warehouse_id, movement_type, direction,
        qty, unit_cost, value, seq, source_document_type, source_document_id,
        journal_line_id
      )
  ON hasad.stock_movements TO hasad_inventory_poster;
GRANT INSERT (
        id, company_id, actor_user_id, action, entity_type, entity_id, details
      ) ON hasad.audit_log TO hasad_inventory_poster;

-- Permissive policies apply only to the locked poster role. No client can
-- assume this role, so authenticated/anon tenant isolation is unchanged.
CREATE POLICY inventory_poster_memberships_read
  ON hasad.company_memberships
  FOR SELECT TO hasad_inventory_poster
  USING (true);

CREATE POLICY inventory_poster_companies_read
  ON hasad.companies
  FOR SELECT TO hasad_inventory_poster
  USING (true);

CREATE POLICY inventory_poster_roles_read
  ON hasad.roles
  FOR SELECT TO hasad_inventory_poster
  USING (true);

CREATE POLICY inventory_poster_permissions_read
  ON hasad.permissions
  FOR SELECT TO hasad_inventory_poster
  USING (true);

CREATE POLICY inventory_poster_role_permissions_read
  ON hasad.role_permissions
  FOR SELECT TO hasad_inventory_poster
  USING (true);

CREATE POLICY inventory_poster_overrides_read
  ON hasad.user_permission_overrides
  FOR SELECT TO hasad_inventory_poster
  USING (true);

CREATE POLICY inventory_poster_products_read
  ON hasad.products
  FOR SELECT TO hasad_inventory_poster
  USING (true);

CREATE POLICY inventory_poster_warehouses_read
  ON hasad.warehouses
  FOR SELECT TO hasad_inventory_poster
  USING (true);

CREATE POLICY inventory_poster_stock_levels_all
  ON hasad.stock_levels
  FOR ALL TO hasad_inventory_poster
  USING (true)
  WITH CHECK (true);

CREATE POLICY inventory_poster_stock_movements_read
  ON hasad.stock_movements
  FOR SELECT TO hasad_inventory_poster
  USING (true);

CREATE POLICY inventory_poster_stock_movements_insert
  ON hasad.stock_movements
  FOR INSERT TO hasad_inventory_poster
  WITH CHECK (true);

CREATE POLICY inventory_poster_audit_insert
  ON hasad.audit_log
  FOR INSERT TO hasad_inventory_poster
  WITH CHECK (true);

-- Read-only movement history for authenticated same-company users.
GRANT SELECT (
  id, company_id, product_id, warehouse_id, movement_type, direction,
  qty, unit_cost, value, seq, source_document_type, source_document_id,
  journal_line_id, posted_at
) ON hasad.stock_movements TO authenticated;

CREATE POLICY direct_authenticated_stock_movements_read
  ON hasad.stock_movements
  FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1
      FROM hasad.company_memberships cm
      JOIN hasad.companies c
        ON c.id = cm.company_id AND c.status = 'active'
      WHERE cm.company_id = stock_movements.company_id
        AND cm.user_id = auth.uid()
        AND cm.status = 'active'
    )
  );

-- Reproduce the approved owner -> deny override -> allow grant -> deny
-- permission order using live rows. This helper runs as the locked poster role
-- under FORCE RLS; application roles cannot execute it or assume its owner.
CREATE OR REPLACE FUNCTION hasad.inventory_post_allowed(
  p_company_id uuid,
  p_user_id uuid
) RETURNS boolean
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = pg_catalog, pg_temp
AS $fn$
  SELECT EXISTS (
    SELECT 1
    FROM hasad.company_memberships cm
    JOIN hasad.companies c
      ON c.id = cm.company_id AND c.status = 'active'
    JOIN hasad.permissions p
      ON p.code = 'inventory.post' AND p.module = 'inventory'
    LEFT JOIN hasad.user_permission_overrides uo
      ON uo.membership_id = cm.id
     AND uo.permission_code = p.code
    WHERE cm.company_id = p_company_id
      AND cm.user_id = p_user_id
      AND cm.status = 'active'
      AND (
        cm.is_owner
        OR (
          uo.effect IS DISTINCT FROM 'deny'
          AND (
            uo.effect = 'allow'
            OR EXISTS (
              SELECT 1
              FROM hasad.role_permissions rp
              JOIN hasad.roles r
                ON r.id = rp.role_id AND r.company_id = cm.company_id
              WHERE rp.role_id = cm.role_id
                AND rp.permission_code = p.code
            )
          )
        )
      )
  );
$fn$;
REVOKE ALL ON FUNCTION hasad.inventory_post_allowed(uuid, uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION hasad.inventory_post_allowed(uuid, uuid)
  TO hasad_inventory_poster;

-- ---------------------------------------------------------------- receipt --
CREATE OR REPLACE FUNCTION hasad.post_stock_receipt(
  p_movement_id uuid,
  p_company_id uuid,
  p_warehouse_id uuid,
  p_product_id uuid,
  p_qty numeric,
  p_unit_cost numeric
) RETURNS hasad.stock_movements
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $fn$
DECLARE
  v_claims jsonb;
  v_user_id uuid;
  v_existing hasad.stock_movements;
  v_level hasad.stock_levels;
  v_movement hasad.stock_movements;
  v_qty numeric(19,4) := pg_catalog.round(p_qty, 4);
  v_cost numeric(19,4) := pg_catalog.round(p_unit_cost, 4);
  v_new_qty numeric(19,4);
  v_new_cost numeric(19,4);
  v_seq bigint;
BEGIN
  IF p_movement_id IS NULL
     OR p_company_id IS NULL
     OR p_warehouse_id IS NULL
     OR p_product_id IS NULL THEN
    RAISE EXCEPTION 'INVALID_ARGUMENT';
  END IF;

  v_claims := NULLIF(
    pg_catalog.current_setting('request.jwt.claims', true), ''
  )::jsonb;
  v_user_id := NULLIF(v_claims->>'sub', '')::uuid;
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'UNAUTHENTICATED' USING ERRCODE = '42501';
  END IF;

  IF p_qty IS NULL OR p_qty <= 0 OR v_qty <= 0 THEN
    RAISE EXCEPTION 'QTY_INVALID';
  END IF;
  IF p_qty <> v_qty THEN
    RAISE EXCEPTION 'QTY_PRECISION';
  END IF;
  IF p_unit_cost IS NULL OR p_unit_cost < 0 OR v_cost < 0 THEN
    RAISE EXCEPTION 'COST_INVALID';
  END IF;
  IF p_unit_cost <> v_cost THEN
    RAISE EXCEPTION 'COST_PRECISION';
  END IF;

  IF NOT hasad.inventory_post_allowed(p_company_id, v_user_id) THEN
    RAISE EXCEPTION 'FORBIDDEN' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_existing
  FROM hasad.stock_movements
  WHERE id = p_movement_id;
  IF FOUND THEN
    IF v_existing.company_id = p_company_id
       AND v_existing.product_id = p_product_id
       AND v_existing.warehouse_id = p_warehouse_id
       AND v_existing.movement_type = 'purchase_receipt'
       AND v_existing.direction = 'in'
       AND v_existing.qty = v_qty
       AND v_existing.unit_cost = v_cost THEN
      RETURN v_existing;
    END IF;
    RAISE EXCEPTION 'IDEMPOTENCY_CONFLICT';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM hasad.products
    WHERE id = p_product_id
      AND company_id = p_company_id
      AND is_active
      AND track_inventory
  ) THEN
    RAISE EXCEPTION 'PRODUCT_NOT_AVAILABLE';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM hasad.warehouses
    WHERE id = p_warehouse_id
      AND company_id = p_company_id
      AND is_active
  ) THEN
    RAISE EXCEPTION 'WAREHOUSE_NOT_AVAILABLE';
  END IF;

  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_product_id::text, 0)
  );

  -- Re-check after serialization so a concurrent duplicate submission
  -- returns the already-committed movement instead of a key violation.
  SELECT * INTO v_existing
  FROM hasad.stock_movements
  WHERE id = p_movement_id;
  IF FOUND THEN
    IF v_existing.company_id = p_company_id
       AND v_existing.product_id = p_product_id
       AND v_existing.warehouse_id = p_warehouse_id
       AND v_existing.movement_type = 'purchase_receipt'
       AND v_existing.direction = 'in'
       AND v_existing.qty = v_qty
       AND v_existing.unit_cost = v_cost THEN
      RETURN v_existing;
    END IF;
    RAISE EXCEPTION 'IDEMPOTENCY_CONFLICT';
  END IF;

  INSERT INTO hasad.stock_levels
    (company_id, product_id, warehouse_id, qty, last_unit_cost)
  VALUES
    (p_company_id, p_product_id, p_warehouse_id, 0, 0)
  ON CONFLICT (company_id, product_id, warehouse_id) DO NOTHING;

  SELECT * INTO v_level
  FROM hasad.stock_levels
  WHERE company_id = p_company_id
    AND product_id = p_product_id
    AND warehouse_id = p_warehouse_id
  FOR UPDATE;

  v_new_qty := v_level.qty + v_qty;
  v_new_cost := pg_catalog.round(
    ((v_level.qty * v_level.last_unit_cost) + (v_qty * v_cost)) / v_new_qty,
    4
  );
  v_seq := COALESCE(
    (
      SELECT pg_catalog.max(seq)
      FROM hasad.stock_movements
      WHERE product_id = p_product_id
    ),
    0
  ) + 1;

  UPDATE hasad.stock_levels
  SET qty = v_new_qty,
      last_unit_cost = v_new_cost
  WHERE company_id = p_company_id
    AND product_id = p_product_id
    AND warehouse_id = p_warehouse_id;

  INSERT INTO hasad.stock_movements
    (id, company_id, product_id, warehouse_id, movement_type, direction,
     qty, unit_cost, value, seq)
  VALUES
    (p_movement_id, p_company_id, p_product_id, p_warehouse_id,
     'purchase_receipt', 'in', v_qty, v_cost,
     pg_catalog.round(v_qty * v_cost, 2), v_seq)
  RETURNING * INTO v_movement;

  INSERT INTO hasad.audit_log
    (id, company_id, actor_user_id, action, entity_type, entity_id, details)
  VALUES
    (p_movement_id, p_company_id, v_user_id, 'stock.posted',
     'stock_movement', p_movement_id,
     pg_catalog.jsonb_build_object(
       'movement_type', 'purchase_receipt',
       'warehouse_id', p_warehouse_id,
       'product_id', p_product_id,
       'qty', v_qty
     ));

  RETURN v_movement;
END;
$fn$;

-- ------------------------------------------------------------------ issue --
CREATE OR REPLACE FUNCTION hasad.post_stock_issue(
  p_movement_id uuid,
  p_company_id uuid,
  p_warehouse_id uuid,
  p_product_id uuid,
  p_qty numeric
) RETURNS hasad.stock_movements
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $fn$
DECLARE
  v_claims jsonb;
  v_user_id uuid;
  v_existing hasad.stock_movements;
  v_level hasad.stock_levels;
  v_movement hasad.stock_movements;
  v_qty numeric(19,4) := pg_catalog.round(p_qty, 4);
  v_cost numeric(19,4);
  v_seq bigint;
BEGIN
  IF p_movement_id IS NULL
     OR p_company_id IS NULL
     OR p_warehouse_id IS NULL
     OR p_product_id IS NULL THEN
    RAISE EXCEPTION 'INVALID_ARGUMENT';
  END IF;

  v_claims := NULLIF(
    pg_catalog.current_setting('request.jwt.claims', true), ''
  )::jsonb;
  v_user_id := NULLIF(v_claims->>'sub', '')::uuid;
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'UNAUTHENTICATED' USING ERRCODE = '42501';
  END IF;

  IF p_qty IS NULL OR p_qty <= 0 OR v_qty <= 0 THEN
    RAISE EXCEPTION 'QTY_INVALID';
  END IF;
  IF p_qty <> v_qty THEN
    RAISE EXCEPTION 'QTY_PRECISION';
  END IF;

  IF NOT hasad.inventory_post_allowed(p_company_id, v_user_id) THEN
    RAISE EXCEPTION 'FORBIDDEN' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_existing
  FROM hasad.stock_movements
  WHERE id = p_movement_id;
  IF FOUND THEN
    IF v_existing.company_id = p_company_id
       AND v_existing.product_id = p_product_id
       AND v_existing.warehouse_id = p_warehouse_id
       AND v_existing.movement_type = 'sales_issue'
       AND v_existing.direction = 'out'
       AND v_existing.qty = v_qty THEN
      RETURN v_existing;
    END IF;
    RAISE EXCEPTION 'IDEMPOTENCY_CONFLICT';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM hasad.products
    WHERE id = p_product_id
      AND company_id = p_company_id
      AND is_active
      AND track_inventory
  ) THEN
    RAISE EXCEPTION 'PRODUCT_NOT_AVAILABLE';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM hasad.warehouses
    WHERE id = p_warehouse_id
      AND company_id = p_company_id
      AND is_active
  ) THEN
    RAISE EXCEPTION 'WAREHOUSE_NOT_AVAILABLE';
  END IF;

  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_product_id::text, 0)
  );

  -- Re-check after serialization so a concurrent duplicate submission
  -- returns the already-committed movement instead of a key violation.
  SELECT * INTO v_existing
  FROM hasad.stock_movements
  WHERE id = p_movement_id;
  IF FOUND THEN
    IF v_existing.company_id = p_company_id
       AND v_existing.product_id = p_product_id
       AND v_existing.warehouse_id = p_warehouse_id
       AND v_existing.movement_type = 'sales_issue'
       AND v_existing.direction = 'out'
       AND v_existing.qty = v_qty THEN
      RETURN v_existing;
    END IF;
    RAISE EXCEPTION 'IDEMPOTENCY_CONFLICT';
  END IF;

  SELECT * INTO v_level
  FROM hasad.stock_levels
  WHERE company_id = p_company_id
    AND product_id = p_product_id
    AND warehouse_id = p_warehouse_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'STOCK_INSUFFICIENT';
  END IF;
  IF v_level.qty < v_qty THEN
    RAISE EXCEPTION 'STOCK_INSUFFICIENT';
  END IF;

  v_cost := v_level.last_unit_cost;
  v_seq := COALESCE(
    (
      SELECT pg_catalog.max(seq)
      FROM hasad.stock_movements
      WHERE product_id = p_product_id
    ),
    0
  ) + 1;

  UPDATE hasad.stock_levels
  SET qty = v_level.qty - v_qty
  WHERE company_id = p_company_id
    AND product_id = p_product_id
    AND warehouse_id = p_warehouse_id;

  INSERT INTO hasad.stock_movements
    (id, company_id, product_id, warehouse_id, movement_type, direction,
     qty, unit_cost, value, seq)
  VALUES
    (p_movement_id, p_company_id, p_product_id, p_warehouse_id,
     'sales_issue', 'out', v_qty, v_cost,
     pg_catalog.round(v_qty * v_cost, 2), v_seq)
  RETURNING * INTO v_movement;

  INSERT INTO hasad.audit_log
    (id, company_id, actor_user_id, action, entity_type, entity_id, details)
  VALUES
    (p_movement_id, p_company_id, v_user_id, 'stock.posted',
     'stock_movement', p_movement_id,
     pg_catalog.jsonb_build_object(
       'movement_type', 'sales_issue',
       'warehouse_id', p_warehouse_id,
       'product_id', p_product_id,
       'qty', v_qty
     ));

  RETURN v_movement;
END;
$fn$;

-- --------------------------------------------------------------- transfer --
CREATE OR REPLACE FUNCTION hasad.post_stock_transfer(
  p_out_movement_id uuid,
  p_in_movement_id uuid,
  p_company_id uuid,
  p_source_warehouse_id uuid,
  p_destination_warehouse_id uuid,
  p_product_id uuid,
  p_qty numeric
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $fn$
DECLARE
  v_claims jsonb;
  v_user_id uuid;
  v_existing_out hasad.stock_movements;
  v_existing_in hasad.stock_movements;
  v_source hasad.stock_levels;
  v_destination hasad.stock_levels;
  v_out hasad.stock_movements;
  v_in hasad.stock_movements;
  v_qty numeric(19,4) := pg_catalog.round(p_qty, 4);
  v_cost numeric(19,4);
  v_destination_cost numeric(19,4);
  v_seq bigint;
BEGIN
  IF p_out_movement_id IS NULL
     OR p_in_movement_id IS NULL
     OR p_company_id IS NULL
     OR p_source_warehouse_id IS NULL
     OR p_destination_warehouse_id IS NULL
     OR p_product_id IS NULL THEN
    RAISE EXCEPTION 'INVALID_ARGUMENT';
  END IF;

  IF p_source_warehouse_id = p_destination_warehouse_id THEN
    RAISE EXCEPTION 'SAME_WAREHOUSE';
  END IF;

  v_claims := NULLIF(
    pg_catalog.current_setting('request.jwt.claims', true), ''
  )::jsonb;
  v_user_id := NULLIF(v_claims->>'sub', '')::uuid;
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'UNAUTHENTICATED' USING ERRCODE = '42501';
  END IF;

  IF p_qty IS NULL OR p_qty <= 0 OR v_qty <= 0 THEN
    RAISE EXCEPTION 'QTY_INVALID';
  END IF;
  IF p_qty <> v_qty THEN
    RAISE EXCEPTION 'QTY_PRECISION';
  END IF;

  IF NOT hasad.inventory_post_allowed(p_company_id, v_user_id) THEN
    RAISE EXCEPTION 'FORBIDDEN' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_existing_out
  FROM hasad.stock_movements
  WHERE id = p_out_movement_id;
  IF FOUND THEN
    SELECT * INTO v_existing_in
    FROM hasad.stock_movements
    WHERE id = p_in_movement_id;

    IF FOUND
       AND v_existing_out.company_id = p_company_id
       AND v_existing_out.product_id = p_product_id
       AND v_existing_out.warehouse_id = p_source_warehouse_id
       AND v_existing_out.movement_type = 'transfer_out'
       AND v_existing_out.direction = 'out'
       AND v_existing_out.qty = v_qty
       AND v_existing_in.company_id = p_company_id
       AND v_existing_in.product_id = p_product_id
       AND v_existing_in.warehouse_id = p_destination_warehouse_id
       AND v_existing_in.movement_type = 'transfer_in'
       AND v_existing_in.direction = 'in'
       AND v_existing_in.qty = v_qty THEN
      RETURN pg_catalog.jsonb_build_object(
        'out', pg_catalog.to_jsonb(v_existing_out),
        'in', pg_catalog.to_jsonb(v_existing_in)
      );
    END IF;
    RAISE EXCEPTION 'IDEMPOTENCY_CONFLICT';
  END IF;

  IF EXISTS (
    SELECT 1 FROM hasad.stock_movements WHERE id = p_in_movement_id
  ) THEN
    RAISE EXCEPTION 'IDEMPOTENCY_CONFLICT';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM hasad.products
    WHERE id = p_product_id
      AND company_id = p_company_id
      AND is_active
      AND track_inventory
  ) THEN
    RAISE EXCEPTION 'PRODUCT_NOT_AVAILABLE';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM hasad.warehouses
    WHERE id = p_source_warehouse_id
      AND company_id = p_company_id
      AND is_active
  ) OR NOT EXISTS (
    SELECT 1 FROM hasad.warehouses
    WHERE id = p_destination_warehouse_id
      AND company_id = p_company_id
      AND is_active
  ) THEN
    RAISE EXCEPTION 'WAREHOUSE_NOT_AVAILABLE';
  END IF;

  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_product_id::text, 0)
  );

  -- Re-check after serialization so a concurrent duplicate submission
  -- returns the already-committed pair instead of a key violation.
  SELECT * INTO v_existing_out
  FROM hasad.stock_movements
  WHERE id = p_out_movement_id;
  IF FOUND THEN
    SELECT * INTO v_existing_in
    FROM hasad.stock_movements
    WHERE id = p_in_movement_id;

    IF FOUND
       AND v_existing_out.company_id = p_company_id
       AND v_existing_out.product_id = p_product_id
       AND v_existing_out.warehouse_id = p_source_warehouse_id
       AND v_existing_out.movement_type = 'transfer_out'
       AND v_existing_out.direction = 'out'
       AND v_existing_out.qty = v_qty
       AND v_existing_in.company_id = p_company_id
       AND v_existing_in.product_id = p_product_id
       AND v_existing_in.warehouse_id = p_destination_warehouse_id
       AND v_existing_in.movement_type = 'transfer_in'
       AND v_existing_in.direction = 'in'
       AND v_existing_in.qty = v_qty THEN
      RETURN pg_catalog.jsonb_build_object(
        'out', pg_catalog.to_jsonb(v_existing_out),
        'in', pg_catalog.to_jsonb(v_existing_in)
      );
    END IF;
    RAISE EXCEPTION 'IDEMPOTENCY_CONFLICT';
  END IF;

  INSERT INTO hasad.stock_levels
    (company_id, product_id, warehouse_id, qty, last_unit_cost)
  VALUES
    (p_company_id, p_product_id, p_source_warehouse_id, 0, 0),
    (p_company_id, p_product_id, p_destination_warehouse_id, 0, 0)
  ON CONFLICT (company_id, product_id, warehouse_id) DO NOTHING;

  PERFORM 1
  FROM hasad.stock_levels
  WHERE company_id = p_company_id
    AND product_id = p_product_id
    AND warehouse_id IN (p_source_warehouse_id, p_destination_warehouse_id)
  ORDER BY warehouse_id
  FOR UPDATE;

  SELECT * INTO v_source
  FROM hasad.stock_levels
  WHERE company_id = p_company_id
    AND product_id = p_product_id
    AND warehouse_id = p_source_warehouse_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'STOCK_INSUFFICIENT';
  END IF;

  SELECT * INTO v_destination
  FROM hasad.stock_levels
  WHERE company_id = p_company_id
    AND product_id = p_product_id
    AND warehouse_id = p_destination_warehouse_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'WAREHOUSE_NOT_AVAILABLE';
  END IF;

  IF v_source.qty < v_qty THEN
    RAISE EXCEPTION 'STOCK_INSUFFICIENT';
  END IF;

  v_cost := v_source.last_unit_cost;
  v_destination_cost := pg_catalog.round(
    (
      (v_destination.qty * v_destination.last_unit_cost)
      + (v_qty * v_cost)
    ) / (v_destination.qty + v_qty),
    4
  );
  v_seq := COALESCE(
    (
      SELECT pg_catalog.max(seq)
      FROM hasad.stock_movements
      WHERE product_id = p_product_id
    ),
    0
  ) + 1;

  UPDATE hasad.stock_levels
  SET qty = v_source.qty - v_qty
  WHERE company_id = p_company_id
    AND product_id = p_product_id
    AND warehouse_id = p_source_warehouse_id;

  UPDATE hasad.stock_levels
  SET qty = v_destination.qty + v_qty,
      last_unit_cost = v_destination_cost
  WHERE company_id = p_company_id
    AND product_id = p_product_id
    AND warehouse_id = p_destination_warehouse_id;

  INSERT INTO hasad.stock_movements
    (id, company_id, product_id, warehouse_id, movement_type, direction,
     qty, unit_cost, value, seq)
  VALUES
    (p_out_movement_id, p_company_id, p_product_id, p_source_warehouse_id,
     'transfer_out', 'out', v_qty, v_cost,
     pg_catalog.round(v_qty * v_cost, 2), v_seq)
  RETURNING * INTO v_out;

  INSERT INTO hasad.stock_movements
    (id, company_id, product_id, warehouse_id, movement_type, direction,
     qty, unit_cost, value, seq)
  VALUES
    (p_in_movement_id, p_company_id, p_product_id, p_destination_warehouse_id,
     'transfer_in', 'in', v_qty, v_cost,
     pg_catalog.round(v_qty * v_cost, 2), v_seq + 1)
  RETURNING * INTO v_in;

  INSERT INTO hasad.audit_log
    (id, company_id, actor_user_id, action, entity_type, entity_id, details)
  VALUES
    (p_out_movement_id, p_company_id, v_user_id, 'stock.posted',
     'stock_transfer', p_out_movement_id,
     pg_catalog.jsonb_build_object(
       'out_movement_id', p_out_movement_id,
       'in_movement_id', p_in_movement_id,
       'source_warehouse_id', p_source_warehouse_id,
       'destination_warehouse_id', p_destination_warehouse_id,
       'product_id', p_product_id,
       'qty', v_qty
     ));

  RETURN pg_catalog.jsonb_build_object(
    'out', pg_catalog.to_jsonb(v_out),
    'in', pg_catalog.to_jsonb(v_in)
  );
END;
$fn$;

-- The executor creates the functions; ownership is then transferred to the
-- locked role so SECURITY DEFINER runs without postgres/BYPASSRLS privileges.
REVOKE ALL ON FUNCTION hasad.post_stock_receipt(uuid, uuid, uuid, uuid, numeric, numeric)
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION hasad.post_stock_issue(uuid, uuid, uuid, uuid, numeric)
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION hasad.post_stock_transfer(uuid, uuid, uuid, uuid, uuid, uuid, numeric)
  FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION hasad.post_stock_receipt(uuid, uuid, uuid, uuid, numeric, numeric)
  TO authenticated;
GRANT EXECUTE ON FUNCTION hasad.post_stock_issue(uuid, uuid, uuid, uuid, numeric)
  TO authenticated;
GRANT EXECUTE ON FUNCTION hasad.post_stock_transfer(uuid, uuid, uuid, uuid, uuid, uuid, numeric)
  TO authenticated;

GRANT CREATE ON SCHEMA hasad TO hasad_inventory_poster;

ALTER FUNCTION hasad.post_stock_receipt(uuid, uuid, uuid, uuid, numeric, numeric)
  OWNER TO hasad_inventory_poster;
ALTER FUNCTION hasad.post_stock_issue(uuid, uuid, uuid, uuid, numeric)
  OWNER TO hasad_inventory_poster;
ALTER FUNCTION hasad.post_stock_transfer(uuid, uuid, uuid, uuid, uuid, uuid, numeric)
  OWNER TO hasad_inventory_poster;

-- CREATE is needed only for the ownership transfers above. The locked owner
-- does not retain schema-object creation privileges at runtime.
REVOKE CREATE ON SCHEMA hasad FROM hasad_inventory_poster;

DO $postflight$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM pg_catalog.pg_auth_members m
    JOIN pg_catalog.pg_roles granted ON granted.oid = m.roleid
    JOIN pg_catalog.pg_roles member ON member.oid = m.member
    WHERE granted.rolname = 'hasad_inventory_poster'
      AND member.rolname IN ('authenticated', 'anon')
  ) THEN
    RAISE EXCEPTION 'POSTFLIGHT_POSTER_ROLE_GRANTED_TO_CLIENT';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM pg_catalog.pg_proc p
    JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
    JOIN pg_catalog.pg_roles r ON r.oid = p.proowner
    WHERE n.nspname = 'hasad'
      AND p.proname IN (
        'post_stock_receipt', 'post_stock_issue', 'post_stock_transfer'
      )
      AND (r.rolname <> 'hasad_inventory_poster' OR NOT p.prosecdef)
  ) THEN
    RAISE EXCEPTION 'POSTFLIGHT_FUNCTION_OWNERSHIP';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_roles
    WHERE rolname = 'hasad_inventory_poster'
      AND NOT rolcanlogin
      AND NOT rolinherit
      AND NOT rolsuper
      AND NOT rolcreaterole
      AND NOT rolcreatedb
      AND NOT rolbypassrls
  ) THEN
    RAISE EXCEPTION 'POSTFLIGHT_POSTER_ROLE_ATTRIBUTES';
  END IF;

  IF pg_catalog.has_table_privilege(
       'authenticated', 'hasad.stock_levels', 'INSERT,UPDATE,DELETE'
     )
     OR pg_catalog.has_any_column_privilege(
       'authenticated', 'hasad.stock_levels', 'INSERT,UPDATE'
     )
     OR pg_catalog.has_table_privilege(
       'authenticated', 'hasad.stock_movements', 'INSERT,UPDATE,DELETE'
     )
     OR pg_catalog.has_any_column_privilege(
       'authenticated', 'hasad.stock_movements', 'INSERT,UPDATE'
     ) THEN
    RAISE EXCEPTION 'POSTFLIGHT_AUTHENTICATED_DIRECT_WRITE';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM hasad.permissions
    WHERE code = 'inventory.post' AND module = 'inventory'
  ) THEN
    RAISE EXCEPTION 'POSTFLIGHT_INVENTORY_POST_PERMISSION_MISSING';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM pg_catalog.pg_proc p
    JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'hasad'
      AND p.proname = 'inventory_post_allowed'
      AND p.prosecdef
  ) THEN
    RAISE EXCEPTION 'POSTFLIGHT_PERMISSION_HELPER_DEFINER';
  END IF;
END
$postflight$;

COMMIT;

-- Activation step after approval: call PostgREST schema reload.
NOTIFY pgrst, 'reload schema';
