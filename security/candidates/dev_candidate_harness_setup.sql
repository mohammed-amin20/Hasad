-- Disposable local harness only. Shape follows applied V2 migrations used by
-- dev_company_product_access_candidate.sql; no DEV connection is used.
CREATE ROLE authenticated NOLOGIN;
CREATE ROLE anon NOLOGIN;
CREATE ROLE service_role NOLOGIN BYPASSRLS;
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
CREATE FUNCTION hasad_api.invoker_probe() RETURNS bigint LANGUAGE sql SECURITY INVOKER
  SET search_path=pg_catalog AS $$ SELECT count(*) FROM hasad.companies $$;
GRANT USAGE ON SCHEMA hasad_api TO authenticated;
GRANT EXECUTE ON FUNCTION hasad_api.invoker_probe() TO authenticated;
