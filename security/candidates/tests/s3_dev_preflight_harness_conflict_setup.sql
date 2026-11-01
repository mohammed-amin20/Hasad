-- Local-only negative fixture: a second active Abo Amen company, a conflicting
-- SI prefix and a missing period. The read-only preflight must report FAIL for
-- the selector, SI and period checks, never a false PASS.
UPDATE hasad.document_types
SET format_prefix = 'LEGACY'
WHERE id = '44000000-0000-0000-0000-000000000601';

DELETE FROM hasad.fiscal_periods
WHERE company_id = '20000000-0000-0000-0000-000000000601';

INSERT INTO auth.users (id) VALUES
  ('10000000-0000-0000-0000-000000000603');
INSERT INTO hasad.user_profiles (id, display_name) VALUES
  ('10000000-0000-0000-0000-000000000603', 'Duplicate Abo Amen owner');
INSERT INTO hasad.companies (id, created_by, status) VALUES
  ('20000000-0000-0000-0000-000000000603',
   '10000000-0000-0000-0000-000000000603', 'active');
INSERT INTO hasad.company_settings (company_id, name_ar, name_en, vat_enabled) VALUES
  ('20000000-0000-0000-0000-000000000603', 'أبو أمين', 'Abo Amen', false);
