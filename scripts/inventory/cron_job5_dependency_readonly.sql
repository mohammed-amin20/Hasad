-- =====================================================================
-- Hasad ERP V2 - Read-only diagnostic: cron job 5 dependency inspection
-- =====================================================================
-- Target: Supabase DEV project sxasnunzspkuwbxiddqd
-- Purpose: Inspect cron.job for jobid=5 only. Do NOT print raw command.
-- Safety: metadata-only classification, BEGIN TRANSACTION READ ONLY / ROLLBACK,
--         ON_ERROR_STOP=1, fail-closed read-only guard, no secrets/URLs/payloads.
-- =====================================================================

\set ON_ERROR_STOP on

SET default_transaction_read_only = on;
SET statement_timeout = '60s';
SET idle_in_transaction_session_timeout = '120s';

BEGIN TRANSACTION READ ONLY;

-- Fail-closed read-only guard
DO $hasad_cron_diag_guard$
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
$hasad_cron_diag_guard$;

\echo '==== CRON JOB 5 DIAGNOSTIC (metadata-only, no raw command) ===='

DO $hasad_cron_job5$
DECLARE
  r record;
  cmd_lc text;
  has_send_pub boolean := false;
  has_send_unq boolean := false;
  has_other_legacy boolean := false;
  has_http boolean := false;
  has_net boolean := false;
  has_perform boolean := false;
  has_exec boolean := false;
  has_dynamic boolean := false;
  has_other boolean := false;
BEGIN
  IF to_regclass('cron.job') IS NULL THEN
    RAISE NOTICE 'job_exists=false';
    RAISE NOTICE 'verdict=UNRESOLVED';
    RAISE NOTICE 'note=cron.job NOT_PRESENT';
    RETURN;
  END IF;

  SELECT jobid::text AS jobid, jobname, schedule, active, 
         lower(coalesce(command::text,'')) AS cmd_lc
  INTO r
  FROM cron.job
  WHERE jobid = 5
  LIMIT 1;

  IF NOT FOUND THEN
    RAISE NOTICE 'job_exists=false';
    RAISE NOTICE 'verdict=UNRESOLVED';
    RAISE NOTICE 'note=no row for jobid=5';
    RETURN;
  END IF;

  RAISE NOTICE 'job_exists=true';
  RAISE NOTICE 'jobid=%', r.jobid;
  RAISE NOTICE 'jobname=%', r.jobname;
  RAISE NOTICE 'schedule=%', r.schedule;
  RAISE NOTICE 'active=%', r.active;

  cmd_lc := r.cmd_lc;

  -- Safe pattern checks (no raw command output)
  has_send_pub := (cmd_lc LIKE '%public.send_due_reminders%');
  has_send_unq := (cmd_lc LIKE '%send_due_reminders%') AND (NOT has_send_pub);
  has_http := (cmd_lc LIKE '%http%' OR cmd_lc LIKE '%curl%' OR cmd_lc LIKE '%wget%');
  has_net  := (cmd_lc LIKE '%net.http%' OR cmd_lc LIKE '%pg_net%');
  has_perform := (cmd_lc LIKE '%perform %');
  has_exec    := (cmd_lc LIKE '%execute %');
  has_dynamic := (cmd_lc LIKE '%dynamic%' OR cmd_lc LIKE '%format(%' OR cmd_lc LIKE '%quote_%');
  has_other_legacy := (cmd_lc LIKE '%send_reminder_now%' OR cmd_lc LIKE '%_fire_reminder%' OR cmd_lc LIKE '%create_sale_invoice%' OR cmd_lc LIKE '%create_purchase_invoice%' OR cmd_lc LIKE '%record_payment%');

  RAISE NOTICE 'refs_public_send_due_reminders=%', has_send_pub;
  RAISE NOTICE 'refs_send_due_reminders_unqualified=%', has_send_unq;
  RAISE NOTICE 'refs_other_identified_legacy=%', has_other_legacy;
  RAISE NOTICE 'uses_http=%', has_http;
  RAISE NOTICE 'uses_pg_net=%', has_net;
  RAISE NOTICE 'uses_perform=%', has_perform;
  RAISE NOTICE 'uses_execute=%', has_exec;
  RAISE NOTICE 'uses_dynamic_execution=%', has_dynamic;

  -- Verdict
  IF has_send_pub THEN
    RAISE NOTICE 'dependency_verdict=CONFIRMED';
    RAISE NOTICE 'dependency_target=public.send_due_reminders (legacy SECURITY DEFINER)';
    RAISE NOTICE 'removal_order=remove_or_disable_jobid_5_BEFORE_dependent_legacy_functions_or_tables';
  ELSIF has_send_unq THEN
    RAISE NOTICE 'dependency_verdict=CONFIRMED';
    RAISE NOTICE 'dependency_target=send_due_reminders (unqualified; likely public)';
    RAISE NOTICE 'removal_order=remove_or_disable_jobid_5_BEFORE_dependent_legacy_functions_or_tables';
  ELSIF has_other_legacy THEN
    RAISE NOTICE 'dependency_verdict=CONFIRMED';
    RAISE NOTICE 'dependency_target=other_identified_legacy_routine';
    RAISE NOTICE 'removal_order=remove_or_disable_jobid_5_BEFORE_dependent_legacy_functions_or_tables';
  ELSIF has_http OR has_net THEN
    RAISE NOTICE 'dependency_verdict=UNRESOLVED';
    RAISE NOTICE 'note=appears_http_or_pg_net_based; cannot confirm legacy_function_linkage_from_metadata';
    RAISE NOTICE 'removal_order=treat_as_dependency_until_confirmed_otherwise';
  ELSIF has_dynamic OR has_perform OR has_exec THEN
    RAISE NOTICE 'dependency_verdict=UNRESOLVED';
    RAISE NOTICE 'note=dynamic/EXECUTE/PERFORM usage; text_match_insufficient';
    RAISE NOTICE 'removal_order=treat_as_dependency_until_confirmed_otherwise';
  ELSE
    RAISE NOTICE 'dependency_verdict=NOT_CONFIRMED';
    RAISE NOTICE 'note=no_explicit_reference_to_identified_legacy_routines_found_in_command_text';
    RAISE NOTICE 'removal_order=still_verify_no_indirect_dependencies';
  END IF;
END
$hasad_cron_job5$;

ROLLBACK;
\echo 'ROLLBACK COMPLETE - NO DATABASE STATE WAS CHANGED'
