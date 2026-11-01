-- REVIEW ONLY / NOT DEPLOYED / DEV ONLY.
-- Unit S1 (corrected): authenticated direct Data API customer INSERT/UPDATE in
-- exposed schema `hasad`, with mandatory same-transaction audit.
--
-- WHY THIS VERSION EXISTS
--   The previous candidate (security/candidates/dev_direct_data_api_customers_candidate.sql,
--   SHA-256 4C2A7D35...) executed auth.uid() inside SECURITY DEFINER functions
--   owned by hasad_rpc_owner and required that owner to hold USAGE on schema
--   `auth`. Hosted DEV evidence established that hasad_rpc_owner has no `auth`
--   USAGE, the executing role cannot grant it, and the executor cannot alter or
--   replace the existing restricted-owner RPCs. That candidate was therefore
--   not installable and must never be deployed.
--
--   This candidate removes hasad_rpc_owner from the design completely. It adds
--   no dependency on schema `auth` for any SECURITY DEFINER function and does
--   not touch whoami / products_list / the RPC ownership model.
--
-- SECURITY DESIGN
--   * One dedicated owner role `hasad_party_writer`, created by the deploying
--     executor inside this transaction:
--       NOLOGIN / NOINHERIT / NOSUPERUSER / NOCREATEDB / NOCREATEROLE /
--       NOREPLICATION / NOBYPASSRLS.
--     Because the executor is the creator, it holds ADMIN OPTION on the new
--     role and can transfer function ownership without any membership in a
--     pre-existing restricted role. This is the same mechanism already used for
--     hasad_inventory_poster.
--   * The actor identity is parsed from the PostgREST request JWT claim GUCs
--     (`request.jwt.claims`, legacy `request.jwt.claim.sub`) by a small
--     SECURITY INVOKER helper that uses only pg_catalog. It is never a function
--     argument and never `auth.uid()` under a non-`authenticated` owner, so the
--     writer role needs no privileges on schema `auth`.
--   * Clients write `hasad.parties` directly through the Data API. RLS enforces
--     live active membership, active company, and `parties.manage` with owner
--     precedence and deny-override for non-owners.
--   * The audit trigger is SECURITY DEFINER owned by the same locked writer
--     role and writes `hasad.audit_log` in the same transaction as the row
--     change, so a write and its audit rows commit or roll back together.
--   * FORCE RLS stays enabled on every table; no table is altered and no policy
--     is dropped.
--   * The writer role receives only the columns it must read (authorization) or
--     insert (audit). It never receives INSERT/UPDATE on `parties`.
--   * `id` and `company_id` are excluded from the client UPDATE column grant, so
--     they are immutable through the Data API.
--
-- AUDIT CONTRACT
--   Only the approved event names from docs/features/05_customers_and_suppliers.md
--   (C8) are emitted: party.created, party.updated, party.classified,
--   party.deactivated. No new event type is introduced. `entity_type` = 'party'
--   and the row-local `details` shape remain PROPOSED pending the action/payload
--   registry decision (docs/16_DATABASE_DECISION_PACKAGE.md); they carry only
--   values already present on the audited row.
--
-- INSTALL FEASIBILITY (hosted DEV)
--   Requires: CREATE ROLE (rolsuper or rolcreaterole), ownership of the eight
--   target tables, CREATE on schema `hasad`, and `parties.manage` seeded.
--   No requirement involves schema `auth`, hasad_rpc_owner, or any pre-existing
--   role the executor cannot administer. If CREATE ROLE / ADMIN OPTION is not
--   available, this script raises PREFLIGHT_* and rolls back. The documented
--   fallbacks (NOT applied automatically) are:
--     F1. Run the identical script once as a role that holds CREATEROLE
--         (platform owner / supabase_admin). Same SQL, no design change.
--     F2. Reuse an executor-controlled locked role that already exists (for
--         example hasad_inventory_poster). Rejected as a silent default: it
--         broadens an inventory-scoped role to party writes and needs explicit
--         owner sign-off.
--     F3. Grant `authenticated` INSERT on audit_log with a WITH CHECK policy.
--         Rejected: it removes the definer boundary and lets a client forge
--         audit rows, which requirement 6 forbids.
--   F1 is the smallest viable alternative; F2/F3 are not applied here.
--
-- PRECONDITION (separate, already-installed read surface)
--   `authenticated` must already hold column SELECT on
--   hasad.company_memberships(company_id,user_id,status) and
--   hasad.companies(id,status), as granted by the approved direct company/product
--   read candidate. The read policy below executes as `authenticated` and needs
--   those privileges; the preflight fails closed if they are missing.

BEGIN;

DO $preflight$
DECLARE
  v_missing text;
BEGIN
  -- 1. Required relations -----------------------------------------------------
  SELECT string_agg(w.table_name, ', ' ORDER BY w.table_name)
  INTO v_missing
  FROM (VALUES
    ('parties'), ('audit_log'), ('company_memberships'), ('companies'),
    ('roles'), ('permissions'), ('role_permissions'),
    ('user_permission_overrides')
  ) AS w(table_name)
  WHERE pg_catalog.to_regclass('hasad.' || w.table_name) IS NULL;
  IF v_missing IS NOT NULL THEN
    RAISE EXCEPTION 'PREFLIGHT_MISSING_TABLES: %', v_missing;
  END IF;

  -- 2. Payload contract (must match lib/customers/domain/customer.dart) -------
  IF EXISTS (
    SELECT 1
    FROM (VALUES
      ('parties','id','uuid'),
      ('parties','company_id','uuid'),
      ('parties','code','text'),
      ('parties','name_ar','text'),
      ('parties','name_en','text'),
      ('parties','party_type','text'),
      ('parties','is_customer','boolean'),
      ('parties','is_supplier','boolean'),
      ('parties','tax_id','text'),
      ('parties','phone','text'),
      ('parties','email','text'),
      ('parties','address','text'),
      ('parties','payment_terms_days','integer'),
      ('parties','is_active','boolean'),
      ('audit_log','id','uuid'),
      ('audit_log','company_id','uuid'),
      ('audit_log','actor_user_id','uuid'),
      ('audit_log','action','text'),
      ('audit_log','entity_type','text'),
      ('audit_log','entity_id','uuid'),
      ('audit_log','details','jsonb')
    ) AS expected(table_name, column_name, type_name)
    LEFT JOIN pg_catalog.pg_class c
      ON c.oid = pg_catalog.to_regclass('hasad.' || expected.table_name)
    LEFT JOIN pg_catalog.pg_attribute a
      ON a.attrelid = c.oid
     AND a.attname = expected.column_name
     AND a.attnum > 0
     AND NOT a.attisdropped
    WHERE a.attnum IS NULL
       OR pg_catalog.format_type(a.atttypid, a.atttypmod)
          IS DISTINCT FROM expected.type_name
  ) THEN
    RAISE EXCEPTION 'PREFLIGHT_PARTY_OR_AUDIT_SCHEMA_MISMATCH';
  END IF;

  -- 3. Constraints that the payload relies on --------------------------------
  IF EXISTS (
    SELECT 1
    FROM (VALUES
      ('parties','parties_pkey'),
      ('parties','parties_company_id_id_key'),
      ('parties','parties_company_code_key'),
      ('parties','parties_party_type_check'),
      ('parties','parties_payment_terms_days_check'),
      ('audit_log','audit_log_pkey'),
      ('audit_log','audit_log_action_nonempty_check'),
      ('audit_log','audit_log_entity_type_nonempty_check'),
      ('audit_log','audit_log_details_object_check')
    ) AS expected(table_name, constraint_name)
    LEFT JOIN pg_catalog.pg_class c
      ON c.oid = pg_catalog.to_regclass('hasad.' || expected.table_name)
    LEFT JOIN pg_catalog.pg_constraint con
      ON con.conrelid = c.oid
     AND con.conname = expected.constraint_name
     AND con.convalidated
    WHERE con.oid IS NULL
  ) THEN
    RAISE EXCEPTION 'PREFLIGHT_PARTY_OR_AUDIT_CONSTRAINT_MISSING';
  END IF;

  -- 4. FORCE RLS must already be on, and must stay on ------------------------
  IF EXISTS (
    SELECT 1
    FROM pg_catalog.pg_class c
    JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'hasad'
      AND c.relname IN (
        'parties', 'audit_log', 'company_memberships', 'companies',
        'roles', 'permissions', 'role_permissions',
        'user_permission_overrides'
      )
      AND (NOT c.relrowsecurity OR NOT c.relforcerowsecurity)
  ) THEN
    RAISE EXCEPTION 'PREFLIGHT_FORCE_RLS';
  END IF;

  -- 5. The executor must own every table it will add policies/triggers to ----
  IF EXISTS (
    SELECT 1
    FROM pg_catalog.pg_class c
    JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'hasad'
      AND c.relname IN (
        'parties', 'audit_log', 'company_memberships', 'companies',
        'roles', 'permissions', 'role_permissions',
        'user_permission_overrides'
      )
      AND pg_catalog.pg_get_userbyid(c.relowner) <> current_user
  ) THEN
    RAISE EXCEPTION 'PREFLIGHT_TABLE_OWNERSHIP';
  END IF;

  -- 6. Executor authority to create and administer the dedicated role --------
  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_roles
    WHERE rolname = current_user AND (rolsuper OR rolcreaterole)
  ) THEN
    RAISE EXCEPTION 'PREFLIGHT_NO_ROLE_ADMIN';
  END IF;
  IF NOT pg_catalog.has_schema_privilege(current_user, 'hasad', 'CREATE') THEN
    RAISE EXCEPTION 'PREFLIGHT_NO_SCHEMA_CREATE';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_roles WHERE rolname = 'authenticated')
     OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_roles WHERE rolname = 'anon') THEN
    RAISE EXCEPTION 'PREFLIGHT_CLIENT_ROLES_MISSING';
  END IF;

  -- 7. The candidate must not depend on hasad_rpc_owner at all ---------------
  --    Preserve only the verified, unrelated products-read policy exactly as
  --    installed. Any other legacy-owner policy on the affected tables blocks.
  IF EXISTS (
    SELECT 1
    FROM pg_catalog.pg_policy p
    WHERE p.polname LIKE 'hasad_rpc_owner%'
      AND p.polrelid IN (
        pg_catalog.to_regclass('hasad.parties'),
        pg_catalog.to_regclass('hasad.audit_log'),
        pg_catalog.to_regclass('hasad.permissions')
      )
      AND NOT (
        p.polname = 'hasad_rpc_owner_products_permission'
        AND p.polrelid = pg_catalog.to_regclass('hasad.permissions')
        AND p.polcmd = 'r'
        AND p.polroles = ARRAY[(
          SELECT oid FROM pg_catalog.pg_roles WHERE rolname = 'hasad_rpc_owner'
        )]::oid[]
        AND p.polwithcheck IS NULL
        AND pg_catalog.pg_get_expr(p.polqual, p.polrelid)
            = '(code = ''products.read''::text)'
      )
  ) THEN
    RAISE EXCEPTION 'PREFLIGHT_LEGACY_RPC_OWNER_POLICY_PRESENT';
  END IF;

  -- 8. Client write boundary as found before this script ---------------------
  IF pg_catalog.has_table_privilege(
       'authenticated', 'hasad.parties', 'INSERT,UPDATE,DELETE'
     ) OR pg_catalog.has_any_column_privilege(
       'authenticated', 'hasad.parties', 'INSERT,UPDATE'
     ) OR pg_catalog.has_table_privilege(
       'authenticated', 'hasad.audit_log', 'INSERT,UPDATE,DELETE'
     ) OR pg_catalog.has_any_column_privilege(
       'authenticated', 'hasad.audit_log', 'INSERT,UPDATE'
     ) THEN
    RAISE EXCEPTION 'PREFLIGHT_UNEXPECTED_CLIENT_WRITE';
  END IF;
  IF pg_catalog.has_schema_privilege('anon', 'hasad', 'USAGE')
     OR pg_catalog.has_table_privilege(
       'anon', 'hasad.parties', 'SELECT,INSERT,UPDATE,DELETE'
     )
     OR pg_catalog.has_table_privilege(
       'anon', 'hasad.audit_log', 'INSERT,UPDATE,DELETE'
     ) THEN
    RAISE EXCEPTION 'PREFLIGHT_ANON_ACCESS';
  END IF;

  -- 9. The read policy below runs as `authenticated`; it needs these columns --
  IF NOT pg_catalog.has_column_privilege(
           'authenticated', 'hasad.company_memberships', 'company_id', 'SELECT'
         )
     OR NOT pg_catalog.has_column_privilege(
           'authenticated', 'hasad.company_memberships', 'user_id', 'SELECT'
         )
     OR NOT pg_catalog.has_column_privilege(
           'authenticated', 'hasad.company_memberships', 'status', 'SELECT'
         )
     OR NOT pg_catalog.has_column_privilege(
           'authenticated', 'hasad.companies', 'id', 'SELECT'
         )
     OR NOT pg_catalog.has_column_privilege(
           'authenticated', 'hasad.companies', 'status', 'SELECT'
         ) THEN
    RAISE EXCEPTION 'PREFLIGHT_AUTHENTICATED_AUTHZ_READ_MISSING';
  END IF;

  -- 10. Authorization catalogue ---------------------------------------------
  IF NOT EXISTS (
    SELECT 1 FROM hasad.permissions
    WHERE code = 'parties.manage' AND module = 'parties'
  ) THEN
    RAISE EXCEPTION 'PREFLIGHT_PARTIES_MANAGE_MISSING';
  END IF;

  -- 11. Founding-owner identity integrity (boolean only; no IDs are emitted) --
  --     Every membership.user_id has an FK to user_profiles, so any user that
  --     can be authorized necessarily has a profile and the audit actor FK can
  --     never fail at runtime. This check additionally proves the company is
  --     not left without a servable owner.
  IF NOT EXISTS (
    SELECT 1
    FROM hasad.company_memberships cm
    JOIN hasad.user_profiles up ON up.id = cm.user_id
    WHERE cm.is_owner
      AND cm.status = 'active'
  ) THEN
    RAISE EXCEPTION 'PREFLIGHT_NO_ACTIVE_OWNER_PROFILE';
  END IF;

  -- 12. Name collisions ------------------------------------------------------
  IF EXISTS (
    SELECT 1
    FROM pg_catalog.pg_proc p
    JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'hasad'
      AND p.proname IN (
        'request_actor_user_id', 'party_manage_allowed', 'audit_party_change'
      )
  ) OR EXISTS (
    SELECT 1 FROM pg_catalog.pg_trigger t
    WHERE t.tgname = 'parties_audit_changes'
      AND NOT t.tgisinternal
  ) OR EXISTS (
    SELECT 1 FROM pg_catalog.pg_policy p
    WHERE p.polname IN (
      'direct_authenticated_parties_read',
      'direct_authenticated_parties_insert',
      'direct_authenticated_parties_update',
      'hasad_party_writer_memberships_read',
      'hasad_party_writer_companies_read',
      'hasad_party_writer_roles_read',
      'hasad_party_writer_permissions_read',
      'hasad_party_writer_role_permissions_read',
      'hasad_party_writer_overrides_read',
      'hasad_party_writer_audit_insert'
    )
  ) THEN
    RAISE EXCEPTION 'PREFLIGHT_NAME_COLLISION';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM pg_catalog.pg_policy p
    WHERE p.polrelid = pg_catalog.to_regclass('hasad.parties')
      AND (
        0 = ANY (p.polroles)
        OR (SELECT oid FROM pg_catalog.pg_roles
            WHERE rolname = 'authenticated') = ANY (p.polroles)
      )
  ) THEN
    RAISE EXCEPTION 'PREFLIGHT_EXISTING_PARTY_CLIENT_POLICY';
  END IF;
END
$preflight$;

-- Dedicated locked owner for customer writes and their audit rows only.
DO $rolesetup$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_roles WHERE rolname = 'hasad_party_writer'
  ) THEN
    CREATE ROLE hasad_party_writer
      NOLOGIN
      NOINHERIT
      NOSUPERUSER
      NOCREATEDB
      NOCREATEROLE
      NOREPLICATION
      NOBYPASSRLS;
  END IF;

  IF EXISTS (
    SELECT 1
    FROM pg_catalog.pg_roles
    WHERE rolname = 'hasad_party_writer'
      AND (
        rolcanlogin OR rolsuper OR rolcreatedb OR rolcreaterole
        OR rolreplication OR rolbypassrls
      )
  ) THEN
    RAISE EXCEPTION 'PREFLIGHT_WRITER_ROLE_UNSAFE';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM pg_catalog.pg_auth_members m
    JOIN pg_catalog.pg_roles granted ON granted.oid = m.roleid
    JOIN pg_catalog.pg_roles member ON member.oid = m.member
    WHERE granted.rolname = 'hasad_party_writer'
      AND member.rolname IN ('authenticated', 'anon')
  ) THEN
    RAISE EXCEPTION 'PREFLIGHT_WRITER_ROLE_GRANTED_TO_CLIENT';
  END IF;

  -- PostgreSQL 16+ distinguishes ADMIN OPTION from SET OPTION. ALTER ... OWNER
  -- TO requires SET privilege on the target role; CREATEROLE alone is not it.
  -- The role creator can administer its new role, but must grant SET OPTION.
  IF NOT pg_catalog.pg_has_role(current_user, 'hasad_party_writer', 'SET') THEN
    BEGIN
      EXECUTE pg_catalog.format(
        'GRANT hasad_party_writer TO %I WITH SET OPTION', current_user
      );
    EXCEPTION WHEN insufficient_privilege THEN
      RAISE EXCEPTION
        'PREFLIGHT_WRITER_ROLE_SET_NOT_GRANTABLE: executor lacks ADMIN OPTION to grant SET OPTION on hasad_party_writer';
    END;
  END IF;

  IF NOT pg_catalog.pg_has_role(current_user, 'hasad_party_writer', 'SET') THEN
    RAISE EXCEPTION
      'PREFLIGHT_WRITER_ROLE_SET_MISSING: executor cannot SET ROLE hasad_party_writer';
  END IF;
END
$rolesetup$;

GRANT USAGE ON SCHEMA hasad TO hasad_party_writer;
GRANT USAGE ON SCHEMA hasad TO authenticated;

-- Authorization reads for the writer role: narrow columns only.
GRANT SELECT (id, company_id, user_id, role_id, is_owner, status)
  ON hasad.company_memberships TO hasad_party_writer;
GRANT SELECT (id, status)
  ON hasad.companies TO hasad_party_writer;
GRANT SELECT (id, company_id)
  ON hasad.roles TO hasad_party_writer;
GRANT SELECT (code, module)
  ON hasad.permissions TO hasad_party_writer;
GRANT SELECT (role_id, permission_code)
  ON hasad.role_permissions TO hasad_party_writer;
GRANT SELECT (membership_id, permission_code, effect)
  ON hasad.user_permission_overrides TO hasad_party_writer;

-- Audit writes for the writer role only. `parties` gets no writer grant.
GRANT INSERT (id, company_id, actor_user_id, action, entity_type, entity_id, details)
  ON hasad.audit_log TO hasad_party_writer;

-- Actor identity from the request JWT claims GUCs. SECURITY INVOKER, no
-- dependency on schema `auth`, no client-supplied identity. Created before the
-- writer policies because they reference it.
CREATE OR REPLACE FUNCTION hasad.request_actor_user_id()
RETURNS uuid
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = pg_catalog, pg_temp
AS $fn$
DECLARE
  v_legacy text := NULLIF(
    pg_catalog.current_setting('request.jwt.claim.sub', true), ''
  );
  v_claims_text text := NULLIF(
    pg_catalog.current_setting('request.jwt.claims', true), ''
  );
  v_claims jsonb;
  v_json_sub text;
  v_candidate text;
BEGIN
  IF v_claims_text IS NOT NULL THEN
    BEGIN
      v_claims := v_claims_text::jsonb;
    EXCEPTION WHEN others THEN
      RAISE EXCEPTION 'UNAUTHORIZED' USING ERRCODE = '28000';
    END;

    IF pg_catalog.jsonb_typeof(v_claims) IS DISTINCT FROM 'object' THEN
      RAISE EXCEPTION 'UNAUTHORIZED' USING ERRCODE = '28000';
    END IF;

    IF v_claims ? 'sub' THEN
      IF pg_catalog.jsonb_typeof(v_claims -> 'sub') IS DISTINCT FROM 'string' THEN
        RAISE EXCEPTION 'UNAUTHORIZED' USING ERRCODE = '28000';
      END IF;
      v_json_sub := v_claims ->> 'sub';
    END IF;
  END IF;

  IF v_legacy IS NOT NULL
     AND v_json_sub IS NOT NULL
     AND v_legacy IS DISTINCT FROM v_json_sub THEN
    RAISE EXCEPTION 'UNAUTHORIZED' USING ERRCODE = '28000';
  END IF;

  v_candidate := COALESCE(v_legacy, v_json_sub);
  IF v_candidate IS NULL OR pg_catalog.btrim(v_candidate) = '' THEN
    RETURN NULL;
  END IF;

  IF v_candidate !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$' THEN
    RAISE EXCEPTION 'UNAUTHORIZED' USING ERRCODE = '28000';
  END IF;

  RETURN v_candidate::uuid;
END
$fn$;
REVOKE ALL ON FUNCTION hasad.request_actor_user_id()
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION hasad.request_actor_user_id()
  TO hasad_party_writer;

-- Permissive policies apply only to the locked, non-assumable writer role.
CREATE POLICY hasad_party_writer_memberships_read
  ON hasad.company_memberships
  FOR SELECT TO hasad_party_writer
  USING (user_id = hasad.request_actor_user_id());

CREATE POLICY hasad_party_writer_companies_read
  ON hasad.companies
  FOR SELECT TO hasad_party_writer
  USING (true);

CREATE POLICY hasad_party_writer_roles_read
  ON hasad.roles
  FOR SELECT TO hasad_party_writer
  USING (true);

CREATE POLICY hasad_party_writer_permissions_read
  ON hasad.permissions
  FOR SELECT TO hasad_party_writer
  USING (code = 'parties.manage' AND module = 'parties');

CREATE POLICY hasad_party_writer_role_permissions_read
  ON hasad.role_permissions
  FOR SELECT TO hasad_party_writer
  USING (permission_code = 'parties.manage');

CREATE POLICY hasad_party_writer_overrides_read
  ON hasad.user_permission_overrides
  FOR SELECT TO hasad_party_writer
  USING (permission_code = 'parties.manage');

-- Client Data API surface: read, insert, and update the approved columns only.
-- `id` and `company_id` are absent from the UPDATE list, so they are immutable.
GRANT SELECT (
  id, company_id, code, name_ar, name_en, party_type, is_customer,
  is_supplier, tax_id, phone, email, address, payment_terms_days, is_active
) ON hasad.parties TO authenticated;
GRANT INSERT (
  id, company_id, code, name_ar, name_en, party_type, is_customer,
  is_supplier, tax_id, phone, email, address, payment_terms_days, is_active
) ON hasad.parties TO authenticated;
GRANT UPDATE (
  code, name_ar, name_en, party_type, is_customer, is_supplier, tax_id,
  phone, email, address, payment_terms_days, is_active
) ON hasad.parties TO authenticated;

-- parties.manage resolution: active identity, active membership, active
-- company; owner precedence; deny-overrides win for non-owners.
CREATE OR REPLACE FUNCTION hasad.party_manage_allowed(p_company_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $fn$
  SELECT EXISTS (
    SELECT 1
    FROM hasad.company_memberships cm
    JOIN hasad.companies c
      ON c.id = cm.company_id AND c.status = 'active'
    JOIN hasad.permissions p
      ON p.code = 'parties.manage' AND p.module = 'parties'
    LEFT JOIN hasad.user_permission_overrides uo
      ON uo.membership_id = cm.id
     AND uo.permission_code = p.code
    WHERE cm.company_id = p_company_id
      AND cm.user_id = hasad.request_actor_user_id()
      AND cm.status = 'active'
      AND (
        cm.is_owner
        OR (
          uo.effect IS DISTINCT FROM 'deny'
          AND (
            uo.effect = 'allow'
            OR EXISTS (
              SELECT 1
              FROM hasad.role_permissions rp
              JOIN hasad.roles r
                ON r.id = rp.role_id
               AND r.company_id = cm.company_id
              WHERE rp.role_id = cm.role_id
                AND rp.permission_code = p.code
            )
          )
        )
      )
  );
$fn$;
REVOKE ALL ON FUNCTION hasad.party_manage_allowed(uuid)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION hasad.party_manage_allowed(uuid)
  TO authenticated;

CREATE POLICY direct_authenticated_parties_read
  ON hasad.parties
  FOR SELECT TO authenticated
  USING (EXISTS (
    SELECT 1
    FROM hasad.company_memberships cm
    JOIN hasad.companies c
      ON c.id = cm.company_id AND c.status = 'active'
    WHERE cm.company_id = parties.company_id
      AND cm.user_id = auth.uid()
      AND cm.status = 'active'
  ));

CREATE POLICY direct_authenticated_parties_insert
  ON hasad.parties
  FOR INSERT TO authenticated
  WITH CHECK (hasad.party_manage_allowed(company_id));

CREATE POLICY direct_authenticated_parties_update
  ON hasad.parties
  FOR UPDATE TO authenticated
  USING (hasad.party_manage_allowed(company_id))
  WITH CHECK (hasad.party_manage_allowed(company_id));

-- Audit rows may only be written with the actor bound to the request identity.
CREATE POLICY hasad_party_writer_audit_insert
  ON hasad.audit_log
  FOR INSERT TO hasad_party_writer
  WITH CHECK (actor_user_id = hasad.request_actor_user_id());

CREATE OR REPLACE FUNCTION hasad.audit_party_change()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $fn$
DECLARE
  v_actor uuid := hasad.request_actor_user_id();
BEGIN
  IF v_actor IS NULL THEN
    RAISE EXCEPTION 'UNAUTHENTICATED' USING ERRCODE = '42501';
  END IF;

  IF TG_OP = 'INSERT' THEN
    INSERT INTO hasad.audit_log
      (id, company_id, actor_user_id, action, entity_type, entity_id, details)
    VALUES
      (pg_catalog.gen_random_uuid(), NEW.company_id, v_actor, 'party.created',
       'party', NEW.id,
       pg_catalog.jsonb_build_object(
         'code', NEW.code,
         'party_type', NEW.party_type,
         'is_customer', NEW.is_customer,
         'is_supplier', NEW.is_supplier
       ));

    IF NEW.is_customer OR NEW.is_supplier THEN
      INSERT INTO hasad.audit_log
        (id, company_id, actor_user_id, action, entity_type, entity_id, details)
      VALUES
        (pg_catalog.gen_random_uuid(), NEW.company_id, v_actor,
         'party.classified', 'party', NEW.id,
         pg_catalog.jsonb_build_object(
           'is_customer', NEW.is_customer,
           'is_supplier', NEW.is_supplier
         ));
    END IF;

    RETURN NEW;
  END IF;

  INSERT INTO hasad.audit_log
    (id, company_id, actor_user_id, action, entity_type, entity_id, details)
  VALUES
    (pg_catalog.gen_random_uuid(), NEW.company_id, v_actor, 'party.updated',
     'party', NEW.id,
     pg_catalog.jsonb_build_object('code', NEW.code));

  IF OLD.is_active AND NOT NEW.is_active THEN
    INSERT INTO hasad.audit_log
      (id, company_id, actor_user_id, action, entity_type, entity_id, details)
    VALUES
      (pg_catalog.gen_random_uuid(), NEW.company_id, v_actor,
       'party.deactivated', 'party', NEW.id,
       pg_catalog.jsonb_build_object('code', NEW.code));
  END IF;

  IF OLD.is_customer IS DISTINCT FROM NEW.is_customer
     OR OLD.is_supplier IS DISTINCT FROM NEW.is_supplier THEN
    INSERT INTO hasad.audit_log
      (id, company_id, actor_user_id, action, entity_type, entity_id, details)
    VALUES
      (pg_catalog.gen_random_uuid(), NEW.company_id, v_actor,
       'party.classified', 'party', NEW.id,
       pg_catalog.jsonb_build_object(
         'is_customer', NEW.is_customer,
         'is_supplier', NEW.is_supplier
       ));
  END IF;

  RETURN NEW;
END
$fn$;
REVOKE ALL ON FUNCTION hasad.audit_party_change()
  FROM PUBLIC, anon, authenticated;

-- Create the trigger while the executor still owns the trigger function, which
-- satisfies CREATE TRIGGER's EXECUTE check. Ownership is transferred to the
-- locked role before this transaction commits.
CREATE TRIGGER parties_audit_changes
  AFTER INSERT OR UPDATE ON hasad.parties
  FOR EACH ROW EXECUTE FUNCTION hasad.audit_party_change();

GRANT CREATE ON SCHEMA hasad TO hasad_party_writer;
ALTER FUNCTION hasad.request_actor_user_id() OWNER TO hasad_party_writer;
ALTER FUNCTION hasad.party_manage_allowed(uuid) OWNER TO hasad_party_writer;
ALTER FUNCTION hasad.audit_party_change() OWNER TO hasad_party_writer;
-- CREATE is needed only for the ownership transfers above.
REVOKE CREATE ON SCHEMA hasad FROM hasad_party_writer;

DO $postflight$
BEGIN
  -- 1. Locked role, never granted to a client role ---------------------------
  IF NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_roles
    WHERE rolname = 'hasad_party_writer'
      AND NOT rolcanlogin
      AND NOT rolinherit
      AND NOT rolsuper
      AND NOT rolcreaterole
      AND NOT rolcreatedb
      AND NOT rolreplication
      AND NOT rolbypassrls
  ) THEN
    RAISE EXCEPTION 'POSTFLIGHT_WRITER_ROLE_ATTRIBUTES';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM pg_catalog.pg_auth_members m
    JOIN pg_catalog.pg_roles granted ON granted.oid = m.roleid
    JOIN pg_catalog.pg_roles member ON member.oid = m.member
    WHERE granted.rolname = 'hasad_party_writer'
      AND member.rolname IN ('authenticated', 'anon')
  ) THEN
    RAISE EXCEPTION 'POSTFLIGHT_WRITER_ROLE_GRANTED_TO_CLIENT';
  END IF;

  IF pg_catalog.has_schema_privilege('hasad_party_writer', 'hasad', 'CREATE') THEN
    RAISE EXCEPTION 'POSTFLIGHT_WRITER_SCHEMA_CREATE_RETAINED';
  END IF;

  -- 2. Function ownership and security attributes ----------------------------
  IF NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_proc p
    JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
    JOIN pg_catalog.pg_roles r ON r.oid = p.proowner
    WHERE n.nspname = 'hasad'
      AND p.proname = 'request_actor_user_id'
      AND p.pronargs = 0
      AND r.rolname = 'hasad_party_writer'
      AND NOT p.prosecdef
      AND p.proconfig IS NOT NULL
      AND NOT r.rolsuper
      AND NOT r.rolbypassrls
  ) THEN
    RAISE EXCEPTION 'POSTFLIGHT_ACTOR_HELPER_SECURITY';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM pg_catalog.pg_proc p
    JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
    JOIN pg_catalog.pg_roles r ON r.oid = p.proowner
    WHERE n.nspname = 'hasad'
      AND p.proname IN ('party_manage_allowed', 'audit_party_change')
      AND (
        r.rolname <> 'hasad_party_writer'
        OR NOT p.prosecdef
        OR p.proconfig IS NULL
        OR r.rolsuper
        OR r.rolbypassrls
      )
  ) THEN
    RAISE EXCEPTION 'POSTFLIGHT_FUNCTION_SECURITY';
  END IF;

  IF pg_catalog.has_function_privilege(
       'authenticated', 'hasad.request_actor_user_id()', 'EXECUTE'
     )
     OR pg_catalog.has_function_privilege(
       'anon', 'hasad.request_actor_user_id()', 'EXECUTE'
     )
     OR pg_catalog.has_function_privilege(
       'authenticated', 'hasad.audit_party_change()', 'EXECUTE'
     )
     OR NOT pg_catalog.has_function_privilege(
       'authenticated', 'hasad.party_manage_allowed(uuid)', 'EXECUTE'
     ) THEN
    RAISE EXCEPTION 'POSTFLIGHT_FUNCTION_EXECUTE_BOUNDARY';
  END IF;

  -- 3. Client write boundary --------------------------------------------------
  IF pg_catalog.has_table_privilege(
       'authenticated', 'hasad.parties', 'DELETE'
     ) OR pg_catalog.has_table_privilege(
       'authenticated', 'hasad.parties', 'TRUNCATE,REFERENCES,TRIGGER'
     ) OR pg_catalog.has_table_privilege(
       'authenticated', 'hasad.audit_log', 'INSERT,UPDATE,DELETE,TRUNCATE'
     ) OR pg_catalog.has_any_column_privilege(
       'authenticated', 'hasad.audit_log', 'INSERT,UPDATE'
     ) THEN
    RAISE EXCEPTION 'POSTFLIGHT_CLIENT_WRITE_BOUNDARY';
  END IF;

  IF pg_catalog.has_column_privilege(
       'authenticated', 'hasad.parties', 'id', 'UPDATE'
     ) OR pg_catalog.has_column_privilege(
       'authenticated', 'hasad.parties', 'company_id', 'UPDATE'
     ) OR NOT pg_catalog.has_column_privilege(
       'authenticated', 'hasad.parties', 'name_ar', 'UPDATE'
     ) THEN
    RAISE EXCEPTION 'POSTFLIGHT_UPDATE_COLUMN_BOUNDARY';
  END IF;

  IF pg_catalog.has_schema_privilege('anon', 'hasad', 'USAGE')
     OR pg_catalog.has_table_privilege(
       'anon', 'hasad.parties', 'SELECT,INSERT,UPDATE,DELETE'
     )
     OR pg_catalog.has_table_privilege(
       'anon', 'hasad.audit_log', 'INSERT,UPDATE,DELETE'
     ) THEN
    RAISE EXCEPTION 'POSTFLIGHT_ANON_ACCESS';
  END IF;

  -- 4. FORCE RLS untouched ----------------------------------------------------
  IF EXISTS (
    SELECT 1
    FROM pg_catalog.pg_class c
    JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'hasad'
      AND c.relname IN (
        'parties', 'audit_log', 'company_memberships', 'companies',
        'roles', 'permissions', 'role_permissions',
        'user_permission_overrides'
      )
      AND (NOT c.relrowsecurity OR NOT c.relforcerowsecurity)
  ) THEN
    RAISE EXCEPTION 'POSTFLIGHT_FORCE_RLS';
  END IF;

  -- 5. Writer cannot touch parties directly ----------------------------------
  IF pg_catalog.has_table_privilege(
       'hasad_party_writer', 'hasad.parties', 'INSERT,UPDATE,DELETE'
     ) OR pg_catalog.has_any_column_privilege(
       'hasad_party_writer', 'hasad.parties', 'INSERT,UPDATE'
     ) THEN
    RAISE EXCEPTION 'POSTFLIGHT_WRITER_PARTY_WRITE';
  END IF;

  -- 6. Catalogue intact -------------------------------------------------------
  IF NOT EXISTS (
    SELECT 1 FROM hasad.permissions
    WHERE code = 'parties.manage' AND module = 'parties'
  ) THEN
    RAISE EXCEPTION 'POSTFLIGHT_PERMISSION_MISSING';
  END IF;
END
$postflight$;

COMMIT;
NOTIFY pgrst, 'reload schema';
