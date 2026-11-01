-- TEST ONLY: minimal local dependency for the V2 baseline migrations.
-- Apply only to the disposable local PostgreSQL databases used by the
-- Phase 8 validation runner. Never place this file in supabase/migrations.
-- This fixture is not Supabase Auth and provides no identity/security model.
-- No user identities, credentials, passwords, tokens, or seed rows are added.

\set ON_ERROR_STOP on

CREATE SCHEMA auth;
CREATE TABLE auth.users (
  id uuid PRIMARY KEY
);
