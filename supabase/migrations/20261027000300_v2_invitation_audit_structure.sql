-- Hasad ERP V2 invitation and audit structural foundation
-- Target: Supabase DEV sxasnunzspkuwbxiddqd (prepared only; not deployed)
-- Depends on: 20261026000000_v2_foundation_schemas.sql,
--             20261026000100_v2_identity_tenancy_foundation.sql,
--             20261026000200_v2_permissions_foundation.sql, and
--             20261026000210_v2_permission_catalogue_seed.sql.
--
-- Scope: exactly two private, default-deny structural tables. No rows, grants,
-- policies, functions, triggers, RPCs, PostgREST exposure, Auth changes, or
-- Storage changes are included.
--
-- Contract source: docs/16_DATABASE_DECISION_PACKAGE.md §11.5.1 and §11.5.3.
-- This file is prepared for review only. Deployment requires a separate owner
-- approval of its exact structural contract. It deliberately excludes token
-- generation, invitation acceptance, audit writing, expiry processing, company
-- creation, membership mutation, and last-owner enforcement because those are
-- application-facing or trigger/function behavior gated by the hosted PoC.

BEGIN;

CREATE TABLE hasad.company_invitations (
  id uuid PRIMARY KEY,
  company_id uuid NOT NULL
    REFERENCES hasad.companies(id) ON DELETE RESTRICT,
  role_id uuid NOT NULL,
  email text NOT NULL,
  token_hash bytea NOT NULL,
  status text NOT NULL DEFAULT 'pending',
  expires_at timestamptz NOT NULL,
  invited_by uuid NOT NULL
    REFERENCES hasad.user_profiles(id) ON DELETE RESTRICT,
  created_at timestamptz NOT NULL DEFAULT now(),
  accepted_by uuid NULL
    REFERENCES hasad.user_profiles(id) ON DELETE RESTRICT,
  accepted_at timestamptz NULL,
  revoked_by uuid NULL
    REFERENCES hasad.user_profiles(id) ON DELETE RESTRICT,
  revoked_at timestamptz NULL,
  expired_at timestamptz NULL,
  CONSTRAINT company_invitations_company_role_fkey
    FOREIGN KEY (company_id, role_id)
    REFERENCES hasad.roles(company_id, id) ON DELETE RESTRICT,
  CONSTRAINT company_invitations_email_normalized_check
    CHECK (email = LOWER(BTRIM(email)) AND email <> ''),
  CONSTRAINT company_invitations_token_hash_length_check
    CHECK (octet_length(token_hash) = 32),
  CONSTRAINT company_invitations_status_check
    CHECK (status IN ('pending', 'accepted', 'revoked', 'expired')),
  CONSTRAINT company_invitations_expires_after_create_check
    CHECK (expires_at > created_at),
  CONSTRAINT company_invitations_terminal_stamp_check
    CHECK (
      (status = 'pending'
       AND accepted_by IS NULL AND accepted_at IS NULL
       AND revoked_by IS NULL AND revoked_at IS NULL AND expired_at IS NULL)
      OR (status = 'accepted'
          AND accepted_by IS NOT NULL AND accepted_at IS NOT NULL
          AND revoked_by IS NULL AND revoked_at IS NULL AND expired_at IS NULL)
      OR (status = 'revoked'
          AND accepted_by IS NULL AND accepted_at IS NULL
          AND revoked_by IS NOT NULL AND revoked_at IS NOT NULL AND expired_at IS NULL)
      OR (status = 'expired'
          AND accepted_by IS NULL AND accepted_at IS NULL
          AND revoked_by IS NULL AND revoked_at IS NULL AND expired_at IS NOT NULL)
    )
);

CREATE UNIQUE INDEX company_invitations_token_hash_key
  ON hasad.company_invitations (token_hash);

CREATE UNIQUE INDEX company_invitations_pending_email_key
  ON hasad.company_invitations ((LOWER(BTRIM(email))))
  WHERE status = 'pending';

CREATE INDEX company_invitations_company_status_expiry_idx
  ON hasad.company_invitations (company_id, status, expires_at);

CREATE TABLE hasad.audit_log (
  id uuid PRIMARY KEY,
  company_id uuid NOT NULL
    REFERENCES hasad.companies(id) ON DELETE RESTRICT,
  actor_user_id uuid NOT NULL
    REFERENCES hasad.user_profiles(id) ON DELETE RESTRICT,
  action text NOT NULL,
  entity_type text NOT NULL,
  entity_id uuid NULL,
  details jsonb NOT NULL DEFAULT '{}'::jsonb,
  request_id uuid NULL,
  occurred_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT audit_log_action_nonempty_check CHECK (BTRIM(action) <> ''),
  CONSTRAINT audit_log_entity_type_nonempty_check CHECK (BTRIM(entity_type) <> ''),
  CONSTRAINT audit_log_details_object_check CHECK (jsonb_typeof(details) = 'object')
);

CREATE INDEX audit_log_company_time_idx
  ON hasad.audit_log (company_id, occurred_at DESC, id);

CREATE INDEX audit_log_entity_idx
  ON hasad.audit_log (entity_type, entity_id)
  WHERE entity_id IS NOT NULL;

ALTER TABLE hasad.company_invitations ENABLE ROW LEVEL SECURITY;
ALTER TABLE hasad.company_invitations FORCE ROW LEVEL SECURITY;
ALTER TABLE hasad.audit_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE hasad.audit_log FORCE ROW LEVEL SECURITY;

COMMIT;
