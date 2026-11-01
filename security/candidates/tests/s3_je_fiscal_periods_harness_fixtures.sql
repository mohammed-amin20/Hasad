-- Local-only JE/fiscal-period fixture. No account, tax, invoice, stock or
-- journal data is needed to prove this configuration candidate.
INSERT INTO auth.users (id) VALUES
  ('10000000-0000-0000-0000-000000000301'),
  ('10000000-0000-0000-0000-000000000302');
INSERT INTO hasad.user_profiles (id, display_name) VALUES
  ('10000000-0000-0000-0000-000000000301', 'Abo Amen period test owner'),
  ('10000000-0000-0000-0000-000000000302', 'Other period test owner');
INSERT INTO hasad.companies (id, created_by, status) VALUES
  ('20000000-0000-0000-0000-000000000301', '10000000-0000-0000-0000-000000000301', 'active'),
  ('20000000-0000-0000-0000-000000000302', '10000000-0000-0000-0000-000000000302', 'active');
INSERT INTO hasad.company_settings (company_id, name_ar, name_en, vat_enabled) VALUES
  ('20000000-0000-0000-0000-000000000301', 'أبو أمين', 'Abo Amen', false),
  ('20000000-0000-0000-0000-000000000302', 'شركة أخرى', 'Other Company', false);
INSERT INTO hasad.fiscal_years (id, company_id, start_date, end_date, status) VALUES
  ('45000000-0000-0000-0000-000000000301', '20000000-0000-0000-0000-000000000301',
   DATE '2026-01-01', DATE '2026-12-31', 'open');
