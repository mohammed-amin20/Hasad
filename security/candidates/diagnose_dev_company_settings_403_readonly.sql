-- HASAD ERP V2 — READ-ONLY DEV DIAGNOSTIC: company_settings 403
-- Target: Supabase DEV project sxasnunzspkuwbxiddqd
--
-- Context: the DEV-only S3 posting smoke screen failed during its read-only
-- precheck with "تعذر قراءة إعدادات الشركة (رمز الخادم: 403)". The membership
-- read succeeded, so the schema, session and authenticated role are reachable.
-- This script separates table/column privilege denial (SQLSTATE 42501 -> 403)
-- from RLS row filtering (0 rows -> maybeSingle() == null, not 403).
--
-- READ-ONLY: this file contains only WITH/SELECT against catalogs and data.
-- It performs no INSERT/UPDATE/DELETE/DDL, no GRANT/REVOKE, no SET ROLE, no
-- function execution that writes, and no impersonation. Run it in the DEV SQL
-- editor only under a separate explicit read-only authorization.
--
-- The last check is the bottom line: if smoke_screen_columns_granted is FAIL,
-- the Flutter select asks for columns the authenticated role cannot read.

WITH
target AS (
  SELECT
    CASE WHEN count(*) = 1 THEN (array_agg(company_id))[1] END AS company_id,
    count(*) AS match_count
  FROM (
    SELECT DISTINCT cs.company_id
    FROM hasad.company_settings cs
    JOIN hasad.companies c
      ON c.id = cs.company_id AND c.status = 'active'
    WHERE lower(btrim(coalesce(cs.name_ar, '')))
            IN (lower('أبو أمين'), lower('Abo Amen'))
       OR lower(btrim(coalesce(cs.name_en, '')))
            IN (lower('أبو أمين'), lower('Abo Amen'))
       OR lower(btrim(coalesce(cs.display_name, '')))
            IN (lower('أبو أمين'), lower('Abo Amen'))
  ) matches
),
required_columns(column_name, normal_app, smoke_screen) AS (
  VALUES
    ('company_id',   true,  true),
    ('display_name', true,  true),
    ('name_ar',      true,  true),
    ('name_en',      false, true),
    ('vat_enabled',  false, true),
    ('currency',     false, true)
),
column_state AS (
  SELECT
    rc.column_name,
    rc.normal_app,
    rc.smoke_screen,
    a.attname IS NOT NULL AS column_exists,
    CASE
      WHEN a.attname IS NULL THEN NULL
      ELSE pg_catalog.has_column_privilege(
        'authenticated', 'hasad.company_settings', rc.column_name, 'SELECT'
      )
    END AS granted
  FROM required_columns rc
  LEFT JOIN pg_catalog.pg_attribute a
    ON a.attrelid = pg_catalog.to_regclass('hasad.company_settings')
   AND a.attname = rc.column_name
   AND a.attnum > 0
   AND NOT a.attisdropped
),
missing_normal AS (
  SELECT coalesce(
    jsonb_agg(column_name ORDER BY column_name)
      FILTER (WHERE normal_app AND NOT coalesce(granted, false)),
    '[]'::jsonb
  ) AS columns
  FROM column_state
),
missing_smoke AS (
  SELECT coalesce(
    jsonb_agg(column_name ORDER BY column_name)
      FILTER (WHERE smoke_screen AND NOT coalesce(granted, false)),
    '[]'::jsonb
  ) AS columns
  FROM column_state
),
policy_state AS (
  SELECT
    coalesce((
      SELECT jsonb_agg(jsonb_build_object(
        'name', p.polname,
        'permissive', p.polpermissive,
        'roles', (
          SELECT coalesce(jsonb_agg(
            CASE WHEN role_oid = 0 THEN 'PUBLIC'
                 ELSE pg_catalog.pg_get_userbyid(role_oid) END
          ), '[]'::jsonb)
          FROM unnest(p.polroles) AS role_oid
        ),
        'cmd', p.polcmd,
        'qual', pg_catalog.pg_get_expr(p.polqual, p.polrelid),
        'with_check', pg_catalog.pg_get_expr(p.polwithcheck, p.polrelid)
      ) ORDER BY p.polname)
      FROM pg_catalog.pg_policy p
      JOIN pg_catalog.pg_class c ON c.oid = p.polrelid
      WHERE c.oid = pg_catalog.to_regclass('hasad.company_settings')
        AND p.polcmd IN ('r', '*')
    ), '[]'::jsonb) AS select_policies,
    (
      SELECT count(*) > 0
      FROM pg_catalog.pg_policy p
      JOIN pg_catalog.pg_class c ON c.oid = p.polrelid
      WHERE c.oid = pg_catalog.to_regclass('hasad.company_settings')
        AND p.polcmd IN ('r', '*')
        AND (
          p.polroles = '{0}'::oid[]
          OR EXISTS (
            SELECT 1 FROM pg_catalog.pg_roles r
            WHERE r.rolname = 'authenticated' AND r.oid = ANY (p.polroles)
          )
        )
    ) AS has_authenticated_select_policy
),
checks AS (
  SELECT 1 AS check_no, 'context' AS check_name, 'INFO' AS status,
    jsonb_build_object(
      'database', current_database(),
      'executor', current_user,
      'server_version', current_setting('server_version'),
      'checked_at', now()
    ) AS detail

  UNION ALL

  SELECT 2, 'authenticated_schema_usage',
    CASE WHEN pg_catalog.has_schema_privilege('authenticated', 'hasad', 'USAGE')
         THEN 'PASS' ELSE 'FAIL' END,
    jsonb_build_object(
      'has_schema_privilege',
      pg_catalog.has_schema_privilege('authenticated', 'hasad', 'USAGE')
    )

  UNION ALL

  SELECT 3, 'anon_schema_usage_must_be_false',
    CASE WHEN NOT pg_catalog.has_schema_privilege('anon', 'hasad', 'USAGE')
         THEN 'PASS' ELSE 'FAIL' END,
    jsonb_build_object(
      'has_schema_privilege',
      pg_catalog.has_schema_privilege('anon', 'hasad', 'USAGE')
    )

  UNION ALL

  SELECT 4, 'anon_company_settings_select_must_be_false',
    CASE WHEN NOT pg_catalog.has_table_privilege(
                'anon', 'hasad.company_settings', 'SELECT')
         THEN 'PASS' ELSE 'FAIL' END,
    jsonb_build_object(
      'has_table_privilege',
      pg_catalog.has_table_privilege('anon', 'hasad.company_settings', 'SELECT')
    )

  UNION ALL

  SELECT 5, 'authenticated_table_level_select_info',
    'INFO',
    jsonb_build_object(
      'has_table_privilege',
      pg_catalog.has_table_privilege(
        'authenticated', 'hasad.company_settings', 'SELECT'
      ),
      'note',
      'false is expected when access is granted per column; do not read it as no access',
      'relacl',
      (SELECT c.relacl::text
       FROM pg_catalog.pg_class c
       WHERE c.oid = pg_catalog.to_regclass('hasad.company_settings'))
    )

  UNION ALL

  SELECT 6, 'company_settings_rls_enabled',
    CASE WHEN coalesce((
           SELECT c.relrowsecurity
           FROM pg_catalog.pg_class c
           WHERE c.oid = pg_catalog.to_regclass('hasad.company_settings')
         ), false)
         THEN 'PASS' ELSE 'FAIL' END,
    jsonb_build_object(
      'relrowsecurity',
      (SELECT c.relrowsecurity
       FROM pg_catalog.pg_class c
       WHERE c.oid = pg_catalog.to_regclass('hasad.company_settings'))
    )

  UNION ALL

  SELECT 7, 'company_settings_force_rls',
    CASE WHEN coalesce((
           SELECT c.relforcerowsecurity
           FROM pg_catalog.pg_class c
           WHERE c.oid = pg_catalog.to_regclass('hasad.company_settings')
         ), false)
         THEN 'PASS' ELSE 'FAIL' END,
    jsonb_build_object(
      'relforcerowsecurity',
      (SELECT c.relforcerowsecurity
       FROM pg_catalog.pg_class c
       WHERE c.oid = pg_catalog.to_regclass('hasad.company_settings'))
    )

  UNION ALL

  SELECT 8, 'normal_app_columns_granted',
    CASE WHEN (SELECT columns = '[]'::jsonb FROM missing_normal)
         THEN 'PASS' ELSE 'FAIL' END,
    jsonb_build_object(
      'required', jsonb_build_array('company_id', 'display_name', 'name_ar'),
      'missing', (SELECT columns FROM missing_normal)
    )

  UNION ALL

  SELECT 9, 'old_smoke_screen_columns_granted',
    CASE WHEN (SELECT columns = '[]'::jsonb FROM missing_smoke)
         THEN 'PASS' ELSE 'FAIL' END,
    jsonb_build_object(
      'requested_before_fix', jsonb_build_array(
        'company_id', 'name_ar', 'name_en', 'display_name', 'vat_enabled', 'currency'
      ),
      'missing', (SELECT columns FROM missing_smoke),
      'per_column', (
        SELECT jsonb_object_agg(
          column_name,
          jsonb_build_object(
            'column_exists', column_exists,
            'authenticated_select', granted
          )
        )
        FROM column_state
      ),
      'interpretation',
      'FAIL with missing name_en/vat_enabled/currency is the root cause of the 403; it is column privilege denial, not RLS filtering'
    )

  UNION ALL

  SELECT 10, 'company_settings_select_policies',
    CASE WHEN (SELECT has_authenticated_select_policy FROM policy_state)
         THEN 'PASS' ELSE 'FAIL' END,
    jsonb_build_object(
      'has_authenticated_select_policy',
      (SELECT has_authenticated_select_policy FROM policy_state),
      'policies', (SELECT select_policies FROM policy_state)
    )

  UNION ALL

  SELECT 11, 'membership_and_company_policies_used_by_exists',
    'INFO',
    jsonb_build_object(
      'policies', coalesce((
        SELECT jsonb_agg(jsonb_build_object(
          'table', c.relname,
          'name', p.polname,
          'roles', (
            SELECT coalesce(jsonb_agg(
              CASE WHEN role_oid = 0 THEN 'PUBLIC'
                   ELSE pg_catalog.pg_get_userbyid(role_oid) END
            ), '[]'::jsonb)
            FROM unnest(p.polroles) AS role_oid
          ),
          'cmd', p.polcmd,
          'qual', pg_catalog.pg_get_expr(p.polqual, p.polrelid)
        ) ORDER BY c.relname, p.polname)
        FROM pg_catalog.pg_policy p
        JOIN pg_catalog.pg_class c ON c.oid = p.polrelid
        WHERE c.oid IN (
          pg_catalog.to_regclass('hasad.company_memberships'),
          pg_catalog.to_regclass('hasad.companies')
        )
          AND p.polcmd IN ('r', '*')
      ), '[]'::jsonb)
    )

  UNION ALL

  SELECT 12, 'target_company_resolves_once',
    CASE WHEN (SELECT match_count = 1 AND company_id IS NOT NULL FROM target)
         THEN 'PASS' ELSE 'FAIL' END,
    jsonb_build_object(
      'match_count', (SELECT match_count FROM target),
      'company_id', (SELECT company_id FROM target)
    )

  UNION ALL

  SELECT 13, 'target_company_settings_row_exists',
    CASE WHEN EXISTS (
           SELECT 1
           FROM hasad.company_settings cs
           JOIN target t ON t.company_id = cs.company_id
         )
         THEN 'PASS' ELSE 'FAIL' END,
    jsonb_build_object(
      'company_id', (SELECT company_id FROM target),
      'settings', (
        SELECT jsonb_build_object(
          'name_ar', cs.name_ar,
          'name_en', cs.name_en,
          'display_name', cs.display_name,
          'vat_enabled', cs.vat_enabled,
          'currency', cs.currency
        )
        FROM hasad.company_settings cs
        JOIN target t ON t.company_id = cs.company_id
      )
    )

  UNION ALL

  SELECT 14, 'target_active_memberships',
    CASE WHEN (
           SELECT count(*)
           FROM hasad.company_memberships cm
           JOIN target t ON t.company_id = cm.company_id
           WHERE cm.status = 'active'
         ) > 0
         THEN 'PASS' ELSE 'FAIL' END,
    jsonb_build_object(
      'company_id', (SELECT company_id FROM target),
      'active_memberships', coalesce((
        SELECT jsonb_agg(jsonb_build_object(
          'user_id', cm.user_id,
          'is_owner', cm.is_owner,
          'role_id', cm.role_id
        ) ORDER BY cm.user_id)
        FROM hasad.company_memberships cm
        JOIN target t ON t.company_id = cm.company_id
        WHERE cm.status = 'active'
      ), '[]'::jsonb),
      'note',
      'run the app as one of these authenticated users; this query does not impersonate anyone'
    )

  UNION ALL

  SELECT 15, 'company_settings_raw_column_acl',
    'INFO',
    jsonb_build_object(
      'columns', coalesce((
        SELECT jsonb_agg(jsonb_build_object(
          'column', a.attname,
          'acl', a.attacl::text
        ) ORDER BY a.attname)
        FROM pg_catalog.pg_attribute a
        WHERE a.attrelid = pg_catalog.to_regclass('hasad.company_settings')
          AND a.attnum > 0
          AND NOT a.attisdropped
      ), '[]'::jsonb)
    )

  UNION ALL

  SELECT 16, 'fixed_smoke_select_would_succeed_now',
    CASE WHEN (SELECT columns = '[]'::jsonb FROM missing_normal)
           AND (SELECT has_authenticated_select_policy FROM policy_state)
           AND EXISTS (
             SELECT 1
             FROM hasad.company_settings cs
             JOIN target t ON t.company_id = cs.company_id
           )
           AND coalesce((
             SELECT c.relrowsecurity AND c.relforcerowsecurity
             FROM pg_catalog.pg_class c
             WHERE c.oid = pg_catalog.to_regclass('hasad.company_settings')
           ), false)
         THEN 'PASS' ELSE 'FAIL' END,
    jsonb_build_object(
      'fixed_columns', jsonb_build_array('company_id', 'display_name', 'name_ar'),
      'missing_columns', (SELECT columns FROM missing_normal),
      'has_authenticated_select_policy',
      (SELECT has_authenticated_select_policy FROM policy_state),
      'target_settings_row_exists', EXISTS (
        SELECT 1
        FROM hasad.company_settings cs
        JOIN target t ON t.company_id = cs.company_id
      ),
      'rls_and_force_rls', coalesce((
        SELECT c.relrowsecurity AND c.relforcerowsecurity
        FROM pg_catalog.pg_class c
        WHERE c.oid = pg_catalog.to_regclass('hasad.company_settings')
      ), false),
      'interpretation',
      'PASS means the fixed Flutter select (normal app columns) can read the target row for an authenticated member; no SQL grant is needed'
    )
)
SELECT check_no, check_name, status, detail
FROM checks
ORDER BY check_no;
