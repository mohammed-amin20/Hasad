-- Disposable local PostgreSQL harness, derived from current V2 migration shapes.
-- Never run against DEV/production. All rows and roles exist only in this database.
CREATE ROLE authenticated NOLOGIN;
CREATE ROLE anon NOLOGIN;
CREATE ROLE hasad_rpc_owner NOLOGIN NOSUPERUSER NOBYPASSRLS;
CREATE SCHEMA auth;
CREATE SCHEMA hasad;
CREATE SCHEMA hasad_api;
CREATE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql STABLE AS
  $$ SELECT NULLIF(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
CREATE TABLE hasad.user_profiles(id uuid primary key, display_name text);
CREATE TABLE hasad.companies(id uuid primary key, created_by uuid not null,
  status text not null check(status in ('active','suspended')));
CREATE TABLE hasad.roles(id uuid primary key, company_id uuid not null,
  code text not null, unique(company_id,id), unique(company_id,code));
CREATE TABLE hasad.company_memberships(id uuid primary key, company_id uuid not null,
  user_id uuid not null unique, role_id uuid, is_owner boolean not null default false,
  status text not null check(status in ('active','suspended','revoked')),
  unique(company_id,user_id));
CREATE TABLE hasad.company_settings(company_id uuid primary key, name_ar text not null,
  name_en text, display_name text);
CREATE TABLE hasad.permissions(code text primary key, module text not null);
CREATE TABLE hasad.role_permissions(role_id uuid not null, permission_code text not null,
  primary key(role_id,permission_code));
CREATE TABLE hasad.user_permission_overrides(membership_id uuid not null,
  permission_code text not null, effect text not null check(effect in ('allow','deny')),
  primary key(membership_id,permission_code));
CREATE TABLE hasad.products(id uuid primary key, company_id uuid not null, code text not null,
  name_ar text not null, name_en text, barcode text, category_id uuid, base_uom_id uuid not null,
  track_inventory boolean not null default true, is_active boolean not null default true);

DO $$ DECLARE t text; BEGIN
 FOREACH t IN ARRAY ARRAY['user_profiles','companies','roles','company_memberships',
  'company_settings','permissions','role_permissions','user_permission_overrides','products'] LOOP
  EXECUTE format('ALTER TABLE hasad.%I ENABLE ROW LEVEL SECURITY',t);
  EXECUTE format('ALTER TABLE hasad.%I FORCE ROW LEVEL SECURITY',t);
 END LOOP;
END $$;
GRANT USAGE ON SCHEMA auth TO authenticated, anon, hasad_rpc_owner;
GRANT EXECUTE ON FUNCTION auth.uid() TO authenticated, anon, hasad_rpc_owner;
GRANT USAGE ON SCHEMA hasad_api TO authenticated, anon;

-- Evidence case 1: reproduce SECURITY INVOKER failure with restricted role and no table grants.
CREATE FUNCTION hasad_api.invoker_probe() RETURNS bigint LANGUAGE sql SECURITY INVOKER
  SET search_path=pg_catalog AS $$ SELECT count(*) FROM hasad.companies $$;
GRANT USAGE ON SCHEMA hasad_api TO authenticated;
GRANT EXECUTE ON FUNCTION hasad_api.invoker_probe() TO authenticated;

-- Review-only alternative is loaded separately after invoker failure is asserted.
INSERT INTO hasad.user_profiles VALUES
 ('00000000-0000-0000-0000-000000000001','A'),
 ('00000000-0000-0000-0000-000000000002','B'),
 ('00000000-0000-0000-0000-000000000003','missing'),
 ('00000000-0000-0000-0000-000000000004','revoked'),
 ('00000000-0000-0000-0000-000000000005','suspended'),
 ('00000000-0000-0000-0000-000000000006','no-permission'),
 ('00000000-0000-0000-0000-000000000007','role-allow'),
 ('00000000-0000-0000-0000-000000000008','override-deny'),
 ('00000000-0000-0000-0000-000000000009','override-allow'),
 ('00000000-0000-0000-0000-000000000010','owner');
INSERT INTO hasad.companies VALUES
 ('10000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000001','active'),
 ('10000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000002','active'),
 ('10000000-0000-0000-0000-000000000005','00000000-0000-0000-0000-000000000005','suspended');
INSERT INTO hasad.company_settings VALUES
 ('10000000-0000-0000-0000-000000000001','شركة ألف','Alpha','Company A'),
 ('10000000-0000-0000-0000-000000000002','شركة باء','Beta','Company B'),
 ('10000000-0000-0000-0000-000000000005','موقوفة','Suspended','Paused');
INSERT INTO hasad.roles VALUES
 ('20000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','sales'),
 ('20000000-0000-0000-0000-000000000002','10000000-0000-0000-0000-000000000002','sales'),
 ('20000000-0000-0000-0000-000000000003','10000000-0000-0000-0000-000000000001','viewer');
INSERT INTO hasad.company_memberships VALUES
 ('30000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001',false,'active'),
 ('30000000-0000-0000-0000-000000000002','10000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000002','20000000-0000-0000-0000-000000000002',false,'active'),
 ('30000000-0000-0000-0000-000000000004','10000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000004','20000000-0000-0000-0000-000000000001',false,'revoked'),
 ('30000000-0000-0000-0000-000000000005','10000000-0000-0000-0000-000000000005','00000000-0000-0000-0000-000000000005','20000000-0000-0000-0000-000000000001',false,'active'),
 ('30000000-0000-0000-0000-000000000006','10000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000006','20000000-0000-0000-0000-000000000003',false,'active'),
 ('30000000-0000-0000-0000-000000000007','10000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000007','20000000-0000-0000-0000-000000000001',false,'active'),
 ('30000000-0000-0000-0000-000000000008','10000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000008','20000000-0000-0000-0000-000000000001',false,'active'),
 ('30000000-0000-0000-0000-000000000009','10000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000009','20000000-0000-0000-0000-000000000001',false,'active'),
 ('30000000-0000-0000-0000-000000000010','10000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000010',null,true,'active');
-- Proposed permission catalogue entry; deliberately no default role mapping.
INSERT INTO hasad.permissions VALUES ('products.read','products');
INSERT INTO hasad.role_permissions VALUES
 ('20000000-0000-0000-0000-000000000001','products.read'),
 ('20000000-0000-0000-0000-000000000002','products.read');
INSERT INTO hasad.user_permission_overrides VALUES
 ('30000000-0000-0000-0000-000000000008','products.read','deny'),
 ('30000000-0000-0000-0000-000000000009','products.read','allow');
INSERT INTO hasad.products(id,company_id,code,name_ar,base_uom_id) VALUES
 ('40000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','A1','منتج ألف','50000000-0000-0000-0000-000000000001'),
 ('40000000-0000-0000-0000-000000000002','10000000-0000-0000-0000-000000000002','B1','منتج باء','50000000-0000-0000-0000-000000000002');
