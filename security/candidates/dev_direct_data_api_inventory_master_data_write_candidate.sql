-- REVIEW ONLY / DEV ONLY / NOT DEPLOYED
-- Enables authenticated same-company reads, INSERTs and UPDATEs for
-- units_of_measure and product_categories. No DELETE, anon/PUBLIC access,
-- Auth change, role change, RPC, data seed, or RLS/FORCE-RLS change.
BEGIN;
DO $preflight$ BEGIN
  IF EXISTS (SELECT 1 FROM pg_catalog.pg_class c JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='hasad' AND c.relname IN ('units_of_measure','product_categories') AND (NOT c.relrowsecurity OR NOT c.relforcerowsecurity)) THEN RAISE EXCEPTION 'PREFLIGHT_RLS'; END IF;
  IF pg_catalog.has_schema_privilege('anon','hasad','USAGE') OR pg_catalog.has_table_privilege('anon','hasad.units_of_measure','INSERT') OR pg_catalog.has_table_privilege('anon','hasad.product_categories','INSERT') THEN RAISE EXCEPTION 'PREFLIGHT_ANON'; END IF;
END $preflight$;
GRANT SELECT (id,company_id,code,name_ar,is_base,is_active), INSERT (id,company_id,code,name_ar,is_base,is_active), UPDATE (code,name_ar,is_base,is_active) ON hasad.units_of_measure TO authenticated;
GRANT SELECT (id,company_id,code,name_ar,is_active), INSERT (id,company_id,code,name_ar,is_active), UPDATE (code,name_ar,is_active) ON hasad.product_categories TO authenticated;
CREATE POLICY direct_authenticated_categories_read ON hasad.product_categories FOR SELECT TO authenticated USING (EXISTS (SELECT 1 FROM hasad.company_memberships cm JOIN hasad.companies c ON c.id=cm.company_id AND c.status='active' WHERE cm.company_id=product_categories.company_id AND cm.user_id=auth.uid() AND cm.status='active'));
CREATE POLICY direct_authenticated_categories_insert ON hasad.product_categories FOR INSERT TO authenticated WITH CHECK (EXISTS (SELECT 1 FROM hasad.company_memberships cm JOIN hasad.companies c ON c.id=cm.company_id AND c.status='active' WHERE cm.company_id=product_categories.company_id AND cm.user_id=auth.uid() AND cm.status='active'));
CREATE POLICY direct_authenticated_categories_update ON hasad.product_categories FOR UPDATE TO authenticated USING (EXISTS (SELECT 1 FROM hasad.company_memberships cm JOIN hasad.companies c ON c.id=cm.company_id AND c.status='active' WHERE cm.company_id=product_categories.company_id AND cm.user_id=auth.uid() AND cm.status='active')) WITH CHECK (EXISTS (SELECT 1 FROM hasad.company_memberships cm JOIN hasad.companies c ON c.id=cm.company_id AND c.status='active' WHERE cm.company_id=product_categories.company_id AND cm.user_id=auth.uid() AND cm.status='active'));
CREATE POLICY direct_authenticated_units_insert ON hasad.units_of_measure FOR INSERT TO authenticated WITH CHECK (EXISTS (SELECT 1 FROM hasad.company_memberships cm JOIN hasad.companies c ON c.id=cm.company_id AND c.status='active' WHERE cm.company_id=units_of_measure.company_id AND cm.user_id=auth.uid() AND cm.status='active'));
CREATE POLICY direct_authenticated_units_update ON hasad.units_of_measure FOR UPDATE TO authenticated USING (EXISTS (SELECT 1 FROM hasad.company_memberships cm JOIN hasad.companies c ON c.id=cm.company_id AND c.status='active' WHERE cm.company_id=units_of_measure.company_id AND cm.user_id=auth.uid() AND cm.status='active')) WITH CHECK (EXISTS (SELECT 1 FROM hasad.company_memberships cm JOIN hasad.companies c ON c.id=cm.company_id AND c.status='active' WHERE cm.company_id=units_of_measure.company_id AND cm.user_id=auth.uid() AND cm.status='active'));
COMMIT;
