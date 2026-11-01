-- Hasad ERP V2 / Unit S3 — READ ONLY DEV diagnostic query.
-- Do not execute without separate owner authorization for a read-only DEV query.
-- This query returns exactly one JSON report and makes a zero account-list result
-- diagnosable: selector failure, no company accounts, inactive-only accounts,
-- or accounts belonging to other companies.
WITH
abo_matches AS (
  SELECT cs.company_id
  FROM hasad.company_settings cs
  JOIN hasad.companies c ON c.id = cs.company_id
  WHERE c.status = 'active'
    AND (
      lower(btrim(coalesce(cs.name_ar, ''))) IN (lower('أبو أمين'), lower('Abo Amen'))
      OR lower(btrim(coalesce(cs.name_en, ''))) IN (lower('أبو أمين'), lower('Abo Amen'))
      OR lower(btrim(coalesce(cs.display_name, ''))) IN (lower('أبو أمين'), lower('Abo Amen'))
    )
),
selector AS (
  SELECT
    count(DISTINCT company_id) AS active_abo_amen_matches,
    array_agg(DISTINCT company_id ORDER BY company_id) AS company_ids
  FROM abo_matches
),
target AS (
  SELECT am.company_id
  FROM abo_matches am
  CROSS JOIN selector s
  WHERE s.active_abo_amen_matches = 1
),
global_counts AS (
  SELECT
    count(*) AS all_company_accounts,
    count(*) FILTER (WHERE is_active) AS all_active_accounts,
    count(*) FILTER (WHERE NOT is_active) AS all_inactive_accounts
  FROM hasad.accounts
),
target_counts AS (
  SELECT
    count(a.id) AS abo_amen_accounts,
    count(a.id) FILTER (WHERE a.is_active) AS abo_amen_active_accounts,
    count(a.id) FILTER (WHERE NOT a.is_active) AS abo_amen_inactive_accounts
  FROM target t
  LEFT JOIN hasad.accounts a ON a.company_id = t.company_id
),
other_company_counts AS (
  SELECT count(*) AS other_company_accounts
  FROM hasad.accounts a
  WHERE NOT EXISTS (
    SELECT 1 FROM target t WHERE t.company_id = a.company_id
  )
)
SELECT jsonb_build_object(
  'abo_amen_selector', jsonb_build_object(
    'active_match_count', s.active_abo_amen_matches,
    'company_ids', coalesce(to_jsonb(s.company_ids), '[]'::jsonb)
  ),
  'accounts', jsonb_build_object(
    'all_companies_total', g.all_company_accounts,
    'all_companies_active', g.all_active_accounts,
    'all_companies_inactive', g.all_inactive_accounts,
    'abo_amen_total', t.abo_amen_accounts,
    'abo_amen_active', t.abo_amen_active_accounts,
    'abo_amen_inactive', t.abo_amen_inactive_accounts,
    'other_companies_total', o.other_company_accounts
  ),
  'interpretation', CASE
    WHEN s.active_abo_amen_matches <> 1 THEN
      'ABO_AMEN_SELECTOR_NOT_EXACTLY_ONE: prior zero rows can be caused by the company selector.'
    WHEN g.all_company_accounts = 0 THEN
      'NO_ACCOUNTS_ANY_COMPANY'
    WHEN t.abo_amen_accounts = 0 AND o.other_company_accounts > 0 THEN
      'NO_ACCOUNTS_FOR_ABO_AMEN_BUT_ACCOUNTS_EXIST_FOR_OTHER_COMPANIES'
    WHEN t.abo_amen_accounts = 0 THEN
      'NO_ACCOUNTS_FOR_ABO_AMEN'
    WHEN t.abo_amen_active_accounts = 0 AND t.abo_amen_inactive_accounts > 0 THEN
      'ABO_AMEN_HAS_INACTIVE_ACCOUNTS_ONLY'
    ELSE
      'ABO_AMEN_HAS_VISIBLE_ACCOUNTS'
  END
) AS s3_abo_amen_account_inventory_diagnostic
FROM selector s
CROSS JOIN global_counts g
CROSS JOIN target_counts t
CROSS JOIN other_company_counts o;
