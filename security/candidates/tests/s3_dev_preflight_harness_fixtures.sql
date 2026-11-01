-- Local-only DEV-shaped fixture for the read-only S3 preflight harness.
-- It identifies no real company and matches the approved Abo Amen shape:
-- one active company, open FY 2026, SI/JE document types, 12 periods with only
-- October open, five accounts/mappings, VAT disabled, no tax rates or counters.
INSERT INTO auth.users (id) VALUES
  ('10000000-0000-0000-0000-000000000601'),
  ('10000000-0000-0000-0000-000000000602');
INSERT INTO hasad.user_profiles (id, display_name) VALUES
  ('10000000-0000-0000-0000-000000000601', 'Abo Amen preflight owner'),
  ('10000000-0000-0000-0000-000000000602', 'Other preflight owner');

INSERT INTO hasad.companies (id, created_by, status) VALUES
  ('20000000-0000-0000-0000-000000000601', '10000000-0000-0000-0000-000000000601', 'active'),
  ('20000000-0000-0000-0000-000000000602', '10000000-0000-0000-0000-000000000602', 'active');

INSERT INTO hasad.company_settings (company_id, name_ar, name_en, vat_enabled) VALUES
  ('20000000-0000-0000-0000-000000000601', 'أبو أمين', 'Abo Amen', false),
  ('20000000-0000-0000-0000-000000000602', 'شركة أخرى', 'Other Company', false);

INSERT INTO hasad.company_memberships
  (id, company_id, user_id, role_id, is_owner, status) VALUES
  ('49000000-0000-0000-0000-000000000601',
   '20000000-0000-0000-0000-000000000601',
   '10000000-0000-0000-0000-000000000601', NULL, true, 'active'),
  ('49000000-0000-0000-0000-000000000602',
   '20000000-0000-0000-0000-000000000602',
   '10000000-0000-0000-0000-000000000602', NULL, true, 'active');

INSERT INTO hasad.fiscal_years
  (id, company_id, start_date, end_date, status) VALUES
  ('45000000-0000-0000-0000-000000000601',
   '20000000-0000-0000-0000-000000000601',
   DATE '2026-01-01', DATE '2026-12-31', 'open'),
  ('45000000-0000-0000-0000-000000000602',
   '20000000-0000-0000-0000-000000000602',
   DATE '2026-01-01', DATE '2026-12-31', 'open');

INSERT INTO hasad.document_types
  (id, company_id, code, name_ar, issuance, format_prefix, pad_length, is_active) VALUES
  ('44000000-0000-0000-0000-000000000601',
   '20000000-0000-0000-0000-000000000601',
   'SI', 'فاتورة مبيعات', 'posting', 'SI', 4, true),
  ('44000000-0000-0000-0000-000000000602',
   '20000000-0000-0000-0000-000000000601',
   'JE', 'قيد يومية', 'posting', 'JE', 4, true),
  ('44000000-0000-0000-0000-000000000603',
   '20000000-0000-0000-0000-000000000602',
   'SI', 'فاتورة شركة أخرى', 'posting', 'OTH', 4, true),
  ('44000000-0000-0000-0000-000000000604',
   '20000000-0000-0000-0000-000000000602',
   'JE', 'قيد شركة أخرى', 'posting', 'OTH', 4, true);

INSERT INTO hasad.fiscal_periods
  (id, company_id, fiscal_year_id, period_no, start_date, end_date, status)
SELECT
  ('46000000-0000-0000-0000-0000000006' || lpad(n::text, 2, '0'))::uuid,
  '20000000-0000-0000-0000-000000000601',
  '45000000-0000-0000-0000-000000000601',
  n,
  (DATE '2026-01-01' + ((n - 1) * INTERVAL '1 month'))::date,
  (DATE '2026-01-01' + ((n - 1) * INTERVAL '1 month')
    + INTERVAL '1 month - 1 day')::date,
  CASE WHEN n = 10 THEN 'open' ELSE 'closed' END
FROM generate_series(1, 12) AS n;

INSERT INTO hasad.accounts
  (id, company_id, code, name_ar, account_type, parent_id, is_active) VALUES
  ('47000000-0000-0000-0000-000000000601',
   '20000000-0000-0000-0000-000000000601',
   '1100', 'الذمم المدينة التجارية', 'asset', NULL, true),
  ('47000000-0000-0000-0000-000000000602',
   '20000000-0000-0000-0000-000000000601',
   '1200', 'مخزون البضاعة', 'asset', NULL, true),
  ('47000000-0000-0000-0000-000000000603',
   '20000000-0000-0000-0000-000000000601',
   '2100', 'ضريبة القيمة المضافة – مخرجات', 'liability', NULL, true),
  ('47000000-0000-0000-0000-000000000604',
   '20000000-0000-0000-0000-000000000601',
   '4100', 'إيرادات المبيعات', 'revenue', NULL, true),
  ('47000000-0000-0000-0000-000000000605',
   '20000000-0000-0000-0000-000000000601',
   '5100', 'تكلفة البضاعة المباعة', 'expense', NULL, true),
  ('47000000-0000-0000-0000-000000000606',
   '20000000-0000-0000-0000-000000000602',
   '1100', 'ذمم شركة أخرى', 'asset', NULL, true);

INSERT INTO hasad.module_account_map
  (id, company_id, module, account_role, account_id) VALUES
  ('48000000-0000-0000-0000-000000000601',
   '20000000-0000-0000-0000-000000000601', 'sales', 'AR_CONTROL',
   '47000000-0000-0000-0000-000000000601'),
  ('48000000-0000-0000-0000-000000000602',
   '20000000-0000-0000-0000-000000000601', 'sales', 'INVENTORY_CONTROL',
   '47000000-0000-0000-0000-000000000602'),
  ('48000000-0000-0000-0000-000000000603',
   '20000000-0000-0000-0000-000000000601', 'sales', 'VAT_OUTPUT',
   '47000000-0000-0000-0000-000000000603'),
  ('48000000-0000-0000-0000-000000000604',
   '20000000-0000-0000-0000-000000000601', 'sales', 'SALES_REVENUE',
   '47000000-0000-0000-0000-000000000604'),
  ('48000000-0000-0000-0000-000000000605',
   '20000000-0000-0000-0000-000000000601', 'sales', 'COGS',
   '47000000-0000-0000-0000-000000000605');
