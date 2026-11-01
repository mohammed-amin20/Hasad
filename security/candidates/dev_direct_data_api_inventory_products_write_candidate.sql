-- HASAD V2 — REVIEW ONLY / NOT DEPLOYED
-- DEV target: sxasnunzspkuwbxiddqd
-- Prerequisite: Unit 1 direct Data API read candidate is deployed and `hasad`
-- is exposed through the approved PostgREST configuration.
--
-- Adds only: authenticated same-company UOM reads and product INSERT/UPDATE.
-- No anon/PUBLIC grants, data writes, role changes, Auth changes, RPCs, or
-- RLS/FORCE-RLS changes. Product DELETE is intentionally absent.

BEGIN;

DO $preflight$
DECLARE
  v_count integer;
BEGIN
  SELECT count(*) INTO v_count
  FROM pg_catalog.pg_class c JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace
  WHERE n.nspname='hasad' AND c.relname IN ('products','units_of_measure','company_memberships','companies')
    AND c.relkind IN ('r','p') AND c.relrowsecurity AND c.relforcerowsecurity;
  IF v_count <> 4 THEN RAISE EXCEPTION 'PREFLIGHT_TARGET_RLS_CHANGED'; END IF;
  IF pg_catalog.has_schema_privilege('anon','hasad','USAGE')
     OR pg_catalog.has_table_privilege('anon','hasad.products','INSERT')
     OR pg_catalog.has_table_privilege('anon','hasad.products','UPDATE') THEN
    RAISE EXCEPTION 'PREFLIGHT_ANON_BOUNDARY';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_catalog.pg_policy WHERE polname IN (
    'direct_authenticated_units_read','direct_authenticated_products_insert','direct_authenticated_products_update'
  )) THEN RAISE EXCEPTION 'PREFLIGHT_POLICY_ALREADY_EXISTS'; END IF;
END
$preflight$;

GRANT SELECT (id,company_id,code,name_ar,is_base,is_active)
  ON hasad.units_of_measure TO authenticated;
GRANT INSERT (id,company_id,code,name_ar,name_en,barcode,base_uom_id,track_inventory,is_active)
  ON hasad.products TO authenticated;
GRANT UPDATE (code,name_ar,name_en,barcode,base_uom_id,track_inventory,is_active)
  ON hasad.products TO authenticated;

CREATE POLICY direct_authenticated_units_read ON hasad.units_of_measure
  FOR SELECT TO authenticated
  USING (EXISTS (
    SELECT 1 FROM hasad.company_memberships cm
    JOIN hasad.companies c ON c.id=cm.company_id AND c.status='active'
    WHERE cm.company_id=units_of_measure.company_id
      AND cm.user_id=auth.uid() AND cm.status='active'
  ));

CREATE POLICY direct_authenticated_products_insert ON hasad.products
  FOR INSERT TO authenticated
  WITH CHECK (EXISTS (
    SELECT 1 FROM hasad.company_memberships cm
    JOIN hasad.companies c ON c.id=cm.company_id AND c.status='active'
    WHERE cm.company_id=products.company_id
      AND cm.user_id=auth.uid() AND cm.status='active'
  ));

CREATE POLICY direct_authenticated_products_update ON hasad.products
  FOR UPDATE TO authenticated
  USING (EXISTS (
    SELECT 1 FROM hasad.company_memberships cm
    JOIN hasad.companies c ON c.id=cm.company_id AND c.status='active'
    WHERE cm.company_id=products.company_id
      AND cm.user_id=auth.uid() AND cm.status='active'
  ))
  WITH CHECK (EXISTS (
    SELECT 1 FROM hasad.company_memberships cm
    JOIN hasad.companies c ON c.id=cm.company_id AND c.status='active'
    WHERE cm.company_id=products.company_id
      AND cm.user_id=auth.uid() AND cm.status='active'
  ));

DO $postflight$
BEGIN
  IF pg_catalog.has_table_privilege('anon','hasad.products','INSERT')
     OR pg_catalog.has_table_privilege('anon','hasad.products','UPDATE')
     OR pg_catalog.has_table_privilege('authenticated','hasad.products','DELETE') THEN
    RAISE EXCEPTION 'POSTCHECK_WRITE_BOUNDARY';
  END IF;
  IF NOT pg_catalog.has_column_privilege('authenticated','hasad.products','code','INSERT')
     OR NOT pg_catalog.has_column_privilege('authenticated','hasad.products','code','UPDATE')
     OR NOT pg_catalog.has_column_privilege('authenticated','hasad.units_of_measure','id','SELECT') THEN
    RAISE EXCEPTION 'POSTCHECK_REQUIRED_PRIVILEGE';
  END IF;
END
$postflight$;

COMMIT;
