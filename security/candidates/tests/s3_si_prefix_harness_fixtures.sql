-- Local-only SI prefix fixture. Both companies have SI rows to prove tenant scope.
INSERT INTO auth.users (id) VALUES
  ('10000000-0000-0000-0000-000000000401'),
  ('10000000-0000-0000-0000-000000000402');
INSERT INTO hasad.user_profiles (id, display_name) VALUES
  ('10000000-0000-0000-0000-000000000401', 'Abo Amen SI test owner'),
  ('10000000-0000-0000-0000-000000000402', 'Other SI test owner');
INSERT INTO hasad.companies (id,created_by,status) VALUES
  ('20000000-0000-0000-0000-000000000401','10000000-0000-0000-0000-000000000401','active'),
  ('20000000-0000-0000-0000-000000000402','10000000-0000-0000-0000-000000000402','active');
INSERT INTO hasad.company_settings (company_id,name_ar,name_en,vat_enabled) VALUES
  ('20000000-0000-0000-0000-000000000401','أبو أمين','Abo Amen',false),
  ('20000000-0000-0000-0000-000000000402','شركة أخرى','Other Company',false);
INSERT INTO hasad.document_types
  (id,company_id,code,name_ar,issuance,format_prefix,pad_length,is_active) VALUES
  ('44000000-0000-0000-0000-000000000401','20000000-0000-0000-0000-000000000401','SI','فاتورة مبيعات','posting',NULL,4,true),
  ('44000000-0000-0000-0000-000000000402','20000000-0000-0000-0000-000000000402','SI','فاتورة مبيعات','posting','OTHER',4,true);
