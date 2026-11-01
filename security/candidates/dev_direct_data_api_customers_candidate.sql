-- REVIEW ONLY / NOT DEPLOYED / DEV ONLY.
-- Unit S1: company-scoped party reads and parties.manage writes through the
-- existing authenticated hasad Data API, with mandatory atomic audit events.
--
-- Requires catalog preflight: parties/audit_log and authz dependencies exist;
-- target tables retain FORCE RLS; current executor owns the altered tables and
-- can grant privileges/role membership; existing hasad_rpc_owner is locked,
-- NOBYPASSRLS, and can SET ROLE from the executor; auth.uid() is executable by
-- that owner. This candidate does not alter Auth, companies, or role mappings.

BEGIN;

DO $preflight$
DECLARE
  v_missing text;
BEGIN
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

  IF EXISTS (
    SELECT 1
    FROM pg_catalog.pg_class c
    JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'hasad'
      AND c.relname IN ('parties', 'audit_log')
      AND (NOT c.relrowsecurity OR NOT c.relforcerowsecurity)
  ) THEN
    RAISE EXCEPTION 'PREFLIGHT_FORCE_RLS';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM pg_catalog.pg_class c
    JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'hasad'
      AND c.relname IN ('parties', 'audit_log')
      AND pg_catalog.pg_get_userbyid(c.relowner) <> current_user
  ) THEN
    RAISE EXCEPTION 'PREFLIGHT_TABLE_OWNERSHIP';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_roles
    WHERE rolname = current_user AND (rolsuper OR rolcreaterole)
  ) THEN
    RAISE EXCEPTION 'PREFLIGHT_NO_ROLE_ADMIN';
  END IF;
  IF NOT pg_catalog.has_schema_privilege(current_user, 'hasad', 'CREATE') THEN
    RAISE EXCEPTION 'PREFLIGHT_NO_SCHEMA_CREATE';
  END IF;
  IF NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_roles r
    WHERE r.rolname = 'hasad_rpc_owner'
      AND NOT r.rolcanlogin
      AND NOT r.rolinherit
      AND NOT r.rolsuper
      AND NOT r.rolbypassrls
      AND pg_catalog.pg_has_role(current_user, r.oid, 'SET')
  ) THEN
    RAISE EXCEPTION 'PREFLIGHT_RESTRICTED_OWNER_UNAVAILABLE';
  END IF;
  IF NOT pg_catalog.has_schema_privilege('hasad_rpc_owner', 'auth', 'USAGE')
     OR NOT pg_catalog.has_function_privilege(
       'hasad_rpc_owner', 'auth.uid()', 'EXECUTE'
     ) THEN
    RAISE EXCEPTION 'PREFLIGHT_AUTH_UID_PRIVILEGE';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM hasad.permissions
    WHERE code = 'parties.manage' AND module = 'parties'
  ) THEN
    RAISE EXCEPTION 'PREFLIGHT_PARTIES_MANAGE_MISSING';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM pg_catalog.pg_proc p
    JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'hasad'
      AND p.proname IN ('party_manage_allowed', 'audit_party_change')
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
      'hasad_rpc_owner_parties_permission',
      'hasad_rpc_owner_party_audit_insert'
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

  IF pg_catalog.has_table_privilege(
       'authenticated', 'hasad.parties', 'INSERT,UPDATE,DELETE'
     ) OR pg_catalog.has_table_privilege(
       'authenticated', 'hasad.audit_log', 'INSERT,UPDATE,DELETE'
     ) THEN
    RAISE EXCEPTION 'PREFLIGHT_UNEXPECTED_CLIENT_WRITE';
  END IF;
  IF pg_catalog.has_schema_privilege('anon', 'hasad', 'USAGE')
     OR pg_catalog.has_table_privilege('anon', 'hasad.parties', 'SELECT,INSERT,UPDATE,DELETE')
     OR pg_catalog.has_table_privilege('anon', 'hasad.audit_log', 'INSERT,UPDATE,DELETE') THEN
    RAISE EXCEPTION 'PREFLIGHT_ANON_ACCESS';
  END IF;
END
$preflight$;

-- The existing restricted owner may see only the parties.manage catalogue row.
CREATE POLICY hasad_rpc_owner_parties_permission
  ON hasad.permissions
  FOR SELECT TO hasad_rpc_owner
  USING (code = 'parties.manage' AND module = 'parties');

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
      AND cm.user_id = auth.uid()
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

CREATE POLICY direct_authenticated_parties_insert
  ON hasad.parties
  FOR INSERT TO authenticated
  WITH CHECK (hasad.party_manage_allowed(company_id));
CREATE POLICY direct_authenticated_parties_update
  ON hasad.parties
  FOR UPDATE TO authenticated
  USING (hasad.party_manage_allowed(company_id))
  WITH CHECK (hasad.party_manage_allowed(company_id));

GRANT INSERT (
  id, company_id, actor_user_id, action, entity_type, entity_id, details
) ON hasad.audit_log TO hasad_rpc_owner;
CREATE POLICY hasad_rpc_owner_party_audit_insert
  ON hasad.audit_log
  FOR INSERT TO hasad_rpc_owner
  WITH CHECK (
    actor_user_id = auth.uid()
    AND EXISTS (
      SELECT 1
      FROM hasad.company_memberships cm
      JOIN hasad.companies c
        ON c.id = cm.company_id AND c.status = 'active'
      WHERE cm.company_id = audit_log.company_id
        AND cm.user_id = auth.uid()
        AND cm.status = 'active'
    )
  );

CREATE OR REPLACE FUNCTION hasad.audit_party_change()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $fn$
DECLARE
  v_actor uuid := auth.uid();
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
REVOKE ALL ON FUNCTION hasad.audit_party_change() FROM PUBLIC, anon, authenticated;

GRANT CREATE ON SCHEMA hasad TO hasad_rpc_owner;
-- Create the trigger while the executor still owns the trigger function,
-- which satisfies CREATE TRIGGER's EXECUTE privilege check. Ownership is
-- transferred to the locked role before this transaction commits.
CREATE TRIGGER parties_audit_changes
  AFTER INSERT OR UPDATE ON hasad.parties
  FOR EACH ROW EXECUTE FUNCTION hasad.audit_party_change();

ALTER FUNCTION hasad.party_manage_allowed(uuid) OWNER TO hasad_rpc_owner;
ALTER FUNCTION hasad.audit_party_change() OWNER TO hasad_rpc_owner;
REVOKE CREATE ON SCHEMA hasad FROM hasad_rpc_owner;

DO $postflight$
BEGIN
  IF pg_catalog.has_table_privilege(
       'authenticated', 'hasad.parties', 'DELETE'
     ) OR pg_catalog.has_table_privilege(
       'authenticated', 'hasad.audit_log', 'INSERT,UPDATE,DELETE'
     ) THEN
    RAISE EXCEPTION 'POSTFLIGHT_CLIENT_WRITE_BOUNDARY';
  END IF;
  IF EXISTS (
    SELECT 1 FROM pg_catalog.pg_proc p
    JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
    JOIN pg_catalog.pg_roles r ON r.oid = p.proowner
    WHERE n.nspname = 'hasad'
      AND p.proname IN ('party_manage_allowed', 'audit_party_change')
      AND (r.rolname <> 'hasad_rpc_owner'
           OR NOT p.prosecdef
           OR p.proconfig IS NULL)
  ) THEN
    RAISE EXCEPTION 'POSTFLIGHT_FUNCTION_SECURITY';
  END IF;
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
