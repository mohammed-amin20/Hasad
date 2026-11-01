-- Local-only auth stand-in for additional disposable databases in one cluster.
-- Cluster roles are created once by customers_harness_setup.sql in the first DB.
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
