-- =====================================================================
-- Hasad ERP V2 - Supabase DEV read-only PLATFORM metadata inventory
-- =====================================================================
-- Target (non-secret): Supabase DEV project sxasnunzspkuwbxiddqd,
-- connected through the already verified pooler endpoint that the runner
-- reads from supabase/.temp/pooler-url.
--
-- Purpose:
--   Complete the remaining Hasad V1 PLATFORM inventory (Auth, Storage,
--   Edge Functions, cron jobs, webhooks, secrets/config) using catalog
--   metadata only, so the DRAFT cleanup manifest can be finalized.
--
-- Safety contract (identical guarantees to dev_inventory_readonly.sql):
--   * Metadata only. No user emails, phone numbers, password hashes,
--     identities, tokens, refresh tokens, session payloads, private
--     metadata, storage object paths/contents, function source, cron job
--     payloads (they may embed secrets), or secret VALUES are selected.
--   * One explicit BEGIN TRANSACTION READ ONLY / ROLLBACK pair wraps every
--     query. Nothing before BEGIN except session-local SETs.
--   * Fail-closed server-side guard: if either the session default or the
--     current transaction is not read-only, a plpgsql RAISE EXCEPTION
--     aborts the run (psql stops immediately via ON_ERROR_STOP).
--   * MISSING-RELATION SAFETY: this inventory may run against a project
--     where some platform schemas/tables are not provisioned. Every
--     section therefore checks existence through to_regclass() first and
--     emits an explicit NOT_PRESENT row instead of raising. No dynamic
--     SQL is executed against absent objects.
--   * psql meta-commands used: only \set and \echo.
-- =====================================================================

\set ON_ERROR_STOP on

-- Session-local defaults only (no database state is touched).
SET default_transaction_read_only = on;
SET statement_timeout = '60s';
SET idle_in_transaction_session_timeout = '120s';

BEGIN TRANSACTION READ ONLY;

-- ---------------------------------------------------------------------
-- Fail-closed read-only guard (aborts the transaction and the psql run
-- if the transaction is not genuinely read-only).
-- ---------------------------------------------------------------------
DO $hasad_platform_guard$
BEGIN
  IF current_setting('transaction_read_only') <> 'on' THEN
    RAISE EXCEPTION 'FAIL-CLOSED: transaction_read_only = %, expected on',
      current_setting('transaction_read_only');
  END IF;
  IF current_setting('default_transaction_read_only') <> 'on' THEN
    RAISE EXCEPTION 'FAIL-CLOSED: default_transaction_read_only = %, expected on',
      current_setting('default_transaction_read_only');
  END IF;
END
$hasad_platform_guard$;

-- ---------------------------------------------------------------------
-- 01. Run context
-- ---------------------------------------------------------------------
\echo '==== 01. RUN CONTEXT ===='
SELECT current_database() AS database_name,
       current_user AS connected_role,
       current_setting('transaction_read_only') AS transaction_read_only,
       current_setting('default_transaction_read_only') AS default_transaction_read_only,
       current_setting('server_version') AS server_version,
       clock_timestamp() AS captured_at;

-- ---------------------------------------------------------------------
-- 02. Platform schema presence (drives expectation for every section)
-- ---------------------------------------------------------------------
\echo '==== 02. PLATFORM SCHEMA PRESENCE ===='
SELECT n.nspname AS schema_name,
       pg_get_userbyid(n.nspowner) AS owner
FROM pg_namespace n
WHERE n.nspname IN ('auth','storage','supabase_functions','net','cron','vault',
                    'realtime','graphql','graphql_public','pgbouncer','extensions')
ORDER BY n.nspname;

\echo '==== 02b. EXPECTED PLATFORM RELATIONS PRESENT? ===='
SELECT x.rel AS expected_relation,
       (to_regclass(x.rel) IS NOT NULL) AS present
FROM (VALUES
  ('auth.users'),
  ('auth.identities'),
  ('auth.sessions'),
  ('auth.refresh_tokens'),
  ('auth.mfa_factors'),
  ('auth.one_time_tokens'),
  ('auth.audit_log_entries'),
  ('auth.hooks'),
  ('auth.instances'),
  ('auth.flow_state'),
  ('storage.buckets'),
  ('storage.objects'),
  ('storage.s3_multipart_uploads'),
  ('supabase_functions.functions'),
  ('supabase_functions.hooks'),
  ('cron.job'),
  ('cron.job_run_details'),
  ('net.http_request_queue'),
  ('net._http_response'),
  ('vault.secrets')
) AS x(rel)
ORDER BY x.rel;

-- ---------------------------------------------------------------------
-- 03. Auth - user counts and non-sensitive ownership indicators ONLY.
--     Implemented as plpgsql with to_regclass guards so the section
--     reports NOT_PRESENT rather than failing when a table is absent.
-- ---------------------------------------------------------------------
\echo '==== 03. AUTH USER AGGREGATES (no PII, no secrets) ===='
DO $hasad_auth_summary$
DECLARE
  n_total bigint; d_min timestamptz; d_max timestamptz; d_last timestamptz;
  has_anon boolean; has_deleted boolean; has_banned boolean;
  has_email_conf boolean; has_phone_conf boolean;
BEGIN
  IF to_regclass('auth.users') IS NULL THEN
    RAISE NOTICE 'auth.users NOT_PRESENT';
    RETURN;
  END IF;

  SELECT EXISTS (SELECT 1 FROM information_schema.columns
                  WHERE table_schema='auth' AND table_name='users' AND column_name='is_anonymous') INTO has_anon;
  SELECT EXISTS (SELECT 1 FROM information_schema.columns
                  WHERE table_schema='auth' AND table_name='users' AND column_name='deleted_at') INTO has_deleted;
  SELECT EXISTS (SELECT 1 FROM information_schema.columns
                  WHERE table_schema='auth' AND table_name='users' AND column_name='banned_until') INTO has_banned;
  SELECT EXISTS (SELECT 1 FROM information_schema.columns
                  WHERE table_schema='auth' AND table_name='users' AND column_name='email_confirmed_at') INTO has_email_conf;
  SELECT EXISTS (SELECT 1 FROM information_schema.columns
                  WHERE table_schema='auth' AND table_name='users' AND column_name='phone_confirmed_at') INTO has_phone_conf;

  SELECT count(*), min(created_at), max(created_at), max(last_sign_in_at)
    INTO n_total, d_min, d_max, d_last
    FROM auth.users;
  RAISE NOTICE 'total_auth_users=%', n_total;
  RAISE NOTICE 'earliest_created=% latest_created=% latest_sign_in=%', d_min, d_max, d_last;

  IF has_anon THEN
    DECLARE n bigint; BEGIN
      EXECUTE 'SELECT count(*) FROM auth.users WHERE is_anonymous' INTO n;
      RAISE NOTICE 'anonymous_users=%', n;
    END;
  ELSE
    RAISE NOTICE 'is_anonymous column NOT_PRESENT';
  END IF;

  IF has_anon THEN
    DECLARE n bigint; BEGIN
      EXECUTE 'SELECT count(*) FROM auth.users WHERE NOT is_anonymous' INTO n;
      RAISE NOTICE 'non_anonymous_users=%', n;
    END;
  END IF;

  IF has_email_conf THEN
    DECLARE n bigint; BEGIN
      EXECUTE 'SELECT count(*) FROM auth.users WHERE email_confirmed_at IS NOT NULL' INTO n;
      RAISE NOTICE 'email_confirmed_users=%', n;
    END;
  ELSE
    RAISE NOTICE 'email_confirmed_at column NOT_PRESENT';
  END IF;

  IF has_phone_conf THEN
    DECLARE n bigint; BEGIN
      EXECUTE 'SELECT count(*) FROM auth.users WHERE phone_confirmed_at IS NOT NULL' INTO n;
      RAISE NOTICE 'phone_confirmed_users=%', n;
    END;
  ELSE
    RAISE NOTICE 'phone_confirmed_at column NOT_PRESENT';
  END IF;

  IF has_banned THEN
    DECLARE n bigint; BEGIN
      EXECUTE 'SELECT count(*) FROM auth.users WHERE banned_until IS NOT NULL AND banned_until > now()' INTO n;
      RAISE NOTICE 'currently_banned_users=%', n;
    END;
  ELSE
    RAISE NOTICE 'banned_until column NOT_PRESENT';
  END IF;

  IF has_deleted THEN
    DECLARE n bigint; BEGIN
      EXECUTE 'SELECT count(*) FROM auth.users WHERE deleted_at IS NOT NULL' INTO n;
      RAISE NOTICE 'soft_deleted_users=%', n;
    END;
  ELSE
    RAISE NOTICE 'deleted_at column NOT_PRESENT';
  END IF;
END
$hasad_auth_summary$;

\echo '==== 03b. AUTH USERS BY SIGN-IN ACTIVITY BUCKET ===='
DO $hasad_auth_activity$
DECLARE
  r record;
BEGIN
  IF to_regclass('auth.users') IS NULL THEN
    RAISE NOTICE 'auth.users NOT_PRESENT';
    RETURN;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                  WHERE table_schema='auth' AND table_name='users' AND column_name='last_sign_in_at') THEN
    RAISE NOTICE 'last_sign_in_at column NOT_PRESENT';
    RETURN;
  END IF;
  FOR r IN SELECT CASE
                   WHEN last_sign_in_at IS NULL THEN '1_never_signed_in'
                   WHEN last_sign_in_at >= now() - interval '30 days' THEN '2_active_30d'
                   WHEN last_sign_in_at >= now() - interval '90 days' THEN '3_active_90d'
                   WHEN last_sign_in_at >= now() - interval '365 days' THEN '4_active_365d'
                   ELSE '5_stale_gt_365d'
                 END AS activity_bucket,
                 count(*) AS users
           FROM auth.users GROUP BY 1 ORDER BY 1
  LOOP
    RAISE NOTICE 'activity_bucket=% users=%', r.activity_bucket, r.users;
  END LOOP;
END
$hasad_auth_activity$;

\echo '==== 03c. AUTH USERS BY CREATION MONTH ===='
DO $hasad_auth_months$
DECLARE
  r record;
BEGIN
  IF to_regclass('auth.users') IS NULL THEN
    RAISE NOTICE 'auth.users NOT_PRESENT';
    RETURN;
  END IF;
  FOR r IN SELECT to_char(created_at, 'YYYY-MM') AS created_month, count(*) AS users
           FROM auth.users GROUP BY 1 ORDER BY 1
  LOOP
    RAISE NOTICE 'created_month=% users=%', r.created_month, r.users;
  END LOOP;
END
$hasad_auth_months$;

\echo '==== 03d. AUTH PROVIDER / IDENTITY COUNTS (no identity ids or subjects) ===='
DO $hasad_auth_identities$
DECLARE
  r record;
BEGIN
  IF to_regclass('auth.identities') IS NULL THEN
    RAISE NOTICE 'auth.identities NOT_PRESENT';
    RETURN;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                  WHERE table_schema='auth' AND table_name='identities' AND column_name='provider') THEN
    RAISE NOTICE 'auth.identities.provider column NOT_PRESENT';
    RETURN;
  END IF;
  FOR r IN SELECT provider, count(*) AS identity_count,
                  count(DISTINCT user_id) AS distinct_users
           FROM auth.identities GROUP BY provider ORDER BY provider
  LOOP
    RAISE NOTICE 'provider=% identity_count=% distinct_users=%',
      r.provider, r.identity_count, r.distinct_users;
  END LOOP;
END
$hasad_auth_identities$;

\echo '==== 03e. AUTH ENTITY ROW COUNTS (counts only) ===='
DO $hasad_auth_entity_counts$
DECLARE
  rel text;
  cnt bigint;
  rels text[] := ARRAY['auth.sessions','auth.refresh_tokens','auth.mfa_factors',
                       'auth.one_time_tokens','auth.audit_log_entries','auth.flow_state',
                       'auth.instances'];
BEGIN
  FOREACH rel IN ARRAY rels LOOP
    IF to_regclass(rel) IS NULL THEN
      RAISE NOTICE '% NOT_PRESENT', rel;
    ELSE
      EXECUTE format('SELECT count(*) FROM %s', rel) INTO cnt;
      RAISE NOTICE '% rows=%', rel, cnt;
    END IF;
  END LOOP;
END
$hasad_auth_entity_counts$;

\echo '==== 03f. AUTH HOOK COLUMN INVENTORY ===='
DO $hasad_auth_hook_columns$
DECLARE
  r record;
BEGIN
  IF to_regclass('auth.hooks') IS NULL THEN
    RAISE NOTICE 'auth.hooks NOT_PRESENT';
    RETURN;
  END IF;
  FOR r IN SELECT column_name, data_type
           FROM information_schema.columns
           WHERE table_schema='auth' AND table_name='hooks'
           ORDER BY ordinal_position
  LOOP
    RAISE NOTICE 'auth.hooks column % (%)', r.column_name, r.data_type;
  END LOOP;
END
$hasad_auth_hook_columns$;

\echo '==== 03g. AUTH HOOKS (metadata only; URI host only, path redacted) ===='
DO $hasad_auth_hooks$
DECLARE
  r record;
  has_name boolean; has_type boolean; has_enabled boolean;
  has_uri boolean; has_secret boolean;
  sql text;
BEGIN
  IF to_regclass('auth.hooks') IS NULL THEN
    RAISE NOTICE 'auth.hooks NOT_PRESENT';
    RETURN;
  END IF;

  SELECT EXISTS (SELECT 1 FROM information_schema.columns
                  WHERE table_schema='auth' AND table_name='hooks' AND column_name='hook_name') INTO has_name;
  SELECT EXISTS (SELECT 1 FROM information_schema.columns
                  WHERE table_schema='auth' AND table_name='hooks' AND column_name='hook_type') INTO has_type;
  SELECT EXISTS (SELECT 1 FROM information_schema.columns
                  WHERE table_schema='auth' AND table_name='hooks' AND column_name='enabled') INTO has_enabled;
  SELECT EXISTS (SELECT 1 FROM information_schema.columns
                  WHERE table_schema='auth' AND table_name='hooks' AND column_name='hook_uri') INTO has_uri;
  -- Presence only: the hook secret column name is reported, never its value.
  SELECT EXISTS (SELECT 1 FROM information_schema.columns
                  WHERE table_schema='auth' AND table_name='hooks' AND column_name='hook_secret') INTO has_secret;

  IF has_secret THEN
    RAISE NOTICE 'auth.hooks has a hook_secret column (value NEVER read)';
  END IF;

  sql := 'SELECT ' ||
         CASE WHEN has_name THEN 'hook_name' ELSE 'NULL::text' END || ' AS hook_name, ' ||
         CASE WHEN has_type THEN 'hook_type' ELSE 'NULL::text' END || ' AS hook_type, ' ||
         CASE WHEN has_enabled THEN 'enabled' ELSE 'NULL::boolean' END || ' AS enabled, ' ||
         CASE WHEN has_uri THEN
           'regexp_replace(hook_uri, ''^(https?://[^/]+).*'', ''\1/<redacted>'')'
           ELSE 'NULL::text' END || ' AS hook_origin_redacted ' ||
         'FROM auth.hooks';
  FOR r IN EXECUTE sql
  LOOP
    RAISE NOTICE 'hook_name=% hook_type=% enabled=% origin=%',
      r.hook_name, r.hook_type, r.enabled, r.hook_origin_redacted;
  END LOOP;
END
$hasad_auth_hooks$;

-- ---------------------------------------------------------------------
-- 04. Storage - buckets and object counts ONLY. No object paths/content.
--     Guarded plpgsql so absent storage tables report NOT_PRESENT instead
--     of failing at parse time.
-- ---------------------------------------------------------------------
\echo '==== 04. STORAGE BUCKET COLUMN INVENTORY ===='
DO $hasad_storage_cols$
DECLARE
  r record;
BEGIN
  IF to_regclass('storage.buckets') IS NULL THEN
    RAISE NOTICE 'storage.buckets NOT_PRESENT';
    RETURN;
  END IF;
  FOR r IN SELECT column_name, data_type FROM information_schema.columns
           WHERE table_schema='storage' AND table_name='buckets'
           ORDER BY ordinal_position
  LOOP
    RAISE NOTICE 'storage.buckets column % (%)', r.column_name, r.data_type;
  END LOOP;
END
$hasad_storage_cols$;

\echo '==== 04b. STORAGE BUCKETS (names, visibility, limits; no objects) ===='
DO $hasad_storage$
DECLARE
  r record;
  has_name boolean; has_public boolean; has_limit boolean;
  has_mime boolean; has_created boolean;
  sql text;
BEGIN
  IF to_regclass('storage.buckets') IS NULL THEN
    RAISE NOTICE 'storage.buckets NOT_PRESENT';
    RETURN;
  END IF;
  SELECT EXISTS (SELECT 1 FROM information_schema.columns
                  WHERE table_schema='storage' AND table_name='buckets' AND column_name='name') INTO has_name;
  SELECT EXISTS (SELECT 1 FROM information_schema.columns
                  WHERE table_schema='storage' AND table_name='buckets' AND column_name='public') INTO has_public;
  SELECT EXISTS (SELECT 1 FROM information_schema.columns
                  WHERE table_schema='storage' AND table_name='buckets' AND column_name='file_size_limit') INTO has_limit;
  SELECT EXISTS (SELECT 1 FROM information_schema.columns
                  WHERE table_schema='storage' AND table_name='buckets' AND column_name='allowed_mime_types') INTO has_mime;
  SELECT EXISTS (SELECT 1 FROM information_schema.columns
                  WHERE table_schema='storage' AND table_name='buckets' AND column_name='created_at') INTO has_created;

  sql := 'SELECT id::text AS bucket_id, ' ||
         CASE WHEN has_name THEN 'name' ELSE 'NULL::text' END || ' AS bucket_name, ' ||
         CASE WHEN has_public THEN 'public' ELSE 'NULL::boolean' END || ' AS is_public, ' ||
         CASE WHEN has_limit THEN 'file_size_limit' ELSE 'NULL::bigint' END || ' AS file_size_limit, ' ||
         CASE WHEN has_mime THEN 'allowed_mime_types' ELSE 'NULL::text[]' END || ' AS allowed_mime_types, ' ||
         CASE WHEN has_created THEN 'created_at' ELSE 'NULL::timestamptz' END || ' AS created_at ' ||
         'FROM storage.buckets ' ||
         CASE WHEN has_created THEN 'ORDER BY created_at' ELSE 'ORDER BY id' END;
  FOR r IN EXECUTE sql
  LOOP
    RAISE NOTICE 'bucket_id=% bucket_name=% is_public=% file_size_limit=% allowed_mime_types=% created_at=%',
      r.bucket_id, r.bucket_name, r.is_public, r.file_size_limit, r.allowed_mime_types, r.created_at;
  END LOOP;
END
$hasad_storage$;

\echo '==== 04c. STORAGE OBJECT COUNTS PER BUCKET (counts only, no paths) ===='
DO $hasad_storage_objects$
DECLARE
  r record;
  has_size boolean;
  sql text;
BEGIN
  IF to_regclass('storage.buckets') IS NULL OR to_regclass('storage.objects') IS NULL THEN
    RAISE NOTICE 'storage.objects NOT_PRESENT (skipped)';
    RETURN;
  END IF;
  SELECT EXISTS (SELECT 1 FROM information_schema.columns
                  WHERE table_schema='storage' AND table_name='objects' AND column_name='metadata') INTO has_size;

  -- Core Storage columns are present in every release, but guard anyway so a
  -- schema drift reports a clear skip instead of aborting the run.
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                  WHERE table_schema='storage' AND table_name='buckets' AND column_name='name')
     OR NOT EXISTS (SELECT 1 FROM information_schema.columns
                  WHERE table_schema='storage' AND table_name='objects' AND column_name='bucket_id')
     OR NOT EXISTS (SELECT 1 FROM information_schema.columns
                  WHERE table_schema='storage' AND table_name='objects' AND column_name='id')
     OR NOT EXISTS (SELECT 1 FROM information_schema.columns
                  WHERE table_schema='storage' AND table_name='objects' AND column_name='created_at') THEN
    RAISE NOTICE 'storage objects/buckets required columns NOT_PRESENT (skipped)';
    RETURN;
  END IF;

  sql := 'SELECT b.name AS bucket_name, count(o.id) AS object_count, ' ||
         CASE WHEN has_size THEN 'coalesce(sum((o.metadata->>''size'')::bigint), 0)'
              ELSE '0::bigint' END || ' AS total_bytes, ' ||
         'min(o.created_at) AS earliest_object_created_at, ' ||
         'max(o.created_at) AS latest_object_created_at ' ||
         'FROM storage.buckets b LEFT JOIN storage.objects o ON o.bucket_id = b.id ' ||
         'GROUP BY b.name ORDER BY b.name';
  FOR r IN EXECUTE sql
  LOOP
    RAISE NOTICE 'bucket_name=% object_count=% total_bytes=% earliest=% latest=%',
      r.bucket_name, r.object_count, r.total_bytes,
      r.earliest_object_created_at, r.latest_object_created_at;
  END LOOP;
END
$hasad_storage_objects$;

\echo '==== 04d. STORAGE TABLE COUNTS (counts only) ===='
DO $hasad_storage_counts$
DECLARE
  rel text;
  cnt bigint;
  rels text[] := ARRAY['storage.objects','storage.s3_multipart_uploads',
                       'storage.buckets_analytics','storage.vector_indexes'];
BEGIN
  FOREACH rel IN ARRAY rels LOOP
    IF to_regclass(rel) IS NULL THEN
      RAISE NOTICE '% NOT_PRESENT', rel;
    ELSE
      EXECUTE format('SELECT count(*) FROM %s', rel) INTO cnt;
      RAISE NOTICE '% rows=%', rel, cnt;
    END IF;
  END LOOP;
END
$hasad_storage_counts$;

-- ---------------------------------------------------------------------
-- 05. Edge Functions - names and deployment metadata ONLY. No source.
-- ---------------------------------------------------------------------
\echo '==== 05. SUPABASE_FUNCTIONS COLUMN INVENTORY ===='
DO $hasad_functions_cols$
DECLARE
  r record;
BEGIN
  IF to_regclass('supabase_functions.functions') IS NULL THEN
    RAISE NOTICE 'supabase_functions.functions NOT_PRESENT (no Edge Functions provisioned)';
    RETURN;
  END IF;
  FOR r IN SELECT column_name, data_type FROM information_schema.columns
           WHERE table_schema='supabase_functions' AND table_name='functions'
           ORDER BY ordinal_position
  LOOP
    RAISE NOTICE 'supabase_functions.functions column % (%)', r.column_name, r.data_type;
  END LOOP;
END
$hasad_functions_cols$;

\echo '==== 05b. EDGE FUNCTIONS (names + versions; no code) ===='
DO $hasad_functions$
DECLARE
  r record;
  has_slug boolean; has_name boolean; has_version boolean; has_status boolean;
  has_created boolean; has_entrypoint boolean; has_jwt boolean;
  sql text;
BEGIN
  IF to_regclass('supabase_functions.functions') IS NULL THEN
    RAISE NOTICE 'supabase_functions.functions NOT_PRESENT (no Edge Functions provisioned)';
    RETURN;
  END IF;
  SELECT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='supabase_functions' AND table_name='functions' AND column_name='slug') INTO has_slug;
  SELECT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='supabase_functions' AND table_name='functions' AND column_name='name') INTO has_name;
  SELECT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='supabase_functions' AND table_name='functions' AND column_name='version') INTO has_version;
  SELECT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='supabase_functions' AND table_name='functions' AND column_name='status') INTO has_status;
  SELECT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='supabase_functions' AND table_name='functions' AND column_name='created_at') INTO has_created;
  SELECT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='supabase_functions' AND table_name='functions' AND column_name='entrypoint_path') INTO has_entrypoint;
  SELECT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='supabase_functions' AND table_name='functions' AND column_name='verify_jwt') INTO has_jwt;

  sql := 'SELECT ' ||
         CASE WHEN has_slug THEN 'slug' ELSE 'NULL::text' END || ' AS function_slug, ' ||
         CASE WHEN has_name THEN 'name' ELSE 'NULL::text' END || ' AS function_name, ' ||
         CASE WHEN has_version THEN 'version::text' ELSE 'NULL::text' END || ' AS deployed_version, ' ||
         CASE WHEN has_status THEN 'status' ELSE 'NULL::text' END || ' AS status, ' ||
         CASE WHEN has_created THEN 'created_at' ELSE 'NULL::timestamptz' END || ' AS created_at, ' ||
         CASE WHEN has_entrypoint THEN 'entrypoint_path' ELSE 'NULL::text' END || ' AS entrypoint_path, ' ||
         CASE WHEN has_jwt THEN 'verify_jwt' ELSE 'NULL::boolean' END || ' AS verify_jwt ' ||
         'FROM supabase_functions.functions ' ||
         CASE WHEN has_slug THEN 'ORDER BY slug' ELSE '' END;
  FOR r IN EXECUTE sql
  LOOP
    RAISE NOTICE 'slug=% name=% version=% status=% created=% entrypoint=% verify_jwt=%',
      r.function_slug, r.function_name, r.deployed_version, r.status,
      r.created_at, r.entrypoint_path, r.verify_jwt;
  END LOOP;
END
$hasad_functions$;

\echo '==== 05c. SUPABASE_FUNCTIONS HOOKS (metadata only; no headers/secrets) ===='
DO $hasad_functions_hooks$
DECLARE
  r record;
  sql text;
BEGIN
  IF to_regclass('supabase_functions.hooks') IS NULL THEN
    RAISE NOTICE 'supabase_functions.hooks NOT_PRESENT';
    RETURN;
  END IF;
  FOR r IN SELECT column_name, data_type FROM information_schema.columns
           WHERE table_schema='supabase_functions' AND table_name='hooks'
           ORDER BY ordinal_position
  LOOP
    RAISE NOTICE 'supabase_functions.hooks column % (%)', r.column_name, r.data_type;
  END LOOP;

  sql := 'SELECT ' ||
         CASE WHEN EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='supabase_functions' AND table_name='hooks' AND column_name='hook_table_id')
              THEN 'hook_table_id::text' ELSE 'NULL::text' END || ' AS hook_table_id, ' ||
         CASE WHEN EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='supabase_functions' AND table_name='hooks' AND column_name='hook_name')
              THEN 'hook_name' ELSE 'NULL::text' END || ' AS hook_name, ' ||
         CASE WHEN EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='supabase_functions' AND table_name='hooks' AND column_name='created_at')
              THEN 'created_at' ELSE 'NULL::timestamptz' END || ' AS created_at ' ||
         'FROM supabase_functions.hooks';
  FOR r IN EXECUTE sql
  LOOP
    RAISE NOTICE 'hook_table=% hook_name=% created=%', r.hook_table_id, r.hook_name, r.created_at;
  END LOOP;
END
$hasad_functions_hooks$;

-- ---------------------------------------------------------------------
-- 06. Cron jobs - identifiers and schedule metadata ONLY. Payloads are
--     redacted because they can embed secrets/URLs.
-- ---------------------------------------------------------------------
\echo '==== 06. CRON JOB COLUMN INVENTORY ===='
DO $hasad_cron_cols$
DECLARE
  r record;
BEGIN
  IF to_regclass('cron.job') IS NULL THEN
    RAISE NOTICE 'cron.job NOT_PRESENT';
    RETURN;
  END IF;
  FOR r IN SELECT column_name, data_type FROM information_schema.columns
           WHERE table_schema='cron' AND table_name='job'
           ORDER BY ordinal_position
  LOOP
    RAISE NOTICE 'cron.job column % (%)', r.column_name, r.data_type;
  END LOOP;
END
$hasad_cron_cols$;

\echo '==== 06b. CRON JOBS (metadata only; command redacted) ===='
DO $hasad_cron$
DECLARE
  r record;
  sql text;
BEGIN
  IF to_regclass('cron.job') IS NULL THEN
    RAISE NOTICE 'cron.job NOT_PRESENT';
    RETURN;
  END IF;
  sql := 'SELECT ' ||
         CASE WHEN EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='cron' AND table_name='job' AND column_name='jobid') THEN 'jobid::text' ELSE 'NULL::text' END || ' AS jobid, ' ||
         CASE WHEN EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='cron' AND table_name='job' AND column_name='jobname') THEN 'jobname' ELSE 'NULL::text' END || ' AS jobname, ' ||
         CASE WHEN EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='cron' AND table_name='job' AND column_name='schedule') THEN 'schedule' ELSE 'NULL::text' END || ' AS schedule, ' ||
         CASE WHEN EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='cron' AND table_name='job' AND column_name='active') THEN 'active' ELSE 'NULL::boolean' END || ' AS active, ' ||
         CASE WHEN EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='cron' AND table_name='job' AND column_name='database') THEN 'database' ELSE 'NULL::text' END || ' AS target_database, ' ||
         CASE WHEN EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='cron' AND table_name='job' AND column_name='username') THEN 'username' ELSE 'NULL::text' END || ' AS run_as_role, ' ||
         CASE WHEN EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='cron' AND table_name='job' AND column_name='nodename') THEN 'nodename' ELSE 'NULL::text' END || ' AS nodename, ' ||
         CASE WHEN EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='cron' AND table_name='job' AND column_name='nodeport') THEN 'nodeport::text' ELSE 'NULL::text' END || ' AS nodeport ' ||
         'FROM cron.job ' ||
         CASE WHEN EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='cron' AND table_name='job' AND column_name='jobid') THEN 'ORDER BY jobid' ELSE '' END;
  FOR r IN EXECUTE sql
  LOOP
    RAISE NOTICE 'jobid=% jobname=% schedule=% active=% db=% run_as=% nodename=% nodeport=% command=<redacted>',
      r.jobid, r.jobname, r.schedule, r.active, r.target_database,
      r.run_as_role, r.nodename, r.nodeport;
  END LOOP;
END
$hasad_cron$;

\echo '==== 06c. CRON COUNTS ===='
DO $hasad_cron_counts$
DECLARE
  rel text;
  cnt bigint;
  rels text[] := ARRAY['cron.job','cron.job_run_details'];
BEGIN
  FOREACH rel IN ARRAY rels LOOP
    IF to_regclass(rel) IS NULL THEN
      RAISE NOTICE '% NOT_PRESENT', rel;
    ELSE
      EXECUTE format('SELECT count(*) FROM %s', rel) INTO cnt;
      RAISE NOTICE '% rows=%', rel, cnt;
    END IF;
  END LOOP;
  IF to_regclass('cron.job') IS NOT NULL THEN
    SELECT count(*) INTO cnt FROM cron.job WHERE active;
    RAISE NOTICE 'cron.job active=%', cnt;
  END IF;
END
$hasad_cron_counts$;

-- ---------------------------------------------------------------------
-- 07. pg_net - outbound HTTP integration metadata ONLY. Bodies/headers
--     (which carry auth tokens) are never selected.
-- ---------------------------------------------------------------------
\echo '==== 07. PG_NET COUNTS (no headers/body) ===='
DO $hasad_pgnet_counts$
DECLARE
  rel text;
  cnt bigint;
  rels text[] := ARRAY['net.http_request_queue','net._http_response'];
BEGIN
  FOREACH rel IN ARRAY rels LOOP
    IF to_regclass(rel) IS NULL THEN
      RAISE NOTICE '% NOT_PRESENT', rel;
    ELSE
      EXECUTE format('SELECT count(*) FROM %s', rel) INTO cnt;
      RAISE NOTICE '% rows=%', rel, cnt;
    END IF;
  END LOOP;
END
$hasad_pgnet_counts$;

\echo '==== 07b. PG_NET COLUMN INVENTORY ===='
DO $hasad_pgnet_cols$
DECLARE
  r record;
BEGIN
  IF to_regclass('net._http_response') IS NULL THEN
    RAISE NOTICE 'net._http_response NOT_PRESENT';
    RETURN;
  END IF;
  FOR r IN SELECT column_name, data_type FROM information_schema.columns
           WHERE table_schema='net' AND table_name='_http_response'
           ORDER BY ordinal_position
  LOOP
    RAISE NOTICE 'net._http_response column % (%)', r.column_name, r.data_type;
  END LOOP;
END
$hasad_pgnet_cols$;

\echo '==== 07c. PG_NET RESPONSE TARGETS (host only, path/query redacted) ===='
DO $hasad_pgnet_targets$
DECLARE
  r record;
  sql text;
BEGIN
  IF to_regclass('net._http_response') IS NULL THEN
    RAISE NOTICE 'net._http_response NOT_PRESENT';
    RETURN;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                  WHERE table_schema='net' AND table_name='_http_response' AND column_name='uri')
     OR NOT EXISTS (SELECT 1 FROM information_schema.columns
                  WHERE table_schema='net' AND table_name='_http_response' AND column_name='created') THEN
    RAISE NOTICE 'net._http_response required columns NOT_PRESENT (skipped)';
    RETURN;
  END IF;
  -- Only the origin is derived; the request/response bodies and headers
  -- (which can carry Authorization tokens) are never selected.
  sql := 'SELECT regexp_replace(uri, ''^(https?://[^/]+).*'', ''\1/<redacted>'') AS target_origin_redacted, ' ||
         'count(*) AS responses, min(created) AS first_seen, max(created) AS last_seen ' ||
         'FROM net._http_response GROUP BY 1 ORDER BY count(*) DESC';
  FOR r IN EXECUTE sql
  LOOP
    RAISE NOTICE 'target_origin=% responses=% first_seen=% last_seen=%',
      r.target_origin_redacted, r.responses, r.first_seen, r.last_seen;
  END LOOP;
END
$hasad_pgnet_targets$;

-- ---------------------------------------------------------------------
-- 08. Secrets - NAMES only, never values.
-- ---------------------------------------------------------------------
\echo '==== 08. VAULT SECRET COLUMN INVENTORY ===='
DO $hasad_vault_cols$
DECLARE
  r record;
BEGIN
  IF to_regclass('vault.secrets') IS NULL THEN
    RAISE NOTICE 'vault.secrets NOT_PRESENT';
    RETURN;
  END IF;
  FOR r IN SELECT column_name, data_type FROM information_schema.columns
           WHERE table_schema='vault' AND table_name='secrets'
           ORDER BY ordinal_position
  LOOP
    RAISE NOTICE 'vault.secrets column % (%)', r.column_name, r.data_type;
  END LOOP;
END
$hasad_vault_cols$;

\echo '==== 08b. VAULT SECRETS (names only; values never selected) ===='
DO $hasad_vault$
DECLARE
  r record;
  cnt bigint;
  sql text;
BEGIN
  IF to_regclass('vault.secrets') IS NULL THEN
    RAISE NOTICE 'vault.secrets NOT_PRESENT';
    RETURN;
  END IF;
  SELECT count(*) INTO cnt FROM vault.secrets;
  RAISE NOTICE 'vault_secret_count=%', cnt;

  -- Only non-value metadata columns are projected. The encrypted secret and
  -- any decrypted view are never touched.
  sql := 'SELECT ' ||
         CASE WHEN EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='vault' AND table_name='secrets' AND column_name='id') THEN 'id::text' ELSE 'NULL::text' END || ' AS vault_secret_id, ' ||
         CASE WHEN EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='vault' AND table_name='secrets' AND column_name='name') THEN 'name' ELSE 'NULL::text' END || ' AS secret_name, ' ||
         CASE WHEN EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='vault' AND table_name='secrets' AND column_name='description') THEN 'description' ELSE 'NULL::text' END || ' AS description, ' ||
         CASE WHEN EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='vault' AND table_name='secrets' AND column_name='created_at') THEN 'created_at' ELSE 'NULL::timestamptz' END || ' AS created_at ' ||
         'FROM vault.secrets ' ||
         CASE WHEN EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='vault' AND table_name='secrets' AND column_name='created_at') THEN 'ORDER BY created_at' ELSE '' END;
  FOR r IN EXECUTE sql
  LOOP
    RAISE NOTICE 'vault_secret_id=% secret_name=% description=% created=%',
      r.vault_secret_id, r.secret_name, r.description, r.created_at;
  END LOOP;
END
$hasad_vault$;

-- ---------------------------------------------------------------------
-- 09. Database webhooks / triggers that POST outbound (metadata only)
--     Uses only pg_catalog, always present.
-- ---------------------------------------------------------------------
\echo '==== 09. DATABASE WEBHOOKS (http_request triggers) ===='
SELECT n.nspname AS schema_name, c.relname AS table_name,
       t.tgname AS trigger_name, t.tgenabled AS enabled_state,
       pg_get_triggerdef(t.oid, true) AS trigger_definition
FROM pg_trigger t
JOIN pg_class c ON c.oid = t.tgrelid
JOIN pg_namespace n ON n.oid = c.relnamespace
JOIN pg_proc p ON p.oid = t.tgfoid
WHERE NOT t.tgisinternal AND p.proname = 'http_request'
ORDER BY n.nspname, c.relname, t.tgname;

-- ---------------------------------------------------------------------
-- 10. Legacy linkage indicators (COUNT comparisons only, no identifiers)
-- ---------------------------------------------------------------------
\echo '==== 10. LEGACY LINKAGE INDICATORS ===='
DO $hasad_linkage$
DECLARE
  v_auth bigint; v_pub_users bigint; v_pub_ut bigint; v_pub_tenants bigint;
  v_nonnull bigint; v_match bigint;
BEGIN
  IF to_regclass('auth.users') IS NULL THEN
    RAISE NOTICE 'auth.users NOT_PRESENT';
  ELSE
    SELECT count(*) INTO v_auth FROM auth.users;
    RAISE NOTICE 'auth.users total=%', v_auth;
  END IF;

  IF to_regclass('public.users') IS NOT NULL THEN
    SELECT count(*) INTO v_pub_users FROM public.users;
    RAISE NOTICE 'public.users rows=%', v_pub_users;
    IF EXISTS (SELECT 1 FROM information_schema.columns
                WHERE table_schema='public' AND table_name='users'
                  AND column_name='auth_user_id') THEN
      SELECT count(*) INTO v_nonnull FROM public.users WHERE auth_user_id IS NOT NULL;
      RAISE NOTICE 'public.users non-null auth_user_id=%', v_nonnull;
      IF to_regclass('auth.users') IS NOT NULL THEN
        SELECT count(*) INTO v_match FROM public.users u
          JOIN auth.users a ON a.id = u.auth_user_id;
        RAISE NOTICE 'public.users matching an auth user id=%', v_match;
      END IF;
    ELSE
      RAISE NOTICE 'public.users.auth_user_id column NOT_PRESENT';
    END IF;
  ELSE
    RAISE NOTICE 'public.users NOT_PRESENT';
  END IF;

  IF to_regclass('public.user_tenants') IS NOT NULL THEN
    SELECT count(*) INTO v_pub_ut FROM public.user_tenants;
    RAISE NOTICE 'public.user_tenants rows=%', v_pub_ut;
  ELSE
    RAISE NOTICE 'public.user_tenants NOT_PRESENT';
  END IF;

  IF to_regclass('public.tenants') IS NOT NULL THEN
    SELECT count(*) INTO v_pub_tenants FROM public.tenants;
    RAISE NOTICE 'public.tenants rows=%', v_pub_tenants;
  ELSE
    RAISE NOTICE 'public.tenants NOT_PRESENT';
  END IF;
END
$hasad_linkage$;

-- ---------------------------------------------------------------------
-- 11. FK linkage: public -> platform schemas (dependency facts).
--     Uses only pg_catalog, always present.
-- ---------------------------------------------------------------------
\echo '==== 11. PUBLIC -> PLATFORM FOREIGN KEYS ===='
SELECT con.conname AS constraint_name,
       src_ns.nspname AS source_schema, src.relname AS source_table,
       tgt_ns.nspname AS target_schema, tgt.relname AS target_table,
       pg_get_constraintdef(con.oid) AS definition
FROM pg_constraint con
JOIN pg_class src ON src.oid = con.conrelid
JOIN pg_namespace src_ns ON src_ns.oid = src.relnamespace
JOIN pg_class tgt ON tgt.oid = con.confrelid
JOIN pg_namespace tgt_ns ON tgt_ns.oid = tgt.relnamespace
WHERE con.contype = 'f'
  AND src_ns.nspname = 'public'
  AND tgt_ns.nspname <> 'public'
ORDER BY src_ns.nspname, src.relname, con.conname;

-- ---------------------------------------------------------------------
-- 12. Auth-managed object counts that must be preserved.
--     Uses only pg_catalog, always present.
-- ---------------------------------------------------------------------
\echo '==== 12. PLATFORM OBJECT COUNTS PRESERVED ===='
SELECT n.nspname AS schema_name, c.relkind AS kind, count(*) AS objects
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname IN ('auth','storage','realtime','supabase_functions','net','cron','vault')
GROUP BY n.nspname, c.relkind
ORDER BY n.nspname, c.relkind;

-- ---------------------------------------------------------------------
-- 13. Extension-owned objects in public (must be preserved, not legacy)
-- ---------------------------------------------------------------------
\echo '==== 13. EXTENSION-OWNED OBJECTS IN PUBLIC (preserve) ===='
SELECT e.extname AS extension_name,
       n.nspname AS schema_name,
       count(*) AS owned_objects
FROM pg_depend d
JOIN pg_extension e ON e.oid = d.refobjid
JOIN pg_class c ON c.oid = d.objid
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE d.deptype = 'e' AND c.relkind IN ('r','v','m','S','p')
GROUP BY e.extname, n.nspname
ORDER BY e.extname, n.nspname;

\echo '==== END OF PLATFORM INVENTORY ===='

ROLLBACK;

\echo 'ROLLBACK COMPLETE - NO DATABASE STATE WAS CHANGED'
