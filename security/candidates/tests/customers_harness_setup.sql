-- Local-only disposable PostgreSQL fixture for the corrected Unit S1 candidate.
-- Not deployed. Mirrors the Supabase-managed `auth` surface only as far as the
-- candidate's non-auth-dependent path needs it.
CREATE ROLE authenticated NOLOGIN;
CREATE ROLE anon NOLOGIN;

CREATE SCHEMA auth;
CREATE TABLE auth.users (id uuid PRIMARY KEY);
CREATE FUNCTION auth.uid() RETURNS uuid
LANGUAGE sql
STABLE
AS $$
  SELECT nullif(
    pg_catalog.current_setting('request.jwt.claims', true)::jsonb->>'sub', ''
  )::uuid
$$;

GRANT USAGE ON SCHEMA auth TO authenticated, anon;
GRANT EXECUTE ON FUNCTION auth.uid() TO PUBLIC;
