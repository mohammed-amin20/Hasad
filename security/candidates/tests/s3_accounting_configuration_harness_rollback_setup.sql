-- A conflicting existing JE is deliberately inserted. The candidate reaches
-- this conflict after its other proposed writes, so transaction rollback proves
-- that no period, SI-prefix or mapping partial state remains.
INSERT INTO hasad.document_types
  (id, company_id, code, name_ar, issuance, format_prefix, pad_length, is_active)
VALUES
  ('44000000-0000-0000-0000-000000000102', '20000000-0000-0000-0000-000000000101',
   'JE', 'قيد مخالف', 'posting', 'JE', 4, true);
