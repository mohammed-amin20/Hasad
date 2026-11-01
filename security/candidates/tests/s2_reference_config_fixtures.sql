-- Local-only fixtures for the Abo Amen reference-data candidate.
INSERT INTO auth.users (id) VALUES
  ('90000000-0000-0000-0000-000000000001'),
  ('90000000-0000-0000-0000-000000000002');
INSERT INTO hasad.user_profiles (id,display_name) VALUES
  ('90000000-0000-0000-0000-000000000001','config owner'),
  ('90000000-0000-0000-0000-000000000002','other owner');
INSERT INTO hasad.companies (id,created_by,status) VALUES
  ('91000000-0000-0000-0000-000000000001','90000000-0000-0000-0000-000000000001','active'),
  ('91000000-0000-0000-0000-000000000002','90000000-0000-0000-0000-000000000002','active');
INSERT INTO hasad.company_settings (company_id,name_ar,name_en,display_name) VALUES
  ('91000000-0000-0000-0000-000000000001','أبو أمين','Abo Amen','Abo Amen'),
  ('91000000-0000-0000-0000-000000000002','شركة أخرى','Other','Abo Amen Co');
-- Deliberate local conflict: candidate must roll back the FY insert before it
-- rejects this non-approved type. The harness removes only this disposable row.
INSERT INTO hasad.document_types (id,company_id,code,name_ar,issuance) VALUES
  ('92000000-0000-0000-0000-000000000001','91000000-0000-0000-0000-000000000001','SI','اسم متعارض','posting');
