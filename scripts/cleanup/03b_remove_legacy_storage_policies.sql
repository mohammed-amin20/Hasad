-- =====================================================================
-- Hasad ERP V2 - DEV CLEANUP SCRIPT 03b: Remove 3 legacy Storage policies
-- =====================================================================
-- Target: Supabase DEV project sxasnunzspkuwbxiddqd
-- Status: PREPARED - NOT EXECUTED - REQUIRES ITS OWN EXPLICIT AUTHORIZATION
-- Purpose: Drop exactly three application policies on storage.objects:
--            tenant_isolated_pdf_select
--            tenant_isolated_pdf_insert
--            tenant_isolated_pdf_delete
--          They are the ONLY remaining catalog-tracked blockers to Stage 4
--          (DROP FUNCTION public.get_my_tenant_id()).
--
-- Why this is a SEPARATE scope:
--   The approved public-schema cleanup (Stage 3) removed 53 policies on the
--   22 legacy public tables. These three policies live in the Supabase-
--   managed `storage` schema on `storage.objects`. They were never part of
--   the approved 53-policy set, and the owner has not authorized any
--   storage-schema DDL. This script therefore requires an additional,
--   scope-specific authorization token (see the authorization gate) that a
--   public-schema authorization cannot satisfy.
--
-- Evidence (all read-only, ended ROLLBACK):
--   local_audit/DEV_STAGE4_DEPENDENCY_20261025_123320.txt
--     * exactly 3 reverse dependencies on the 33 legacy functions:
--       pg_policy -> public.get_my_tenant_id(), all on storage.objects
--     * each policy command: SELECT / INSERT / DELETE
--     * each permissive, roles = {PUBLIC}, extension_owned = false
--     * each catalog dependency set is exactly
--         {public.get_my_tenant_id(), storage.foldername(text)}
--     * table owner = supabase_storage_admin
--   Catalog facts cannot prove WHO created the policies (pg_policy has no
--   owner and no created_at); see docs/legacy_audit for the evidenced
--   classification limits.
--
-- Safety model:
--   * Exact identity allowlist of 3 (relation|policy), not a count.
--   * Command type, permissiveness, role list, expression presence and the
--     exact function-dependency set are verified per policy.
--   * Expected state: storage.objects is an ordinary table WITH row-level
--     security ENABLED; each policy is permissive, applies to exactly
--     {PUBLIC}, and is not extension-owned. Any difference aborts.
--   * storage.objects must have EXACTLY 3 policies before the drop, so no
--     unrelated policy can exist to be affected. Any drift aborts.
--   * DDL is limited to three DROP POLICY statements. There is NO
--     ALTER TABLE, no column/default/grant/ACL change, no RLS toggle, no
--     bucket change, no DROP SCHEMA, no CASCADE, no dynamic SQL.
--   * An object fingerprint (owner, table ACL, RLS flags, reloptions, and
--     per column: name, type, NOT NULL, column ACL, default) is captured
--     before the DROPs and must be bit-identical afterwards.
--   * DROP POLICY is written WITHOUT "IF EXISTS": presence was proven in
--     this same transaction, so a missing policy must abort, never silently
--     succeed.
--   * DRY_RUN runs every check and then ROLLBACKs; EXECUTE drops only these
--     three policies, verifies their absence plus the unchanged object
--     fingerprint, and only then COMMITs.
--
-- Project binding (hard limit): the Supabase project ref is NOT visible in
--   any PostgreSQL catalog. The authorization gate checks the operator-
--   supplied ref against the literal AND rejects a connection whose
--   database name is not "postgres" (the captured DEV database). That is the
--   strongest check available from inside PostgreSQL; it does NOT prove the
--   connection target. The operator must still confirm the connection string
--   points at sxasnunzspkuwbxiddqd before running.
--
-- Concurrency (bounded, not silently ignored): the preflight is not run
--   under an explicit table lock. DROP/CREATE POLICY take an ACCESS EXCLUSIVE
--   lock on the table. A policy created between preflight and the DROPs makes
--   the post-drop "0 policies remain" check fail and rolls everything back; a
--   policy created after the DROPs blocks until COMMIT. No unrelated policy
--   can be removed silently.
--
-- Alignment: same authorization GUC mapping, BEGIN/COMMIT/ROLLBACK split
--            and fail-closed notice style as 03_drop_rls_policies.sql.
-- =====================================================================

\set ON_ERROR_STOP on

-- ---------------------------------------------------------------------
-- psql-side presence normalization (MUST run before any interpolation)
-- ---------------------------------------------------------------------
-- psql substitutes only variables that are DEFINED in the session. An
-- UNDEFINED psql variable reference is emitted verbatim, so a missing or
-- misspelled -v argument reaches the server as a stray colon and fails
-- with "ERROR: syntax error at or near \":\"" - exactly what broke the
-- first Stage 3b DRY_RUN at the storage_policy_scope mapping line.
-- psql variables also cannot be referenced inside dollar-quoted bodies,
-- so every psql value is mapped to a GUC here, at top level, before any
-- DO block; the DO blocks below read GUCs only via current_setting().
-- Defaulting an absent variable to '' authorizes NOTHING: the empty value
-- still trips the fail-closed gates below with the real reason
-- (AUTHORIZATION REQUIRED / PROJECT MISMATCH / SCOPE AUTHORIZATION
-- REQUIRED), and cleanup_mode still falls back to DRY_RUN.
-- These four names are the contract. Do NOT rename them to match a
-- caller's typo: the Stage 3b scope token name is exactly
-- cleanup_storage_policy_scope.
\if :{?cleanup_authorized}
\else
  \set cleanup_authorized ''
\endif
\if :{?cleanup_project}
\else
  \set cleanup_project ''
\endif
\if :{?cleanup_mode}
\else
  \set cleanup_mode ''
\endif
\if :{?cleanup_storage_policy_scope}
\else
  \set cleanup_storage_policy_scope ''
\endif

-- Map psql variables to session GUCs (psql -v vars are not auto-GUCs)
SELECT set_config('cleanup.authorized', COALESCE(NULLIF(:'cleanup_authorized',''), 'false'), false);
SELECT set_config('cleanup.project_ref', COALESCE(NULLIF(:'cleanup_project',''), ''), false);
SELECT set_config('cleanup.mode', COALESCE(NULLIF(:'cleanup_mode',''), 'DRY_RUN'), false);
SELECT set_config('cleanup.storage_policy_scope', COALESCE(NULLIF(:'cleanup_storage_policy_scope',''), ''), false);

-- ---------------------------------------------------------------------
-- Authorization gate (fail-closed, project-bound, scope-bound)
-- ---------------------------------------------------------------------
DO $cleanup_authz$
BEGIN
  IF current_setting('cleanup.authorized', true) IS DISTINCT FROM 'true' THEN
    RAISE EXCEPTION 'AUTHORIZATION REQUIRED: pass -v cleanup_authorized=true (GUC cleanup.authorized is not ''true'')';
  END IF;
  IF current_setting('cleanup.project_ref', true) IS DISTINCT FROM 'sxasnunzspkuwbxiddqd' THEN
    RAISE EXCEPTION 'PROJECT MISMATCH: pass -v cleanup_project=sxasnunzspkuwbxiddqd (GUC cleanup.project_ref does not match)';
  END IF;
  IF current_setting('cleanup.mode', true) NOT IN ('DRY_RUN', 'EXECUTE') THEN
    RAISE EXCEPTION 'INVALID MODE: pass -v cleanup_mode=DRY_RUN or -v cleanup_mode=EXECUTE';
  END IF;

  -- Weak environment guard (see header). The project ref cannot be read
  -- from the catalogs; this only rejects an obviously wrong connection.
  IF current_database() IS DISTINCT FROM 'postgres' THEN
    RAISE EXCEPTION 'DATABASE MISMATCH: connected database is "%", expected "postgres" (project ref is operator-asserted, not catalog-visible)',
      current_database();
  END IF;

  -- NEW SCOPE ITEM: storage-schema DDL is not covered by the approved
  -- public-schema cleanup authorization. A different token is required.
  IF current_setting('cleanup.storage_policy_scope', true)
     IS DISTINCT FROM 'CONFIRM_DROP_3_LEGACY_PDF_POLICIES_SXASNUNZSPKUWBXIDDQD' THEN
    RAISE EXCEPTION 'SCOPE AUTHORIZATION REQUIRED: pass -v cleanup_storage_policy_scope=CONFIRM_DROP_3_LEGACY_PDF_POLICIES_SXASNUNZSPKUWBXIDDQD (GUC cleanup.storage_policy_scope) - the public-schema cleanup authorization does NOT cover storage.objects policies';
  END IF;
END
$cleanup_authz$;

BEGIN;

-- Fail fast on lock contention instead of hanging; nothing is committed.
SET LOCAL statement_timeout = '60s';
SET LOCAL lock_timeout = '15s';
SET LOCAL idle_in_transaction_session_timeout = '120s';

-- ---------------------------------------------------------------------
-- Preflight: exact identities, semantics, dependencies, privilege.
-- DRY_RUN stops after this block and rolls back; no DROP is sent.
-- ---------------------------------------------------------------------
DO $verify_storage_policies_exact$
DECLARE
  -- Exact 3 authorized identities. Order is fixed and used for the
  -- per-policy expectations below.
  v_names   text[]    := ARRAY[
    'tenant_isolated_pdf_select',
    'tenant_isolated_pdf_insert',
    'tenant_isolated_pdf_delete'
  ];
  v_cmd     text[]    := ARRAY['r', 'a', 'd'];              -- SELECT, INSERT, DELETE
  v_using   boolean[] := ARRAY[true, false, true];          -- polqual present?
  v_check   boolean[] := ARRAY[false, true, false];         -- polwithcheck present?
  v_deps_expected text := 'public.get_my_tenant_id()|storage.foldername(name text)';

  v_table_oid    oid;
  v_relkind      "char";
  v_owner_oid    oid;
  v_owner_name   name;
  v_rls_enabled  boolean;
  v_rls_forced   boolean;
  v_is_super     boolean;
  v_is_owner     boolean;
  v_total        int;
  v_present      text;
  v_i            int;
  v_relid        oid;
  v_cmd_actual   text;
  v_perm_actual  boolean;
  v_using_actual boolean;
  v_check_actual boolean;
  v_roles_public boolean;
  v_ext_owned    boolean;
  v_deps_actual  text;
  v_fn_count     int;
  v_fn_owner     name;
  v_fn_ext       boolean;
BEGIN
  -- 0. Target relation must exist and be the ordinary table storage.objects.
  IF to_regclass('storage.objects') IS NULL THEN
    RAISE EXCEPTION 'PRECONDITION FAILED: storage.objects not found - refusing to proceed';
  END IF;

  SELECT c.oid, c.relkind, c.relowner, pg_get_userbyid(c.relowner),
         c.relrowsecurity, c.relforcerowsecurity
    INTO v_table_oid, v_relkind, v_owner_oid, v_owner_name,
         v_rls_enabled, v_rls_forced
  FROM pg_class c
  JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'storage' AND c.relname = 'objects';

  IF v_relkind IS DISTINCT FROM 'r' THEN
    RAISE EXCEPTION 'TARGET MISMATCH: storage.objects relkind is %, expected an ordinary table (r)', v_relkind::text;
  END IF;

  -- 0b. The three policies are expected to be ACTIVE access controls. If RLS
  --     is disabled on the table, the environment differs from the recorded
  --     state and its security model must be re-reviewed before any drop.
  IF v_rls_enabled IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'UNEXPECTED STATE: storage.objects has row-level security DISABLED (relrowsecurity=%) - aborting for owner review (the 3 policies are not active controls in this state)', v_rls_enabled;
  END IF;

  -- 1. Script allowlist sanity (guards a copy/paste edit of this file).
  IF cardinality(v_names) <> 3
     OR cardinality(v_cmd) <> 3
     OR cardinality(v_using) <> 3
     OR cardinality(v_check) <> 3 THEN
    RAISE EXCEPTION 'SCRIPT ALLOWLIST ERROR: expected 3 identities and 3 expectations, found %/%/%/%',
      cardinality(v_names), cardinality(v_cmd), cardinality(v_using), cardinality(v_check);
  END IF;

  -- 2. Exactly 3 policies exist on storage.objects. If anything else exists,
  --    this is not the known state and no drop may proceed.
  SELECT COUNT(*),
         string_agg(po.polname, ', ' ORDER BY po.polname)
    INTO v_total, v_present
  FROM pg_policy po
  WHERE po.polrelid = v_table_oid;

  IF v_total <> 3 THEN
    RAISE EXCEPTION 'UNEXPECTED POLICY SET: storage.objects has % polic(ies) [%], expected exactly 3 - aborting (no unrelated policy may be affected)',
      v_total, COALESCE(v_present, 'none');
  END IF;

  -- 3. Per-policy identity and semantics.
  FOR v_i IN 1..3 LOOP
    SELECT po.polrelid,
           po.polcmd::text,
           po.polpermissive,
           (po.polqual IS NOT NULL),
           (po.polwithcheck IS NOT NULL),
           (po.polroles = ARRAY[0]::oid[]),
           EXISTS (SELECT 1
                     FROM pg_depend d
                    WHERE d.classid = 'pg_policy'::regclass
                      AND d.objid = po.oid
                      AND d.deptype = 'e'),
           COALESCE((SELECT string_agg(f.fn, '|' ORDER BY f.fn)
                       FROM (SELECT p2.pronamespace::regnamespace::text||'.'||p2.proname||
                                    '('||pg_get_function_identity_arguments(p2.oid)||')' AS fn
                               FROM pg_depend d
                               JOIN pg_proc p2
                                 ON p2.oid = d.refobjid
                                AND d.refclassid = 'pg_proc'::regclass
                              WHERE d.classid = 'pg_policy'::regclass
                                AND d.objid = po.oid) f), '')
      INTO v_relid, v_cmd_actual, v_perm_actual, v_using_actual, v_check_actual,
           v_roles_public, v_ext_owned, v_deps_actual
    FROM pg_policy po
    WHERE po.polrelid = v_table_oid
      AND po.polname = v_names[v_i];

    IF NOT FOUND THEN
      RAISE EXCEPTION 'POLICY IDENTITY MISMATCH: policy "%" not found on storage.objects', v_names[v_i];
    END IF;

    IF v_relid IS DISTINCT FROM v_table_oid THEN
      RAISE EXCEPTION 'TARGET MISMATCH: policy "%" is not attached to storage.objects', v_names[v_i];
    END IF;

    IF v_cmd_actual IS DISTINCT FROM v_cmd[v_i] THEN
      RAISE EXCEPTION 'POLICY SEMANTICS MISMATCH: "%" command is "%", expected "%"', v_names[v_i], v_cmd_actual, v_cmd[v_i];
    END IF;

    IF v_perm_actual IS DISTINCT FROM true THEN
      RAISE EXCEPTION 'POLICY SEMANTICS MISMATCH: "%" is restrictive, expected permissive', v_names[v_i];
    END IF;

    IF v_roles_public IS DISTINCT FROM true THEN
      RAISE EXCEPTION 'POLICY SEMANTICS MISMATCH: "%" roles are not exactly {PUBLIC}', v_names[v_i];
    END IF;

    IF v_using_actual IS DISTINCT FROM v_using[v_i] THEN
      RAISE EXCEPTION 'POLICY SEMANTICS MISMATCH: "%" USING-expression presence is %, expected %', v_names[v_i], v_using_actual, v_using[v_i];
    END IF;

    IF v_check_actual IS DISTINCT FROM v_check[v_i] THEN
      RAISE EXCEPTION 'POLICY SEMANTICS MISMATCH: "%" WITH CHECK-expression presence is %, expected %', v_names[v_i], v_check_actual, v_check[v_i];
    END IF;

    IF v_ext_owned IS DISTINCT FROM false THEN
      RAISE EXCEPTION 'EXTENSION-OWNED POLICY DETECTED: "%" belongs to an extension - not application-owned', v_names[v_i];
    END IF;

    -- Exact dependency set: both the legacy tenant function and the
    -- standard storage folder helper, and nothing else.
    IF v_deps_actual IS DISTINCT FROM v_deps_expected THEN
      RAISE EXCEPTION 'POLICY DEPENDENCY MISMATCH: "%" depends on [%], expected exactly [%]',
        v_names[v_i], COALESCE(NULLIF(v_deps_actual,''), 'none'), v_deps_expected;
    END IF;
  END LOOP;

  -- 4. The blocked function must still be the single Stage-4 target.
  SELECT COUNT(*) INTO v_fn_count
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND p.proname = 'get_my_tenant_id'
    AND p.prokind = 'f';

  IF v_fn_count <> 1 THEN
    RAISE EXCEPTION 'FUNCTION PRECONDITION FAILED: expected exactly 1 public.get_my_tenant_id() function, found %', v_fn_count;
  END IF;

  SELECT pg_get_userbyid(p.proowner),
         EXISTS (SELECT 1
                   FROM pg_depend d
                  WHERE d.classid = 'pg_proc'::regclass
                    AND d.objid = p.oid
                    AND d.deptype = 'e')
    INTO v_fn_owner, v_fn_ext
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND p.proname = 'get_my_tenant_id'
    AND p.prokind = 'f';

  IF v_fn_owner IS DISTINCT FROM 'postgres'::name OR v_fn_ext IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'FUNCTION PRECONDITION FAILED: public.get_my_tenant_id() owner=% extension_owned=% (expected postgres-owned, not extension-owned)',
      v_fn_owner, v_fn_ext;
  END IF;

  -- 5. DROP POLICY requires ownership of the table (or superuser).
  SELECT rolsuper INTO v_is_super FROM pg_roles WHERE rolname = current_user;
  v_is_owner := pg_has_role(current_user, v_owner_name, 'USAGE');

  IF NOT (COALESCE(v_is_super, false) OR COALESCE(v_is_owner, false)) THEN
    RAISE EXCEPTION 'PRIVILEGE PRECONDITION FAILED: role % is not superuser and not a member of the owner of storage.objects (%). Do not proceed with a different credential without separate owner authorization.',
      current_user, v_owner_name;
  END IF;

  RAISE NOTICE 'Verified 3/3 authorized storage.objects policies: names, commands (SELECT/INSERT/DELETE), permissive, roles={PUBLIC}, expression shape, extension_owned=false';
  RAISE NOTICE 'Verified per-policy catalog dependency set = {public.get_my_tenant_id(), storage.foldername(text)}; no other dependency';
  RAISE NOTICE 'Verified storage.objects has exactly 3 policies in total: no unrelated policy exists that these DROPs could affect';
  RAISE NOTICE 'Verified public.get_my_tenant_id() still present (postgres-owned, not extension-owned); storage.objects owner=%', v_owner_name;
  RAISE NOTICE 'Verified storage.objects state: relkind=r, RLS enabled=%, force RLS=%', v_rls_enabled, v_rls_forced;
  RAISE NOTICE 'Executing role=% (superuser=%, member_of_storage_owner=%): privilege preconditions OK', current_user, v_is_super, v_is_owner;
END
$verify_storage_policies_exact$;

-- ---------------------------------------------------------------------
-- Object fingerprint: everything on storage.objects that must NOT change.
-- (owner, table ACL, RLS flags, reloptions, and per column: name, type,
--  NOT NULL, column ACL, default expression)
-- ---------------------------------------------------------------------
SELECT set_config(
         'cleanup.s3b_object_fingerprint',
         md5(
           pg_get_userbyid(c.relowner)||'|'||
           COALESCE(c.relacl::text,'')||'|'||
           c.relrowsecurity::text||'|'||
           c.relforcerowsecurity::text||'|'||
           COALESCE(c.reloptions::text,'')||'|'||
           COALESCE((SELECT string_agg(a.attname||':'||format_type(a.atttypid,a.atttypmod)||':'||
                                      a.attnotnull::text||':'||COALESCE(a.attacl::text,'')||':'||
                                      COALESCE(pg_get_expr(ad.adbin, ad.adrelid),''),
                                      ',' ORDER BY a.attnum)
                       FROM pg_attribute a
                       LEFT JOIN pg_attrdef ad
                         ON ad.adrelid = a.attrelid
                        AND ad.adnum = a.attnum
                      WHERE a.attrelid = c.oid
                        AND a.attnum > 0
                        AND NOT a.attisdropped), '')
         ),
         true
       ) AS storage_objects_fingerprint_captured
FROM pg_class c
WHERE c.oid = 'storage.objects'::regclass;

-- ---------------------------------------------------------------------
-- DRY_RUN / EXECUTE gating
-- ---------------------------------------------------------------------
-- COALESCE is deliberate: \gset stores SQL NULL as an empty string, and an
-- empty value is not an unambiguous true/false match for \if (psql warns and
-- falls through). Collapsing NULL to false means the one branch that sends
-- DDL can only ever be selected by an explicit 'EXECUTE'. cleanup.mode is
-- already validated above, so this is defence in depth, not the gate.
SELECT COALESCE(current_setting('cleanup.mode', true) = 'EXECUTE', false) AS exec_flag_bool \gset

\if :exec_flag_bool
  -- Drop exactly the 3 verified policies. No IF EXISTS by design: presence
  -- was proven in this transaction, so an unexpected absence must abort.
  DROP POLICY "tenant_isolated_pdf_select" ON storage.objects;
  DROP POLICY "tenant_isolated_pdf_insert" ON storage.objects;
  DROP POLICY "tenant_isolated_pdf_delete" ON storage.objects;

  -- Post-drop verification: absence + no collateral change + Stage 4
  -- blocker class cleared, all before COMMIT.
  DO $verify_after$
  DECLARE
    v_names      text[] := ARRAY[
      'tenant_isolated_pdf_select',
      'tenant_isolated_pdf_insert',
      'tenant_isolated_pdf_delete'
    ];
    v_table_oid  oid := 'storage.objects'::regclass;
    v_present    text;
    v_remaining  int;
    v_remaining_names text;
    v_fingerprint_before text;
    v_fingerprint_now    text;
    v_fn_count   int;
    v_policy_refs int;
  BEGIN
    -- 1. The three authorized policies must be gone.
    SELECT string_agg(po.polname, ', ' ORDER BY po.polname)
      INTO v_present
    FROM pg_policy po
    WHERE po.polrelid = v_table_oid
      AND po.polname = ANY (v_names);

    IF v_present IS NOT NULL THEN
      RAISE EXCEPTION 'POST-DROP VERIFICATION FAILED: authorized policies still present: %', v_present;
    END IF;

    -- 2. Nothing else may remain on storage.objects (state was exactly 3).
    SELECT COUNT(*),
           string_agg(po.polname, ', ' ORDER BY po.polname)
      INTO v_remaining, v_remaining_names
    FROM pg_policy po
    WHERE po.polrelid = v_table_oid;

    IF v_remaining <> 0 THEN
      RAISE EXCEPTION 'POST-DROP VERIFICATION FAILED: % unexpected polic(ies) remain on storage.objects: %',
        v_remaining, COALESCE(v_remaining_names, '?');
    END IF;

    -- 3. Object fingerprint must be bit-identical (owner, table/column ACLs,
    --    column type/NOT NULL/default, RLS flags, reloptions untouched).
    v_fingerprint_before := current_setting('cleanup.s3b_object_fingerprint', true);

    SELECT md5(
             pg_get_userbyid(c.relowner)||'|'||
             COALESCE(c.relacl::text,'')||'|'||
             c.relrowsecurity::text||'|'||
             c.relforcerowsecurity::text||'|'||
             COALESCE(c.reloptions::text,'')||'|'||
             COALESCE((SELECT string_agg(a.attname||':'||format_type(a.atttypid,a.atttypmod)||':'||
                                        a.attnotnull::text||':'||COALESCE(a.attacl::text,'')||':'||
                                        COALESCE(pg_get_expr(ad.adbin, ad.adrelid),''),
                                        ',' ORDER BY a.attnum)
                         FROM pg_attribute a
                         LEFT JOIN pg_attrdef ad
                           ON ad.adrelid = a.attrelid
                          AND ad.adnum = a.attnum
                        WHERE a.attrelid = c.oid
                          AND a.attnum > 0
                          AND NOT a.attisdropped), '')
           )
      INTO v_fingerprint_now
    FROM pg_class c
    WHERE c.oid = v_table_oid;

    IF v_fingerprint_before IS NULL
       OR v_fingerprint_now IS DISTINCT FROM v_fingerprint_before THEN
      RAISE EXCEPTION 'POST-DROP VERIFICATION FAILED: storage.objects fingerprint changed (before=%, after=%) - an owner, ACL, column definition/default, RLS flag or reloption was modified',
        COALESCE(v_fingerprint_before, 'MISSING'), COALESCE(v_fingerprint_now, 'MISSING');
    END IF;

    -- 4. This script must not have touched functions.
    SELECT COUNT(*) INTO v_fn_count
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.proname = 'get_my_tenant_id'
      AND p.prokind = 'f';

    IF v_fn_count <> 1 THEN
      RAISE EXCEPTION 'POST-DROP VERIFICATION FAILED: public.get_my_tenant_id() count is %, expected 1 (this script must not drop functions)', v_fn_count;
    END IF;

    -- 5. Known Stage-4 blocker class must now be empty. Stage 4 still runs
    --    its own fail-closed preflight across ALL catalog classes.
    SELECT COUNT(*) INTO v_policy_refs
    FROM pg_policy po
    JOIN pg_depend d
      ON d.classid = 'pg_policy'::regclass
     AND d.objid = po.oid
     AND d.refclassid = 'pg_proc'::regclass
    JOIN pg_proc p ON p.oid = d.refobjid
    JOIN pg_namespace pn ON pn.oid = p.pronamespace
    WHERE pn.nspname = 'public'
      AND p.proname = 'get_my_tenant_id';

    IF v_policy_refs <> 0 THEN
      RAISE EXCEPTION 'POST-DROP VERIFICATION FAILED: % polic(ies) still depend on public.get_my_tenant_id()', v_policy_refs;
    END IF;

    RAISE NOTICE 'All 3 authorized storage.objects policies absent - VERIFIED REMOVED';
    RAISE NOTICE 'storage.objects fingerprint unchanged (owner, table/column ACLs, column type/NOT NULL/default, RLS flags, reloptions)';
    RAISE NOTICE 'public.get_my_tenant_id() still present; no pg_policy anywhere depends on it - Stage 4 known blocker class cleared';
    RAISE NOTICE 'Side effect (expected): storage.objects now has 0 policies, i.e. default-deny for non-owner/non-bypass roles. Bucket "pdfs" is NOT touched by this script - Stage 7 owns it';
  END
  $verify_after$;

  COMMIT;
  SELECT 'SCRIPT 03b COMPLETED (EXECUTE)' AS status;
\else
  -- DRY_RUN: identities/semantics/dependencies/privilege verified above;
  -- no DROP POLICY was sent, nothing is committed.
  ROLLBACK;
  SELECT 'SCRIPT 03b COMPLETED (DRY_RUN - ROLLED BACK, NO DROPS)' AS status;
\endif
