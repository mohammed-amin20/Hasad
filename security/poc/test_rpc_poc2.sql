-- LOCAL RPC POC TESTS (synthetic) - NOT FOR DEPLOYMENT
SET client_min_messages = NOTICE;
BEGIN;

CREATE SCHEMA IF NOT EXISTS auth;
CREATE TABLE IF NOT EXISTS auth.users (id uuid PRIMARY KEY, email text);

-- Setup roles
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'hasad_api_invoker') THEN
    CREATE ROLE hasad_api_invoker NOLOGIN;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'hasad_api_definer_test') THEN
    CREATE ROLE hasad_api_definer_test NOLOGIN;
  END IF;
END $$;

GRANT USAGE ON SCHEMA hasad TO hasad_api_invoker;
GRANT USAGE ON SCHEMA hasad_api TO hasad_api_invoker;

-- Create synthetic data
CREATE EXTENSION IF NOT EXISTS pgcrypto;

INSERT INTO auth.users (id, email) VALUES 
  ('11111111-1111-1111-1111-111111111111', 'user1@test.com'),
  ('22222222-2222-2222-2222-222222222222', 'user2@test.com'),
  ('33333333-3333-3333-3333-333333333333', 'user3@test.com')
ON CONFLICT DO NOTHING;

INSERT INTO hasad.user_profiles (id) VALUES 
  ('11111111-1111-1111-1111-111111111111'),
  ('22222222-2222-2222-2222-222222222222'),
  ('33333333-3333-3333-3333-333333333333')
ON CONFLICT DO NOTHING;

INSERT INTO hasad.companies (id, created_by, status) VALUES
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '11111111-1111-1111-1111-111111111111', 'active'),
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', '22222222-2222-2222-2222-222222222222', 'active'),
  ('cccccccc-cccc-cccc-cccc-cccccccccccc', '33333333-3333-3333-3333-333333333333', 'suspended')
ON CONFLICT DO NOTHING;

INSERT INTO hasad.roles (id, company_id, code, is_system) VALUES
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaa01', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'admin', true),
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbb01', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'sales', true)
ON CONFLICT DO NOTHING;

INSERT INTO hasad.company_memberships (id, company_id, user_id, role_id, is_owner, status) VALUES
  ('11111111-1111-1111-1111-111111111112', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '11111111-1111-1111-1111-111111111111', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaa01', true, 'active'),
  ('22222222-2222-2222-2222-222222222223', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', '22222222-2222-2222-2222-222222222222', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbb01', false, 'active'),
  ('33333333-3333-3333-3333-333333333334', 'cccccccc-cccc-cccc-cccc-cccccccccccc', '33333333-3333-3333-3333-333333333333', NULL, true, 'active')
ON CONFLICT DO NOTHING;

INSERT INTO hasad.products (id, company_id, code, name_ar, base_uom_id, is_active) VALUES
  ('p1111111-1111-1111-1111-111111111111', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'P001', 'منتج أ', gen_random_uuid(), true),
  ('p2222222-2222-2222-2222-222222222222', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'P002', 'منتج ب', gen_random_uuid(), true)
ON CONFLICT DO NOTHING;

COMMIT;

-- Test auth.uid simulation
BEGIN;
SET LOCAL "request.jwt.claim.sub" = '11111111-1111-1111-1111-111111111111';
SELECT 'whoami_user1' as test, * FROM hasad_api.whoami();
SELECT 'products_user1' as test, count(*) FROM hasad_api.products_list();
ROLLBACK;

BEGIN;
SET LOCAL "request.jwt.claim.sub" = '22222222-2222-2222-2222-222222222222';
SELECT 'whoami_user2' as test, * FROM hasad_api.whoami();
SELECT 'products_user2' as test, count(*) FROM hasad_api.products_list();
ROLLBACK;

BEGIN;
SET LOCAL "request.jwt.claim.sub" = '33333333-3333-3333-3333-333333333333';
SELECT 'whoami_suspended_company' as test;
ROLLBACK;
