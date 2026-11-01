-- =====================================================================
-- Hasad ERP V2 - DEV CLEANUP SCRIPT 01: Cron Job Removal (FIXED v3)
-- =====================================================================
-- Target: Supabase DEV project sxasnunzspkuwbxiddqd
-- Status: REQUIRES EXPLICIT AUTHORIZATION
-- Purpose: Remove/suspend cron job 5 BEFORE dependent legacy functions
-- Safety: Strict identity assertions, dependency-aware ordering, project-bound auth
-- =====================================================================

\set ON_ERROR_STOP on

-- Map psql variables to session GUCs (psql -v vars are not auto-GUCs)
SELECT set_config('cleanup.authorized', COALESCE(NULLIF(:'cleanup_authorized',''), 'false'), false);
SELECT set_config('cleanup.project_ref', COALESCE(NULLIF(:'cleanup_project',''), ''), false);
SELECT set_config('cleanup.mode', COALESCE(NULLIF(:'cleanup_mode',''), 'DRY_RUN'), false);

-- Authorization gate (top level, fail-closed)
DO $cleanup_authz$
BEGIN
  IF current_setting('cleanup.authorized', true) IS DISTINCT FROM 'true' THEN
    RAISE EXCEPTION 'AUTHORIZATION REQUIRED: cleanup.authorized not set to true';
  END IF;
  IF current_setting('cleanup.project_ref', true) IS DISTINCT FROM 'sxasnunzspkuwbxiddqd' THEN
    RAISE EXCEPTION 'PROJECT MISMATCH: cleanup.project_ref must be sxasnunzspkuwbxiddqd';
  END IF;
  IF current_setting('cleanup.mode', true) NOT IN ('DRY_RUN', 'EXECUTE') THEN
    RAISE EXCEPTION 'INVALID MODE: cleanup.mode must be DRY_RUN or EXECUTE';
  END IF;
END
$cleanup_authz$;

BEGIN;

-- Fail-closed: verify cron schema and job identity
DO $cron_verify$
DECLARE
  v_jobid bigint;
  v_jobname text;
  v_schedule text;
  v_active boolean;
  v_count int;
BEGIN
  IF to_regnamespace('cron') IS NULL THEN
    RAISE EXCEPTION 'CRON SCHEMA MISSING - unexpected state';
  END IF;
  
  SELECT COUNT(*) INTO v_count FROM cron.job WHERE jobid = 5;
  IF v_count = 0 THEN
    RAISE EXCEPTION 'JOB 5 NOT FOUND: expected jobid=5 (send-due-reminders-daily, schedule 0 9 * * *, active) to exist before removal';
  END IF;
  IF v_count > 1 THEN
    RAISE EXCEPTION 'MULTIPLE JOBS WITH jobid=5 - unexpected';
  END IF;
  
  SELECT jobid, jobname, schedule, active 
  INTO v_jobid, v_jobname, v_schedule, v_active
  FROM cron.job 
  WHERE jobid = 5;
  
  -- Strict identity assertions (HARD ERRORS)
  IF v_jobid IS DISTINCT FROM 5 THEN
    RAISE EXCEPTION 'JOB ID MISMATCH: expected jobid=5, got %', v_jobid;
  END IF;
  IF v_jobname IS DISTINCT FROM 'send-due-reminders-daily' THEN
    RAISE EXCEPTION 'JOB NAME MISMATCH: expected send-due-reminders-daily, got %', v_jobname;
  END IF;
  IF v_schedule IS DISTINCT FROM '0 9 * * *' THEN
    RAISE EXCEPTION 'SCHEDULE MISMATCH: expected 0 9 * * *, got %', v_schedule;
  END IF;
  IF v_active IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'ACTIVE STATE MISMATCH: expected active=true, got %', v_active;
  END IF;
  
  RAISE NOTICE 'Job 5 verified: jobid=%, name=%, schedule=%, active=%', v_jobid, v_jobname, v_schedule, v_active;
  RAISE NOTICE 'DEPENDENCY: Must remove/suspend BEFORE legacy functions (potential link to send_due_reminders)';
END
$cron_verify$;

-- DRY_RUN/EXECUTE gating (valid psql: boolean from SQL)
SELECT (current_setting('cleanup.mode', true) = 'EXECUTE') AS exec_flag_bool \gset

\if :exec_flag_bool
  -- EXECUTE path only: unschedule after all checks passed
  DO $unschedule$
  BEGIN
    IF current_setting('cleanup.mode', true) = 'EXECUTE' AND current_setting('cleanup.authorized', true) = 'true' THEN
      IF EXISTS (SELECT 1 FROM cron.job WHERE jobid = 5) THEN
        PERFORM cron.unschedule(5);
        RAISE NOTICE 'cron.unschedule(5) executed';
      ELSE
        RAISE EXCEPTION 'Job 5 not found at unschedule time despite prior verification';
      END IF;
    ELSE
      RAISE EXCEPTION 'UNSCHEDULE GUARD: not in EXECUTE+authorized mode';
    END IF;
  END
  $unschedule$;

  -- Verify removal (EXECUTE only)
  DO $cron_verify_after$
  DECLARE
    v_count int;
  BEGIN
    IF current_setting('cleanup.mode', true) = 'EXECUTE' AND current_setting('cleanup.authorized', true) = 'true' THEN
      SELECT COUNT(*) INTO v_count FROM cron.job WHERE jobid = 5;
      IF v_count != 0 THEN
        RAISE EXCEPTION 'POST-UNSCHEDULE VERIFICATION FAILED: job 5 still exists';
      END IF;
      RAISE NOTICE 'Cron job 5 unscheduled successfully - VERIFIED REMOVED';
    ELSE
      RAISE EXCEPTION 'VERIFICATION GUARD: not in EXECUTE+authorized mode';
    END IF;
  END
  $cron_verify_after$;

  COMMIT;
  SELECT 'SCRIPT 01 COMPLETED (EXECUTE)' AS status;
\else
  -- DRY_RUN: identity checks only, never call cron.unschedule(5)
  ROLLBACK;
  SELECT 'SCRIPT 01 COMPLETED (DRY_RUN - ROLLED BACK, NO UNSCHEDULE)' AS status;
\endif
