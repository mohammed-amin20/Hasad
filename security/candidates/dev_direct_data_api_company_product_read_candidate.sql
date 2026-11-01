-- HASAD V2 — REVIEW ONLY / NOT A MIGRATION / NOT DEPLOYED
-- DEV target: sxasnunzspkuwbxiddqd
--
-- Purpose: enable the smallest direct PostgREST read surface required by the
-- authenticated Flutter application: active membership, active company,
-- company display settings, and same-company products.
--
-- This script intentionally does NOT expose `hasad` through PostgREST. Schema
-- exposure is a separate Supabase DEV configuration decision and must be
-- approved and applied independently after this candidate is reviewed.
--
-- No Auth data, business data, anonymous/PUBLIC privilege, INSERT/UPDATE/
-- DELETE privilege, role, function, trigger, or RLS/FORCE-RLS setting changes.

BEGIN;

DO $preflight$
DECLARE
  v_target_count integer;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_namespace WHERE nspname = 'hasad') THEN
    RAISE EXCEPTION 'PREFLIGHT_HASAD_SCHEMA_MISSING';
  END IF;
  IF pg_catalog.has_schema_privilege('anon', 'hasad', 'USAGE') THEN
    RAISE EXCEPTION 'PREFLIGHT_ANON_OR_PUBLIC_SCHEMA_USAGE';
  END IF;

  SELECT count(*) INTO v_target_count
  FROM pg_catalog.pg_class c
  JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'hasad'
    AND c.relname IN (
      'company_memberships',
      'companies',
      'company_settings',
      'products'
    )
    AND c.relkind IN ('r', 'p')
    AND c.relrowsecurity
    AND c.relforcerowsecurity;
  IF v_target_count <> 4 THEN
    RAISE EXCEPTION 'PREFLIGHT_TARGET_RLS_OR_TABLE_SHAPE_CHANGED';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM pg_catalog.pg_policy p
    JOIN pg_catalog.pg_class c ON c.oid = p.polrelid
    JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'hasad'
      AND p.polname IN (
        'direct_authenticated_memberships_read',
        'direct_authenticated_companies_read',
        'direct_authenticated_company_settings_read',
        'direct_authenticated_products_read'
      )
  ) THEN
    RAISE EXCEPTION 'PREFLIGHT_DIRECT_READ_POLICY_ALREADY_EXISTS';
  END IF;

  IF pg_catalog.has_table_privilege('anon', 'hasad.company_memberships', 'SELECT')
     OR pg_catalog.has_table_privilege('anon', 'hasad.companies', 'SELECT')
     OR pg_catalog.has_table_privilege('anon', 'hasad.company_settings', 'SELECT')
     OR pg_catalog.has_table_privilege('anon', 'hasad.products', 'SELECT') THEN
    RAISE EXCEPTION 'PREFLIGHT_ANON_TABLE_SELECT_PRESENT';
  END IF;
END
$preflight$;

-- Only the columns returned by the Unit 1 Flutter reads are selectable.
GRANT USAGE ON SCHEMA hasad TO authenticated;
GRANT SELECT (company_id, user_id, is_owner, status)
  ON hasad.company_memberships TO authenticated;
GRANT SELECT (id, status) ON hasad.companies TO authenticated;
GRANT SELECT (company_id, display_name, name_ar)
  ON hasad.company_settings TO authenticated;
GRANT SELECT (
  id, company_id, code, name_ar, name_en, barcode, category_id, base_uom_id,
  track_inventory, is_active
) ON hasad.products TO authenticated;

-- Each policy independently derives the caller's tenant from auth.uid() and
-- a live active membership. Client company IDs only narrow a query; they never
-- authorize it.
CREATE POLICY direct_authenticated_memberships_read
  ON hasad.company_memberships
  FOR SELECT TO authenticated
  USING (user_id = auth.uid() AND status = 'active');

CREATE POLICY direct_authenticated_companies_read
  ON hasad.companies
  FOR SELECT TO authenticated
  USING (
    status = 'active'
    AND EXISTS (
      SELECT 1
      FROM hasad.company_memberships cm
      WHERE cm.company_id = companies.id
        AND cm.user_id = auth.uid()
        AND cm.status = 'active'
    )
  );

CREATE POLICY direct_authenticated_company_settings_read
  ON hasad.company_settings
  FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1
      FROM hasad.company_memberships cm
      JOIN hasad.companies c
        ON c.id = cm.company_id
       AND c.status = 'active'
      WHERE cm.company_id = company_settings.company_id
        AND cm.user_id = auth.uid()
        AND cm.status = 'active'
    )
  );

CREATE POLICY direct_authenticated_products_read
  ON hasad.products
  FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1
      FROM hasad.company_memberships cm
      JOIN hasad.companies c
        ON c.id = cm.company_id
       AND c.status = 'active'
      WHERE cm.company_id = products.company_id
        AND cm.user_id = auth.uid()
        AND cm.status = 'active'
    )
  );

DO $postflight$
DECLARE
  v_target_count integer;
BEGIN
  SELECT count(*) INTO v_target_count
  FROM pg_catalog.pg_class c
  JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'hasad'
    AND c.relname IN (
      'company_memberships',
      'companies',
      'company_settings',
      'products'
    )
    AND c.relkind IN ('r', 'p')
    AND c.relrowsecurity
    AND c.relforcerowsecurity;
  IF v_target_count <> 4 THEN
    RAISE EXCEPTION 'POSTCHECK_FORCE_RLS_CHANGED';
  END IF;

  IF NOT pg_catalog.has_schema_privilege('authenticated', 'hasad', 'USAGE')
     OR NOT pg_catalog.has_column_privilege(
       'authenticated', 'hasad.company_memberships', 'company_id', 'SELECT'
     )
     OR NOT pg_catalog.has_column_privilege(
       'authenticated', 'hasad.companies', 'id', 'SELECT'
     )
     OR NOT pg_catalog.has_column_privilege(
       'authenticated', 'hasad.company_settings', 'name_ar', 'SELECT'
     )
     OR NOT pg_catalog.has_column_privilege(
       'authenticated', 'hasad.products', 'id', 'SELECT'
     ) THEN
    RAISE EXCEPTION 'POSTCHECK_AUTHENTICATED_READ_BOUNDARY';
  END IF;

  IF pg_catalog.has_schema_privilege('anon', 'hasad', 'USAGE')
     OR pg_catalog.has_table_privilege('anon', 'hasad.company_memberships', 'SELECT')
     OR pg_catalog.has_table_privilege('anon', 'hasad.companies', 'SELECT')
     OR pg_catalog.has_table_privilege('anon', 'hasad.company_settings', 'SELECT')
     OR pg_catalog.has_table_privilege('anon', 'hasad.products', 'SELECT')
     OR pg_catalog.has_table_privilege('authenticated', 'hasad.products', 'INSERT')
     OR pg_catalog.has_table_privilege('authenticated', 'hasad.products', 'UPDATE')
     OR pg_catalog.has_table_privilege('authenticated', 'hasad.products', 'DELETE') THEN
    RAISE EXCEPTION 'POSTCHECK_NO_WRITE_OR_ANON_BOUNDARY';
  END IF;
END
$postflight$;

COMMIT;
