-- Hasad ERP V2 — Expenses (STRUCTURAL CANDIDATE — NOT DEPLOYABLE)
-- Target: Supabase DEV sxasnunzspkuwbxiddqd (NO PUSH WITHOUT EXPLICIT OWNER APPROVAL)
-- Depends on: 20261029000800 and prior
--
-- Scope (proposed): expense_categories, expense_documents, expense_document_lines, expense_attachments, expense_receipt_dedup
-- Source: docs/17_ERP_STRUCTURAL_READINESS_PACKAGE.md §E3
--
-- Conventions: ON DELETE RESTRICT, composite tenant FKs, ENABLE+FORCE RLS,
-- zero policies/grants/functions/triggers/seeds/RPCs. Storage/attachment operations deferred per D-011.

BEGIN;

CREATE TABLE hasad.expense_categories (
  id uuid PRIMARY KEY,
  company_id uuid NOT NULL
    REFERENCES hasad.companies(id) ON DELETE RESTRICT,
  code text NOT NULL,
  name_ar text NOT NULL,
  account_id uuid NOT NULL,
  is_active boolean NOT NULL DEFAULT true,
  CONSTRAINT expense_categories_company_id_id_key UNIQUE (company_id, id),
  CONSTRAINT expense_categories_company_code_key UNIQUE (company_id, code),
  CONSTRAINT expense_categories_company_account_fkey
    FOREIGN KEY (company_id, account_id)
    REFERENCES hasad.accounts(company_id, id) ON DELETE RESTRICT
);

CREATE TABLE hasad.expense_documents (
  id uuid PRIMARY KEY,
  company_id uuid NOT NULL
    REFERENCES hasad.companies(id) ON DELETE RESTRICT,
  settlement text NOT NULL,
  party_id uuid NULL,
  container_account_id uuid NULL,
  doc_date date NOT NULL,
  vat_mode text NOT NULL,
  doc_type_id uuid NOT NULL,
  fiscal_year_id uuid NOT NULL,
  doc_no text NULL,
  external_ref text NULL,
  reversal_of_id uuid NULL,
  idempotency_key uuid NULL,
  net numeric(18,2) NOT NULL DEFAULT 0,
  tax numeric(18,2) NOT NULL DEFAULT 0,
  gross numeric(18,2) NOT NULL DEFAULT 0,
  status text NOT NULL DEFAULT 'draft',
  posted_at timestamptz NULL,
  CONSTRAINT expense_documents_company_id_id_key UNIQUE (company_id, id),
  CONSTRAINT expense_documents_company_party_fkey
    FOREIGN KEY (company_id, party_id)
    REFERENCES hasad.parties(company_id, id) ON DELETE RESTRICT,
  CONSTRAINT expense_documents_company_doc_type_fkey
    FOREIGN KEY (company_id, doc_type_id)
    REFERENCES hasad.document_types(company_id, id) ON DELETE RESTRICT,
  CONSTRAINT expense_documents_company_fiscal_year_fkey
    FOREIGN KEY (company_id, fiscal_year_id)
    REFERENCES hasad.fiscal_years(company_id, id) ON DELETE RESTRICT,
  CONSTRAINT expense_documents_company_reversal_fkey
    FOREIGN KEY (company_id, reversal_of_id)
    REFERENCES hasad.expense_documents(company_id, id) ON DELETE RESTRICT,
  CONSTRAINT expense_documents_settlement_check CHECK (settlement IN ('cash','credit','employee')),
  CONSTRAINT expense_documents_vat_mode_check CHECK (vat_mode IN ('inclusive','exclusive')),
  CONSTRAINT expense_documents_status_check CHECK (status IN ('draft','posted','cancelled')),
  CONSTRAINT expense_documents_money_check CHECK (net>=0 AND tax>=0 AND gross>=0)
);

ALTER TABLE hasad.payment_allocations
  ADD CONSTRAINT payment_allocations_company_expense_fkey
  FOREIGN KEY (company_id, expense_document_id)
  REFERENCES hasad.expense_documents(company_id, id) ON DELETE RESTRICT;

CREATE UNIQUE INDEX expense_documents_company_idempotency_key_key
  ON hasad.expense_documents (company_id, idempotency_key)
  WHERE idempotency_key IS NOT NULL;

CREATE UNIQUE INDEX expense_documents_company_doc_no_key
  ON hasad.expense_documents (company_id, doc_no)
  WHERE doc_no IS NOT NULL;

CREATE TABLE hasad.expense_document_lines (
  id uuid PRIMARY KEY,
  company_id uuid NOT NULL
    REFERENCES hasad.companies(id) ON DELETE RESTRICT,
  document_id uuid NOT NULL,
  line_no integer NOT NULL,
  category_id uuid NOT NULL,
  amount numeric(19,4) NOT NULL,
  tax_rate numeric(6,3),
  net numeric(18,2) NOT NULL,
  tax numeric(18,2) NOT NULL,
  gross numeric(18,2) NOT NULL,
  account_id uuid NULL,
  CONSTRAINT expense_document_lines_company_id_id_key UNIQUE (company_id, id),
  CONSTRAINT expense_document_lines_document_line_no_key UNIQUE (document_id, line_no),
  CONSTRAINT expense_document_lines_company_document_fkey
    FOREIGN KEY (company_id, document_id)
    REFERENCES hasad.expense_documents(company_id, id) ON DELETE RESTRICT,
  CONSTRAINT expense_document_lines_company_category_fkey
    FOREIGN KEY (company_id, category_id)
    REFERENCES hasad.expense_categories(company_id, id) ON DELETE RESTRICT,
  CONSTRAINT expense_document_lines_company_account_fkey
    FOREIGN KEY (company_id, account_id)
    REFERENCES hasad.accounts(company_id, id) ON DELETE RESTRICT,
  CONSTRAINT expense_document_lines_amount_check CHECK (amount > 0),
  CONSTRAINT expense_document_lines_tax_rate_check CHECK (tax_rate IS NULL OR tax_rate >= 0),
  CONSTRAINT expense_document_lines_money_check CHECK (net>=0 AND tax>=0 AND gross>=0)
);

CREATE INDEX expense_document_lines_category_idx ON hasad.expense_document_lines (category_id);

CREATE TABLE hasad.expense_attachments (
  id uuid PRIMARY KEY,
  company_id uuid NOT NULL
    REFERENCES hasad.companies(id) ON DELETE RESTRICT,
  expense_document_id uuid NOT NULL,
  storage_path text NOT NULL,
  content_hash bytea NOT NULL,
  byte_size bigint NOT NULL,
  mime text NOT NULL,
  uploaded_by uuid NOT NULL
    REFERENCES hasad.user_profiles(id) ON DELETE RESTRICT,
  uploaded_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT expense_attachments_company_id_id_key UNIQUE (company_id, id),
  CONSTRAINT expense_attachments_company_document_fkey
    FOREIGN KEY (company_id, expense_document_id)
    REFERENCES hasad.expense_documents(company_id, id) ON DELETE RESTRICT,
  CONSTRAINT expense_attachments_byte_size_check CHECK (byte_size > 0)
);

CREATE TABLE hasad.expense_receipt_dedup (
  id uuid PRIMARY KEY,
  company_id uuid NOT NULL
    REFERENCES hasad.companies(id) ON DELETE RESTRICT,
  party_id uuid NULL,
  external_ref text NOT NULL,
  expense_document_id uuid NOT NULL,
  status text NOT NULL DEFAULT 'active',
  CONSTRAINT expense_receipt_dedup_company_id_id_key UNIQUE (company_id, id),
  CONSTRAINT expense_receipt_dedup_company_party_fkey
    FOREIGN KEY (company_id, party_id)
    REFERENCES hasad.parties(company_id, id) ON DELETE RESTRICT,
  CONSTRAINT expense_receipt_dedup_company_document_fkey
    FOREIGN KEY (company_id, expense_document_id)
    REFERENCES hasad.expense_documents(company_id, id) ON DELETE RESTRICT,
  CONSTRAINT expense_receipt_dedup_company_party_external_ref_key UNIQUE (company_id, party_id, external_ref),
  CONSTRAINT expense_receipt_dedup_status_check CHECK (status IN ('active','released'))
);

ALTER TABLE hasad.cashboxes ENABLE ROW LEVEL SECURITY;
ALTER TABLE hasad.cashboxes FORCE ROW LEVEL SECURITY;
ALTER TABLE hasad.bank_accounts ENABLE ROW LEVEL SECURITY;
ALTER TABLE hasad.bank_accounts FORCE ROW LEVEL SECURITY;
ALTER TABLE hasad.payment_documents ENABLE ROW LEVEL SECURITY;
ALTER TABLE hasad.payment_documents FORCE ROW LEVEL SECURITY;
ALTER TABLE hasad.payment_allocations ENABLE ROW LEVEL SECURITY;
ALTER TABLE hasad.payment_allocations FORCE ROW LEVEL SECURITY;
ALTER TABLE hasad.reconciliation_statements ENABLE ROW LEVEL SECURITY;
ALTER TABLE hasad.reconciliation_statements FORCE ROW LEVEL SECURITY;
ALTER TABLE hasad.reconciliation_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE hasad.reconciliation_items FORCE ROW LEVEL SECURITY;
ALTER TABLE hasad.expense_categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE hasad.expense_categories FORCE ROW LEVEL SECURITY;
ALTER TABLE hasad.expense_documents ENABLE ROW LEVEL SECURITY;
ALTER TABLE hasad.expense_documents FORCE ROW LEVEL SECURITY;
ALTER TABLE hasad.expense_document_lines ENABLE ROW LEVEL SECURITY;
ALTER TABLE hasad.expense_document_lines FORCE ROW LEVEL SECURITY;
ALTER TABLE hasad.expense_attachments ENABLE ROW LEVEL SECURITY;
ALTER TABLE hasad.expense_attachments FORCE ROW LEVEL SECURITY;
ALTER TABLE hasad.expense_receipt_dedup ENABLE ROW LEVEL SECURITY;
ALTER TABLE hasad.expense_receipt_dedup FORCE ROW LEVEL SECURITY;

COMMIT;
