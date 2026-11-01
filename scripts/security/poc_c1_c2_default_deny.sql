-- Hasad ERP V2 C1/C2 disposable-target security PoC — default-deny baseline
--
-- NEVER run this against DEV sxasnunzspkuwbxiddqd or production. The script
-- refuses the known DEV ref and requires an explicit disposable project ref.
-- The ref check is an operator guardrail, not a security boundary: the operator
-- must still confirm the target is disposable before running it.
--
-- Usage (disposable target only):
--   psql -X -h <disposable-host> -p 5432 -U postgres -d postgres \
--        -v poc_project_ref=<20-letter-disposable-ref> \
--        -f scripts/security/poc_c1_c2_default_deny.sql
--
-- The script is read-only: it opens a READ ONLY transaction and rolls back.
-- It asserts the deployed permissions foundation before any application-facing
-- policy, grant, or RPC exists. Real-JWT cross-tenant cases live in
-- poc_c1_c2_real_jwt.md and remain blocked until those RPCs are approved.

\set ON_ERROR_STOP on

\if :{?poc_project_ref}
\else
  \echo 'REFUSED: pass -v poc_project_ref=<disposable-project-ref>'
  \quit 3
\endif

SELECT set_config('hasad.poc_project_ref', :'poc_project_ref', false);

BEGIN TRANSACTION READ ONLY;

DO $poc$
DECLARE
  v_ref text := current_setting('hasad.poc_project_ref', true);
  v_tables text[] := ARRAY[
    'user_profiles', 'companies', 'roles', 'company_memberships',
    'permissions', 'role_permissions', 'user_permission_overrides'
  ];
  v_count int;
  v_name text;
  v_privilege text;
BEGIN
  IF v_ref IS NULL OR v_ref = '' THEN
    RAISE EXCEPTION 'REFUSED: poc_project_ref is empty';
  END IF;
  IF lower(v_ref) = 'sxasnunzspkuwbxiddqd' THEN
    RAISE EXCEPTION 'REFUSED: DEV project sxasnunzspkuwbxiddqd is forbidden for this PoC';
  END IF;
  IF lower(v_ref) !~ '^[a-z]{20}$' THEN
    RAISE EXCEPTION 'REFUSED: poc_project_ref must be a 20-letter Supabase project ref';
  END IF;

  IF to_regnamespace('hasad') IS NULL OR to_regnamespace('hasad_api') IS NULL THEN
    RAISE EXCEPTION 'FAIL: hasad and hasad_api schemas must both exist';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon')
     OR NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN
    RAISE EXCEPTION 'FAIL: Supabase anon/authenticated roles are absent';
  END IF;

  SELECT count(*) INTO v_count
  FROM pg_class c
  JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'hasad' AND c.relkind IN ('r', 'p')
    AND c.relname = ANY (v_tables);
  IF v_count <> 7 THEN
    RAISE EXCEPTION 'FAIL: expected 7 V2 tables, found %', v_count;
  END IF;

  SELECT count(*) INTO v_count
  FROM pg_class c
  JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'hasad' AND c.relkind IN ('r', 'p')
    AND c.relname = ANY (v_tables)
    AND c.relrowsecurity AND c.relforcerowsecurity;
  IF v_count <> 7 THEN
    RAISE EXCEPTION 'FAIL: RLS must be ENABLE + FORCE on all 7 V2 tables (% of 7)', v_count;
  END IF;

  SELECT count(*) INTO v_count
  FROM pg_policy p
  WHERE p.polrelid IN (
    SELECT c.oid
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'hasad' AND c.relname = ANY (v_tables)
  );
  IF v_count <> 0 THEN
    RAISE EXCEPTION 'FAIL: expected zero RLS policies before the PoC, found %', v_count;
  END IF;

  SELECT count(*) INTO v_count
  FROM pg_trigger t
  WHERE t.tgrelid IN (
    SELECT c.oid
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'hasad' AND c.relname = ANY (v_tables)
  )
    AND NOT t.tgisinternal;
  IF v_count <> 0 THEN
    RAISE EXCEPTION 'FAIL: expected zero non-internal triggers, found %', v_count;
  END IF;

  SELECT count(*) INTO v_count
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname IN ('hasad', 'hasad_api');
  IF v_count <> 0 THEN
    RAISE EXCEPTION 'FAIL: expected zero functions in hasad/hasad_api, found %', v_count;
  END IF;

  SELECT count(*) INTO v_count
  FROM pg_class c
  JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'hasad' AND c.relname = ANY (v_tables)
    AND c.relacl IS NOT NULL;
  IF v_count <> 0 THEN
    RAISE EXCEPTION 'FAIL: expected no table ACLs, found % table(s) with ACLs', v_count;
  END IF;

  FOREACH v_name IN ARRAY v_tables LOOP
    FOREACH v_privilege IN ARRAY ARRAY[
      'SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER'
    ] LOOP
      IF has_table_privilege('anon', format('hasad.%I', v_name), v_privilege) THEN
        RAISE EXCEPTION 'FAIL: anon has % on hasad.%', v_privilege, v_name;
      END IF;
      IF has_table_privilege('authenticated', format('hasad.%I', v_name), v_privilege) THEN
        RAISE EXCEPTION 'FAIL: authenticated has % on hasad.%', v_privilege, v_name;
      END IF;
    END LOOP;
  END LOOP;

  SELECT count(*) INTO v_count
  FROM pg_constraint con
  WHERE con.contype = 'f'
    AND con.conrelid IN (
      'hasad.role_permissions'::regclass,
      'hasad.user_permission_overrides'::regclass
    )
    AND con.confdeltype = 'r';
  IF v_count <> 4 THEN
    RAISE EXCEPTION 'FAIL: expected 4 restrictive permission-foundation FKs, found %', v_count;
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'user_permission_overrides_effect_check'
      AND conrelid = 'hasad.user_permission_overrides'::regclass
      AND pg_get_constraintdef(oid) LIKE '%allow%'
      AND pg_get_constraintdef(oid) LIKE '%deny%'
  ) THEN
    RAISE EXCEPTION 'FAIL: allow/deny effect CHECK is absent or incorrect';
  END IF;

  SELECT count(*) INTO v_count FROM hasad.permissions;
  IF v_count NOT IN (0, 37) THEN
    RAISE EXCEPTION 'FAIL: permissions has % rows; expected 0 (structure only) or 37 (seed applied)', v_count;
  END IF;

  RAISE NOTICE 'PASS: default-deny baseline holds for 7 tables; catalogue rows=%', v_count;
END
$poc$;

ROLLBACK;
