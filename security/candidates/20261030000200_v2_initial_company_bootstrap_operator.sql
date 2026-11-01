-- REVIEW-ONLY OPERATOR TEMPLATE. Never place in supabase/migrations.
--
-- This is a one-time initial-tenant bootstrap for the empty V2 DEV state.
-- It accepts only an explicitly selected existing Auth UUID. It never selects
-- the first/newest Auth user, creates no additional Auth user, and grants no
-- role permissions or user permission overrides.
--
-- An approved operator workflow replaces every __...__ token in a protected
-- temporary copy immediately before execution, then deletes that copy. Do not
-- place real operator values in this review file or in command arguments.

BEGIN;

SELECT set_config('hasad.bootstrap.owner_user_id','__OWNER_AUTH_USER_ID__',true);
SELECT set_config('hasad.bootstrap.company_id','__COMPANY_ID__',true);
SELECT set_config('hasad.bootstrap.owner_role_id','__OWNER_ROLE_ID__',true);
SELECT set_config('hasad.bootstrap.membership_id','__MEMBERSHIP_ID__',true);
SELECT set_config('hasad.bootstrap.audit_id','__AUDIT_ID__',true);
SELECT set_config('hasad.bootstrap.company_name_ar','__COMPANY_NAME_AR__',true);
SELECT set_config('hasad.bootstrap.owner_role_code','__OWNER_ROLE_CODE__',true);

DO $initial_company_bootstrap$
DECLARE
  v_owner_user_id uuid := current_setting('hasad.bootstrap.owner_user_id',true)::uuid;
  v_company_id uuid := current_setting('hasad.bootstrap.company_id',true)::uuid;
  v_owner_role_id uuid := current_setting('hasad.bootstrap.owner_role_id',true)::uuid;
  v_membership_id uuid := current_setting('hasad.bootstrap.membership_id',true)::uuid;
  v_audit_id uuid := current_setting('hasad.bootstrap.audit_id',true)::uuid;
  v_company_name_ar text := current_setting('hasad.bootstrap.company_name_ar',true);
  v_owner_role_code text := current_setting('hasad.bootstrap.owner_role_code',true);
BEGIN
  -- Fail closed: this template is only for an entirely unbootstrapped tenant
  -- surface, and only for an Auth identity selected by the operator.
  IF NOT EXISTS (SELECT 1 FROM auth.users WHERE id=v_owner_user_id) THEN
    RAISE EXCEPTION 'BOOTSTRAP_OWNER_AUTH_ID_NOT_FOUND';
  END IF;
  IF EXISTS (SELECT 1 FROM hasad.user_profiles WHERE id=v_owner_user_id) THEN
    RAISE EXCEPTION 'BOOTSTRAP_OWNER_PROFILE_ALREADY_EXISTS';
  END IF;
  IF EXISTS (SELECT 1 FROM hasad.company_memberships WHERE user_id=v_owner_user_id) THEN
    RAISE EXCEPTION 'BOOTSTRAP_OWNER_MEMBERSHIP_ALREADY_EXISTS';
  END IF;
  IF (SELECT count(*) FROM hasad.companies)<>0
     OR (SELECT count(*) FROM hasad.company_settings)<>0
     OR (SELECT count(*) FROM hasad.roles)<>0
     OR (SELECT count(*) FROM hasad.company_memberships)<>0 THEN
    RAISE EXCEPTION 'BOOTSTRAP_TENANT_SURFACE_NOT_EMPTY';
  END IF;
  IF v_company_name_ar IS NULL OR v_company_name_ar<>BTRIM(v_company_name_ar)
     OR v_company_name_ar='' THEN
    RAISE EXCEPTION 'BOOTSTRAP_COMPANY_NAME_AR_INVALID';
  END IF;
  IF v_owner_role_code IS NULL OR v_owner_role_code<>BTRIM(v_owner_role_code)
     OR v_owner_role_code='' THEN
    RAISE EXCEPTION 'BOOTSTRAP_OWNER_ROLE_CODE_INVALID';
  END IF;
  IF cardinality(ARRAY[v_owner_user_id,v_company_id,v_owner_role_id,v_membership_id,v_audit_id])<>5
     OR (SELECT count(DISTINCT x) FROM unnest(ARRAY[v_owner_user_id,v_company_id,v_owner_role_id,v_membership_id,v_audit_id]) x)<>5 THEN
    RAISE EXCEPTION 'BOOTSTRAP_IDS_MUST_BE_DISTINCT';
  END IF;

  INSERT INTO hasad.user_profiles(id) VALUES (v_owner_user_id);
  INSERT INTO hasad.companies(id,created_by,status)
    VALUES (v_company_id,v_owner_user_id,'active');
  INSERT INTO hasad.company_settings(company_id,name_ar,updated_by)
    VALUES (v_company_id,v_company_name_ar,v_owner_user_id);
  -- The role code is an explicit operator/owner decision. It is created with
  -- no role_permissions; owner access follows the reviewed owner rule only.
  INSERT INTO hasad.roles(id,company_id,code,is_system)
    VALUES (v_owner_role_id,v_company_id,v_owner_role_code,false);
  INSERT INTO hasad.company_memberships(
    id,company_id,user_id,role_id,is_owner,status,invited_by,revoked_at
  ) VALUES (
    v_membership_id,v_company_id,v_owner_user_id,v_owner_role_id,true,'active',NULL,NULL
  );
  INSERT INTO hasad.audit_log(
    id,company_id,actor_user_id,action,entity_type,entity_id,details,request_id
  ) VALUES (
    v_audit_id,v_company_id,v_owner_user_id,'company.created','company',v_company_id,
    '{}'::jsonb,NULL
  );
END
$initial_company_bootstrap$;

COMMIT;
