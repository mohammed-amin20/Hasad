-- =====================================================================
-- Hasad ERP V2 - Supabase DEV login probe (read-only, minimal)
-- =====================================================================
-- Companion to scripts/inventory/test_dev_login.ps1
--
-- Purpose:
--   Prove, with the minimum possible surface, whether a successful
--   PostgreSQL login is possible against the DEV pooler. It answers
--   exactly one question: "did authentication succeed and which role /
--   database did we land on?"
--
-- Safety contract:
--   * ONE statement only: SELECT current_user, current_database() plus
--     session metadata. No business data, no catalog dump, no user
--     records, no secrets, no application rows.
--   * One explicit BEGIN TRANSACTION READ ONLY / ROLLBACK pair wraps the
--     statement. Nothing before BEGIN except session-local SETs.
--   * Fail-closed server-side guard: if the transaction is not genuinely
--     read-only, a plpgsql RAISE EXCEPTION aborts the run (psql stops
--     immediately via ON_ERROR_STOP).
--   * The probe is rolled back; it changes nothing on the server.
--   * psql meta-commands used: only \set and \echo.
-- =====================================================================

\set ON_ERROR_STOP on

-- Session-local defaults only (no database state is touched).
SET default_transaction_read_only = on;
SET statement_timeout = '30s';
SET idle_in_transaction_session_timeout = '60s';

BEGIN TRANSACTION READ ONLY;

-- ---------------------------------------------------------------------
-- Fail-closed read-only guard.
-- ---------------------------------------------------------------------
DO $hasad_login_probe_guard$
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
$hasad_login_probe_guard$;

-- ---------------------------------------------------------------------
-- The only statement executed by this diagnostic.
-- ---------------------------------------------------------------------
\echo '==== LOGIN PROBE ===='
SELECT current_user AS connected_role,
       current_database() AS connected_database,
       current_setting('transaction_read_only') AS transaction_read_only,
       current_setting('default_transaction_read_only') AS default_transaction_read_only,
       clock_timestamp() AS probe_at;

ROLLBACK;

\echo 'ROLLBACK COMPLETE - NO DATABASE STATE WAS CHANGED'
