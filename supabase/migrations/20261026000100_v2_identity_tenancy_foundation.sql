-- Hasad ERP V2 identity and tenancy foundation
-- Target: Supabase DEV sxasnunzspkuwbxiddqd
-- Depends on: 20261026000000_v2_foundation_schemas.sql
-- Scope: exactly four private, default-deny tables. No seed data, grants,
-- policies, functions, triggers, RPCs, PostgREST exposure, or managed-schema
-- changes are included.

BEGIN;

CREATE TABLE hasad.user_profiles (
  id uuid PRIMARY KEY
    REFERENCES auth.users(id) ON DELETE RESTRICT,
  display_name text NULL,
  last_permission_check_at timestamptz NULL DEFAULT NULL
);

CREATE TABLE hasad.companies (
  id uuid PRIMARY KEY,
  created_by uuid NOT NULL
    REFERENCES hasad.user_profiles(id) ON DELETE RESTRICT,
  status text NOT NULL DEFAULT 'active',
  CONSTRAINT companies_status_check
    CHECK (status IN ('active', 'suspended'))
);

CREATE TABLE hasad.roles (
  id uuid PRIMARY KEY,
  company_id uuid NOT NULL
    REFERENCES hasad.companies(id) ON DELETE RESTRICT,
  code text NOT NULL,
  is_system boolean NOT NULL DEFAULT false,
  CONSTRAINT roles_company_code_key UNIQUE (company_id, code),
  CONSTRAINT roles_company_id_id_key UNIQUE (company_id, id)
);

CREATE TABLE hasad.company_memberships (
  id uuid PRIMARY KEY,
  company_id uuid NOT NULL
    REFERENCES hasad.companies(id) ON DELETE RESTRICT,
  user_id uuid NOT NULL
    REFERENCES hasad.user_profiles(id) ON DELETE RESTRICT,
  role_id uuid NULL,
  is_owner boolean NOT NULL DEFAULT false,
  status text NOT NULL,
  invited_by uuid NULL
    REFERENCES hasad.user_profiles(id) ON DELETE RESTRICT,
  revoked_at timestamptz NULL,
  CONSTRAINT company_memberships_user_key UNIQUE (user_id),
  CONSTRAINT company_memberships_company_user_key UNIQUE (company_id, user_id),
  CONSTRAINT company_memberships_company_role_fkey
    FOREIGN KEY (company_id, role_id)
    REFERENCES hasad.roles(company_id, id) ON DELETE RESTRICT,
  CONSTRAINT company_memberships_role_required_for_non_owner_check
    CHECK (role_id IS NOT NULL OR is_owner),
  CONSTRAINT company_memberships_status_check
    CHECK (status IN ('active', 'suspended', 'revoked')),
  CONSTRAINT company_memberships_revoked_at_check
    CHECK ((status = 'revoked') = (revoked_at IS NOT NULL))
);

CREATE INDEX company_memberships_active_company_idx
  ON hasad.company_memberships (company_id)
  WHERE status = 'active';

ALTER TABLE hasad.user_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE hasad.user_profiles FORCE ROW LEVEL SECURITY;
ALTER TABLE hasad.companies ENABLE ROW LEVEL SECURITY;
ALTER TABLE hasad.companies FORCE ROW LEVEL SECURITY;
ALTER TABLE hasad.roles ENABLE ROW LEVEL SECURITY;
ALTER TABLE hasad.roles FORCE ROW LEVEL SECURITY;
ALTER TABLE hasad.company_memberships ENABLE ROW LEVEL SECURITY;
ALTER TABLE hasad.company_memberships FORCE ROW LEVEL SECURITY;

COMMIT;
