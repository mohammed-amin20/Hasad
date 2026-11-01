-- Local-only stand-in for the already-approved direct company/product read
-- candidate, limited to what the Unit S1 read policy and preflight require.
GRANT USAGE ON SCHEMA hasad TO authenticated;
GRANT SELECT (company_id, user_id, status)
  ON hasad.company_memberships TO authenticated;
GRANT SELECT (id, status) ON hasad.companies TO authenticated;

CREATE POLICY harness_authenticated_memberships_read
  ON hasad.company_memberships FOR SELECT TO authenticated
  USING (user_id = auth.uid() AND status = 'active');

CREATE POLICY harness_authenticated_companies_read
  ON hasad.companies FOR SELECT TO authenticated
  USING (
    status = 'active'
    AND EXISTS (
      SELECT 1 FROM hasad.company_memberships cm
      WHERE cm.company_id = companies.id
        AND cm.user_id = auth.uid()
        AND cm.status = 'active'
    )
  );
