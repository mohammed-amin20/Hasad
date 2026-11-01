-- REVIEW ONLY / NOT DEPLOYED. Same-company authenticated warehouse CRUD and stock read.
BEGIN;
GRANT SELECT (id,company_id,code,name_ar,is_active), INSERT (id,company_id,code,name_ar,is_active), UPDATE (code,name_ar,is_active) ON hasad.warehouses TO authenticated;
GRANT SELECT (company_id,product_id,warehouse_id,qty,last_unit_cost) ON hasad.stock_levels TO authenticated;
CREATE POLICY direct_authenticated_warehouses_read ON hasad.warehouses FOR SELECT TO authenticated USING (EXISTS (SELECT 1 FROM hasad.company_memberships cm JOIN hasad.companies c ON c.id=cm.company_id AND c.status='active' WHERE cm.company_id=warehouses.company_id AND cm.user_id=auth.uid() AND cm.status='active'));
CREATE POLICY direct_authenticated_warehouses_insert ON hasad.warehouses FOR INSERT TO authenticated WITH CHECK (EXISTS (SELECT 1 FROM hasad.company_memberships cm JOIN hasad.companies c ON c.id=cm.company_id AND c.status='active' WHERE cm.company_id=warehouses.company_id AND cm.user_id=auth.uid() AND cm.status='active'));
CREATE POLICY direct_authenticated_warehouses_update ON hasad.warehouses FOR UPDATE TO authenticated USING (EXISTS (SELECT 1 FROM hasad.company_memberships cm WHERE cm.company_id=warehouses.company_id AND cm.user_id=auth.uid() AND cm.status='active')) WITH CHECK (EXISTS (SELECT 1 FROM hasad.company_memberships cm WHERE cm.company_id=warehouses.company_id AND cm.user_id=auth.uid() AND cm.status='active'));
CREATE POLICY direct_authenticated_stock_levels_read ON hasad.stock_levels FOR SELECT TO authenticated USING (EXISTS (SELECT 1 FROM hasad.company_memberships cm JOIN hasad.companies c ON c.id=cm.company_id AND c.status='active' WHERE cm.company_id=stock_levels.company_id AND cm.user_id=auth.uid() AND cm.status='active'));
COMMIT;
