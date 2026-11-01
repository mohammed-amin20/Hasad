-- Local-only bridge fixture for yearly numbering. It adds no account, tax,
-- invoice, stock or mapping data beyond the existing S3 fixture; it only gives
-- its existing company the Abo Amen selector required by the config candidate.
INSERT INTO hasad.company_settings (company_id, name_ar, name_en, vat_enabled) VALUES
  ('20000000-0000-0000-0000-000000000001', 'أبو أمين', 'Abo Amen', false);
