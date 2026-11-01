-- Disposable PostgreSQL 17 harness only. Never run against DEV.
CREATE SCHEMA auth;
CREATE TABLE auth.users(
  id uuid PRIMARY KEY,
  email_confirmed_at timestamptz NULL,
  banned_until timestamptz NULL
);
CREATE SCHEMA hasad;
CREATE TABLE hasad.user_profiles(
  id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE RESTRICT,
  display_name text NULL,
  last_permission_check_at timestamptz NULL DEFAULT NULL
);
CREATE TABLE hasad.companies(
  id uuid PRIMARY KEY,
  created_by uuid NOT NULL REFERENCES hasad.user_profiles(id) ON DELETE RESTRICT,
  status text NOT NULL DEFAULT 'active' CHECK(status IN ('active','suspended'))
);
CREATE TABLE hasad.company_settings(
  company_id uuid PRIMARY KEY REFERENCES hasad.companies(id) ON DELETE RESTRICT,
  name_ar text NOT NULL,
  name_en text NULL,
  display_name text NULL,
  currency text NOT NULL DEFAULT 'ILS',
  vat_enabled boolean NOT NULL DEFAULT false,
  preferences jsonb NOT NULL DEFAULT '{}'::jsonb,
  updated_at timestamptz NOT NULL DEFAULT now(),
  updated_by uuid NULL REFERENCES hasad.user_profiles(id) ON DELETE RESTRICT,
  CHECK(currency='ILS'), CHECK(jsonb_typeof(preferences)='object')
);
CREATE TABLE hasad.roles(
  id uuid PRIMARY KEY,
  company_id uuid NOT NULL REFERENCES hasad.companies(id) ON DELETE RESTRICT,
  code text NOT NULL,
  is_system boolean NOT NULL DEFAULT false,
  UNIQUE(company_id,code), UNIQUE(company_id,id)
);
CREATE TABLE hasad.company_memberships(
  id uuid PRIMARY KEY,
  company_id uuid NOT NULL REFERENCES hasad.companies(id) ON DELETE RESTRICT,
  user_id uuid NOT NULL UNIQUE REFERENCES hasad.user_profiles(id) ON DELETE RESTRICT,
  role_id uuid NULL,
  is_owner boolean NOT NULL DEFAULT false,
  status text NOT NULL,
  invited_by uuid NULL REFERENCES hasad.user_profiles(id) ON DELETE RESTRICT,
  revoked_at timestamptz NULL,
  UNIQUE(company_id,user_id),
  FOREIGN KEY(company_id,role_id) REFERENCES hasad.roles(company_id,id) ON DELETE RESTRICT,
  CHECK(role_id IS NOT NULL OR is_owner),
  CHECK(status IN ('active','suspended','revoked')),
  CHECK((status='revoked')=(revoked_at IS NOT NULL))
);
CREATE TABLE hasad.permissions(code text PRIMARY KEY, module text NOT NULL, description text NOT NULL);
CREATE TABLE hasad.role_permissions(
  role_id uuid NOT NULL REFERENCES hasad.roles(id) ON DELETE RESTRICT,
  permission_code text NOT NULL REFERENCES hasad.permissions(code) ON DELETE RESTRICT,
  PRIMARY KEY(role_id,permission_code)
);
CREATE TABLE hasad.user_permission_overrides(
  membership_id uuid NOT NULL REFERENCES hasad.company_memberships(id) ON DELETE RESTRICT,
  permission_code text NOT NULL REFERENCES hasad.permissions(code) ON DELETE RESTRICT,
  effect text NOT NULL CHECK(effect IN ('allow','deny')),
  PRIMARY KEY(membership_id,permission_code)
);
CREATE TABLE hasad.audit_log(
  id uuid PRIMARY KEY,
  company_id uuid NOT NULL REFERENCES hasad.companies(id) ON DELETE RESTRICT,
  actor_user_id uuid NOT NULL REFERENCES hasad.user_profiles(id) ON DELETE RESTRICT,
  action text NOT NULL CHECK(BTRIM(action)<>''),
  entity_type text NOT NULL CHECK(BTRIM(entity_type)<>''),
  entity_id uuid NULL,
  details jsonb NOT NULL DEFAULT '{}'::jsonb CHECK(jsonb_typeof(details)='object'),
  request_id uuid NULL,
  occurred_at timestamptz NOT NULL DEFAULT now()
);
DO $$ DECLARE t text; BEGIN
  FOREACH t IN ARRAY ARRAY['user_profiles','companies','company_settings','roles',
    'company_memberships','permissions','role_permissions','user_permission_overrides','audit_log'] LOOP
    EXECUTE format('ALTER TABLE hasad.%I ENABLE ROW LEVEL SECURITY',t);
    EXECUTE format('ALTER TABLE hasad.%I FORCE ROW LEVEL SECURITY',t);
  END LOOP;
END $$;
INSERT INTO auth.users(id,email_confirmed_at) VALUES
  ('00000000-0000-0000-0000-000000000001', now()),
  ('00000000-0000-0000-0000-000000000002', now());
