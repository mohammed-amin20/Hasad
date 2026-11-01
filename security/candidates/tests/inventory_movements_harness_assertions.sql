INSERT INTO auth.users (id) VALUES
  ('10000000-0000-0000-0000-000000000001'),
  ('10000000-0000-0000-0000-000000000002'),
  ('10000000-0000-0000-0000-000000000003');

INSERT INTO hasad.user_profiles (id) VALUES
  ('10000000-0000-0000-0000-000000000001'),
  ('10000000-0000-0000-0000-000000000002'),
  ('10000000-0000-0000-0000-000000000003');

INSERT INTO hasad.companies (id, created_by) VALUES
  ('20000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001'),
  ('20000000-0000-0000-0000-000000000002', '10000000-0000-0000-0000-000000000002');

INSERT INTO hasad.roles (id, company_id, code, is_system) VALUES
  ('30000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001', 'warehouse', true),
  ('30000000-0000-0000-0000-000000000002', '20000000-0000-0000-0000-000000000002', 'warehouse', true);

INSERT INTO hasad.role_permissions (role_id, permission_code) VALUES
  ('30000000-0000-0000-0000-000000000001', 'inventory.post');

INSERT INTO hasad.company_memberships
  (id, company_id, user_id, role_id, is_owner, status)
VALUES
  ('40000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', '30000000-0000-0000-0000-000000000001', false, 'active'),
  ('40000000-0000-0000-0000-000000000002', '20000000-0000-0000-0000-000000000002', '10000000-0000-0000-0000-000000000002', null, true, 'active'),
  ('40000000-0000-0000-0000-000000000003', '20000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000003', '30000000-0000-0000-0000-000000000001', false, 'active');

INSERT INTO hasad.user_permission_overrides
  (membership_id, permission_code, effect)
VALUES
  ('40000000-0000-0000-0000-000000000003', 'inventory.post', 'deny');

INSERT INTO hasad.units_of_measure
  (id, company_id, code, name_ar, is_base)
VALUES
  ('50000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001', 'EA', 'Each', true),
  ('50000000-0000-0000-0000-000000000002', '20000000-0000-0000-0000-000000000002', 'EA', 'Each', true);

INSERT INTO hasad.products (id, company_id, code, name_ar, base_uom_id) VALUES
  ('60000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001', 'A-1', 'Item A', '50000000-0000-0000-0000-000000000001'),
  ('60000000-0000-0000-0000-000000000002', '20000000-0000-0000-0000-000000000002', 'B-1', 'Item B', '50000000-0000-0000-0000-000000000002');

INSERT INTO hasad.warehouses (id, company_id, code, name_ar) VALUES
  ('70000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001', 'A-1', 'Warehouse A1'),
  ('70000000-0000-0000-0000-000000000002', '20000000-0000-0000-0000-000000000001', 'A-2', 'Warehouse A2'),
  ('70000000-0000-0000-0000-000000000003', '20000000-0000-0000-0000-000000000002', 'B-1', 'Warehouse B1');

INSERT INTO hasad.stock_levels
  (company_id, product_id, warehouse_id, qty, last_unit_cost)
VALUES
  ('20000000-0000-0000-0000-000000000001', '60000000-0000-0000-0000-000000000001', '70000000-0000-0000-0000-000000000001', 10, 4),
  ('20000000-0000-0000-0000-000000000002', '60000000-0000-0000-0000-000000000002', '70000000-0000-0000-0000-000000000003', 20, 8);

DO $catalog_assertions$
DECLARE
  v_name text;
BEGIN
  SELECT pg_catalog.pg_get_userbyid(p.proowner)
  INTO v_name
  FROM pg_catalog.pg_proc p
  JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'hasad' AND p.proname = 'post_stock_receipt';
  IF v_name <> 'hasad_inventory_poster' THEN
    RAISE EXCEPTION 'wrong function owner: %', v_name;
  END IF;

  IF EXISTS (
    SELECT 1 FROM pg_catalog.pg_roles
    WHERE rolname = 'hasad_inventory_poster'
      AND (rolsuper OR rolbypassrls OR rolcanlogin OR rolinherit)
  ) THEN
    RAISE EXCEPTION 'unsafe function owner attributes';
  END IF;

  IF EXISTS (
    SELECT 1 FROM pg_catalog.pg_auth_members m
    JOIN pg_catalog.pg_roles r ON r.oid = m.roleid
    JOIN pg_catalog.pg_roles u ON u.oid = m.member
    WHERE r.rolname = 'hasad_inventory_poster'
      AND u.rolname IN ('authenticated', 'anon')
  ) THEN
    RAISE EXCEPTION 'client can assume function owner';
  END IF;

  IF EXISTS (
    SELECT 1 FROM pg_catalog.pg_class c
    JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'hasad'
      AND c.relname IN ('stock_levels', 'stock_movements')
      AND (NOT c.relrowsecurity OR NOT c.relforcerowsecurity)
  ) THEN
    RAISE EXCEPTION 'FORCE RLS was not retained';
  END IF;

  IF pg_catalog.has_table_privilege('authenticated', 'hasad.stock_levels', 'INSERT,UPDATE,DELETE')
     OR pg_catalog.has_any_column_privilege('authenticated', 'hasad.stock_levels', 'INSERT,UPDATE')
     OR pg_catalog.has_table_privilege('authenticated', 'hasad.stock_movements', 'INSERT,UPDATE,DELETE') THEN
    RAISE EXCEPTION 'authenticated has direct stock write privileges';
  END IF;
END
$catalog_assertions$;

SET ROLE authenticated;
SELECT pg_catalog.set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-0000-0000-000000000001"}',
  false
);

DO $posting_assertions$
DECLARE
  v_qty numeric;
  v_count bigint;
BEGIN
  BEGIN
    PERFORM hasad.post_stock_receipt(
      '80000000-0000-0000-0000-000000000009',
      '20000000-0000-0000-0000-000000000001',
      '70000000-0000-0000-0000-000000000001',
      '60000000-0000-0000-0000-000000000001', 1.00001, 1
    );
    RAISE EXCEPTION 'over-precision quantity unexpectedly succeeded';
  EXCEPTION WHEN SQLSTATE 'P0001' THEN
    IF SQLERRM <> 'QTY_PRECISION' THEN RAISE; END IF;
  END;
  BEGIN
    PERFORM hasad.post_stock_receipt(
      '80000000-0000-0000-0000-00000000000a',
      '20000000-0000-0000-0000-000000000001',
      '70000000-0000-0000-0000-000000000001',
      '60000000-0000-0000-0000-000000000001', 1, 1.00001
    );
    RAISE EXCEPTION 'over-precision cost unexpectedly succeeded';
  EXCEPTION WHEN SQLSTATE 'P0001' THEN
    IF SQLERRM <> 'COST_PRECISION' THEN RAISE; END IF;
  END;

  PERFORM hasad.post_stock_receipt(
    '80000000-0000-0000-0000-000000000001',
    '20000000-0000-0000-0000-000000000001',
    '70000000-0000-0000-0000-000000000001',
    '60000000-0000-0000-0000-000000000001', 2, 6
  );
  BEGIN
    PERFORM hasad.post_stock_receipt(
      '80000000-0000-0000-0000-000000000001',
      '20000000-0000-0000-0000-000000000001',
      '70000000-0000-0000-0000-000000000001',
      '60000000-0000-0000-0000-000000000001', 3, 6
    );
    RAISE EXCEPTION 'idempotency key conflict unexpectedly succeeded';
  EXCEPTION WHEN SQLSTATE 'P0001' THEN
    IF SQLERRM <> 'IDEMPOTENCY_CONFLICT' THEN RAISE; END IF;
  END;
  -- A retry with the same key and payload returns the original transaction.
  PERFORM hasad.post_stock_receipt(
    '80000000-0000-0000-0000-000000000001',
    '20000000-0000-0000-0000-000000000001',
    '70000000-0000-0000-0000-000000000001',
    '60000000-0000-0000-0000-000000000001', 2, 6
  );
  SELECT qty INTO v_qty FROM hasad.stock_levels
  WHERE company_id = '20000000-0000-0000-0000-000000000001'
    AND product_id = '60000000-0000-0000-0000-000000000001'
    AND warehouse_id = '70000000-0000-0000-0000-000000000001';
  SELECT count(*) INTO v_count FROM hasad.stock_movements
  WHERE id = '80000000-0000-0000-0000-000000000001';
  IF v_qty <> 12 OR v_count <> 1 THEN
    RAISE EXCEPTION 'receipt retry changed state: qty %, rows %', v_qty, v_count;
  END IF;

  BEGIN
    PERFORM hasad.post_stock_issue(
      '80000000-0000-0000-0000-000000000002',
      '20000000-0000-0000-0000-000000000001',
      '70000000-0000-0000-0000-000000000001',
      '60000000-0000-0000-0000-000000000001', 13
    );
    RAISE EXCEPTION 'oversell unexpectedly succeeded';
  EXCEPTION WHEN SQLSTATE 'P0001' THEN
    IF SQLERRM <> 'STOCK_INSUFFICIENT' THEN RAISE; END IF;
  END;

  PERFORM hasad.post_stock_issue(
    '80000000-0000-0000-0000-000000000003',
    '20000000-0000-0000-0000-000000000001',
    '70000000-0000-0000-0000-000000000001',
    '60000000-0000-0000-0000-000000000001', 2
  );
  PERFORM hasad.post_stock_transfer(
    '80000000-0000-0000-0000-000000000004',
    '80000000-0000-0000-0000-000000000005',
    '20000000-0000-0000-0000-000000000001',
    '70000000-0000-0000-0000-000000000001',
    '70000000-0000-0000-0000-000000000002',
    '60000000-0000-0000-0000-000000000001', 3
  );
  -- Exact retry is idempotent; changed quantity under either key is rejected.
  PERFORM hasad.post_stock_transfer(
    '80000000-0000-0000-0000-000000000004',
    '80000000-0000-0000-0000-000000000005',
    '20000000-0000-0000-0000-000000000001',
    '70000000-0000-0000-0000-000000000001',
    '70000000-0000-0000-0000-000000000002',
    '60000000-0000-0000-0000-000000000001', 3
  );
  BEGIN
    PERFORM hasad.post_stock_transfer(
      '80000000-0000-0000-0000-000000000004',
      '80000000-0000-0000-0000-000000000005',
      '20000000-0000-0000-0000-000000000001',
      '70000000-0000-0000-0000-000000000001',
      '70000000-0000-0000-0000-000000000002',
      '60000000-0000-0000-0000-000000000001', 2
    );
    RAISE EXCEPTION 'changed transfer retry unexpectedly succeeded';
  EXCEPTION WHEN SQLSTATE 'P0001' THEN
    IF SQLERRM <> 'IDEMPOTENCY_CONFLICT' THEN RAISE; END IF;
  END;

  BEGIN
    PERFORM hasad.post_stock_issue(
      '80000000-0000-0000-0000-000000000006',
      '20000000-0000-0000-0000-000000000002',
      '70000000-0000-0000-0000-000000000003',
      '60000000-0000-0000-0000-000000000002', 1
    );
    RAISE EXCEPTION 'cross-company post unexpectedly succeeded';
  EXCEPTION WHEN SQLSTATE '42501' THEN
    IF SQLERRM <> 'FORBIDDEN' THEN RAISE; END IF;
  END;

  SELECT qty INTO v_qty FROM hasad.stock_levels
  WHERE company_id = '20000000-0000-0000-0000-000000000001'
    AND product_id = '60000000-0000-0000-0000-000000000001'
    AND warehouse_id = '70000000-0000-0000-0000-000000000001';
  IF v_qty <> 7 THEN RAISE EXCEPTION 'unexpected source quantity: %', v_qty; END IF;

  SELECT qty INTO v_qty FROM hasad.stock_levels
  WHERE company_id = '20000000-0000-0000-0000-000000000001'
    AND product_id = '60000000-0000-0000-0000-000000000001'
    AND warehouse_id = '70000000-0000-0000-0000-000000000002';
  IF v_qty <> 3 THEN RAISE EXCEPTION 'unexpected destination quantity: %', v_qty; END IF;
  IF (SELECT last_unit_cost FROM hasad.stock_levels
      WHERE company_id = '20000000-0000-0000-0000-000000000001'
        AND product_id = '60000000-0000-0000-0000-000000000001'
        AND warehouse_id = '70000000-0000-0000-0000-000000000001') <> 4.3333
     OR (SELECT last_unit_cost FROM hasad.stock_levels
         WHERE company_id = '20000000-0000-0000-0000-000000000001'
           AND product_id = '60000000-0000-0000-0000-000000000001'
           AND warehouse_id = '70000000-0000-0000-0000-000000000002') <> 4.3333 THEN
    RAISE EXCEPTION 'weighted average or zero-stock transfer destination cost is incorrect';
  END IF;
  IF (SELECT value FROM hasad.stock_movements
      WHERE id = '80000000-0000-0000-0000-000000000003') <> 8.67
     OR (SELECT value FROM hasad.stock_movements
         WHERE id = '80000000-0000-0000-0000-000000000004') <> 13.00 THEN
    RAISE EXCEPTION 'movement values do not use 2dp half-up valuation';
  END IF;

  BEGIN
    UPDATE hasad.stock_levels SET qty = 0
    WHERE company_id = '20000000-0000-0000-0000-000000000001';
    RAISE EXCEPTION 'direct stock_levels update unexpectedly succeeded';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
END
$posting_assertions$;

RESET ROLE;
CREATE FUNCTION hasad.inventory_harness_reject_transfer_in()
RETURNS trigger
LANGUAGE plpgsql
AS $fn$
BEGIN
  IF NEW.movement_type = 'transfer_in' THEN
    RAISE EXCEPTION 'HARNESS_TRANSFER_IN_FAILURE';
  END IF;
  RETURN NEW;
END
$fn$;
GRANT EXECUTE ON FUNCTION hasad.inventory_harness_reject_transfer_in()
  TO hasad_inventory_poster;
CREATE TRIGGER inventory_harness_reject_transfer_in
  BEFORE INSERT ON hasad.stock_movements
  FOR EACH ROW EXECUTE FUNCTION hasad.inventory_harness_reject_transfer_in();
SELECT pg_catalog.set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-0000-0000-000000000001"}',
  false
);
SET ROLE authenticated;
DO $transfer_atomicity_assertion$
BEGIN
  BEGIN
    PERFORM hasad.post_stock_transfer(
      '80000000-0000-0000-0000-00000000000d',
      '80000000-0000-0000-0000-00000000000e',
      '20000000-0000-0000-0000-000000000001',
      '70000000-0000-0000-0000-000000000001',
      '70000000-0000-0000-0000-000000000002',
      '60000000-0000-0000-0000-000000000001', 1
    );
    RAISE EXCEPTION 'forced transfer failure unexpectedly succeeded';
  EXCEPTION WHEN SQLSTATE 'P0001' THEN
    IF SQLERRM <> 'HARNESS_TRANSFER_IN_FAILURE' THEN RAISE; END IF;
  END;
END
$transfer_atomicity_assertion$;
RESET ROLE;
DO $transfer_rollback_state_assertion$
BEGIN
  IF (SELECT qty FROM hasad.stock_levels
      WHERE company_id='20000000-0000-0000-0000-000000000001'
        AND product_id='60000000-0000-0000-0000-000000000001'
        AND warehouse_id='70000000-0000-0000-0000-000000000001') <> 7
     OR (SELECT qty FROM hasad.stock_levels
         WHERE company_id='20000000-0000-0000-0000-000000000001'
           AND product_id='60000000-0000-0000-0000-000000000001'
           AND warehouse_id='70000000-0000-0000-0000-000000000002') <> 3
     OR EXISTS (SELECT 1 FROM hasad.stock_movements
                WHERE id IN ('80000000-0000-0000-0000-00000000000d',
                             '80000000-0000-0000-0000-00000000000e'))
     OR EXISTS (SELECT 1 FROM hasad.audit_log
                WHERE entity_id='80000000-0000-0000-0000-00000000000d') THEN
    RAISE EXCEPTION 'failed transfer left partial stock, movement, or audit state';
  END IF;
END
$transfer_rollback_state_assertion$;
DROP TRIGGER inventory_harness_reject_transfer_in ON hasad.stock_movements;
DROP FUNCTION hasad.inventory_harness_reject_transfer_in();
DO $audit_assertions$
DECLARE
  v_count bigint;
BEGIN
  SELECT count(*) INTO v_count FROM hasad.audit_log
  WHERE company_id = '20000000-0000-0000-0000-000000000001'
    AND action = 'stock.posted';
  IF v_count <> 3 THEN
    RAISE EXCEPTION 'expected one audit event per committed receipt, issue, transfer; found %', v_count;
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM hasad.audit_log
    WHERE entity_id = '80000000-0000-0000-0000-000000000004'
      AND action = 'stock.posted' AND entity_type = 'stock_transfer'
      AND actor_user_id = '10000000-0000-0000-0000-000000000001'
  ) THEN
    RAISE EXCEPTION 'transfer audit event did not preserve actor and entity';
  END IF;
END
$audit_assertions$;

SELECT pg_catalog.set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-0000-0000-000000000003"}',
  false
);
SET ROLE authenticated;
DO $denied_override_assertion$
BEGIN
  BEGIN
    PERFORM hasad.post_stock_receipt(
      '80000000-0000-0000-0000-000000000007',
      '20000000-0000-0000-0000-000000000001',
      '70000000-0000-0000-0000-000000000001',
      '60000000-0000-0000-0000-000000000001', 1, 1
    );
    RAISE EXCEPTION 'deny override was ignored';
  EXCEPTION WHEN SQLSTATE '42501' THEN
    IF SQLERRM <> 'FORBIDDEN' THEN RAISE; END IF;
  END;
END
$denied_override_assertion$;
RESET ROLE;

SELECT pg_catalog.set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-0000-0000-000000000002"}',
  false
);
SET ROLE authenticated;
DO $owner_assertion$
BEGIN
  PERFORM hasad.post_stock_receipt(
    '80000000-0000-0000-0000-000000000008',
    '20000000-0000-0000-0000-000000000002',
    '70000000-0000-0000-0000-000000000003',
    '60000000-0000-0000-0000-000000000002', 1, 8
  );
END
$owner_assertion$;
RESET ROLE;
SELECT 'PASS: local inventory posting assertions completed' AS result;
