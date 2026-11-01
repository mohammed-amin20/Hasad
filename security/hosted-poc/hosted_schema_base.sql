-- Test-project-only base schema. The runner appends the review-only RPC candidate,
-- exact authenticated grants, and PostgREST exposure setting into an isolated migration.
BEGIN;
DO $$ BEGIN
  IF to_regprocedure('auth.uid()') IS NULL THEN
    RAISE EXCEPTION 'REAL_SUPABASE_AUTH_UID_REQUIRED';
  END IF;
END $$;

CREATE SCHEMA hasad;
CREATE TABLE hasad.user_profiles (
  id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE RESTRICT,
  display_name text NULL
);
CREATE TABLE hasad.companies (
  id uuid PRIMARY KEY,
  created_by uuid NOT NULL REFERENCES hasad.user_profiles(id) ON DELETE RESTRICT,
  status text NOT NULL CHECK (status IN ('active','suspended'))
);
CREATE TABLE hasad.roles (
  id uuid PRIMARY KEY,
  company_id uuid NOT NULL REFERENCES hasad.companies(id) ON DELETE RESTRICT,
  code text NOT NULL,
  UNIQUE(company_id,id),
  UNIQUE(company_id,code)
);
CREATE TABLE hasad.company_memberships (
  id uuid PRIMARY KEY,
  company_id uuid NOT NULL REFERENCES hasad.companies(id) ON DELETE RESTRICT,
  user_id uuid NOT NULL UNIQUE REFERENCES hasad.user_profiles(id) ON DELETE RESTRICT,
  role_id uuid NULL,
  is_owner boolean NOT NULL DEFAULT false,
  status text NOT NULL CHECK (status IN ('active','suspended','revoked')),
  revoked_at timestamptz NULL,
  UNIQUE(company_id,user_id),
  FOREIGN KEY(company_id,role_id) REFERENCES hasad.roles(company_id,id) ON DELETE RESTRICT,
  CHECK(role_id IS NOT NULL OR is_owner),
  CHECK((status='revoked')=(revoked_at IS NOT NULL))
);
CREATE TABLE hasad.company_settings (
  company_id uuid PRIMARY KEY REFERENCES hasad.companies(id) ON DELETE RESTRICT,
  name_ar text NOT NULL,
  name_en text NULL,
  display_name text NULL
);
CREATE TABLE hasad.permissions (
  code text PRIMARY KEY,
  module text NOT NULL CHECK(module=split_part(code,'.',1)),
  description text NOT NULL
);
CREATE TABLE hasad.role_permissions (
  role_id uuid NOT NULL REFERENCES hasad.roles(id) ON DELETE RESTRICT,
  permission_code text NOT NULL REFERENCES hasad.permissions(code) ON DELETE RESTRICT,
  PRIMARY KEY(role_id,permission_code)
);
CREATE TABLE hasad.user_permission_overrides (
  membership_id uuid NOT NULL REFERENCES hasad.company_memberships(id) ON DELETE RESTRICT,
  permission_code text NOT NULL REFERENCES hasad.permissions(code) ON DELETE RESTRICT,
  effect text NOT NULL CHECK(effect IN ('allow','deny')),
  PRIMARY KEY(membership_id,permission_code)
);
CREATE TABLE hasad.product_categories (
  id uuid PRIMARY KEY,
  company_id uuid NOT NULL REFERENCES hasad.companies(id) ON DELETE RESTRICT,
  code text NOT NULL,
  name_ar text NOT NULL,
  UNIQUE(company_id,id),
  UNIQUE(company_id,code)
);
CREATE TABLE hasad.units_of_measure (
  id uuid PRIMARY KEY,
  company_id uuid NOT NULL REFERENCES hasad.companies(id) ON DELETE RESTRICT,
  code text NOT NULL,
  name_ar text NOT NULL,
  UNIQUE(company_id,id),
  UNIQUE(company_id,code)
);
CREATE TABLE hasad.products (
  id uuid PRIMARY KEY,
  company_id uuid NOT NULL REFERENCES hasad.companies(id) ON DELETE RESTRICT,
  code text NOT NULL,
  name_ar text NOT NULL,
  name_en text NULL,
  barcode text NULL,
  category_id uuid NULL,
  base_uom_id uuid NOT NULL,
  track_inventory boolean NOT NULL DEFAULT true,
  is_active boolean NOT NULL DEFAULT true,
  UNIQUE(company_id,id),
  UNIQUE(company_id,code),
  FOREIGN KEY(company_id,category_id) REFERENCES hasad.product_categories(company_id,id) ON DELETE RESTRICT,
  FOREIGN KEY(company_id,base_uom_id) REFERENCES hasad.units_of_measure(company_id,id) ON DELETE RESTRICT
);

DO $$ DECLARE t text; BEGIN
 FOREACH t IN ARRAY ARRAY['user_profiles','companies','roles','company_memberships',
  'company_settings','permissions','role_permissions','user_permission_overrides',
  'product_categories','units_of_measure','products'] LOOP
  EXECUTE format('ALTER TABLE hasad.%I ENABLE ROW LEVEL SECURITY',t);
  EXECUTE format('ALTER TABLE hasad.%I FORCE ROW LEVEL SECURITY',t);
 END LOOP;
END $$;
