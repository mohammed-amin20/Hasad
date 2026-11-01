-- Disposable PostgreSQL 17 harness only. Run as bootstrap postgres, then run
-- candidates as migration_executor: a non-superuser CREATEROLE login role.
-- Its BYPASSRLS attribute mirrors DEV's observed non-superuser postgres role;
-- hasad_rpc_owner itself is never granted BYPASSRLS.
CREATE ROLE authenticated NOLOGIN;
CREATE ROLE anon NOLOGIN;
CREATE ROLE service_role NOLOGIN BYPASSRLS;
CREATE ROLE executor_existing_role NOLOGIN;
CREATE ROLE migration_executor NOLOGIN NOINHERIT NOSUPERUSER NOCREATEDB CREATEROLE BYPASSRLS;
CREATE ROLE migration_login LOGIN NOINHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE NOBYPASSRLS;
GRANT migration_executor TO migration_login WITH INHERIT FALSE, SET TRUE;
GRANT executor_existing_role TO migration_executor WITH INHERIT FALSE, SET TRUE;

CREATE SCHEMA auth;
CREATE SCHEMA hasad;
CREATE SCHEMA hasad_api;
CREATE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql STABLE AS
  $$ SELECT NULLIF(current_setting('request.jwt.claim.sub', true), '')::uuid $$;

CREATE TABLE hasad.user_profiles(id uuid PRIMARY KEY, display_name text);
CREATE TABLE hasad.companies(id uuid PRIMARY KEY, created_by uuid NOT NULL,
  status text NOT NULL CHECK(status IN ('active','suspended')));
CREATE TABLE hasad.roles(id uuid PRIMARY KEY, company_id uuid NOT NULL,
  code text NOT NULL, is_system boolean NOT NULL DEFAULT false,
  UNIQUE(company_id,id), UNIQUE(company_id,code));
CREATE TABLE hasad.company_memberships(id uuid PRIMARY KEY, company_id uuid NOT NULL,
  user_id uuid NOT NULL UNIQUE, role_id uuid, is_owner boolean NOT NULL DEFAULT false,
  status text NOT NULL CHECK(status IN ('active','suspended','revoked')),
  revoked_at timestamptz,
  UNIQUE(company_id,user_id),
  CHECK(role_id IS NOT NULL OR is_owner),
  CHECK((status='revoked')=(revoked_at IS NOT NULL)));
CREATE TABLE hasad.company_settings(company_id uuid PRIMARY KEY, name_ar text NOT NULL,
  name_en text, display_name text);
CREATE TABLE hasad.permissions(code text PRIMARY KEY, module text NOT NULL,
  description text NOT NULL, CHECK(module=split_part(code,'.',1)));
CREATE TABLE hasad.role_permissions(role_id uuid NOT NULL, permission_code text NOT NULL,
  PRIMARY KEY(role_id,permission_code));
CREATE TABLE hasad.user_permission_overrides(membership_id uuid NOT NULL,
  permission_code text NOT NULL, effect text NOT NULL CHECK(effect IN ('allow','deny')),
  PRIMARY KEY(membership_id,permission_code));
CREATE TABLE hasad.products(id uuid PRIMARY KEY, company_id uuid NOT NULL,
  code text NOT NULL, name_ar text NOT NULL, name_en text, barcode text,
  category_id uuid, base_uom_id uuid NOT NULL,
  track_inventory boolean NOT NULL DEFAULT true, is_active boolean NOT NULL DEFAULT true);

DO $$ DECLARE t text; BEGIN
  FOREACH t IN ARRAY ARRAY['user_profiles','companies','roles','company_memberships',
    'company_settings','permissions','role_permissions','user_permission_overrides','products'] LOOP
    EXECUTE format('ALTER TABLE hasad.%I ENABLE ROW LEVEL SECURITY',t);
    EXECUTE format('ALTER TABLE hasad.%I FORCE ROW LEVEL SECURITY',t);
  END LOOP;
END $$;

ALTER SCHEMA auth OWNER TO migration_executor;
ALTER SCHEMA hasad OWNER TO migration_executor;
ALTER SCHEMA hasad_api OWNER TO migration_executor;
ALTER FUNCTION auth.uid() OWNER TO migration_executor;
ALTER TABLE hasad.user_profiles OWNER TO migration_executor;
ALTER TABLE hasad.companies OWNER TO migration_executor;
ALTER TABLE hasad.roles OWNER TO migration_executor;
ALTER TABLE hasad.company_memberships OWNER TO migration_executor;
ALTER TABLE hasad.company_settings OWNER TO migration_executor;
ALTER TABLE hasad.permissions OWNER TO migration_executor;
ALTER TABLE hasad.role_permissions OWNER TO migration_executor;
ALTER TABLE hasad.user_permission_overrides OWNER TO migration_executor;
ALTER TABLE hasad.products OWNER TO migration_executor;
