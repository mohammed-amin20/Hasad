-- Assertions for the disposable end-to-end runner test. Local cluster only.
CREATE OR REPLACE FUNCTION pg_temp.assert_true(ok boolean, label text) RETURNS void
LANGUAGE plpgsql AS $$ BEGIN
  IF NOT ok THEN RAISE EXCEPTION 'ASSERTION_FAILED: %', label; END IF;
  RAISE NOTICE 'PASS: %', label;
END $$;

SELECT pg_temp.assert_true((SELECT count(*)=1 FROM hasad.user_profiles), 'exactly one profile created');
SELECT pg_temp.assert_true((SELECT count(*)=1 FROM hasad.companies WHERE status='active'), 'exactly one active company');
SELECT pg_temp.assert_true((SELECT count(*)=1 FROM hasad.company_settings WHERE name_ar='Abo Amen' AND currency='ILS' AND vat_enabled=false AND preferences='{}'::jsonb), 'one settings row with schema defaults');
SELECT pg_temp.assert_true((SELECT count(*)=1 FROM hasad.roles WHERE code='owner' AND is_system=false), 'one non-system owner role');
SELECT pg_temp.assert_true((SELECT count(*)=1 FROM hasad.company_memberships WHERE is_owner AND status='active' AND revoked_at IS NULL), 'one active owner membership');
SELECT pg_temp.assert_true((SELECT count(*)=1 FROM hasad.company_memberships m JOIN hasad.roles r ON r.id=m.role_id AND r.company_id=m.company_id WHERE m.is_owner), 'owner membership references the same-company owner role');
SELECT pg_temp.assert_true((SELECT count(*)=1 FROM hasad.audit_log WHERE action='company.created' AND entity_type='company' AND details='{}'::jsonb), 'one company.created audit event');
SELECT pg_temp.assert_true((SELECT count(*)=0 FROM hasad.role_permissions), 'zero role-permission mappings');
SELECT pg_temp.assert_true((SELECT count(*)=0 FROM hasad.role_permissions WHERE permission_code='products.read'), 'zero products.read role mappings');
SELECT pg_temp.assert_true((SELECT count(*)=0 FROM hasad.user_permission_overrides), 'zero user permission overrides');
SELECT pg_temp.assert_true((SELECT count(*)=0 FROM hasad.user_profiles WHERE id='00000000-0000-0000-0000-000000000002'::uuid), 'unselected Auth user received no profile');
SELECT pg_temp.assert_true((SELECT count(*)=0 FROM hasad.company_memberships WHERE user_id='00000000-0000-0000-0000-000000000002'::uuid), 'unselected Auth user received no membership');
SELECT pg_temp.assert_true((SELECT count(*)=0 FROM hasad.user_profiles WHERE id<>'00000000-0000-0000-0000-000000000001'::uuid), 'no profile for any other identity');
SELECT pg_temp.assert_true((SELECT count(*)=0 FROM hasad.audit_log WHERE actor_user_id<>'00000000-0000-0000-0000-000000000001'::uuid), 'no audit event for any other identity');
SELECT pg_temp.assert_true((SELECT count(*)=9 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='hasad' AND c.relkind='r' AND c.relrowsecurity AND c.relforcerowsecurity), 'all harness hasad tables retain FORCE RLS');
