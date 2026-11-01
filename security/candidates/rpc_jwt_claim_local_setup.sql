-- Synthetic-only fixture additions for the JWT-claim RPC regression harness.
ALTER ROLE hasad_rpc_owner NOINHERIT;
CREATE TABLE auth.users(id uuid PRIMARY KEY);

CREATE FUNCTION hasad.has_permission(
  p_membership_id uuid,p_role_id uuid,p_is_owner boolean,p_permission_code text
) RETURNS boolean
LANGUAGE sql STABLE SECURITY INVOKER SET search_path=pg_catalog,pg_temp
AS $$
  SELECT CASE
    WHEN p_is_owner THEN true
    WHEN EXISTS (SELECT 1 FROM hasad.user_permission_overrides o
      WHERE o.membership_id=p_membership_id AND o.permission_code=p_permission_code AND o.effect='deny')
      THEN false
    WHEN EXISTS (SELECT 1 FROM hasad.user_permission_overrides o
      WHERE o.membership_id=p_membership_id AND o.permission_code=p_permission_code AND o.effect='allow')
      THEN true
    ELSE EXISTS (SELECT 1 FROM hasad.role_permissions rp
      WHERE rp.role_id=p_role_id AND rp.permission_code=p_permission_code)
  END
$$;
ALTER FUNCTION hasad.has_permission(uuid,uuid,boolean,text) OWNER TO hasad_rpc_owner;
REVOKE ALL ON FUNCTION hasad.has_permission(uuid,uuid,boolean,text) FROM PUBLIC,anon,authenticated;

DO $fixture_tables$
DECLARE i integer;
BEGIN
  FOR i IN 1..38 LOOP
    EXECUTE pg_catalog.format('CREATE TABLE hasad.jwt_rls_fixture_%s (id integer)',i);
    EXECUTE pg_catalog.format('ALTER TABLE hasad.jwt_rls_fixture_%s ENABLE ROW LEVEL SECURITY',i);
    EXECUTE pg_catalog.format('ALTER TABLE hasad.jwt_rls_fixture_%s FORCE ROW LEVEL SECURITY',i);
  END LOOP;
END
$fixture_tables$;
