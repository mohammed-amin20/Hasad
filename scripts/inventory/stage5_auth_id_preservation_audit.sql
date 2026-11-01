-- =====================================================================
-- Hasad ERP V2 - READ-ONLY AUDIT: Stage 5 Auth-ID preservation
-- =====================================================================
-- Target : Supabase DEV project sxasnunzspkuwbxiddqd (owner-operated)
-- Purpose: Preserve only the exact UUIDs in auth.users linked to the four
--          authorized legacy public.users rows, before that table is dropped.
-- Output : Redirect psql output only to a private, git-ignored file beneath
--          local_audit/. Do not paste its UUIDs into tracked files or logs.
-- Safety : No DDL/DML. One read-only transaction followed by ROLLBACK.
-- Hides  : emails, phones, password/session/token data, profile fields, and
--          every public.users column other than the linked auth UUID.
-- =====================================================================

\set ON_ERROR_STOP on

SELECT set_config('audit.project_ref', COALESCE(NULLIF(:'audit_project',''), ''), false);
SET default_transaction_read_only = on;
SET statement_timeout = '60s';
SET idle_in_transaction_session_timeout = '120s';

DO $audit_gate$
BEGIN
  IF current_setting('audit.project_ref', true) IS DISTINCT FROM 'sxasnunzspkuwbxiddqd' THEN
    RAISE EXCEPTION 'PROJECT MISMATCH: audit.project_ref must be sxasnunzspkuwbxiddqd';
  END IF;
  IF current_database() IS DISTINCT FROM 'postgres' THEN
    RAISE EXCEPTION 'DATABASE MISMATCH: expected postgres, got %', current_database();
  END IF;
END
$audit_gate$;

BEGIN TRANSACTION READ ONLY;

DO $readonly_guard$
BEGIN
  IF current_setting('transaction_read_only') <> 'on'
     OR current_setting('default_transaction_read_only') <> 'on' THEN
    RAISE EXCEPTION 'FAIL-CLOSED: read-only transaction guard is not active';
  END IF;
END
$readonly_guard$;

-- Fail closed: the preservation set is exactly the four linked legacy rows.
DO $mapping_preconditions$
DECLARE
  v_public_users_oid oid;
  v_public_users_owner name;
  v_total_public_users int;
  v_nonnull_links int;
  v_distinct_links int;
  v_missing_auth int;
  v_duplicate_links text;
  v_invalid_link_type text;
BEGIN
  SELECT c.oid, pg_get_userbyid(c.relowner)
    INTO v_public_users_oid, v_public_users_owner
  FROM pg_class c
  JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'public' AND c.relname = 'users' AND c.relkind = 'r';

  IF v_public_users_oid IS NULL THEN
    RAISE EXCEPTION 'PRECONDITION FAILED: public.users must be an ordinary table';
  END IF;
  IF v_public_users_owner IS DISTINCT FROM 'postgres'::name THEN
    RAISE EXCEPTION 'OWNERSHIP MISMATCH: public.users owner is %, expected postgres', v_public_users_owner;
  END IF;
  IF to_regclass('auth.users') IS NULL THEN
    RAISE EXCEPTION 'PRECONDITION FAILED: auth.users is absent';
  END IF;

  SELECT format_type(a.atttypid, a.atttypmod)
    INTO v_invalid_link_type
  FROM pg_attribute a
  WHERE a.attrelid = v_public_users_oid
    AND a.attname = 'auth_user_id'
    AND a.attnum > 0
    AND NOT a.attisdropped;
  IF v_invalid_link_type IS DISTINCT FROM 'uuid' THEN
    RAISE EXCEPTION 'PRECONDITION FAILED: public.users.auth_user_id type is %, expected uuid',
      COALESCE(v_invalid_link_type, 'missing');
  END IF;

  SELECT count(*), count(auth_user_id), count(DISTINCT auth_user_id)
    INTO v_total_public_users, v_nonnull_links, v_distinct_links
  FROM public.users;
  IF v_total_public_users <> 4 OR v_nonnull_links <> 4 OR v_distinct_links <> 4 THEN
    RAISE EXCEPTION 'AMBIGUOUS/INCOMPLETE MAPPING: public.users total=% nonnull_links=% distinct_links=%; expected 4/4/4',
      v_total_public_users, v_nonnull_links, v_distinct_links;
  END IF;

  SELECT count(*) INTO v_missing_auth
  FROM public.users u
  LEFT JOIN auth.users a ON a.id = u.auth_user_id
  WHERE a.id IS NULL;
  IF v_missing_auth <> 0 THEN
    RAISE EXCEPTION 'INCOMPLETE MAPPING: % public.users auth_user_id value(s) have no auth.users row', v_missing_auth;
  END IF;

  SELECT string_agg(auth_user_id::text, ', ' ORDER BY auth_user_id::text)
    INTO v_duplicate_links
  FROM (
    SELECT auth_user_id
    FROM public.users
    GROUP BY auth_user_id
    HAVING count(*) > 1
  ) d;
  IF v_duplicate_links IS NOT NULL THEN
    RAISE EXCEPTION 'AMBIGUOUS MAPPING: duplicate public.users.auth_user_id value(s): %', v_duplicate_links;
  END IF;
END
$mapping_preconditions$;

\echo '==== STAGE 5 AUTH-ID PRESERVATION EVIDENCE (PRIVATE OUTPUT) ===='
-- This is intentionally the only data-bearing result: four Auth UUIDs.
SELECT a.id AS linked_auth_user_id
FROM public.users u
JOIN auth.users a ON a.id = u.auth_user_id
ORDER BY a.id;

SELECT 'STAGE5_AUTH_ID_AUDIT_SXASNUNZSPKUWBXIDDQD_COMPLETE' AS completion_attestation,
       'exact_count=4; mapping=complete_unique; no_personal_fields_selected' AS verdict;

ROLLBACK;
