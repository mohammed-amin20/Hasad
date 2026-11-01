-- Hasad ERP V2 — Cash/Banking/Payments/Reconciliation (STRUCTURAL CANDIDATE — NOT DEPLOYABLE)
-- Target: Supabase DEV sxasnunzspkuwbxiddqd (NO PUSH WITHOUT EXPLICIT OWNER APPROVAL)
-- Depends on: 20261026000000,20261026000100,20261026000200,20261026000210,20261027000300,20261027000400,20261028000500,20261028000600,20261028000700
--
-- Scope (proposed): cashboxes, bank_accounts, payment_documents, payment_allocations, reconciliation_statements, reconciliation_items
-- Source: docs/17_ERP_STRUCTURAL_READINESS_PACKAGE.md §E3
--
-- Conventions: UUID keys without DB defaults; tenant-safe composite FKs where parent is tenant-scoped; ON DELETE RESTRICT;
-- ENABLE+FORCE RLS, zero policies/grants/functions/triggers/seeds/RPCs. Monetary numeric(18,2). Behavior deferred.

BEGIN;

CREATE TABLE hasad.cashboxes (
  id uuid PRIMARY KEY,
  company_id uuid NOT NULL
    REFERENCES hasad.companies(id) ON DELETE RESTRICT,
  code text NOT NULL,
  name_ar text NOT NULL,
  account_id uuid NOT NULL,
  is_active boolean NOT NULL DEFAULT true,
  CONSTRAINT cashboxes_company_id_id_key UNIQUE (company_id, id),
  CONSTRAINT cashboxes_company_code_key UNIQUE (company_id, code),
  CONSTRAINT cashboxes_company_account_fkey
    FOREIGN KEY (company_id, account_id)
    REFERENCES hasad.accounts(company_id, id) ON DELETE RESTRICT
);

CREATE TABLE hasad.bank_accounts (
  id uuid PRIMARY KEY,
  company_id uuid NOT NULL
    REFERENCES hasad.companies(id) ON DELETE RESTRICT,
  code text NOT NULL,
  name_ar text NOT NULL,
  account_id uuid NOT NULL,
  bank_name text NULL,
  branch_no text NULL,
  account_no text NULL,
  iban text NULL,
  is_active boolean NOT NULL DEFAULT true,
  CONSTRAINT bank_accounts_company_id_id_key UNIQUE (company_id, id),
  CONSTRAINT bank_accounts_company_code_key UNIQUE (company_id, code),
  CONSTRAINT bank_accounts_company_account_fkey
    FOREIGN KEY (company_id, account_id)
    REFERENCES hasad.accounts(company_id, id) ON DELETE RESTRICT
);

CREATE TABLE hasad.payment_documents (
  id uuid PRIMARY KEY,
  company_id uuid NOT NULL
    REFERENCES hasad.companies(id) ON DELETE RESTRICT,
  doc_kind text NOT NULL,
  status text NOT NULL DEFAULT 'draft',
  party_id uuid NULL,
  employee_id uuid NULL,
  from_account_id uuid NULL,
  to_account_id uuid NULL,
  amount numeric(18,2) NOT NULL,
  doc_type_id uuid NOT NULL,
  fiscal_year_id uuid NOT NULL,
  doc_no text NULL,
  reversal_of_id uuid NULL,
  idempotency_key uuid NULL,
  tender_method text NULL,
  tender_reference text NULL,
  posted_at timestamptz NULL,
  CONSTRAINT payment_documents_company_id_id_key UNIQUE (company_id, id),
  CONSTRAINT payment_documents_company_party_fkey
    FOREIGN KEY (company_id, party_id)
    REFERENCES hasad.parties(company_id, id) ON DELETE RESTRICT,
  CONSTRAINT payment_documents_company_doc_type_fkey
    FOREIGN KEY (company_id, doc_type_id)
    REFERENCES hasad.document_types(company_id, id) ON DELETE RESTRICT,
  CONSTRAINT payment_documents_company_fiscal_year_fkey
    FOREIGN KEY (company_id, fiscal_year_id)
    REFERENCES hasad.fiscal_years(company_id, id) ON DELETE RESTRICT,
  CONSTRAINT payment_documents_company_reversal_fkey
    FOREIGN KEY (company_id, reversal_of_id)
    REFERENCES hasad.payment_documents(company_id, id) ON DELETE RESTRICT,
  CONSTRAINT payment_documents_doc_kind_check CHECK (doc_kind IN ('receipt','payment','transfer','refund')),
  CONSTRAINT payment_documents_status_check CHECK (status IN ('draft','posted','cancelled')),
  CONSTRAINT payment_documents_amount_check CHECK (amount > 0)
);

CREATE UNIQUE INDEX payment_documents_company_idempotency_key_key
  ON hasad.payment_documents (company_id, idempotency_key)
  WHERE idempotency_key IS NOT NULL;

CREATE UNIQUE INDEX payment_documents_company_doc_no_key
  ON hasad.payment_documents (company_id, doc_no)
  WHERE doc_no IS NOT NULL;

CREATE INDEX payment_documents_company_party_idx ON hasad.payment_documents (company_id, party_id);
CREATE INDEX payment_documents_company_date_idx ON hasad.payment_documents (company_id, posted_at);

CREATE TABLE hasad.payment_allocations (
  id uuid PRIMARY KEY,
  company_id uuid NOT NULL
    REFERENCES hasad.companies(id) ON DELETE RESTRICT,
  payment_id uuid NOT NULL,
  target_kind text NOT NULL,
  sales_document_id uuid NULL,
  purchase_document_id uuid NULL,
  expense_document_id uuid NULL,
  amount numeric(18,2) NOT NULL,
  status text NOT NULL DEFAULT 'active',
  supersedes_id uuid NULL,
  CONSTRAINT payment_allocations_company_id_id_key UNIQUE (company_id, id),
  CONSTRAINT payment_allocations_company_payment_fkey
    FOREIGN KEY (company_id, payment_id)
    REFERENCES hasad.payment_documents(company_id, id) ON DELETE RESTRICT,
  CONSTRAINT payment_allocations_company_sales_fkey
    FOREIGN KEY (company_id, sales_document_id)
    REFERENCES hasad.sales_documents(company_id, id) ON DELETE RESTRICT,
  CONSTRAINT payment_allocations_company_purchase_fkey
    FOREIGN KEY (company_id, purchase_document_id)
    REFERENCES hasad.purchase_documents(company_id, id) ON DELETE RESTRICT,
  CONSTRAINT payment_allocations_target_kind_check CHECK (target_kind IN ('sales','purchase','expense')),
  CONSTRAINT payment_allocations_status_check CHECK (status IN ('active','superseded','reversed')),
  CONSTRAINT payment_allocations_amount_check CHECK (amount > 0),
  CONSTRAINT payment_allocations_exactly_one_target_check
    CHECK (
      (target_kind='sales' AND sales_document_id IS NOT NULL AND purchase_document_id IS NULL AND expense_document_id IS NULL) OR
      (target_kind='purchase' AND purchase_document_id IS NOT NULL AND sales_document_id IS NULL AND expense_document_id IS NULL) OR
      (target_kind='expense' AND expense_document_id IS NOT NULL AND sales_document_id IS NULL AND purchase_document_id IS NULL)
    )
);

CREATE INDEX payment_allocations_payment_idx ON hasad.payment_allocations (payment_id);
CREATE INDEX payment_allocations_sales_idx ON hasad.payment_allocations (sales_document_id) WHERE sales_document_id IS NOT NULL;
CREATE INDEX payment_allocations_purchase_idx ON hasad.payment_allocations (purchase_document_id) WHERE purchase_document_id IS NOT NULL;
CREATE INDEX payment_allocations_expense_idx ON hasad.payment_allocations (expense_document_id) WHERE expense_document_id IS NOT NULL;

CREATE TABLE hasad.reconciliation_statements (
  id uuid PRIMARY KEY,
  company_id uuid NOT NULL
    REFERENCES hasad.companies(id) ON DELETE RESTRICT,
  account_id uuid NOT NULL,
  statement_date date NOT NULL,
  opening_balance numeric(18,2) NOT NULL,
  closing_balance numeric(18,2) NOT NULL,
  status text NOT NULL DEFAULT 'open',
  closed_at timestamptz NULL,
  closed_by uuid NULL
    REFERENCES hasad.user_profiles(id) ON DELETE RESTRICT,
  CONSTRAINT reconciliation_statements_company_id_id_key UNIQUE (company_id, id),
  CONSTRAINT reconciliation_statements_company_account_fkey
    FOREIGN KEY (company_id, account_id)
    REFERENCES hasad.accounts(company_id, id) ON DELETE RESTRICT,
  CONSTRAINT reconciliation_statements_status_check CHECK (status IN ('open','closed'))
);

CREATE TABLE hasad.reconciliation_items (
  id uuid PRIMARY KEY,
  company_id uuid NOT NULL
    REFERENCES hasad.companies(id) ON DELETE RESTRICT,
  statement_id uuid NOT NULL,
  value_date date NOT NULL,
  description text NOT NULL,
  amount numeric(18,2) NOT NULL,
  journal_line_id uuid NULL,
  is_external boolean NOT NULL DEFAULT true,
  CONSTRAINT reconciliation_items_company_id_id_key UNIQUE (company_id, id),
  CONSTRAINT reconciliation_items_company_statement_fkey
    FOREIGN KEY (company_id, statement_id)
    REFERENCES hasad.reconciliation_statements(company_id, id) ON DELETE RESTRICT,
  CONSTRAINT reconciliation_items_company_journal_line_fkey
    FOREIGN KEY (company_id, journal_line_id)
    REFERENCES hasad.journal_lines(company_id, id) ON DELETE RESTRICT
);

CREATE INDEX reconciliation_items_statement_idx ON hasad.reconciliation_items (statement_id);
CREATE INDEX reconciliation_items_journal_line_idx ON hasad.reconciliation_items (journal_line_id) WHERE journal_line_id IS NOT NULL;

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

COMMIT;
