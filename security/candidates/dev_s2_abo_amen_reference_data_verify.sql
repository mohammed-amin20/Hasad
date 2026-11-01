-- READ ONLY: run only after separately authorized deployment.
WITH abo_amen AS (
  SELECT cs.company_id,
    coalesce(nullif(cs.display_name,''),nullif(cs.name_ar,''),nullif(cs.name_en,'')) AS company_name
  FROM hasad.company_settings cs JOIN hasad.companies c ON c.id=cs.company_id
  WHERE c.status='active'
    AND (lower(btrim(coalesce(cs.name_ar,''))) IN (lower('أبو أمين'),lower('Abo Amen'))
      OR lower(btrim(coalesce(cs.name_en,''))) IN (lower('أبو أمين'),lower('Abo Amen'))
      OR lower(btrim(coalesce(cs.display_name,''))) IN (lower('أبو أمين'),lower('Abo Amen')))
)
SELECT 'company_selector' AS check_key,
  format('matches=%s',count(*)) AS observed
FROM abo_amen
UNION ALL
SELECT 'fiscal_year',format('approved_rows=%s',count(*))
FROM abo_amen a JOIN hasad.fiscal_years fy ON fy.company_id=a.company_id
WHERE fy.start_date=DATE '2026-01-01' AND fy.end_date=DATE '2026-12-31' AND fy.status='open' AND fy.reopen_count=0
UNION ALL
SELECT 'document_type',format('approved_rows=%s',count(*))
FROM abo_amen a JOIN hasad.document_types dt ON dt.company_id=a.company_id
WHERE dt.code='SI' AND dt.name_ar='فاتورة مبيعات' AND dt.issuance='posting' AND dt.is_active AND dt.pad_length=4 AND dt.format_prefix IS NULL
UNION ALL
SELECT 'forbidden_side_effects',format('doc_numbers=%s fiscal_periods=%s sales_documents=%s stock_movements=%s',
  (SELECT count(*) FROM hasad.doc_numbers dn JOIN abo_amen a ON a.company_id=dn.company_id),
  (SELECT count(*) FROM hasad.fiscal_periods fp JOIN abo_amen a ON a.company_id=fp.company_id),
  (SELECT count(*) FROM hasad.sales_documents sd JOIN abo_amen a ON a.company_id=sd.company_id),
  (SELECT count(*) FROM hasad.stock_movements sm JOIN abo_amen a ON a.company_id=sm.company_id));
