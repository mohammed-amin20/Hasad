-- Hasad ERP V2 / Unit S3 — REVIEW ONLY, NOT DEPLOYED, NOT DEPLOYABLE YET
-- Atomic sales invoice posting for the DEV direct Data API surface (`hasad`).
--
-- ONE server transaction: permission + tenant checks, document row lock, full
-- reference/totals/tax-rate validation, per-product advisory locks, stock row
-- locks, aggregated availability check, moving-weighted-average issue writes,
-- official invoice number, posted journal entry, invoice status flip, audit
-- records, idempotent replay. Any failure rolls back everything.
--
-- HARD BLOCKERS BEFORE DEPLOYMENT (owner decisions, not implementation gaps):
--   1. Accounting posting is NOT approved. `docs/features/06_sales_and_invoicing.md`
--      is DRAFT and `docs/09_ACCOUNTING_INVARIANTS.md` is PROPOSED. This file
--      implements the documented *proposed* matrix so the mechanism can be
--      reviewed and tested locally, but it refuses to post unless real, active
--      `sales` account mappings, an OPEN fiscal period covering the document
--      date, and a JE numbering document type all exist. The candidate never
--      creates accounts, mappings, periods or tax rows and fails closed with
--      `ACCOUNTING_PREREQUISITES_MISSING` when they are absent.
--   2. OWNER-APPROVED numbering design: `SI-YYYY-0001` and `JE-YYYY-0001`,
--      with the year taken from the selected fiscal year's start date, never
--      from the server clock. A non-empty type prefix is mandatory to keep
--      company-wide `sales_documents.doc_no` values unique across annual resets.
--   3. The journal-entry numbering document type code is an OPEN DEPENDENCY.
--      This candidate requires a company row `code = 'JE'`,
--      `issuance='posting'`, `is_active`. No JE type is seeded by this file.
--   4. VAT rate resolution requires an effective-dated `hasad.tax_rates` row
--      matching each non-zero line rate. No statutory rate is invented or
--      seeded; `tax_rates` is currently empty and D-023 is OPEN.
--   5. `hasad.post_sales_invoice` reuses the invoice's own `idempotency_key`
--      (written by `save_sales_invoice_draft`). No new column is created.
--
-- Rejected alternative: "inventory-only posting". A posted invoice with stock
-- issued but no journal entry is an incomplete financial record that cannot be
-- completed later, because posted rows are immutable and corrections must be
-- linked reversals. Therefore this candidate never offers that mode.
--
-- Security design mirrors the deployed S2 draft candidate:
--   * dedicated NOLOGIN / NOINHERIT / NOSUPERUSER / NOCREATEDB / NOCREATEROLE /
--     NOREPLICATION / NOBYPASSRLS owner `hasad_sales_poster`;
--   * owner receives narrow column grants and role-scoped policies only;
--   * FORCE RLS stays enabled on every table;
--   * actor identity comes from `request.jwt.claims`, never a parameter;
--   * every function pins `search_path = pg_catalog, pg_temp` and fully
--     schema-qualifies relations.
--
-- This file supersedes the precondition note in
-- `dev_sales_invoice_posting_atomic_candidate.sql` (kept as the blocker record).

BEGIN;

DO $preflight$
DECLARE v_missing text; v_bad text;
BEGIN
  SELECT string_agg(t, ', ' ORDER BY t) INTO v_missing
  FROM (VALUES
    ('sales_documents'),('sales_document_lines'),('parties'),('products'),
    ('warehouses'),('document_types'),('fiscal_years'),('fiscal_periods'),
    ('accounts'),('module_account_map'),('tax_rates'),('doc_numbers'),
    ('journal_entries'),('journal_lines'),('stock_levels'),('stock_movements'),
    ('companies'),('company_memberships'),('roles'),('permissions'),
    ('role_permissions'),('user_permission_overrides'),('audit_log')
  ) q(t)
  WHERE pg_catalog.to_regclass('hasad.' || t) IS NULL;
  IF v_missing IS NOT NULL THEN
    RAISE EXCEPTION 'PREFLIGHT_MISSING_TABLES: %', v_missing;
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

  SELECT string_agg(c.relname, ', ' ORDER BY c.relname) INTO v_bad
  FROM pg_catalog.pg_class c
  JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'hasad'
    AND c.relname IN (
      'sales_documents','sales_document_lines','parties','products',
      'warehouses','document_types','fiscal_years','fiscal_periods',
      'accounts','module_account_map','tax_rates','doc_numbers',
      'journal_entries','journal_lines','stock_levels','stock_movements',
      'companies','company_memberships','roles','permissions',
      'role_permissions','user_permission_overrides','audit_log'
    )
    AND (
      NOT c.relrowsecurity
      OR NOT c.relforcerowsecurity
      OR pg_catalog.pg_get_userbyid(c.relowner) <> current_user
    );
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'PREFLIGHT_FORCE_RLS_OR_OWNERSHIP: %', v_bad;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM hasad.permissions WHERE code = 'sales.post' AND module = 'sales'
  ) THEN
    RAISE EXCEPTION 'PREFLIGHT_SALES_POST_PERMISSION_MISSING';
  END IF;

  IF EXISTS (
    SELECT 1 FROM pg_catalog.pg_proc p
    JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'hasad'
      AND p.proname IN (
        'sales_posting_actor_id', 'sales_posting_allowed',
        'allocate_document_number', 'post_sales_invoice'
      )
  ) THEN
    RAISE EXCEPTION 'PREFLIGHT_S3_FUNCTION_ALREADY_EXISTS';
  END IF;
END
$preflight$;

-- Dedicated locked owner for invoice posting only.
DO $rolesetup$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_roles WHERE rolname = 'hasad_sales_poster'
  ) THEN
    CREATE ROLE hasad_sales_poster
      NOLOGIN NOINHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE
      NOREPLICATION NOBYPASSRLS;
  END IF;

  IF EXISTS (
    SELECT 1 FROM pg_catalog.pg_roles
    WHERE rolname = 'hasad_sales_poster'
      AND (
        rolcanlogin OR rolsuper OR rolcreatedb OR rolcreaterole
        OR rolreplication OR rolbypassrls
      )
  ) THEN
    RAISE EXCEPTION 'PREFLIGHT_POSTER_ROLE_UNSAFE';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM pg_catalog.pg_auth_members m
    JOIN pg_catalog.pg_roles granted ON granted.oid = m.roleid
    JOIN pg_catalog.pg_roles member ON member.oid = m.member
    WHERE granted.rolname = 'hasad_sales_poster'
      AND member.rolname IN ('authenticated', 'anon')
  ) THEN
    RAISE EXCEPTION 'PREFLIGHT_POSTER_ROLE_GRANTED_TO_CLIENT';
  END IF;

  IF NOT pg_catalog.pg_has_role(current_user, 'hasad_sales_poster', 'SET') THEN
    BEGIN
      EXECUTE pg_catalog.format(
        'GRANT hasad_sales_poster TO %I WITH SET OPTION', current_user
      );
    EXCEPTION WHEN insufficient_privilege THEN
      RAISE EXCEPTION 'PREFLIGHT_POSTER_SET_NOT_GRANTABLE';
    END;
  END IF;
  IF NOT pg_catalog.pg_has_role(current_user, 'hasad_sales_poster', 'SET') THEN
    RAISE EXCEPTION 'PREFLIGHT_POSTER_SET_MISSING';
  END IF;
END
$rolesetup$;

GRANT USAGE ON SCHEMA hasad TO hasad_sales_poster, authenticated;

-- Narrow reads needed to re-derive permission, tenancy, references and state.
GRANT SELECT (id,company_id,user_id,role_id,is_owner,status)
  ON hasad.company_memberships TO hasad_sales_poster;
GRANT SELECT (id,status) ON hasad.companies TO hasad_sales_poster;
GRANT SELECT (id,company_id) ON hasad.roles TO hasad_sales_poster;
GRANT SELECT (code,module) ON hasad.permissions TO hasad_sales_poster;
GRANT SELECT (role_id,permission_code) ON hasad.role_permissions TO hasad_sales_poster;
GRANT SELECT (membership_id,permission_code,effect)
  ON hasad.user_permission_overrides TO hasad_sales_poster;
GRANT SELECT (id,company_id,is_customer,is_active) ON hasad.parties TO hasad_sales_poster;
GRANT SELECT (id,company_id,track_inventory,is_active) ON hasad.products TO hasad_sales_poster;
GRANT SELECT (id,company_id,is_active) ON hasad.warehouses TO hasad_sales_poster;
-- Full read of the three reference/detail tables is required because the
-- functions read whole rows (`%ROWTYPE`). Writes stay column-narrow below.
GRANT SELECT (id,company_id,code,name_ar,issuance,format_prefix,pad_length,is_active)
  ON hasad.document_types TO hasad_sales_poster;
GRANT SELECT (id,company_id,start_date,end_date,status)
  ON hasad.fiscal_years TO hasad_sales_poster;
GRANT SELECT (id,company_id,fiscal_year_id,period_no,start_date,end_date,status)
  ON hasad.fiscal_periods TO hasad_sales_poster;
GRANT SELECT (id,company_id,code,account_type,is_active) ON hasad.accounts TO hasad_sales_poster;
GRANT SELECT (id,company_id,module,account_role,account_id)
  ON hasad.module_account_map TO hasad_sales_poster;
GRANT SELECT (id,company_id,code,rate,valid_from,valid_to,is_active)
  ON hasad.tax_rates TO hasad_sales_poster;
GRANT SELECT (company_id,document_type_id,fiscal_year_id,next_value)
  ON hasad.doc_numbers TO hasad_sales_poster;
GRANT INSERT, UPDATE (next_value) ON hasad.doc_numbers TO hasad_sales_poster;
GRANT SELECT (id,company_id,doc_kind,status,party_id,doc_date,vat_mode,doc_type_id,
              fiscal_year_id,doc_no,original_document_id,idempotency_key,net,tax,
              gross,posted_at,posted_by)
  ON hasad.sales_documents TO hasad_sales_poster;
GRANT UPDATE (status,doc_no,posted_at,posted_by) ON hasad.sales_documents TO hasad_sales_poster;
GRANT SELECT (id,company_id,document_id,line_no,product_id,warehouse_id,qty,
              unit_price,discount_amount,tax_rate,net,tax,gross,order_line_id,
              original_line_id)
  ON hasad.sales_document_lines TO hasad_sales_poster;
GRANT SELECT (company_id,product_id,warehouse_id,qty,last_unit_cost)
  ON hasad.stock_levels TO hasad_sales_poster;
GRANT UPDATE (qty) ON hasad.stock_levels TO hasad_sales_poster;
GRANT SELECT (id,company_id,product_id,warehouse_id,movement_type,direction,qty,
              unit_cost,value,seq,source_document_type,source_document_id,
              journal_line_id,posted_at)
  ON hasad.stock_movements TO hasad_sales_poster;
GRANT INSERT ON hasad.stock_movements TO hasad_sales_poster;
GRANT SELECT (id,company_id,fiscal_year_id,period_id,entry_date,entry_kind,status,
              entry_no,reversal_of_id,idempotency_key,posted_at,posted_by,reason)
  ON hasad.journal_entries TO hasad_sales_poster;
GRANT INSERT ON hasad.journal_entries TO hasad_sales_poster;
GRANT SELECT (id,company_id,entry_id,line_no,account_id,party_id,debit,credit,description)
  ON hasad.journal_lines TO hasad_sales_poster;
GRANT INSERT ON hasad.journal_lines TO hasad_sales_poster;
GRANT INSERT (id,company_id,actor_user_id,action,entity_type,entity_id,details)
  ON hasad.audit_log TO hasad_sales_poster;

-- Actor identity from the trusted request context. Returns NULL (never raises)
-- so a policy with no JWT simply excludes every row.
CREATE FUNCTION hasad.sales_posting_actor_id() RETURNS uuid
LANGUAGE plpgsql STABLE SECURITY INVOKER
SET search_path = pg_catalog, pg_temp
AS $fn$
DECLARE
  v_claims text := NULLIF(current_setting('request.jwt.claims', true), '');
  v_sub text;
BEGIN
  IF v_claims IS NULL THEN RETURN NULL; END IF;
  BEGIN
    v_sub := (v_claims::jsonb)->>'sub';
  EXCEPTION WHEN others THEN
    RAISE EXCEPTION 'UNAUTHORIZED' USING ERRCODE = '28000';
  END;
  IF v_sub IS NULL
     OR v_sub !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
  THEN
    RAISE EXCEPTION 'UNAUTHORIZED' USING ERRCODE = '28000';
  END IF;
  RETURN v_sub::uuid;
END
$fn$;
REVOKE ALL ON FUNCTION hasad.sales_posting_actor_id() FROM PUBLIC, anon, authenticated;

-- `sales.post` gate: active membership + active company + owner OR effective
-- allow, with an explicit deny override winning.
CREATE FUNCTION hasad.sales_posting_allowed(p_company_id uuid) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $fn$
  SELECT EXISTS (
    SELECT 1
    FROM hasad.company_memberships cm
    JOIN hasad.companies c ON c.id = cm.company_id AND c.status = 'active'
    JOIN hasad.permissions p ON p.code = 'sales.post' AND p.module = 'sales'
    LEFT JOIN hasad.user_permission_overrides uo
      ON uo.membership_id = cm.id AND uo.permission_code = p.code
    WHERE cm.company_id = p_company_id
      AND cm.user_id = hasad.sales_posting_actor_id()
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
              JOIN hasad.roles r ON r.id = rp.role_id AND r.company_id = cm.company_id
              WHERE rp.role_id = cm.role_id AND rp.permission_code = p.code
            )
          )
        )
      )
  )
$fn$;
REVOKE ALL ON FUNCTION hasad.sales_posting_allowed(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION hasad.sales_posting_allowed(uuid) TO authenticated;

-- Owner-scoped policies. FORCE RLS stays on; every policy is restricted to the
-- locked poster role, which no client role can SET.
CREATE POLICY hasad_sales_poster_memberships_read ON hasad.company_memberships
  FOR SELECT TO hasad_sales_poster USING (user_id = hasad.sales_posting_actor_id());
CREATE POLICY hasad_sales_poster_companies_read ON hasad.companies
  FOR SELECT TO hasad_sales_poster USING (true);
CREATE POLICY hasad_sales_poster_roles_read ON hasad.roles
  FOR SELECT TO hasad_sales_poster USING (true);
CREATE POLICY hasad_sales_poster_permissions_read ON hasad.permissions
  FOR SELECT TO hasad_sales_poster
  USING (code = 'sales.post' AND module = 'sales');
CREATE POLICY hasad_sales_poster_role_permissions_read ON hasad.role_permissions
  FOR SELECT TO hasad_sales_poster USING (permission_code = 'sales.post');
CREATE POLICY hasad_sales_poster_overrides_read ON hasad.user_permission_overrides
  FOR SELECT TO hasad_sales_poster USING (permission_code = 'sales.post');
CREATE POLICY hasad_sales_poster_parties_read ON hasad.parties
  FOR SELECT TO hasad_sales_poster USING (hasad.sales_posting_allowed(company_id));
CREATE POLICY hasad_sales_poster_products_read ON hasad.products
  FOR SELECT TO hasad_sales_poster USING (hasad.sales_posting_allowed(company_id));
CREATE POLICY hasad_sales_poster_warehouses_read ON hasad.warehouses
  FOR SELECT TO hasad_sales_poster USING (hasad.sales_posting_allowed(company_id));
CREATE POLICY hasad_sales_poster_document_types_read ON hasad.document_types
  FOR SELECT TO hasad_sales_poster USING (hasad.sales_posting_allowed(company_id));
CREATE POLICY hasad_sales_poster_fiscal_years_read ON hasad.fiscal_years
  FOR SELECT TO hasad_sales_poster USING (hasad.sales_posting_allowed(company_id));
CREATE POLICY hasad_sales_poster_fiscal_periods_read ON hasad.fiscal_periods
  FOR SELECT TO hasad_sales_poster USING (hasad.sales_posting_allowed(company_id));
CREATE POLICY hasad_sales_poster_accounts_read ON hasad.accounts
  FOR SELECT TO hasad_sales_poster USING (hasad.sales_posting_allowed(company_id));
CREATE POLICY hasad_sales_poster_module_map_read ON hasad.module_account_map
  FOR SELECT TO hasad_sales_poster USING (hasad.sales_posting_allowed(company_id));
CREATE POLICY hasad_sales_poster_tax_rates_read ON hasad.tax_rates
  FOR SELECT TO hasad_sales_poster USING (hasad.sales_posting_allowed(company_id));
CREATE POLICY hasad_sales_poster_doc_numbers_all ON hasad.doc_numbers
  FOR ALL TO hasad_sales_poster
  USING (hasad.sales_posting_allowed(company_id))
  WITH CHECK (hasad.sales_posting_allowed(company_id));
CREATE POLICY hasad_sales_poster_documents_read ON hasad.sales_documents
  FOR SELECT TO hasad_sales_poster USING (hasad.sales_posting_allowed(company_id));
CREATE POLICY hasad_sales_poster_documents_update ON hasad.sales_documents
  FOR UPDATE TO hasad_sales_poster
  USING (hasad.sales_posting_allowed(company_id))
  WITH CHECK (hasad.sales_posting_allowed(company_id));
CREATE POLICY hasad_sales_poster_lines_read ON hasad.sales_document_lines
  FOR SELECT TO hasad_sales_poster USING (hasad.sales_posting_allowed(company_id));
CREATE POLICY hasad_sales_poster_stock_levels_read ON hasad.stock_levels
  FOR SELECT TO hasad_sales_poster USING (hasad.sales_posting_allowed(company_id));
CREATE POLICY hasad_sales_poster_stock_levels_update ON hasad.stock_levels
  FOR UPDATE TO hasad_sales_poster
  USING (hasad.sales_posting_allowed(company_id))
  WITH CHECK (hasad.sales_posting_allowed(company_id));
CREATE POLICY hasad_sales_poster_stock_movements_read ON hasad.stock_movements
  FOR SELECT TO hasad_sales_poster USING (hasad.sales_posting_allowed(company_id));
CREATE POLICY hasad_sales_poster_stock_movements_insert ON hasad.stock_movements
  FOR INSERT TO hasad_sales_poster
  WITH CHECK (hasad.sales_posting_allowed(company_id));
CREATE POLICY hasad_sales_poster_journal_entries_read ON hasad.journal_entries
  FOR SELECT TO hasad_sales_poster USING (hasad.sales_posting_allowed(company_id));
CREATE POLICY hasad_sales_poster_journal_entries_insert ON hasad.journal_entries
  FOR INSERT TO hasad_sales_poster
  WITH CHECK (hasad.sales_posting_allowed(company_id));
CREATE POLICY hasad_sales_poster_journal_lines_read ON hasad.journal_lines
  FOR SELECT TO hasad_sales_poster USING (hasad.sales_posting_allowed(company_id));
CREATE POLICY hasad_sales_poster_journal_lines_insert ON hasad.journal_lines
  FOR INSERT TO hasad_sales_poster
  WITH CHECK (hasad.sales_posting_allowed(company_id));
CREATE POLICY hasad_sales_poster_audit_insert ON hasad.audit_log
  FOR INSERT TO hasad_sales_poster
  WITH CHECK (actor_user_id = hasad.sales_posting_actor_id());

-- Counter allocation per (company, document type, fiscal year).
-- PROPOSED format only; O30 remains OPEN (see header). Never exposed to clients.
CREATE FUNCTION hasad.allocate_document_number(
  p_company_id uuid,
  p_document_type_id uuid,
  p_fiscal_year_id uuid
) RETURNS text
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $fn$
DECLARE
  v_prefix text;
  v_pad smallint;
  v_fiscal_year integer;
  v_value bigint;
BEGIN
  IF p_company_id IS NULL OR p_document_type_id IS NULL OR p_fiscal_year_id IS NULL THEN
    RAISE EXCEPTION 'NUMBER_INPUT_INVALID' USING ERRCODE = '23514';
  END IF;
  IF NOT hasad.sales_posting_allowed(p_company_id) THEN
    RAISE EXCEPTION 'PERMISSION_DENIED' USING ERRCODE = '42501';
  END IF;

  SELECT dt.format_prefix, dt.pad_length,
         extract(year FROM fy.start_date)::integer
  INTO v_prefix, v_pad, v_fiscal_year
  FROM hasad.document_types dt
  JOIN hasad.fiscal_years fy
    ON fy.company_id = dt.company_id AND fy.id = p_fiscal_year_id
  WHERE dt.id = p_document_type_id
    AND dt.company_id = p_company_id
    AND dt.is_active;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'NUMBER_TYPE_OR_FISCAL_YEAR_INVALID' USING ERRCODE = '23514';
  END IF;
  IF v_prefix IS NULL OR btrim(v_prefix) = '' THEN
    RAISE EXCEPTION 'NUMBER_PREFIX_REQUIRED' USING ERRCODE = '23514';
  END IF;

  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      p_company_id::text || ':' || p_document_type_id::text || ':' || p_fiscal_year_id::text,
      0
    )
  );

  INSERT INTO hasad.doc_numbers (company_id, document_type_id, fiscal_year_id, next_value)
  VALUES (p_company_id, p_document_type_id, p_fiscal_year_id, 1)
  ON CONFLICT (company_id, document_type_id, fiscal_year_id) DO NOTHING;

  SELECT next_value INTO v_value
  FROM hasad.doc_numbers
  WHERE company_id = p_company_id
    AND document_type_id = p_document_type_id
    AND fiscal_year_id = p_fiscal_year_id
  FOR UPDATE;

  UPDATE hasad.doc_numbers
  SET next_value = v_value + 1
  WHERE company_id = p_company_id
    AND document_type_id = p_document_type_id
    AND fiscal_year_id = p_fiscal_year_id;

  RETURN v_prefix || '-' || v_fiscal_year::text || '-'
    || pg_catalog.lpad(v_value::text, v_pad, '0');
END
$fn$;
REVOKE ALL ON FUNCTION hasad.allocate_document_number(uuid, uuid, uuid)
  FROM PUBLIC, anon, authenticated;

-- ------------------------------------------------------------------ posting --
CREATE FUNCTION hasad.post_sales_invoice(
  p_company_id uuid,
  p_document_id uuid,
  p_idempotency_key uuid
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $fn$
DECLARE
  v_actor uuid := hasad.sales_posting_actor_id();
  v_doc hasad.sales_documents%ROWTYPE;
  v_doc_type hasad.document_types%ROWTYPE;
  v_je_type hasad.document_types%ROWTYPE;
  v_period_id uuid;
  v_line record;
  v_stock record;
  v_lock record;
  v_count integer;
  v_distinct integer;
  v_min integer;
  v_max integer;
  v_sum_net numeric(18,2);
  v_sum_tax numeric(18,2);
  v_sum_gross numeric(18,2);
  v_basis numeric(18,2);
  v_net numeric(18,2);
  v_tax numeric(18,2);
  v_gross numeric(18,2);
  v_track boolean;
  v_required numeric(19,4);
  v_ar uuid;
  v_rev uuid;
  v_vat uuid;
  v_cogs uuid;
  v_inv uuid;
  v_inv_total numeric(18,2) := 0;
  v_movement_count integer := 0;
  v_doc_no text;
  v_je_no text;
  v_je_id uuid := pg_catalog.gen_random_uuid();
  v_inv_line uuid;
  v_cogs_line uuid;
  v_line_no integer := 0;
  v_cost numeric(19,4);
  v_value numeric(18,2);
  v_seq bigint;
  v_movement_id uuid;
  v_prev_je uuid;
  v_prev_je_no text;
  v_missing text;
BEGIN
  -- 1. Trusted actor.
  IF v_actor IS NULL THEN
    RAISE EXCEPTION 'UNAUTHENTICATED' USING ERRCODE = '28000';
  END IF;
  IF p_company_id IS NULL OR p_document_id IS NULL OR p_idempotency_key IS NULL THEN
    RAISE EXCEPTION 'POST_INPUT_INVALID' USING ERRCODE = '23514';
  END IF;

  -- 2. Active membership, active company, sales.post.
  IF NOT hasad.sales_posting_allowed(p_company_id) THEN
    RAISE EXCEPTION 'PERMISSION_DENIED' USING ERRCODE = '42501';
  END IF;

  -- 3. Lock the invoice, then decide replay vs. posting.
  SELECT * INTO v_doc
  FROM hasad.sales_documents
  WHERE company_id = p_company_id AND id = p_document_id
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'DOCUMENT_NOT_FOUND' USING ERRCODE = '23514';
  END IF;

  IF v_doc.status = 'posted' THEN
    IF v_doc.doc_no IS NULL
       OR v_doc.idempotency_key IS DISTINCT FROM p_idempotency_key THEN
      RAISE EXCEPTION 'ALREADY_POSTED' USING ERRCODE = '23505';
    END IF;
    SELECT je.id, je.entry_no INTO v_prev_je, v_prev_je_no
    FROM hasad.journal_entries je
    WHERE je.company_id = p_company_id
      AND je.idempotency_key = p_idempotency_key
    ORDER BY je.posted_at, je.id
    LIMIT 1;
    RETURN pg_catalog.jsonb_build_object(
      'document', pg_catalog.to_jsonb(v_doc),
      'replayed', true,
      'doc_no', v_doc.doc_no,
      'journal_entry_id', v_prev_je,
      'journal_entry_no', v_prev_je_no
    );
  END IF;

  IF v_doc.status <> 'draft'
     OR v_doc.doc_kind <> 'invoice'
     OR v_doc.doc_no IS NOT NULL
     OR v_doc.posted_at IS NOT NULL
     OR v_doc.posted_by IS NOT NULL THEN
    RAISE EXCEPTION 'DOCUMENT_NOT_POSTABLE' USING ERRCODE = '23514';
  END IF;
  IF v_doc.idempotency_key IS NULL THEN
    RAISE EXCEPTION 'IDEMPOTENCY_REQUIRED' USING ERRCODE = '23505';
  END IF;
  IF v_doc.idempotency_key <> p_idempotency_key THEN
    RAISE EXCEPTION 'IDEMPOTENCY_MISMATCH' USING ERRCODE = '23505';
  END IF;

  -- 4. References and fiscal calendar.
  IF NOT EXISTS (
    SELECT 1 FROM hasad.parties
    WHERE id = v_doc.party_id AND company_id = p_company_id
      AND is_customer AND is_active
  ) THEN
    RAISE EXCEPTION 'PARTY_NOT_AVAILABLE' USING ERRCODE = '23514';
  END IF;

  SELECT * INTO v_doc_type
  FROM hasad.document_types
  WHERE id = v_doc.doc_type_id AND company_id = p_company_id
    AND code = 'SI' AND issuance = 'posting' AND is_active;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'DOCUMENT_TYPE_NOT_AVAILABLE' USING ERRCODE = '23514';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM hasad.fiscal_years
    WHERE id = v_doc.fiscal_year_id AND company_id = p_company_id
      AND v_doc.doc_date BETWEEN start_date AND end_date
  ) THEN
    RAISE EXCEPTION 'FISCAL_YEAR_MISMATCH' USING ERRCODE = '23514';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM hasad.fiscal_years
    WHERE id = v_doc.fiscal_year_id AND company_id = p_company_id
      AND status = 'open'
  ) THEN
    RAISE EXCEPTION 'FISCAL_YEAR_CLOSED' USING ERRCODE = '23514';
  END IF;

  SELECT fp.id INTO v_period_id
  FROM hasad.fiscal_periods fp
  WHERE fp.company_id = p_company_id
    AND fp.fiscal_year_id = v_doc.fiscal_year_id
    AND v_doc.doc_date BETWEEN fp.start_date AND fp.end_date
    AND fp.status = 'open'
  ORDER BY fp.period_no
  LIMIT 1;
  IF v_period_id IS NULL THEN
    RAISE EXCEPTION 'ACCOUNTING_PREREQUISITES_MISSING'
      USING ERRCODE = '23514', DETAIL = 'open_fiscal_period';
  END IF;

  -- 5. Lines, precision, recomputed totals and tax-rate resolution.
  SELECT count(*), count(DISTINCT line_no), min(line_no), max(line_no),
         coalesce(sum(net), 0), coalesce(sum(tax), 0), coalesce(sum(gross), 0)
  INTO v_count, v_distinct, v_min, v_max, v_sum_net, v_sum_tax, v_sum_gross
  FROM hasad.sales_document_lines
  WHERE company_id = p_company_id AND document_id = p_document_id;

  IF v_count = 0 OR v_count <> v_distinct OR v_min <> 1 OR v_max <> v_count THEN
    RAISE EXCEPTION 'LINES_INVALID' USING ERRCODE = '23514';
  END IF;

  FOR v_line IN
    SELECT * FROM hasad.sales_document_lines
    WHERE company_id = p_company_id AND document_id = p_document_id
    ORDER BY line_no
  LOOP
    IF v_line.qty IS NULL OR v_line.qty <= 0
       OR v_line.unit_price IS NULL OR v_line.unit_price < 0
       OR v_line.discount_amount IS NULL OR v_line.discount_amount < 0
       OR v_line.tax_rate IS NULL OR v_line.tax_rate < 0 THEN
      RAISE EXCEPTION 'LINE_AMOUNT_INVALID' USING ERRCODE = '23514';
    END IF;
    IF v_line.qty <> pg_catalog.trunc(v_line.qty, 4)
       OR v_line.unit_price <> pg_catalog.trunc(v_line.unit_price, 4)
       OR v_line.discount_amount <> pg_catalog.trunc(v_line.discount_amount, 2)
       OR v_line.tax_rate <> pg_catalog.trunc(v_line.tax_rate, 3) THEN
      RAISE EXCEPTION 'LINE_PRECISION_INVALID' USING ERRCODE = '23514';
    END IF;

    v_basis := pg_catalog.round(v_line.qty * v_line.unit_price - v_line.discount_amount, 2);
    IF v_basis < 0 THEN
      RAISE EXCEPTION 'LINE_AMOUNT_INVALID' USING ERRCODE = '23514';
    END IF;
    IF v_doc.vat_mode = 'exclusive' THEN
      v_net := v_basis;
      v_tax := pg_catalog.round(v_basis * v_line.tax_rate / 100, 2);
      v_gross := v_net + v_tax;
    ELSE
      v_net := pg_catalog.round(v_basis / (1 + v_line.tax_rate / 100), 2);
      v_tax := v_basis - v_net;
      v_gross := v_basis;
    END IF;
    IF v_line.net IS DISTINCT FROM v_net
       OR v_line.tax IS DISTINCT FROM v_tax
       OR v_line.gross IS DISTINCT FROM v_gross THEN
      RAISE EXCEPTION 'TOTALS_MISMATCH' USING ERRCODE = '23514';
    END IF;

    IF v_line.tax_rate > 0 AND NOT EXISTS (
      SELECT 1 FROM hasad.tax_rates tr
      WHERE tr.company_id = p_company_id
        AND tr.rate = v_line.tax_rate
        AND tr.is_active
        AND tr.valid_from <= v_doc.doc_date
        AND (tr.valid_to IS NULL OR tr.valid_to >= v_doc.doc_date)
    ) THEN
      RAISE EXCEPTION 'RATE_NOT_FOUND_FOR_DATE' USING ERRCODE = '23514';
    END IF;

    IF v_line.product_id IS NOT NULL THEN
      SELECT p.track_inventory INTO v_track
      FROM hasad.products p
      WHERE p.id = v_line.product_id AND p.company_id = p_company_id AND p.is_active;
      IF NOT FOUND THEN
        RAISE EXCEPTION 'PRODUCT_NOT_AVAILABLE' USING ERRCODE = '23514';
      END IF;
      IF v_track THEN
        IF v_line.warehouse_id IS NULL THEN
          RAISE EXCEPTION 'WAREHOUSE_REQUIRED' USING ERRCODE = '23514';
        END IF;
        IF NOT EXISTS (
          SELECT 1 FROM hasad.warehouses w
          WHERE w.id = v_line.warehouse_id AND w.company_id = p_company_id AND w.is_active
        ) THEN
          RAISE EXCEPTION 'WAREHOUSE_NOT_AVAILABLE' USING ERRCODE = '23514';
        END IF;
      END IF;
    END IF;
  END LOOP;

  IF v_doc.net IS DISTINCT FROM v_sum_net
     OR v_doc.tax IS DISTINCT FROM v_sum_tax
     OR v_doc.gross IS DISTINCT FROM v_sum_gross
     OR v_doc.gross <> v_doc.net + v_doc.tax THEN
    RAISE EXCEPTION 'TOTALS_MISMATCH' USING ERRCODE = '23514';
  END IF;
  IF v_doc.gross <= 0 THEN
    RAISE EXCEPTION 'DOCUMENT_TOTAL_INVALID' USING ERRCODE = '23514';
  END IF;

  -- 6. Accounting prerequisites. Fail closed before any write.
  SELECT d.id INTO v_ar
  FROM hasad.module_account_map m
  JOIN hasad.accounts d ON d.id = m.account_id AND d.company_id = m.company_id
  WHERE m.company_id = p_company_id AND m.module = 'sales'
    AND m.account_role = 'AR_CONTROL' AND d.is_active;
  SELECT d.id INTO v_rev
  FROM hasad.module_account_map m
  JOIN hasad.accounts d ON d.id = m.account_id AND d.company_id = m.company_id
  WHERE m.company_id = p_company_id AND m.module = 'sales'
    AND m.account_role = 'SALES_REVENUE' AND d.is_active;
  IF v_doc.tax > 0 THEN
    SELECT d.id INTO v_vat
    FROM hasad.module_account_map m
    JOIN hasad.accounts d ON d.id = m.account_id AND d.company_id = m.company_id
    WHERE m.company_id = p_company_id AND m.module = 'sales'
      AND m.account_role = 'VAT_OUTPUT' AND d.is_active;
  END IF;

  SELECT EXISTS (
    SELECT 1
    FROM hasad.sales_document_lines l
    JOIN hasad.products p
      ON p.id = l.product_id AND p.company_id = l.company_id AND p.track_inventory
    WHERE l.company_id = p_company_id AND l.document_id = p_document_id
  ) INTO v_track;

  IF v_track THEN
    SELECT d.id INTO v_cogs
    FROM hasad.module_account_map m
    JOIN hasad.accounts d ON d.id = m.account_id AND d.company_id = m.company_id
    WHERE m.company_id = p_company_id AND m.module = 'sales'
      AND m.account_role = 'COGS' AND d.is_active;
    SELECT d.id INTO v_inv
    FROM hasad.module_account_map m
    JOIN hasad.accounts d ON d.id = m.account_id AND d.company_id = m.company_id
    WHERE m.company_id = p_company_id AND m.module = 'sales'
      AND m.account_role = 'INVENTORY_CONTROL' AND d.is_active;
  END IF;

  v_missing := pg_catalog.concat_ws(',',
    CASE WHEN v_ar IS NULL THEN 'AR_CONTROL' END,
    CASE WHEN v_rev IS NULL THEN 'SALES_REVENUE' END,
    CASE WHEN v_doc.tax > 0 AND v_vat IS NULL THEN 'VAT_OUTPUT' END,
    CASE WHEN v_track AND v_cogs IS NULL THEN 'COGS' END,
    CASE WHEN v_track AND v_inv IS NULL THEN 'INVENTORY_CONTROL' END
  );
  IF v_missing <> '' THEN
    RAISE EXCEPTION 'ACCOUNTING_PREREQUISITES_MISSING'
      USING ERRCODE = '23514', DETAIL = 'sales_account_mapping: ' || v_missing;
  END IF;

  SELECT * INTO v_je_type
  FROM hasad.document_types
  WHERE company_id = p_company_id AND code = 'JE'
    AND issuance = 'posting' AND is_active;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'ACCOUNTING_PREREQUISITES_MISSING'
      USING ERRCODE = '23514', DETAIL = 'journal_document_type';
  END IF;

  -- 7. Serialize per product exactly like `hasad.post_stock_issue`, then lock
  --    the stock rows in a deterministic order and verify aggregated demand.
  FOR v_lock IN
    SELECT l.product_id
    FROM hasad.sales_document_lines l
    JOIN hasad.products p
      ON p.id = l.product_id AND p.company_id = l.company_id AND p.track_inventory
    WHERE l.company_id = p_company_id AND l.document_id = p_document_id
    GROUP BY l.product_id
    ORDER BY l.product_id
  LOOP
    PERFORM pg_catalog.pg_advisory_xact_lock(
      pg_catalog.hashtextextended(v_lock.product_id::text, 0)
    );
  END LOOP;

  FOR v_lock IN
    SELECT s.product_id, s.warehouse_id
    FROM hasad.stock_levels s
    JOIN (
      SELECT DISTINCT l.product_id, l.warehouse_id
      FROM hasad.sales_document_lines l
      JOIN hasad.products p
        ON p.id = l.product_id AND p.company_id = l.company_id AND p.track_inventory
      WHERE l.company_id = p_company_id AND l.document_id = p_document_id
    ) r ON r.product_id = s.product_id AND r.warehouse_id = s.warehouse_id
    WHERE s.company_id = p_company_id
    ORDER BY s.product_id, s.warehouse_id
    FOR UPDATE OF s
  LOOP
    NULL;
  END LOOP;

  FOR v_stock IN
    SELECT d.product_id, d.warehouse_id, d.required, s.qty
    FROM (
      SELECT l.product_id, l.warehouse_id, pg_catalog.sum(l.qty) AS required
      FROM hasad.sales_document_lines l
      JOIN hasad.products p
        ON p.id = l.product_id AND p.company_id = l.company_id AND p.track_inventory
      WHERE l.company_id = p_company_id AND l.document_id = p_document_id
      GROUP BY l.product_id, l.warehouse_id
    ) d
    LEFT JOIN hasad.stock_levels s
      ON s.company_id = p_company_id
     AND s.product_id = d.product_id
     AND s.warehouse_id = d.warehouse_id
    ORDER BY d.product_id, d.warehouse_id
  LOOP
    IF v_stock.qty IS NULL OR v_stock.qty < v_stock.required THEN
      RAISE EXCEPTION 'STOCK_INSUFFICIENT' USING ERRCODE = '23514',
        DETAIL = 'product ' || v_stock.product_id || ', warehouse ' || v_stock.warehouse_id;
    END IF;
  END LOOP;

  -- 8. Cost basis for COGS. Uses the locked moving average and the same
  --    per-line rounding as the existing issue contract.
  SELECT coalesce(pg_catalog.sum(pg_catalog.round(l.qty * s.last_unit_cost, 2)), 0)
  INTO v_inv_total
  FROM hasad.sales_document_lines l
  JOIN hasad.products p
    ON p.id = l.product_id AND p.company_id = l.company_id AND p.track_inventory
  JOIN hasad.stock_levels s
    ON s.company_id = l.company_id
   AND s.product_id = l.product_id
   AND s.warehouse_id = l.warehouse_id
  WHERE l.company_id = p_company_id AND l.document_id = p_document_id;

  -- 9. Official numbers: once, at posting, inside this transaction.
  v_doc_no := hasad.allocate_document_number(
    p_company_id, v_doc.doc_type_id, v_doc.fiscal_year_id
  );
  v_je_no := hasad.allocate_document_number(
    p_company_id, v_je_type.id, v_doc.fiscal_year_id
  );

  -- 10. Posted journal entry (documented PROPOSED matrix, feature 06 §G).
  INSERT INTO hasad.journal_entries
    (id, company_id, fiscal_year_id, period_id, entry_date, entry_kind, status,
     entry_no, idempotency_key, posted_at, posted_by, reason)
  VALUES
    (v_je_id, p_company_id, v_doc.fiscal_year_id, v_period_id, v_doc.doc_date,
     'standard', 'posted', v_je_no, p_idempotency_key, pg_catalog.now(), v_actor,
     'sales invoice ' || v_doc_no);

  IF v_doc.gross > 0 THEN
    v_line_no := v_line_no + 1;
    INSERT INTO hasad.journal_lines
      (id, company_id, entry_id, line_no, account_id, party_id, debit, credit, description)
    VALUES
      (pg_catalog.gen_random_uuid(), p_company_id, v_je_id, v_line_no, v_ar,
       v_doc.party_id, v_doc.gross, 0, 'AR_CONTROL / ' || v_doc_no);
  END IF;
  IF v_doc.net > 0 THEN
    v_line_no := v_line_no + 1;
    INSERT INTO hasad.journal_lines
      (id, company_id, entry_id, line_no, account_id, party_id, debit, credit, description)
    VALUES
      (pg_catalog.gen_random_uuid(), p_company_id, v_je_id, v_line_no, v_rev,
       NULL, 0, v_doc.net, 'SALES_REVENUE / ' || v_doc_no);
  END IF;
  IF v_doc.tax > 0 THEN
    v_line_no := v_line_no + 1;
    INSERT INTO hasad.journal_lines
      (id, company_id, entry_id, line_no, account_id, party_id, debit, credit, description)
    VALUES
      (pg_catalog.gen_random_uuid(), p_company_id, v_je_id, v_line_no, v_vat,
       NULL, 0, v_doc.tax, 'VAT_OUTPUT / ' || v_doc_no);
  END IF;
  IF v_inv_total > 0 THEN
    v_cogs_line := pg_catalog.gen_random_uuid();
    v_inv_line := pg_catalog.gen_random_uuid();
    v_line_no := v_line_no + 1;
    INSERT INTO hasad.journal_lines
      (id, company_id, entry_id, line_no, account_id, party_id, debit, credit, description)
    VALUES
      (v_cogs_line, p_company_id, v_je_id, v_line_no, v_cogs,
       NULL, v_inv_total, 0, 'COGS / ' || v_doc_no);
    v_line_no := v_line_no + 1;
    INSERT INTO hasad.journal_lines
      (id, company_id, entry_id, line_no, account_id, party_id, debit, credit, description)
    VALUES
      (v_inv_line, p_company_id, v_je_id, v_line_no, v_inv,
       NULL, 0, v_inv_total, 'INVENTORY_CONTROL / ' || v_doc_no);
  END IF;

  -- 11. Inventory issue, one movement per stocked invoice line, linked to the
  --     inventory credit line. Costing mirrors `hasad.post_stock_issue`.
  FOR v_line IN
    SELECT l.id, l.line_no, l.product_id, l.warehouse_id, l.qty,
           s.last_unit_cost
    FROM hasad.sales_document_lines l
    JOIN hasad.products p
      ON p.id = l.product_id AND p.company_id = l.company_id AND p.track_inventory
    JOIN hasad.stock_levels s
      ON s.company_id = l.company_id
     AND s.product_id = l.product_id
     AND s.warehouse_id = l.warehouse_id
    WHERE l.company_id = p_company_id AND l.document_id = p_document_id
    ORDER BY l.product_id, l.warehouse_id, l.line_no
  LOOP
    v_cost := v_line.last_unit_cost;
    v_value := pg_catalog.round(v_line.qty * v_cost, 2);
    v_seq := coalesce(
      (
        SELECT pg_catalog.max(seq) FROM hasad.stock_movements
        WHERE product_id = v_line.product_id
      ),
      0
    ) + 1;

    UPDATE hasad.stock_levels
    SET qty = qty - v_line.qty
    WHERE company_id = p_company_id
      AND product_id = v_line.product_id
      AND warehouse_id = v_line.warehouse_id;

    INSERT INTO hasad.stock_movements
      (id, company_id, product_id, warehouse_id, movement_type, direction,
       qty, unit_cost, value, seq, source_document_type, source_document_id,
       journal_line_id)
    VALUES
      (pg_catalog.gen_random_uuid(), p_company_id, v_line.product_id,
       v_line.warehouse_id, 'sales_issue', 'out', v_line.qty, v_cost, v_value,
       v_seq, 'sales_invoice', p_document_id, v_inv_line)
    RETURNING id INTO v_movement_id;

    INSERT INTO hasad.audit_log
      (id, company_id, actor_user_id, action, entity_type, entity_id, details)
    VALUES
      (pg_catalog.gen_random_uuid(), p_company_id, v_actor, 'stock.posted',
       'stock_movement', v_movement_id,
       pg_catalog.jsonb_build_object(
         'movement_type', 'sales_issue',
         'warehouse_id', v_line.warehouse_id,
         'product_id', v_line.product_id,
         'qty', v_line.qty,
         'source_document_type', 'sales_invoice',
         'source_document_id', p_document_id
       ));

    v_movement_count := v_movement_count + 1;
  END LOOP;

  -- 12. Flip the invoice exactly once.
  UPDATE hasad.sales_documents
  SET status = 'posted',
      doc_no = v_doc_no,
      posted_at = pg_catalog.now(),
      posted_by = v_actor
  WHERE company_id = p_company_id
    AND id = p_document_id
    AND status = 'draft'
    AND doc_no IS NULL
  RETURNING * INTO v_doc;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'CONCURRENT_POSTING' USING ERRCODE = '23505';
  END IF;

  -- 13. Audit: posting fact and number issuance.
  INSERT INTO hasad.audit_log
    (id, company_id, actor_user_id, action, entity_type, entity_id, details)
  VALUES
    (pg_catalog.gen_random_uuid(), p_company_id, v_actor, 'sale.invoice_posted',
     'sales_document', p_document_id,
     pg_catalog.jsonb_build_object(
       'doc_no', v_doc_no,
       'status', 'posted',
       'net', v_doc.net,
       'tax', v_doc.tax,
       'gross', v_doc.gross,
       'line_count', v_count,
       'journal_entry_id', v_je_id,
       'journal_entry_no', v_je_no,
       'movement_count', v_movement_count
     ));
  INSERT INTO hasad.audit_log
    (id, company_id, actor_user_id, action, entity_type, entity_id, details)
  VALUES
    (pg_catalog.gen_random_uuid(), p_company_id, v_actor, 'number.issued',
     'sales_document', p_document_id,
     pg_catalog.jsonb_build_object(
       'document_type_code', 'SI',
       'fiscal_year_id', v_doc.fiscal_year_id,
       'doc_no', v_doc_no
     ));

  RETURN pg_catalog.jsonb_build_object(
    'document', pg_catalog.to_jsonb(v_doc),
    'replayed', false,
    'doc_no', v_doc_no,
    'journal_entry_id', v_je_id,
    'journal_entry_no', v_je_no
  );
END
$fn$;
REVOKE ALL ON FUNCTION hasad.post_sales_invoice(uuid, uuid, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION hasad.post_sales_invoice(uuid, uuid, uuid) TO authenticated;

-- Ownership transfer after all grants/policies exist.
-- PostgreSQL requires the new function owner to hold CREATE on the function's
-- schema. The lock owner is NOLOGIN and must not retain CREATE at rest, so the
-- privilege is granted only for the ownership transfers and revoked immediately
-- afterwards (same pattern as the deployed S2 draft candidate).
GRANT CREATE ON SCHEMA hasad TO hasad_sales_poster;
ALTER FUNCTION hasad.sales_posting_actor_id() OWNER TO hasad_sales_poster;
ALTER FUNCTION hasad.sales_posting_allowed(uuid) OWNER TO hasad_sales_poster;
ALTER FUNCTION hasad.allocate_document_number(uuid, uuid, uuid) OWNER TO hasad_sales_poster;
ALTER FUNCTION hasad.post_sales_invoice(uuid, uuid, uuid) OWNER TO hasad_sales_poster;
REVOKE CREATE ON SCHEMA hasad FROM hasad_sales_poster;

DO $postflight$
DECLARE v_bad text;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_roles
    WHERE rolname = 'hasad_sales_poster'
      AND NOT rolcanlogin AND NOT rolinherit AND NOT rolsuper
      AND NOT rolcreaterole AND NOT rolcreatedb AND NOT rolreplication
      AND NOT rolbypassrls
  ) THEN
    RAISE EXCEPTION 'POSTFLIGHT_POSTER_ATTRIBUTES';
  END IF;

  IF pg_catalog.has_schema_privilege('hasad_sales_poster', 'hasad', 'CREATE') THEN
    RAISE EXCEPTION 'POSTFLIGHT_POSTER_CREATE_RETAINED';
  END IF;

  IF pg_catalog.has_schema_privilege('anon', 'hasad', 'USAGE')
     OR pg_catalog.has_function_privilege('anon', 'hasad.post_sales_invoice(uuid,uuid,uuid)', 'EXECUTE')
     OR pg_catalog.has_function_privilege('anon', 'hasad.allocate_document_number(uuid,uuid,uuid)', 'EXECUTE') THEN
    RAISE EXCEPTION 'POSTFLIGHT_ANON_EXPOSURE';
  END IF;

  IF NOT pg_catalog.has_function_privilege('authenticated', 'hasad.post_sales_invoice(uuid,uuid,uuid)', 'EXECUTE') THEN
    RAISE EXCEPTION 'POSTFLIGHT_AUTHENTICATED_EXECUTE_MISSING';
  END IF;
  IF pg_catalog.has_function_privilege('authenticated', 'hasad.allocate_document_number(uuid,uuid,uuid)', 'EXECUTE') THEN
    RAISE EXCEPTION 'POSTFLIGHT_ALLOCATOR_EXPOSED';
  END IF;

  IF pg_catalog.has_table_privilege('authenticated', 'hasad.sales_documents', 'INSERT,UPDATE,DELETE')
     OR pg_catalog.has_any_column_privilege('authenticated', 'hasad.sales_documents', 'INSERT,UPDATE')
     OR pg_catalog.has_table_privilege('authenticated', 'hasad.stock_levels', 'INSERT,UPDATE,DELETE')
     OR pg_catalog.has_any_column_privilege('authenticated', 'hasad.stock_levels', 'INSERT,UPDATE')
     OR pg_catalog.has_table_privilege('authenticated', 'hasad.stock_movements', 'INSERT,UPDATE,DELETE')
     OR pg_catalog.has_table_privilege('authenticated', 'hasad.doc_numbers', 'INSERT,UPDATE,DELETE')
     OR pg_catalog.has_table_privilege('authenticated', 'hasad.journal_entries', 'INSERT,UPDATE,DELETE')
     OR pg_catalog.has_table_privilege('authenticated', 'hasad.journal_lines', 'INSERT,UPDATE,DELETE') THEN
    RAISE EXCEPTION 'POSTFLIGHT_AUTHENTICATED_DIRECT_WRITE';
  END IF;

  SELECT string_agg(c.relname, ', ' ORDER BY c.relname) INTO v_bad
  FROM pg_catalog.pg_class c
  JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'hasad'
    AND c.relname IN (
      'sales_documents','sales_document_lines','doc_numbers','journal_entries',
      'journal_lines','stock_levels','stock_movements','audit_log'
    )
    AND (NOT c.relrowsecurity OR NOT c.relforcerowsecurity);
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'POSTFLIGHT_FORCE_RLS: %', v_bad;
  END IF;
END
$postflight$;

COMMIT;

NOTIFY pgrst, 'reload schema';
