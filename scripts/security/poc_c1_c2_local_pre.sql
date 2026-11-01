-- Hasad ERP V2 C1/C2 local disposable PoC — pre-migration stub
-- Target: disposable local PostgreSQL database only. Never run on DEV.
--
-- This file supplies only the Supabase-managed primitives the deployed V2
-- migrations expect: anon/authenticated roles and auth.users/auth.uid().
-- It is not a V2 migration and must never be applied to DEV or production.

\set ON_ERROR_STOP on

DO $roles$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
    EXECUTE 'CREATE ROLE anon NOLOGIN NOINHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE NOBYPASSRLS';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN
    EXECUTE 'CREATE ROLE authenticated NOLOGIN NOINHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE NOBYPASSRLS';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'hasad_poc_owner') THEN
    EXECUTE 'CREATE ROLE hasad_poc_owner NOLOGIN NOINHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE NOBYPASSRLS';
  END IF;
END
$roles$;

CREATE SCHEMA IF NOT EXISTS auth;

CREATE TABLE IF NOT EXISTS auth.users (
  id uuid PRIMARY KEY,
  email text NOT NULL,
  email_confirmed_at timestamptz NULL
);

CREATE OR REPLACE FUNCTION auth.jwt()
RETURNS jsonb
LANGUAGE sql
STABLE
AS $fn$
  SELECT CASE
    WHEN current_setting('request.jwt.claims', true) IS NULL THEN '{}'::jsonb
    WHEN current_setting('request.jwt.claims', true) = '' THEN '{}'::jsonb
    ELSE current_setting('request.jwt.claims', true)::jsonb
  END;
$fn$;

CREATE OR REPLACE FUNCTION auth.uid()
RETURNS uuid
LANGUAGE sql
STABLE
AS $fn$
  SELECT NULLIF(auth.jwt() ->> 'sub', '')::uuid;
$fn$;

GRANT USAGE ON SCHEMA auth TO anon, authenticated, hasad_poc_owner;
GRANT EXECUTE ON FUNCTION auth.jwt() TO anon, authenticated, hasad_poc_owner;
GRANT EXECUTE ON FUNCTION auth.uid() TO anon, authenticated, hasad_poc_owner;
REVOKE CREATE ON SCHEMA auth FROM PUBLIC;
