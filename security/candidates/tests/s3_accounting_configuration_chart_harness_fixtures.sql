-- Disposable-only chart candidate fixture. Values identify no real company.
INSERT INTO auth.users (id) VALUES
  ('10000000-0000-0000-0000-000000000201'),
  ('10000000-0000-0000-0000-000000000202');
INSERT INTO hasad.user_profiles (id, display_name) VALUES
  ('10000000-0000-0000-0000-000000000201', 'Abo Amen chart test owner'),
  ('10000000-0000-0000-0000-000000000202', 'Other company test owner');
INSERT INTO hasad.companies (id, created_by, status) VALUES
  ('20000000-0000-0000-0000-000000000201', '10000000-0000-0000-0000-000000000201', 'active'),
  ('20000000-0000-0000-0000-000000000202', '10000000-0000-0000-0000-000000000202', 'active');
INSERT INTO hasad.company_settings (company_id, name_ar, name_en, vat_enabled) VALUES
  ('20000000-0000-0000-0000-000000000201', 'أبو أمين', 'Abo Amen', false),
  ('20000000-0000-0000-0000-000000000202', 'شركة أخرى', 'Other Company', false);
INSERT INTO hasad.accounts (id, company_id, code, name_ar, account_type) VALUES
  ('47000000-0000-0000-0000-000000000299', '20000000-0000-0000-0000-000000000202',
   '1100', 'حساب شركة أخرى', 'asset');
