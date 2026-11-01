-- Hasad ERP V2 / Unit S2 — DEV review candidate, NOT DEPLOYED
-- Atomic draft only: no stock, stock movement, journal, document number, or posting.
-- Requires PostgreSQL 17 role SET OPTION; never uses hasad_rpc_owner or grants
-- the restricted owner USAGE on auth. auth.uid() appears only in authenticated
-- read policies, never in a SECURITY DEFINER function.
BEGIN;

DO $preflight$
DECLARE v_missing text;
BEGIN
  SELECT string_agg(t, ', ' ORDER BY t) INTO v_missing
  FROM (VALUES ('sales_documents'),('sales_document_lines'),('parties'),
               ('products'),('warehouses'),('document_types'),('fiscal_years'),
               ('companies'),('company_memberships'),('roles'),('permissions'),
               ('role_permissions'),('user_permission_overrides'),('audit_log')) q(t)
  WHERE pg_catalog.to_regclass('hasad.' || t) IS NULL;
  IF v_missing IS NOT NULL THEN RAISE EXCEPTION 'PREFLIGHT_MISSING_TABLES: %', v_missing; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_roles WHERE rolname=current_user AND (rolsuper OR rolcreaterole)) THEN
    RAISE EXCEPTION 'PREFLIGHT_NO_ROLE_ADMIN';
  END IF;
  IF NOT pg_catalog.has_schema_privilege(current_user, 'hasad', 'CREATE') THEN
    RAISE EXCEPTION 'PREFLIGHT_NO_SCHEMA_CREATE';
  END IF;
  IF EXISTS (
    SELECT 1 FROM pg_catalog.pg_class c JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace
    WHERE n.nspname='hasad' AND c.relname IN ('sales_documents','sales_document_lines','parties','products','warehouses','document_types','fiscal_years','companies','company_memberships','roles','permissions','role_permissions','user_permission_overrides','audit_log')
      AND (NOT c.relrowsecurity OR NOT c.relforcerowsecurity OR pg_catalog.pg_get_userbyid(c.relowner) <> current_user)
  ) THEN RAISE EXCEPTION 'PREFLIGHT_FORCE_RLS_OR_OWNERSHIP'; END IF;
  IF NOT EXISTS (SELECT 1 FROM hasad.permissions WHERE code='sales.create' AND module='sales') THEN
    RAISE EXCEPTION 'PREFLIGHT_SALES_CREATE_MISSING';
  END IF;
  -- Authenticated sales read policies evaluate the already-installed active
  -- membership/company read surface; do not create a duplicate broad policy.
  IF NOT pg_catalog.has_column_privilege('authenticated','hasad.company_memberships','company_id','SELECT')
     OR NOT pg_catalog.has_column_privilege('authenticated','hasad.company_memberships','user_id','SELECT')
     OR NOT pg_catalog.has_column_privilege('authenticated','hasad.company_memberships','status','SELECT')
     OR NOT pg_catalog.has_column_privilege('authenticated','hasad.companies','id','SELECT')
     OR NOT pg_catalog.has_column_privilege('authenticated','hasad.companies','status','SELECT') THEN
    RAISE EXCEPTION 'PREFLIGHT_AUTHENTICATED_CONTEXT_READ_MISSING';
  END IF;
END $preflight$;

DO $rolesetup$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_roles WHERE rolname='hasad_sales_draft_writer') THEN
    CREATE ROLE hasad_sales_draft_writer NOLOGIN NOINHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS;
  END IF;
  IF EXISTS (SELECT 1 FROM pg_catalog.pg_roles WHERE rolname='hasad_sales_draft_writer'
    AND (rolcanlogin OR rolsuper OR rolcreatedb OR rolcreaterole OR rolreplication OR rolbypassrls)) THEN
    RAISE EXCEPTION 'PREFLIGHT_SALES_WRITER_UNSAFE';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_catalog.pg_auth_members m JOIN pg_catalog.pg_roles r ON r.oid=m.member
    WHERE m.roleid=(SELECT oid FROM pg_catalog.pg_roles WHERE rolname='hasad_sales_draft_writer')
      AND r.rolname IN ('authenticated','anon')) THEN
    RAISE EXCEPTION 'PREFLIGHT_SALES_WRITER_GRANTED_TO_CLIENT';
  END IF;
  IF NOT pg_catalog.pg_has_role(current_user, 'hasad_sales_draft_writer', 'SET') THEN
    BEGIN
      EXECUTE pg_catalog.format('GRANT hasad_sales_draft_writer TO %I WITH SET OPTION', current_user);
    EXCEPTION WHEN insufficient_privilege THEN
      RAISE EXCEPTION 'PREFLIGHT_SALES_WRITER_SET_NOT_GRANTABLE';
    END;
  END IF;
  IF NOT pg_catalog.pg_has_role(current_user, 'hasad_sales_draft_writer', 'SET') THEN
    RAISE EXCEPTION 'PREFLIGHT_SALES_WRITER_SET_MISSING';
  END IF;
END $rolesetup$;

GRANT USAGE ON SCHEMA hasad TO hasad_sales_draft_writer, authenticated;
GRANT SELECT (id,company_id,user_id,role_id,is_owner,status) ON hasad.company_memberships TO hasad_sales_draft_writer;
GRANT SELECT (id,status) ON hasad.companies TO hasad_sales_draft_writer;
GRANT SELECT (id,company_id) ON hasad.roles TO hasad_sales_draft_writer;
GRANT SELECT (code,module) ON hasad.permissions TO hasad_sales_draft_writer;
GRANT SELECT (role_id,permission_code) ON hasad.role_permissions TO hasad_sales_draft_writer;
GRANT SELECT (membership_id,permission_code,effect) ON hasad.user_permission_overrides TO hasad_sales_draft_writer;
GRANT SELECT (id,company_id,is_customer,is_active) ON hasad.parties TO hasad_sales_draft_writer;
GRANT SELECT (id,company_id,track_inventory,is_active) ON hasad.products TO hasad_sales_draft_writer;
GRANT SELECT (id,company_id,is_active) ON hasad.warehouses TO hasad_sales_draft_writer;
GRANT SELECT (id,company_id,code,issuance,is_active) ON hasad.document_types TO hasad_sales_draft_writer;
GRANT SELECT (id,company_id,start_date,end_date) ON hasad.fiscal_years TO hasad_sales_draft_writer;
GRANT SELECT, INSERT, UPDATE ON hasad.sales_documents TO hasad_sales_draft_writer;
GRANT SELECT, INSERT, DELETE ON hasad.sales_document_lines TO hasad_sales_draft_writer;
GRANT INSERT (id,company_id,actor_user_id,action,entity_type,entity_id,details) ON hasad.audit_log TO hasad_sales_draft_writer;
-- Authenticated users receive tenant-scoped read-only invoice access only.
GRANT SELECT (id,company_id,doc_kind,status,party_id,doc_date,vat_mode,doc_type_id,fiscal_year_id,doc_no,idempotency_key,net,tax,gross,posted_at,posted_by) ON hasad.sales_documents TO authenticated;
GRANT SELECT (id,company_id,document_id,line_no,product_id,warehouse_id,qty,unit_price,discount_amount,tax_rate,net,tax,gross,order_line_id,original_line_id) ON hasad.sales_document_lines TO authenticated;

CREATE FUNCTION hasad.sales_request_actor_user_id() RETURNS uuid
LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE v_claims text:=NULLIF(current_setting('request.jwt.claims',true),''); v_sub text;
BEGIN
  IF v_claims IS NULL THEN RETURN NULL; END IF;
  BEGIN v_sub:=(v_claims::jsonb)->>'sub'; EXCEPTION WHEN others THEN RAISE EXCEPTION 'UNAUTHORIZED' USING ERRCODE='28000'; END;
  IF v_sub IS NULL OR v_sub !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$' THEN
    RAISE EXCEPTION 'UNAUTHORIZED' USING ERRCODE='28000';
  END IF;
  RETURN v_sub::uuid;
END $fn$;
REVOKE ALL ON FUNCTION hasad.sales_request_actor_user_id() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION hasad.sales_request_actor_user_id() TO hasad_sales_draft_writer;

CREATE FUNCTION hasad.sales_draft_allowed(p_company_id uuid) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
  SELECT EXISTS (
    SELECT 1 FROM hasad.company_memberships cm
    JOIN hasad.companies c ON c.id=cm.company_id AND c.status='active'
    JOIN hasad.permissions p ON p.code='sales.create' AND p.module='sales'
    LEFT JOIN hasad.user_permission_overrides uo ON uo.membership_id=cm.id AND uo.permission_code=p.code
    WHERE cm.company_id=p_company_id AND cm.user_id=hasad.sales_request_actor_user_id() AND cm.status='active'
      AND (cm.is_owner OR (uo.effect IS DISTINCT FROM 'deny' AND (uo.effect='allow' OR EXISTS (
        SELECT 1 FROM hasad.role_permissions rp JOIN hasad.roles r ON r.id=rp.role_id AND r.company_id=cm.company_id
        WHERE rp.role_id=cm.role_id AND rp.permission_code=p.code)))));
$fn$;
REVOKE ALL ON FUNCTION hasad.sales_draft_allowed(uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION hasad.sales_draft_allowed(uuid) TO authenticated;

CREATE POLICY hasad_sales_writer_memberships_read ON hasad.company_memberships FOR SELECT TO hasad_sales_draft_writer USING (user_id=hasad.sales_request_actor_user_id());
CREATE POLICY hasad_sales_writer_companies_read ON hasad.companies FOR SELECT TO hasad_sales_draft_writer USING (true);
CREATE POLICY hasad_sales_writer_roles_read ON hasad.roles FOR SELECT TO hasad_sales_draft_writer USING (true);
CREATE POLICY hasad_sales_writer_permissions_read ON hasad.permissions FOR SELECT TO hasad_sales_draft_writer USING (code='sales.create' AND module='sales');
CREATE POLICY hasad_sales_writer_role_permissions_read ON hasad.role_permissions FOR SELECT TO hasad_sales_draft_writer USING (permission_code='sales.create');
CREATE POLICY hasad_sales_writer_overrides_read ON hasad.user_permission_overrides FOR SELECT TO hasad_sales_draft_writer USING (permission_code='sales.create');
CREATE POLICY hasad_sales_writer_parties_read ON hasad.parties FOR SELECT TO hasad_sales_draft_writer USING (hasad.sales_draft_allowed(company_id));
CREATE POLICY hasad_sales_writer_products_read ON hasad.products FOR SELECT TO hasad_sales_draft_writer USING (hasad.sales_draft_allowed(company_id));
CREATE POLICY hasad_sales_writer_warehouses_read ON hasad.warehouses FOR SELECT TO hasad_sales_draft_writer USING (hasad.sales_draft_allowed(company_id));
CREATE POLICY hasad_sales_writer_document_types_read ON hasad.document_types FOR SELECT TO hasad_sales_draft_writer USING (hasad.sales_draft_allowed(company_id) AND code='SI' AND issuance='posting');
CREATE POLICY hasad_sales_writer_fiscal_years_read ON hasad.fiscal_years FOR SELECT TO hasad_sales_draft_writer USING (hasad.sales_draft_allowed(company_id));
CREATE POLICY hasad_sales_writer_documents_write ON hasad.sales_documents FOR ALL TO hasad_sales_draft_writer USING (hasad.sales_draft_allowed(company_id)) WITH CHECK (hasad.sales_draft_allowed(company_id));
CREATE POLICY hasad_sales_writer_lines_write ON hasad.sales_document_lines FOR ALL TO hasad_sales_draft_writer USING (hasad.sales_draft_allowed(company_id)) WITH CHECK (hasad.sales_draft_allowed(company_id));
CREATE POLICY hasad_sales_writer_audit_insert ON hasad.audit_log FOR INSERT TO hasad_sales_draft_writer WITH CHECK (actor_user_id=hasad.sales_request_actor_user_id());
CREATE POLICY direct_authenticated_sales_documents_read ON hasad.sales_documents FOR SELECT TO authenticated USING (EXISTS (
  SELECT 1 FROM hasad.company_memberships cm JOIN hasad.companies c ON c.id=cm.company_id AND c.status='active'
  WHERE cm.company_id=sales_documents.company_id AND cm.user_id=auth.uid() AND cm.status='active'));
CREATE POLICY direct_authenticated_sales_document_lines_read ON hasad.sales_document_lines FOR SELECT TO authenticated USING (EXISTS (
  SELECT 1 FROM hasad.company_memberships cm JOIN hasad.companies c ON c.id=cm.company_id AND c.status='active'
  WHERE cm.company_id=sales_document_lines.company_id AND cm.user_id=auth.uid() AND cm.status='active'));

CREATE FUNCTION hasad.save_sales_invoice_draft(
  p_document_id uuid, p_company_id uuid, p_party_id uuid, p_doc_date date,
  p_vat_mode text, p_document_type_id uuid, p_fiscal_year_id uuid,
  p_idempotency_key uuid, p_lines jsonb
) RETURNS hasad.sales_documents
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE v_actor uuid:=hasad.sales_request_actor_user_id(); v_doc hasad.sales_documents%ROWTYPE;
  v_existing uuid; v_count integer; v_distinct integer; v_min integer; v_max integer; v_created boolean:=false;
BEGIN
  IF v_actor IS NULL OR NOT hasad.sales_draft_allowed(p_company_id) THEN RAISE EXCEPTION 'PERMISSION_DENIED' USING ERRCODE='42501'; END IF;
  IF p_document_id IS NULL OR p_party_id IS NULL OR p_doc_date IS NULL OR p_document_type_id IS NULL OR p_fiscal_year_id IS NULL OR p_idempotency_key IS NULL OR p_vat_mode NOT IN ('inclusive','exclusive') OR jsonb_typeof(p_lines) IS DISTINCT FROM 'array' THEN
    RAISE EXCEPTION 'DRAFT_INPUT_INVALID' USING ERRCODE='23514';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM hasad.parties WHERE id=p_party_id AND company_id=p_company_id AND is_customer AND is_active)
     OR NOT EXISTS (SELECT 1 FROM hasad.document_types WHERE id=p_document_type_id AND company_id=p_company_id AND code='SI' AND issuance='posting' AND is_active)
     OR NOT EXISTS (SELECT 1 FROM hasad.fiscal_years WHERE id=p_fiscal_year_id AND company_id=p_company_id AND p_doc_date BETWEEN start_date AND end_date) THEN
    RAISE EXCEPTION 'DRAFT_REFERENCE_INVALID' USING ERRCODE='23514';
  END IF;
  SELECT count(*),count(DISTINCT line_no),min(line_no),max(line_no) INTO v_count,v_distinct,v_min,v_max
  FROM jsonb_to_recordset(p_lines) AS x(line_no integer);
  IF v_count=0 OR v_count<>v_distinct OR v_min<>1 OR v_max<>v_count THEN RAISE EXCEPTION 'DRAFT_LINES_INVALID' USING ERRCODE='23514'; END IF;
  IF EXISTS (SELECT 1 FROM jsonb_to_recordset(p_lines) AS x(id uuid,line_no integer,product_id uuid,warehouse_id uuid,qty numeric,unit_price numeric,discount_amount numeric,tax_rate numeric)
    WHERE id IS NULL OR qty IS NULL OR unit_price IS NULL OR discount_amount IS NULL OR tax_rate IS NULL
       OR qty<=0 OR unit_price<0 OR discount_amount<0 OR tax_rate<0
       OR qty<>trunc(qty,4) OR unit_price<>trunc(unit_price,4) OR discount_amount<>trunc(discount_amount,2) OR tax_rate<>trunc(tax_rate,3)
       OR round(qty*unit_price-discount_amount,2)<0) THEN RAISE EXCEPTION 'DRAFT_LINE_AMOUNT_INVALID' USING ERRCODE='23514'; END IF;
  IF EXISTS (SELECT 1 FROM jsonb_to_recordset(p_lines) AS x(product_id uuid,warehouse_id uuid)
    LEFT JOIN hasad.products p ON p.id=x.product_id AND p.company_id=p_company_id
    LEFT JOIN hasad.warehouses w ON w.id=x.warehouse_id AND w.company_id=p_company_id
    WHERE (x.product_id IS NOT NULL AND (p.id IS NULL OR NOT p.is_active))
       OR (x.warehouse_id IS NOT NULL AND (w.id IS NULL OR NOT w.is_active))
       OR (p.track_inventory AND x.warehouse_id IS NULL)) THEN RAISE EXCEPTION 'DRAFT_LINE_REFERENCE_INVALID' USING ERRCODE='23514'; END IF;
  SELECT * INTO v_doc FROM hasad.sales_documents WHERE id=p_document_id AND company_id=p_company_id FOR UPDATE;
  IF FOUND THEN
    IF v_doc.status<>'draft' OR v_doc.doc_kind<>'invoice' THEN RAISE EXCEPTION 'DRAFT_NOT_EDITABLE' USING ERRCODE='23514'; END IF;
    IF v_doc.idempotency_key IS DISTINCT FROM p_idempotency_key THEN RAISE EXCEPTION 'IDEMPOTENCY_MISMATCH' USING ERRCODE='23505'; END IF;
    UPDATE hasad.sales_documents SET party_id=p_party_id,doc_date=p_doc_date,vat_mode=p_vat_mode,doc_type_id=p_document_type_id,fiscal_year_id=p_fiscal_year_id WHERE id=p_document_id AND company_id=p_company_id;
  ELSE
    SELECT id INTO v_existing FROM hasad.sales_documents WHERE company_id=p_company_id AND idempotency_key=p_idempotency_key FOR UPDATE;
    IF FOUND THEN RAISE EXCEPTION 'IDEMPOTENCY_MISMATCH' USING ERRCODE='23505'; END IF;
    INSERT INTO hasad.sales_documents(id,company_id,doc_kind,status,party_id,doc_date,vat_mode,doc_type_id,fiscal_year_id,idempotency_key,net,tax,gross)
    VALUES(p_document_id,p_company_id,'invoice','draft',p_party_id,p_doc_date,p_vat_mode,p_document_type_id,p_fiscal_year_id,p_idempotency_key,0,0,0);
    v_created:=true;
  END IF;
  DELETE FROM hasad.sales_document_lines WHERE company_id=p_company_id AND document_id=p_document_id;
  INSERT INTO hasad.sales_document_lines(id,company_id,document_id,line_no,product_id,warehouse_id,qty,unit_price,discount_amount,tax_rate,net,tax,gross)
  SELECT x.id,p_company_id,p_document_id,x.line_no,x.product_id,x.warehouse_id,x.qty,x.unit_price,x.discount_amount,x.tax_rate,
    CASE WHEN p_vat_mode='exclusive' THEN round(x.qty*x.unit_price-x.discount_amount,2) ELSE round(round(x.qty*x.unit_price-x.discount_amount,2)/(1+x.tax_rate/100),2) END,
    CASE WHEN p_vat_mode='exclusive' THEN round(round(x.qty*x.unit_price-x.discount_amount,2)*x.tax_rate/100,2) ELSE round(x.qty*x.unit_price-x.discount_amount,2)-round(round(x.qty*x.unit_price-x.discount_amount,2)/(1+x.tax_rate/100),2) END,
    CASE WHEN p_vat_mode='exclusive' THEN round(x.qty*x.unit_price-x.discount_amount,2)+round(round(x.qty*x.unit_price-x.discount_amount,2)*x.tax_rate/100,2) ELSE round(x.qty*x.unit_price-x.discount_amount,2) END
  FROM jsonb_to_recordset(p_lines) AS x(id uuid,line_no integer,product_id uuid,warehouse_id uuid,qty numeric,unit_price numeric,discount_amount numeric,tax_rate numeric);
  UPDATE hasad.sales_documents d SET net=s.net,tax=s.tax,gross=s.gross FROM (SELECT coalesce(sum(net),0) net,coalesce(sum(tax),0) tax,coalesce(sum(gross),0) gross FROM hasad.sales_document_lines WHERE company_id=p_company_id AND document_id=p_document_id) s WHERE d.id=p_document_id AND d.company_id=p_company_id RETURNING d.* INTO v_doc;
  INSERT INTO hasad.audit_log(id,company_id,actor_user_id,action,entity_type,entity_id,details)
  VALUES(pg_catalog.gen_random_uuid(),p_company_id,v_actor,CASE WHEN v_created THEN 'sale.draft_created' ELSE 'sale.draft_updated' END,'sales_document',p_document_id,pg_catalog.jsonb_build_object('doc_kind','invoice','status','draft','line_count',v_count,'net',v_doc.net,'tax',v_doc.tax,'gross',v_doc.gross));
  RETURN v_doc;
END $fn$;
REVOKE ALL ON FUNCTION hasad.save_sales_invoice_draft(uuid,uuid,uuid,date,text,uuid,uuid,uuid,jsonb) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION hasad.save_sales_invoice_draft(uuid,uuid,uuid,date,text,uuid,uuid,uuid,jsonb) TO authenticated;

GRANT CREATE ON SCHEMA hasad TO hasad_sales_draft_writer;
ALTER FUNCTION hasad.sales_request_actor_user_id() OWNER TO hasad_sales_draft_writer;
ALTER FUNCTION hasad.sales_draft_allowed(uuid) OWNER TO hasad_sales_draft_writer;
ALTER FUNCTION hasad.save_sales_invoice_draft(uuid,uuid,uuid,date,text,uuid,uuid,uuid,jsonb) OWNER TO hasad_sales_draft_writer;
REVOKE CREATE ON SCHEMA hasad FROM hasad_sales_draft_writer;

DO $postflight$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_roles WHERE rolname='hasad_sales_draft_writer' AND NOT rolcanlogin AND NOT rolinherit AND NOT rolsuper AND NOT rolcreaterole AND NOT rolcreatedb AND NOT rolreplication AND NOT rolbypassrls) THEN RAISE EXCEPTION 'POSTFLIGHT_WRITER_ATTRIBUTES'; END IF;
  IF pg_catalog.has_schema_privilege('hasad_sales_draft_writer','hasad','CREATE') THEN RAISE EXCEPTION 'POSTFLIGHT_WRITER_CREATE_RETAINED'; END IF;
  IF EXISTS (SELECT 1 FROM pg_catalog.pg_class c JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='hasad' AND c.relname IN ('sales_documents','sales_document_lines') AND (NOT c.relrowsecurity OR NOT c.relforcerowsecurity)) THEN RAISE EXCEPTION 'POSTFLIGHT_FORCE_RLS'; END IF;
END $postflight$;
COMMIT;
NOTIFY pgrst, 'reload schema';
