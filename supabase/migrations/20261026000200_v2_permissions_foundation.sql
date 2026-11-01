-- Hasad ERP V2 permission foundation
-- Target: Supabase DEV sxasnunzspkuwbxiddqd (prepared only; not deployed)
-- Depends on: 20261026000000_v2_foundation_schemas.sql,
--             20261026000100_v2_identity_tenancy_foundation.sql
-- Scope: exactly three private, default-deny tables. No seed rows, grants,
-- policies, functions, triggers, RPCs, PostgREST exposure, or managed-schema
-- changes are included.
--
-- Deployment requires explicit owner approval of
-- docs/16_DATABASE_DECISION_PACKAGE.md section 11. The catalogue seed is a
-- separate migration (20261026000210) and is not part of this structure.
--
-- Table shape source: docs/05_DATABASE_SCHEMA.md lines 38-40 and
-- docs/features/02_roles_and_permissions.md section D. The override effect
-- values are the documented allow/deny pair. No unapproved column is added.
--
-- Deletion policy: every reference uses ON DELETE RESTRICT because no
-- application hard-delete lifecycle is approved. This deliberately does not
-- implement the illustrative "cascade with unassigned role" note in
-- docs/05_DATABASE_SCHEMA.md; the deviation is recorded in section 11.2.

BEGIN;

CREATE TABLE hasad.permissions (
  code text PRIMARY KEY,
  module text NOT NULL,
  description text NOT NULL,
  CONSTRAINT permissions_module_prefix_check
    CHECK (module = split_part(code, '.', 1))
);

CREATE TABLE hasad.role_permissions (
  role_id uuid NOT NULL
    REFERENCES hasad.roles(id) ON DELETE RESTRICT,
  permission_code text NOT NULL
    REFERENCES hasad.permissions(code) ON DELETE RESTRICT,
  CONSTRAINT role_permissions_pkey
    PRIMARY KEY (role_id, permission_code)
);

CREATE TABLE hasad.user_permission_overrides (
  membership_id uuid NOT NULL
    REFERENCES hasad.company_memberships(id) ON DELETE RESTRICT,
  permission_code text NOT NULL
    REFERENCES hasad.permissions(code) ON DELETE RESTRICT,
  effect text NOT NULL,
  CONSTRAINT user_permission_overrides_pkey
    PRIMARY KEY (membership_id, permission_code),
  CONSTRAINT user_permission_overrides_effect_check
    CHECK (effect IN ('allow', 'deny'))
);

CREATE INDEX role_permissions_permission_code_idx
  ON hasad.role_permissions (permission_code);

CREATE INDEX user_permission_overrides_permission_code_idx
  ON hasad.user_permission_overrides (permission_code);

ALTER TABLE hasad.permissions ENABLE ROW LEVEL SECURITY;
ALTER TABLE hasad.permissions FORCE ROW LEVEL SECURITY;
ALTER TABLE hasad.role_permissions ENABLE ROW LEVEL SECURITY;
ALTER TABLE hasad.role_permissions FORCE ROW LEVEL SECURITY;
ALTER TABLE hasad.user_permission_overrides ENABLE ROW LEVEL SECURITY;
ALTER TABLE hasad.user_permission_overrides FORCE ROW LEVEL SECURITY;

COMMIT;
