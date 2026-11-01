-- Hasad ERP V2 — Sales and Purchases (STRUCTURAL CANDIDATE — NOT DEPLOYABLE)
-- Target: Supabase DEV sxasnunzspkuwbxiddqd (NO PUSH WITHOUT EXPLICIT OWNER APPROVAL)
-- Depends on: 20261027000400, prior
--
-- Scope (proposed): sales_documents, sales_document_lines, purchase_documents, purchase_document_lines
-- Source: docs/17_ERP_STRUCTURAL_READINESS_PACKAGE.md §E2
--
-- Conventions: ON DELETE RESTRICT, composite tenant FKs, ENABLE+FORCE RLS,
-- zero policies/grants/functions/triggers/seeds/RPCs. Money numeric(18,2), qty/price numeric(19,4).
-- No posting/tax resolution behavior.

BEGIN;

CREATE TABLE hasad.sales_documents (
  id uuid PRIMARY KEY,
  company_id uuid NOT NULL
    REFERENCES hasad.companies(id) ON DELETE RESTRICT,
  doc_kind text NOT NULL,
  status text NOT NULL DEFAULT 'draft',
  party_id uuid NOT NULL,
  doc_date date NOT NULL,
  vat_mode text NOT NULL,
  doc_type_id uuid NOT NULL,
  fiscal_year_id uuid NOT NULL,
  doc_no text NULL,
  original_document_id uuid NULL,
  idempotency_key uuid NULL,
  net numeric(18,2) NOT NULL DEFAULT 0,
  tax numeric(18,2) NOT NULL DEFAULT 0,
  gross numeric(18,2) NOT NULL DEFAULT 0,
  posted_at timestamptz NULL,
  posted_by uuid NULL
    REFERENCES hasad.user_profiles(id) ON DELETE RESTRICT,
  CONSTRAINT sales_documents_company_id_id_key UNIQUE (company_id, id),
  CONSTRAINT sales_documents_company_party_fkey
    FOREIGN KEY (company_id, party_id)
    REFERENCES hasad.parties(company_id, id) ON DELETE RESTRICT,
  CONSTRAINT sales_documents_company_doc_type_fkey
    FOREIGN KEY (company_id, doc_type_id)
    REFERENCES hasad.document_types(company_id, id) ON DELETE RESTRICT,
  CONSTRAINT sales_documents_company_fiscal_year_fkey
    FOREIGN KEY (company_id, fiscal_year_id)
    REFERENCES hasad.fiscal_years(company_id, id) ON DELETE RESTRICT,
  CONSTRAINT sales_documents_company_original_fkey
    FOREIGN KEY (company_id, original_document_id)
    REFERENCES hasad.sales_documents(company_id, id) ON DELETE RESTRICT,
  CONSTRAINT sales_documents_doc_kind_check CHECK (doc_kind IN ('quotation','order','invoice','credit_note','debit_note')),
  CONSTRAINT sales_documents_status_check CHECK (status IN ('draft','posted','cancelled')),
  CONSTRAINT sales_documents_vat_mode_check CHECK (vat_mode IN ('inclusive','exclusive')),
  CONSTRAINT sales_documents_money_check CHECK (net>=0 AND tax>=0 AND gross>=0)
);

CREATE UNIQUE INDEX sales_documents_company_idempotency_key_key
  ON hasad.sales_documents (company_id, idempotency_key)
  WHERE idempotency_key IS NOT NULL;

CREATE UNIQUE INDEX sales_documents_company_doc_no_key
  ON hasad.sales_documents (company_id, doc_no)
  WHERE doc_no IS NOT NULL;

CREATE INDEX sales_documents_company_party_date_idx ON hasad.sales_documents (company_id, party_id, doc_date);

CREATE TABLE hasad.sales_document_lines (
  id uuid PRIMARY KEY,
  company_id uuid NOT NULL
    REFERENCES hasad.companies(id) ON DELETE RESTRICT,
  document_id uuid NOT NULL,
  line_no integer NOT NULL,
  product_id uuid NULL,
  warehouse_id uuid NULL,
  qty numeric(19,4) NOT NULL,
  unit_price numeric(19,4) NOT NULL,
  discount_amount numeric(18,2) NOT NULL DEFAULT 0,
  tax_rate numeric(6,3),
  net numeric(18,2) NOT NULL,
  tax numeric(18,2) NOT NULL,
  gross numeric(18,2) NOT NULL,
  order_line_id uuid NULL,
  original_line_id uuid NULL,
  CONSTRAINT sales_document_lines_company_id_id_key UNIQUE (company_id, id),
  CONSTRAINT sales_document_lines_document_line_no_key UNIQUE (document_id, line_no),
  CONSTRAINT sales_document_lines_company_document_fkey
    FOREIGN KEY (company_id, document_id)
    REFERENCES hasad.sales_documents(company_id, id) ON DELETE RESTRICT,
  CONSTRAINT sales_document_lines_company_product_fkey
    FOREIGN KEY (company_id, product_id)
    REFERENCES hasad.products(company_id, id) ON DELETE RESTRICT,
  CONSTRAINT sales_document_lines_company_warehouse_fkey
    FOREIGN KEY (company_id, warehouse_id)
    REFERENCES hasad.warehouses(company_id, id) ON DELETE RESTRICT,
  CONSTRAINT sales_document_lines_qty_check CHECK (qty > 0),
  CONSTRAINT sales_document_lines_price_discount_check CHECK (unit_price>=0 AND discount_amount>=0),
  CONSTRAINT sales_document_lines_tax_rate_check CHECK (tax_rate IS NULL OR tax_rate >= 0),
  CONSTRAINT sales_document_lines_money_check CHECK (net>=0 AND tax>=0 AND gross>=0)
);

CREATE INDEX sales_document_lines_product_idx ON hasad.sales_document_lines (product_id);
CREATE INDEX sales_document_lines_warehouse_idx ON hasad.sales_document_lines (warehouse_id);

CREATE TABLE hasad.purchase_documents (
  id uuid PRIMARY KEY,
  company_id uuid NOT NULL
    REFERENCES hasad.companies(id) ON DELETE RESTRICT,
  doc_kind text NOT NULL,
  status text NOT NULL DEFAULT 'draft',
  party_id uuid NOT NULL,
  supplier_ref text NULL,
  doc_date date NOT NULL,
  vat_mode text NOT NULL,
  doc_type_id uuid NOT NULL,
  fiscal_year_id uuid NOT NULL,
  doc_no text NULL,
  original_document_id uuid NULL,
  idempotency_key uuid NULL,
  net numeric(18,2) NOT NULL DEFAULT 0,
  tax numeric(18,2) NOT NULL DEFAULT 0,
  gross numeric(18,2) NOT NULL DEFAULT 0,
  posted_at timestamptz NULL,
  posted_by uuid NULL
    REFERENCES hasad.user_profiles(id) ON DELETE RESTRICT,
  CONSTRAINT purchase_documents_company_id_id_key UNIQUE (company_id, id),
  CONSTRAINT purchase_documents_company_party_fkey
    FOREIGN KEY (company_id, party_id)
    REFERENCES hasad.parties(company_id, id) ON DELETE RESTRICT,
  CONSTRAINT purchase_documents_company_doc_type_fkey
    FOREIGN KEY (company_id, doc_type_id)
    REFERENCES hasad.document_types(company_id, id) ON DELETE RESTRICT,
  CONSTRAINT purchase_documents_company_fiscal_year_fkey
    FOREIGN KEY (company_id, fiscal_year_id)
    REFERENCES hasad.fiscal_years(company_id, id) ON DELETE RESTRICT,
  CONSTRAINT purchase_documents_company_original_fkey
    FOREIGN KEY (company_id, original_document_id)
    REFERENCES hasad.purchase_documents(company_id, id) ON DELETE RESTRICT,
  CONSTRAINT purchase_documents_doc_kind_check CHECK (doc_kind IN ('quotation','order','goods_receipt','purchase_bill','credit_note','debit_note')),
  CONSTRAINT purchase_documents_status_check CHECK (status IN ('draft','posted','cancelled')),
  CONSTRAINT purchase_documents_vat_mode_check CHECK (vat_mode IN ('inclusive','exclusive')),
  CONSTRAINT purchase_documents_money_check CHECK (net>=0 AND tax>=0 AND gross>=0)
);

CREATE UNIQUE INDEX purchase_documents_company_party_supplier_ref_key
  ON hasad.purchase_documents (company_id, party_id, supplier_ref)
  WHERE supplier_ref IS NOT NULL;

CREATE UNIQUE INDEX purchase_documents_company_idempotency_key_key
  ON hasad.purchase_documents (company_id, idempotency_key)
  WHERE idempotency_key IS NOT NULL;

CREATE UNIQUE INDEX purchase_documents_company_doc_no_key
  ON hasad.purchase_documents (company_id, doc_no)
  WHERE doc_no IS NOT NULL;

CREATE TABLE hasad.purchase_document_lines (
  id uuid PRIMARY KEY,
  company_id uuid NOT NULL
    REFERENCES hasad.companies(id) ON DELETE RESTRICT,
  document_id uuid NOT NULL,
  line_no integer NOT NULL,
  product_id uuid NULL,
  warehouse_id uuid NULL,
  qty numeric(19,4) NOT NULL,
  unit_price numeric(19,4) NOT NULL,
  discount_amount numeric(18,2) NOT NULL DEFAULT 0,
  tax_rate numeric(6,3),
  net numeric(18,2) NOT NULL,
  tax numeric(18,2) NOT NULL,
  gross numeric(18,2) NOT NULL,
  order_line_id uuid NULL,
  receipt_line_id uuid NULL,
  original_line_id uuid NULL,
  CONSTRAINT purchase_document_lines_company_id_id_key UNIQUE (company_id, id),
  CONSTRAINT purchase_document_lines_document_line_no_key UNIQUE (document_id, line_no),
  CONSTRAINT purchase_document_lines_company_document_fkey
    FOREIGN KEY (company_id, document_id)
    REFERENCES hasad.purchase_documents(company_id, id) ON DELETE RESTRICT,
  CONSTRAINT purchase_document_lines_company_product_fkey
    FOREIGN KEY (company_id, product_id)
    REFERENCES hasad.products(company_id, id) ON DELETE RESTRICT,
  CONSTRAINT purchase_document_lines_company_warehouse_fkey
    FOREIGN KEY (company_id, warehouse_id)
    REFERENCES hasad.warehouses(company_id, id) ON DELETE RESTRICT,
  CONSTRAINT purchase_document_lines_qty_check CHECK (qty > 0),
  CONSTRAINT purchase_document_lines_price_discount_check CHECK (unit_price>=0 AND discount_amount>=0),
  CONSTRAINT purchase_document_lines_tax_rate_check CHECK (tax_rate IS NULL OR tax_rate >= 0),
  CONSTRAINT purchase_document_lines_money_check CHECK (net>=0 AND tax>=0 AND gross>=0)
);

CREATE INDEX purchase_document_lines_product_idx ON hasad.purchase_document_lines (product_id);
CREATE INDEX purchase_document_lines_warehouse_idx ON hasad.purchase_document_lines (warehouse_id);

ALTER TABLE hasad.sales_documents ENABLE ROW LEVEL SECURITY;
ALTER TABLE hasad.sales_documents FORCE ROW LEVEL SECURITY;
ALTER TABLE hasad.sales_document_lines ENABLE ROW LEVEL SECURITY;
ALTER TABLE hasad.sales_document_lines FORCE ROW LEVEL SECURITY;
ALTER TABLE hasad.purchase_documents ENABLE ROW LEVEL SECURITY;
ALTER TABLE hasad.purchase_documents FORCE ROW LEVEL SECURITY;
ALTER TABLE hasad.purchase_document_lines ENABLE ROW LEVEL SECURITY;
ALTER TABLE hasad.purchase_document_lines FORCE ROW LEVEL SECURITY;

COMMIT;
