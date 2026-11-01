-- Local-only S3 accounting-configuration fixture. Account codes/IDs are test
-- data only and do not represent Abo Amen accounts or approved account codes.
INSERT INTO auth.users (id) VALUES ('10000000-0000-0000-0000-000000000101');
INSERT INTO hasad.user_profiles (id, display_name) VALUES
  ('10000000-0000-0000-0000-000000000101', 'Abo Amen test owner');
INSERT INTO hasad.companies (id, created_by, status) VALUES
  ('20000000-0000-0000-0000-000000000101', '10000000-0000-0000-0000-000000000101', 'active');
INSERT INTO hasad.company_settings (company_id, name_ar, name_en, vat_enabled) VALUES
  ('20000000-0000-0000-0000-000000000101', 'أبو أمين', 'Abo Amen', false);
INSERT INTO hasad.fiscal_years (id, company_id, start_date, end_date, status) VALUES
  ('45000000-0000-0000-0000-000000000101', '20000000-0000-0000-0000-000000000101',
   '2026-01-01', '2026-12-31', 'open');
-- Baseline supplied by S2: prefix is intentionally NULL before configuration.
INSERT INTO hasad.document_types
  (id, company_id, code, name_ar, issuance, format_prefix, pad_length, is_active)
VALUES
  ('44000000-0000-0000-0000-000000000101', '20000000-0000-0000-0000-000000000101',
   'SI', 'فاتورة مبيعات', 'posting', NULL, 4, true);
-- These rows prove that the candidate maps pre-existing active accounts only.
INSERT INTO hasad.accounts (id, company_id, code, name_ar, account_type) VALUES
  ('47000000-0000-0000-0000-000000000101', '20000000-0000-0000-0000-000000000101', 'TEST-AR', 'ذمم اختبار', 'asset'),
  ('47000000-0000-0000-0000-000000000102', '20000000-0000-0000-0000-000000000101', 'TEST-REV', 'إيراد اختبار', 'revenue'),
  ('47000000-0000-0000-0000-000000000103', '20000000-0000-0000-0000-000000000101', 'TEST-COGS', 'تكلفة اختبار', 'expense'),
  ('47000000-0000-0000-0000-000000000104', '20000000-0000-0000-0000-000000000101', 'TEST-INV', 'مخزون اختبار', 'asset'),
  ('47000000-0000-0000-0000-000000000105', '20000000-0000-0000-0000-000000000101', 'TEST-VAT', 'ضريبة اختبار', 'liability');
