-- Hasad ERP V2 — Accounting journals (STRUCTURAL CANDIDATE — NOT DEPLOYABLE)
-- Target: Supabase DEV sxasnunzspkuwbxiddqd (NO PUSH WITHOUT EXPLICIT OWNER APPROVAL)
-- Depends on: 20261026000000,20261026000100,20261026000200,20261026000210,20261027000300,20261027000400
--
-- Scope (proposed): journal_entries, journal_lines
-- Source: docs/17_ERP_STRUCTURAL_READINESS_PACKAGE.md §E1 (proposed)
--
-- Conventions: tenant-safe composite FKs where applicable, ON DELETE RESTRICT,
-- ENABLE+FORCE RLS, zero policies/grants/functions/triggers/seeds/RPCs/exposure.
-- Monetary precision follows proposed numeric(18,2) for final facts; no posting logic.
-- Cross-row validation (balance, period-open, immutability, numbering) deferred.

BEGIN;

CREATE TABLE hasad.journal_entries (
  id uuid PRIMARY KEY,
  company_id uuid NOT NULL
    REFERENCES hasad.companies(id) ON DELETE RESTRICT,
  fiscal_year_id uuid NOT NULL,
  period_id uuid NOT NULL,
  entry_date date NOT NULL,
  entry_kind text NOT NULL,
  status text NOT NULL DEFAULT 'draft',
  entry_no text NULL,
  reversal_of_id uuid NULL,
  idempotency_key uuid NULL,
  posted_at timestamptz NULL,
  posted_by uuid NULL
    REFERENCES hasad.user_profiles(id) ON DELETE RESTRICT,
  reason text NULL,
  CONSTRAINT journal_entries_company_id_id_key UNIQUE (company_id, id),
  CONSTRAINT journal_entries_company_fiscal_year_fkey
    FOREIGN KEY (company_id, fiscal_year_id)
    REFERENCES hasad.fiscal_years(company_id, id) ON DELETE RESTRICT,
  CONSTRAINT journal_entries_company_period_fkey
    FOREIGN KEY (company_id, period_id)
    REFERENCES hasad.fiscal_periods(company_id, id) ON DELETE RESTRICT,
  CONSTRAINT journal_entries_company_reversal_fkey
    FOREIGN KEY (company_id, reversal_of_id)
    REFERENCES hasad.journal_entries(company_id, id) ON DELETE RESTRICT,
  CONSTRAINT journal_entries_entry_kind_check
    CHECK (entry_kind IN ('standard','opening','closing','reversal','adjustment')),
  CONSTRAINT journal_entries_status_check CHECK (status IN ('draft','posted'))
);

CREATE UNIQUE INDEX journal_entries_company_idempotency_key_key
  ON hasad.journal_entries (company_id, idempotency_key)
  WHERE idempotency_key IS NOT NULL;

CREATE UNIQUE INDEX journal_entries_company_entry_no_key
  ON hasad.journal_entries (company_id, entry_no)
  WHERE entry_no IS NOT NULL;

CREATE INDEX journal_entries_company_period_date_idx
  ON hasad.journal_entries (company_id, period_id, entry_date);

CREATE INDEX journal_entries_reversal_of_idx
  ON hasad.journal_entries (reversal_of_id)
  WHERE reversal_of_id IS NOT NULL;

CREATE TABLE hasad.journal_lines (
  id uuid PRIMARY KEY,
  company_id uuid NOT NULL
    REFERENCES hasad.companies(id) ON DELETE RESTRICT,
  entry_id uuid NOT NULL,
  line_no integer NOT NULL,
  account_id uuid NOT NULL,
  party_id uuid NULL,
  debit numeric(18,2) NOT NULL DEFAULT 0,
  credit numeric(18,2) NOT NULL DEFAULT 0,
  description text NULL,
  CONSTRAINT journal_lines_company_id_id_key UNIQUE (company_id, id),
  CONSTRAINT journal_lines_entry_line_no_key UNIQUE (entry_id, line_no),
  CONSTRAINT journal_lines_company_entry_fkey
    FOREIGN KEY (company_id, entry_id)
    REFERENCES hasad.journal_entries(company_id, id) ON DELETE RESTRICT,
  CONSTRAINT journal_lines_company_account_fkey
    FOREIGN KEY (company_id, account_id)
    REFERENCES hasad.accounts(company_id, id) ON DELETE RESTRICT,
  CONSTRAINT journal_lines_company_party_fkey
    FOREIGN KEY (company_id, party_id)
    REFERENCES hasad.parties(company_id, id) ON DELETE RESTRICT,
  CONSTRAINT journal_lines_debit_check CHECK (debit >= 0),
  CONSTRAINT journal_lines_credit_check CHECK (credit >= 0),
  CONSTRAINT journal_lines_debit_credit_exclusive_check
    CHECK (NOT (debit > 0 AND credit > 0))
);

CREATE INDEX journal_lines_company_account_idx ON hasad.journal_lines (company_id, account_id);
CREATE INDEX journal_lines_company_party_idx ON hasad.journal_lines (company_id, party_id);
CREATE INDEX journal_lines_entry_id_idx ON hasad.journal_lines (entry_id);

ALTER TABLE hasad.journal_entries ENABLE ROW LEVEL SECURITY;
ALTER TABLE hasad.journal_entries FORCE ROW LEVEL SECURITY;
ALTER TABLE hasad.journal_lines ENABLE ROW LEVEL SECURITY;
ALTER TABLE hasad.journal_lines FORCE ROW LEVEL SECURITY;

COMMIT;
