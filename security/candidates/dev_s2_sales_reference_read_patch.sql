-- Hasad ERP V2 / S2 — DEV REVIEW-ONLY patch, NOT DEPLOYED
-- Scope: authenticated same-company SELECT only for document_types/fiscal_years.
-- No write privilege, role, stock, invoice, numbering, or data mutation.
BEGIN;
DO $preflight$
BEGIN
  IF pg_catalog.to_regclass('hasad.document_types') IS NULL
     OR pg_catalog.to_regclass('hasad.fiscal_years') IS NULL THEN
    RAISE EXCEPTION 'PREFLIGHT_REFERENCE_TABLE_MISSING';
  END IF;
  IF EXISTS (
    SELECT 1 FROM pg_catalog.pg_class c JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace
    WHERE n.nspname='hasad' AND c.relname IN ('document_types','fiscal_years')
      AND (NOT c.relrowsecurity OR NOT c.relforcerowsecurity)
  ) THEN RAISE EXCEPTION 'PREFLIGHT_FORCE_RLS'; END IF;
  IF EXISTS (
    SELECT 1 FROM pg_catalog.pg_policy
    WHERE polname IN ('direct_authenticated_document_types_read','direct_authenticated_fiscal_years_read')
  ) THEN RAISE EXCEPTION 'PREFLIGHT_POLICY_NAME_COLLISION'; END IF;
  IF pg_catalog.has_table_privilege('authenticated','hasad.document_types','INSERT,UPDATE,DELETE')
     OR pg_catalog.has_table_privilege('authenticated','hasad.fiscal_years','INSERT,UPDATE,DELETE')
     OR pg_catalog.has_any_column_privilege('authenticated','hasad.document_types','INSERT,UPDATE')
     OR pg_catalog.has_any_column_privilege('authenticated','hasad.fiscal_years','INSERT,UPDATE') THEN
    RAISE EXCEPTION 'PREFLIGHT_EXISTING_AUTHENTICATED_WRITE';
  END IF;
  IF NOT pg_catalog.has_column_privilege('authenticated','hasad.company_memberships','company_id','SELECT')
     OR NOT pg_catalog.has_column_privilege('authenticated','hasad.company_memberships','user_id','SELECT')
     OR NOT pg_catalog.has_column_privilege('authenticated','hasad.company_memberships','status','SELECT')
     OR NOT pg_catalog.has_column_privilege('authenticated','hasad.companies','id','SELECT')
     OR NOT pg_catalog.has_column_privilege('authenticated','hasad.companies','status','SELECT') THEN
    RAISE EXCEPTION 'PREFLIGHT_AUTH_CONTEXT_READ_MISSING';
  END IF;
END
$preflight$;

GRANT USAGE ON SCHEMA hasad TO authenticated;
GRANT SELECT (id,company_id,code,name_ar,issuance,is_active)
  ON hasad.document_types TO authenticated;
GRANT SELECT (id,company_id,start_date,end_date,status)
  ON hasad.fiscal_years TO authenticated;

CREATE POLICY direct_authenticated_document_types_read
  ON hasad.document_types FOR SELECT TO authenticated
  USING (EXISTS (
    SELECT 1 FROM hasad.company_memberships cm
    JOIN hasad.companies c ON c.id=cm.company_id AND c.status='active'
    WHERE cm.company_id=document_types.company_id
      AND cm.user_id=auth.uid() AND cm.status='active'
  ));
CREATE POLICY direct_authenticated_fiscal_years_read
  ON hasad.fiscal_years FOR SELECT TO authenticated
  USING (EXISTS (
    SELECT 1 FROM hasad.company_memberships cm
    JOIN hasad.companies c ON c.id=cm.company_id AND c.status='active'
    WHERE cm.company_id=fiscal_years.company_id
      AND cm.user_id=auth.uid() AND cm.status='active'
  ));

DO $postflight$
BEGIN
  IF pg_catalog.has_table_privilege('authenticated','hasad.document_types','INSERT,UPDATE,DELETE')
     OR pg_catalog.has_table_privilege('authenticated','hasad.fiscal_years','INSERT,UPDATE,DELETE')
     OR NOT pg_catalog.has_column_privilege('authenticated','hasad.document_types','code','SELECT')
     OR NOT pg_catalog.has_column_privilege('authenticated','hasad.fiscal_years','status','SELECT') THEN
    RAISE EXCEPTION 'POSTFLIGHT_READ_ONLY_BOUNDARY';
  END IF;
END
$postflight$;
COMMIT;
NOTIFY pgrst, 'reload schema';
