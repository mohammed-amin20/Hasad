-- JE conflict occurs after the candidate has attempted period writes; its
-- transaction must roll every period back.
INSERT INTO hasad.document_types
  (id, company_id, code, name_ar, issuance, format_prefix, pad_length, is_active)
VALUES
  ('44000000-0000-0000-0000-000000000301', '20000000-0000-0000-0000-000000000301',
   'JE', 'قيد متعارض', 'posting', 'JE', 4, true);
