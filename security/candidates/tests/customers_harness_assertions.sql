-- Local-only assertions for the corrected Unit S1 candidate.
-- Requires: foundation/identity/permissions/catalogue/audit/erp migrations,
-- customers_harness_fixtures.sql, customers_direct_read_setup.sql, and the
-- corrected candidate installed in the same disposable database.
-- Every block runs as the client role to exercise RLS, then returns to the
-- session owner to inspect the committed state.

CREATE OR REPLACE FUNCTION pg_temp.assert_true(p_ok boolean, p_label text)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  IF p_ok IS NOT TRUE THEN
    RAISE EXCEPTION 'ASSERT_FAIL: %', p_label;
  END IF;
END
$$;

CREATE OR REPLACE FUNCTION pg_temp.expect_state(
  p_sql text, p_state text, p_label text
)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
  v_state text;
BEGIN
  BEGIN
    EXECUTE p_sql;
  EXCEPTION WHEN others THEN
    GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE;
    IF v_state <> p_state THEN
      RAISE EXCEPTION 'ASSERT_FAIL: % (expected %, got % - %)',
        p_label, p_state, v_state, SQLERRM;
    END IF;
    RETURN;
  END;
  RAISE EXCEPTION 'ASSERT_FAIL: % (expected %, statement succeeded)',
    p_label, p_state;
END
$$;

-- ===========================================================================
-- A. Owner precedence: founding owner may create without parties.manage.
-- ===========================================================================
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-0000-0000-000000000001"}', true
);
INSERT INTO hasad.parties
  (id, company_id, code, name_ar, name_en, party_type, is_customer,
   is_supplier, payment_terms_days)
VALUES
  ('40000000-0000-0000-0000-000000000001',
   '20000000-0000-0000-0000-000000000001',
   'CUST-001', 'Owner Customer', 'Owner Customer', 'company', true, false, 30);
RESET ROLE;
SELECT pg_temp.assert_true(
  (SELECT count(*) FROM hasad.audit_log
   WHERE entity_id = '40000000-0000-0000-0000-000000000001') = 2,
  'owner create writes exactly two audit rows'
);
SELECT pg_temp.assert_true(
  (SELECT count(*) FROM hasad.audit_log
   WHERE entity_id = '40000000-0000-0000-0000-000000000001'
     AND action = 'party.created'
     AND entity_type = 'party'
     AND company_id = '20000000-0000-0000-0000-000000000001'
     AND actor_user_id = '10000000-0000-0000-0000-000000000001') = 1,
  'party.created binds company and JWT actor'
);
SELECT pg_temp.assert_true(
  (SELECT count(*) FROM hasad.audit_log
   WHERE entity_id = '40000000-0000-0000-0000-000000000001'
     AND action = 'party.classified') = 1,
  'party.classified emitted for a classified customer'
);
COMMIT;

-- ===========================================================================
-- B. Create with no classification emits no party.classified.
-- ===========================================================================
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-0000-0000-000000000001"}', true
);
INSERT INTO hasad.parties
  (id, company_id, code, name_ar, party_type, is_customer, is_supplier)
VALUES
  ('40000000-0000-0000-0000-000000000002',
   '20000000-0000-0000-0000-000000000001',
   'PARTY-002', 'Unclassified Party', 'individual', false, false);
RESET ROLE;
SELECT pg_temp.assert_true(
  (SELECT count(*) FROM hasad.audit_log
   WHERE entity_id = '40000000-0000-0000-0000-000000000002'
     AND action = 'party.created') = 1,
  'unclassified create still audits party.created'
);
SELECT pg_temp.assert_true(
  (SELECT count(*) FROM hasad.audit_log
   WHERE entity_id = '40000000-0000-0000-0000-000000000002'
     AND action = 'party.classified') = 0,
  'unclassified create emits no party.classified'
);
COMMIT;

-- ===========================================================================
-- C. Non-owner with role grant (parties.manage) may create.
-- ===========================================================================
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-0000-0000-000000000002"}', true
);
INSERT INTO hasad.parties
  (id, company_id, code, name_ar, party_type, is_customer)
VALUES
  ('40000000-0000-0000-0000-000000000003',
   '20000000-0000-0000-0000-000000000001',
   'CUST-003', 'Accountant Customer', 'company', true);
RESET ROLE;
SELECT pg_temp.assert_true(
  (SELECT count(*) FROM hasad.audit_log
   WHERE entity_id = '40000000-0000-0000-0000-000000000003'
     AND action = 'party.created'
     AND actor_user_id = '10000000-0000-0000-0000-000000000002') = 1,
  'role-granted non-owner create audits with its own actor'
);
COMMIT;

-- ===========================================================================
-- D. Non-owner without parties.manage is denied by deny-by-default.
-- ===========================================================================
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-0000-0000-000000000003"}', true
);
SELECT pg_temp.expect_state(
  $q$INSERT INTO hasad.parties
       (id, company_id, code, name_ar, party_type, is_customer)
     VALUES
       ('40000000-0000-0000-0000-000000000004',
        '20000000-0000-0000-0000-000000000001',
        'CUST-004', 'Denied Customer', 'company', true)$q$,
  '42501', 'staff without parties.manage is denied'
);
RESET ROLE;
SELECT pg_temp.assert_true(
  (SELECT count(*) FROM hasad.parties
   WHERE id = '40000000-0000-0000-0000-000000000004') = 0,
  'denied insert wrote no party row'
);
SELECT pg_temp.assert_true(
  (SELECT count(*) FROM hasad.audit_log
   WHERE entity_id = '40000000-0000-0000-0000-000000000004') = 0,
  'denied insert wrote no audit row'
);
COMMIT;

-- ===========================================================================
-- E. Explicit allow override grants a role without the permission.
-- ===========================================================================
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-0000-0000-000000000004"}', true
);
INSERT INTO hasad.parties
  (id, company_id, code, name_ar, party_type, is_customer)
VALUES
  ('40000000-0000-0000-0000-000000000005',
   '20000000-0000-0000-0000-000000000001',
   'CUST-005', 'Allow Override Customer', 'company', true);
RESET ROLE;
SELECT pg_temp.assert_true(
  (SELECT count(*) FROM hasad.parties
   WHERE id = '40000000-0000-0000-0000-000000000005') = 1,
  'allow override permits the write'
);
COMMIT;

-- ===========================================================================
-- F. Deny override wins for a non-owner that otherwise has the permission.
-- ===========================================================================
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-0000-0000-000000000005"}', true
);
SELECT pg_temp.expect_state(
  $q$INSERT INTO hasad.parties
       (id, company_id, code, name_ar, party_type, is_customer)
     VALUES
       ('40000000-0000-0000-0000-000000000006',
        '20000000-0000-0000-0000-000000000001',
        'CUST-006', 'Deny Override Customer', 'company', true)$q$,
  '42501', 'deny override blocks a role-granted non-owner'
);
RESET ROLE;
SELECT pg_temp.assert_true(
  (SELECT count(*) FROM hasad.parties
   WHERE id = '40000000-0000-0000-0000-000000000006') = 0,
  'deny override wrote no party row'
);
COMMIT;

-- ===========================================================================
-- G. Cross-company INSERT is impossible even for a company owner.
-- ===========================================================================
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-0000-0000-000000000001"}', true
);
SELECT pg_temp.expect_state(
  $q$INSERT INTO hasad.parties
       (id, company_id, code, name_ar, party_type, is_customer)
     VALUES
       ('40000000-0000-0000-0000-000000000007',
        '20000000-0000-0000-0000-000000000002',
        'CUST-B-001', 'Cross Company Customer', 'company', true)$q$,
  '42501', 'owner A cannot insert into company B'
);
RESET ROLE;
COMMIT;

BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-0000-0000-000000000006"}', true
);
INSERT INTO hasad.parties
  (id, company_id, code, name_ar, party_type, is_customer)
VALUES
  ('40000000-0000-0000-0000-000000000008',
   '20000000-0000-0000-0000-000000000002',
   'CUST-B-001', 'Company B Customer', 'company', true);
RESET ROLE;
SELECT pg_temp.assert_true(
  (SELECT count(*) FROM hasad.audit_log
   WHERE entity_id = '40000000-0000-0000-0000-000000000008'
     AND company_id = '20000000-0000-0000-0000-000000000002'
     AND actor_user_id = '10000000-0000-0000-0000-000000000006') = 2,
  'company B owner create audits inside company B'
);
COMMIT;

-- ===========================================================================
-- H. Suspended membership and suspended company are refused.
-- ===========================================================================
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-0000-0000-000000000008"}', true
);
SELECT pg_temp.expect_state(
  $q$INSERT INTO hasad.parties
       (id, company_id, code, name_ar, party_type, is_customer)
     VALUES
       ('40000000-0000-0000-0000-000000000009',
        '20000000-0000-0000-0000-000000000001',
        'CUST-009', 'Suspended Membership', 'company', true)$q$,
  '42501', 'suspended membership is denied'
);
RESET ROLE;
COMMIT;

BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-0000-0000-000000000007"}', true
);
SELECT pg_temp.expect_state(
  $q$INSERT INTO hasad.parties
       (id, company_id, code, name_ar, party_type, is_customer)
     VALUES
       ('40000000-0000-0000-0000-00000000000a',
        '20000000-0000-0000-0000-000000000003',
        'CUST-00A', 'Suspended Company', 'company', true)$q$,
  '42501', 'suspended company is denied'
);
RESET ROLE;
COMMIT;

-- ===========================================================================
-- I. No identity / malformed identity never reaches the write path.
-- ===========================================================================
BEGIN;
SET LOCAL ROLE authenticated;
SELECT pg_temp.expect_state(
  $q$INSERT INTO hasad.parties
       (id, company_id, code, name_ar, party_type, is_customer)
     VALUES
       ('40000000-0000-0000-0000-00000000000b',
        '20000000-0000-0000-0000-000000000001',
        'CUST-00B', 'Anonymous Write', 'company', true)$q$,
  '42501', 'missing JWT claims is denied'
);
RESET ROLE;
COMMIT;

BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', 'not-json', true);
SELECT pg_temp.expect_state(
  $q$INSERT INTO hasad.parties
       (id, company_id, code, name_ar, party_type, is_customer)
     VALUES
       ('40000000-0000-0000-0000-00000000000c',
        '20000000-0000-0000-0000-000000000001',
        'CUST-00C', 'Malformed Claims', 'company', true)$q$,
  '28000', 'malformed JWT claims is rejected as unauthorized'
);
RESET ROLE;
COMMIT;

-- ===========================================================================
-- J. Same-company UPDATE audits updated / classified / deactivated exactly.
-- ===========================================================================
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-0000-0000-000000000001"}', true
);
UPDATE hasad.parties SET name_ar = 'Owner Customer Renamed'
WHERE id = '40000000-0000-0000-0000-000000000001';
RESET ROLE;
SELECT pg_temp.assert_true(
  (SELECT count(*) FROM hasad.audit_log
   WHERE entity_id = '40000000-0000-0000-0000-000000000001'
     AND action = 'party.updated') = 1,
  'plain update emits one party.updated'
);
SELECT pg_temp.assert_true(
  (SELECT count(*) FROM hasad.audit_log
   WHERE entity_id = '40000000-0000-0000-0000-000000000001'
     AND action = 'party.classified') = 1,
  'plain update emits no party.classified'
);
COMMIT;

BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-0000-0000-000000000001"}', true
);
UPDATE hasad.parties SET is_customer = false, is_supplier = true
WHERE id = '40000000-0000-0000-0000-000000000001';
RESET ROLE;
SELECT pg_temp.assert_true(
  (SELECT count(*) FROM hasad.audit_log
   WHERE entity_id = '40000000-0000-0000-0000-000000000001'
     AND action = 'party.updated') = 2,
  'classification update emits party.updated'
);
SELECT pg_temp.assert_true(
  (SELECT count(*) FROM hasad.audit_log
   WHERE entity_id = '40000000-0000-0000-0000-000000000001'
     AND action = 'party.classified') = 2,
  'classification change emits party.classified'
);
COMMIT;

BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-0000-0000-000000000001"}', true
);
UPDATE hasad.parties SET is_active = false
WHERE id = '40000000-0000-0000-0000-000000000001';
RESET ROLE;
SELECT pg_temp.assert_true(
  (SELECT count(*) FROM hasad.audit_log
   WHERE entity_id = '40000000-0000-0000-0000-000000000001'
     AND action = 'party.deactivated') = 1,
  'deactivation emits one party.deactivated'
);
COMMIT;

BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-0000-0000-000000000001"}', true
);
UPDATE hasad.parties SET is_active = false
WHERE id = '40000000-0000-0000-0000-000000000001';
RESET ROLE;
SELECT pg_temp.assert_true(
  (SELECT count(*) FROM hasad.audit_log
   WHERE entity_id = '40000000-0000-0000-0000-000000000001'
     AND action = 'party.deactivated') = 1,
  'repeated deactivation emits no second party.deactivated'
);
COMMIT;

-- ===========================================================================
-- K. id and company_id are immutable through the Data API.
-- ===========================================================================
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-0000-0000-000000000001"}', true
);
SELECT pg_temp.expect_state(
  $q$UPDATE hasad.parties
     SET company_id = '20000000-0000-0000-0000-000000000002'
     WHERE id = '40000000-0000-0000-0000-000000000001'$q$,
  '42501', 'company_id is not updatable'
);
SELECT pg_temp.expect_state(
  $q$UPDATE hasad.parties
     SET id = '40000000-0000-0000-0000-0000000000ff'
     WHERE id = '40000000-0000-0000-0000-000000000001'$q$,
  '42501', 'id is not updatable'
);
RESET ROLE;
COMMIT;

-- ===========================================================================
-- L. Cross-company UPDATE affects no row.
-- ===========================================================================
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-0000-0000-000000000001"}', true
);
UPDATE hasad.parties SET name_ar = 'Hijacked'
WHERE id = '40000000-0000-0000-0000-000000000008';
RESET ROLE;
SELECT pg_temp.assert_true(
  (SELECT name_ar FROM hasad.parties
   WHERE id = '40000000-0000-0000-0000-000000000008') = 'Company B Customer',
  'owner A cannot update a company B party'
);
SELECT pg_temp.assert_true(
  (SELECT count(*) FROM hasad.audit_log
   WHERE entity_id = '40000000-0000-0000-0000-000000000008'
     AND action = 'party.updated') = 0,
  'blocked cross-company update wrote no audit row'
);
COMMIT;

-- ===========================================================================
-- M. PostgREST `return=representation` path and Flutter error mapping.
--    The Flutter repository does .insert(...).select(columns).single() and
--    .update(...).select(columns).single(), so RETURNING must work under RLS.
-- ===========================================================================
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-0000-0000-000000000002"}', true
);
WITH inserted AS (
  INSERT INTO hasad.parties
    (id, company_id, code, name_ar, party_type, is_customer)
  VALUES
    ('40000000-0000-0000-0000-00000000000d',
     '20000000-0000-0000-0000-000000000001',
     'CUST-00D', 'Returning Customer', 'company', true)
  RETURNING id, company_id, code, name_ar, party_type, is_customer,
            is_supplier, payment_terms_days, is_active
)
SELECT pg_temp.assert_true(
  (SELECT count(*) FROM inserted) = 1
  AND (SELECT code FROM inserted) = 'CUST-00D',
  'insert with RETURNING returns the visible row to the client'
);
WITH updated AS (
  UPDATE hasad.parties SET name_ar = 'Returning Customer 2'
  WHERE id = '40000000-0000-0000-0000-00000000000d'
  RETURNING id, name_ar
)
SELECT pg_temp.assert_true(
  (SELECT count(*) FROM updated) = 1
  AND (SELECT name_ar FROM updated) = 'Returning Customer 2',
  'update with RETURNING returns the visible row to the client'
);
SELECT pg_temp.expect_state(
  $q$INSERT INTO hasad.parties
       (id, company_id, code, name_ar, party_type, is_customer)
     VALUES
       ('40000000-0000-0000-0000-00000000000e',
        '20000000-0000-0000-0000-000000000001',
        'CUST-00D', 'Duplicate Code', 'company', true)$q$,
  '23505', 'duplicate party code maps to 23505'
);
SELECT pg_temp.expect_state(
  $q$INSERT INTO hasad.parties
       (id, company_id, code, name_ar, party_type, is_customer,
        payment_terms_days)
     VALUES
       ('40000000-0000-0000-0000-00000000000f',
        '20000000-0000-0000-0000-000000000001',
        'CUST-00F', 'Invalid Terms', 'company', true, -1)$q$,
  '23514', 'negative payment terms maps to 23514'
);
RESET ROLE;
COMMIT;

-- ===========================================================================
-- N. RLS read isolation and no direct audit/privilege bypass.
-- ===========================================================================
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-0000-0000-000000000001"}', true
);
SELECT pg_temp.assert_true(
  (SELECT count(*) FROM hasad.parties
   WHERE company_id = '20000000-0000-0000-0000-000000000002') = 0,
  'owner A cannot read company B parties'
);
SELECT pg_temp.assert_true(
  (SELECT count(*) FROM hasad.parties
   WHERE company_id = '20000000-0000-0000-0000-000000000001') > 0,
  'owner A can read company A parties'
);
SELECT pg_temp.assert_true(
  hasad.party_manage_allowed('20000000-0000-0000-0000-000000000001'),
  'owner precedence returns true for own company'
);
SELECT pg_temp.assert_true(
  NOT hasad.party_manage_allowed('20000000-0000-0000-0000-000000000002'),
  'authorization helper returns false for a foreign company'
);
SELECT pg_temp.expect_state(
  $q$INSERT INTO hasad.audit_log
       (id, company_id, actor_user_id, action, entity_type, entity_id, details)
     VALUES
       (pg_catalog.gen_random_uuid(),
        '20000000-0000-0000-0000-000000000001',
        '10000000-0000-0000-0000-000000000001',
        'party.created', 'party',
        '40000000-0000-0000-0000-000000000001', '{}'::jsonb)$q$,
  '42501', 'clients cannot forge audit rows'
);
SELECT pg_temp.expect_state(
  $q$SELECT hasad.request_actor_user_id()$q$,
  '42501', 'clients cannot call the actor helper'
);
SELECT pg_temp.expect_state(
  $q$SELECT hasad.audit_party_change()$q$,
  '42501', 'clients cannot call the audit trigger function'
);
RESET ROLE;
COMMIT;

BEGIN;
SET LOCAL ROLE anon;
SELECT pg_temp.expect_state(
  $q$SELECT count(*) FROM hasad.parties$q$,
  '42501', 'anon has no party access'
);
RESET ROLE;
COMMIT;

-- ===========================================================================
-- O. Installed object shape and privilege boundary.
-- ===========================================================================
SELECT pg_temp.assert_true(
  EXISTS (
    SELECT 1 FROM pg_catalog.pg_roles
    WHERE rolname = 'hasad_party_writer'
      AND NOT rolcanlogin
      AND NOT rolinherit
      AND NOT rolsuper
      AND NOT rolcreatedb
      AND NOT rolcreaterole
      AND NOT rolreplication
      AND NOT rolbypassrls
  ),
  'writer role is locked and NOBYPASSRLS'
);
SELECT pg_temp.assert_true(
  NOT pg_catalog.pg_has_role('authenticated', 'hasad_party_writer', 'MEMBER')
  AND NOT pg_catalog.pg_has_role('anon', 'hasad_party_writer', 'MEMBER'),
  'client roles cannot assume the writer role'
);
SELECT pg_temp.assert_true(
  NOT pg_catalog.has_schema_privilege('hasad_party_writer', 'hasad', 'CREATE'),
  'writer role does not retain schema CREATE'
);
SELECT pg_temp.assert_true(
  EXISTS (
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
  ),
  'actor helper is invoker-rights, writer-owned, search_path pinned'
);
SELECT pg_temp.assert_true(
  NOT EXISTS (
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
  ),
  'definer functions are writer-owned, NOBYPASSRLS, search_path pinned'
);
SELECT pg_temp.assert_true(
  NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_proc p
    JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'hasad'
      AND p.proname IN (
        'request_actor_user_id', 'party_manage_allowed', 'audit_party_change'
      )
      AND p.proowner = (
        SELECT oid FROM pg_catalog.pg_roles WHERE rolname = 'hasad_rpc_owner'
      )
  ),
  'no candidate object is owned by hasad_rpc_owner'
);
SELECT pg_temp.assert_true(
  NOT pg_catalog.has_table_privilege(
    'authenticated', 'hasad.parties', 'DELETE'
  )
  AND NOT pg_catalog.has_any_column_privilege(
    'authenticated', 'hasad.audit_log', 'INSERT,UPDATE'
  )
  AND NOT pg_catalog.has_column_privilege(
    'authenticated', 'hasad.parties', 'id', 'UPDATE'
  )
  AND NOT pg_catalog.has_column_privilege(
    'authenticated', 'hasad.parties', 'company_id', 'UPDATE'
  )
  AND pg_catalog.has_column_privilege(
    'authenticated', 'hasad.parties', 'name_ar', 'UPDATE'
  ),
  'client column-level write boundary is exact'
);
SELECT pg_temp.assert_true(
  NOT EXISTS (
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
  ),
  'FORCE RLS remains enabled on every touched table'
);
SELECT pg_temp.assert_true(
  NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_policy p
    WHERE p.polrelid IN (
      pg_catalog.to_regclass('hasad.parties'),
      pg_catalog.to_regclass('hasad.audit_log')
    )
      AND 0 = ANY (p.polroles)
  ),
  'no PUBLIC policy exists on parties or audit_log'
);
SELECT pg_temp.assert_true(
  (SELECT count(*) FROM hasad.audit_log
   WHERE entity_id = '40000000-0000-0000-0000-000000000001'
     AND actor_user_id <> '10000000-0000-0000-0000-000000000001') = 0,
  'no client-supplied actor identity is reachable'
);

SELECT 'PASS: unit S1 corrected customer write candidate assertions' AS result;
