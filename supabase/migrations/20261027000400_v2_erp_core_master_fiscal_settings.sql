-- Hasad ERP V2 core master, fiscal, settings, and party structural foundation
-- Target: Supabase DEV sxasnunzspkuwbxiddqd
-- Depends on: 20261026000000, 20261026000100, 20261026000200,
--             20261026000210, 20261027000300
--
-- Scope: exactly nine private, empty, default-deny structural tables:
-- company_settings, accounts, module_account_map, fiscal_years, fiscal_periods,
-- document_types, tax_rates, doc_numbers, and parties.
--
-- Source: docs/17_ERP_STRUCTURAL_READINESS_PACKAGE.md, Core-nine OWNER
-- APPROVAL BLOCK accepted 2026-10-27. This migration deliberately includes no
-- seed rows, policies, grants, functions, triggers, RPCs, PostgREST exposure,
-- Auth changes, Storage changes, or modification of existing V2 tables.
--
-- Cross-row lifecycle enforcement (fiscal overlap/period generation, tax-window
-- overlap, CoA cycles and leaf eligibility, numbering allocation/locking,
-- classification, and deactivation-in-use) is deferred to later approved
-- transaction logic. No structural constraint below claims to enforce it.

BEGIN;

CREATE TABLE hasad.company_settings (
  company_id uuid PRIMARY KEY
    REFERENCES hasad.companies(id) ON DELETE RESTRICT,
  name_ar text NOT NULL,
  name_en text NULL,
  display_name text NULL,
  address_line1 text NULL,
  address_line2 text NULL,
  city text NULL,
  region text NULL,
  postal_code text NULL,
  phone text NULL,
  email text NULL,
  website text NULL,
  tax_id text NULL,
  registry_no text NULL,
  currency text NOT NULL DEFAULT 'ILS',
  vat_enabled boolean NOT NULL DEFAULT false,
  logo_storage_path text NULL,
  preferences jsonb NOT NULL DEFAULT '{}'::jsonb,
  updated_at timestamptz NOT NULL DEFAULT now(),
  updated_by uuid NULL
    REFERENCES hasad.user_profiles(id) ON DELETE RESTRICT,
  CONSTRAINT company_settings_currency_check CHECK (currency = 'ILS'),
  CONSTRAINT company_settings_preferences_object_check
    CHECK (jsonb_typeof(preferences) = 'object')
);

CREATE TABLE hasad.accounts (
  id uuid PRIMARY KEY,
  company_id uuid NOT NULL
    REFERENCES hasad.companies(id) ON DELETE RESTRICT,
  code text NOT NULL,
  name_ar text NOT NULL,
  name_en text NULL,
  account_type text NOT NULL,
  parent_id uuid NULL,
  is_active boolean NOT NULL DEFAULT true,
  CONSTRAINT accounts_company_id_id_key UNIQUE (company_id, id),
  CONSTRAINT accounts_company_code_key UNIQUE (company_id, code),
  CONSTRAINT accounts_account_type_check
    CHECK (account_type IN ('asset', 'liability', 'equity', 'revenue', 'expense')),
  CONSTRAINT accounts_company_parent_fkey
    FOREIGN KEY (company_id, parent_id)
    REFERENCES hasad.accounts(company_id, id) ON DELETE RESTRICT
);

CREATE INDEX accounts_company_parent_idx
  ON hasad.accounts (company_id, parent_id);

CREATE TABLE hasad.module_account_map (
  id uuid PRIMARY KEY,
  company_id uuid NOT NULL
    REFERENCES hasad.companies(id) ON DELETE RESTRICT,
  module text NOT NULL,
  account_role text NOT NULL,
  account_id uuid NOT NULL,
  CONSTRAINT module_account_map_company_id_id_key UNIQUE (company_id, id),
  CONSTRAINT module_account_map_company_module_role_key
    UNIQUE (company_id, module, account_role),
  CONSTRAINT module_account_map_company_account_fkey
    FOREIGN KEY (company_id, account_id)
    REFERENCES hasad.accounts(company_id, id) ON DELETE RESTRICT
);

CREATE INDEX module_account_map_company_account_idx
  ON hasad.module_account_map (company_id, account_id);

CREATE TABLE hasad.fiscal_years (
  id uuid PRIMARY KEY,
  company_id uuid NOT NULL
    REFERENCES hasad.companies(id) ON DELETE RESTRICT,
  start_date date NOT NULL,
  end_date date NOT NULL,
  status text NOT NULL DEFAULT 'open',
  closed_at timestamptz NULL,
  closed_by uuid NULL
    REFERENCES hasad.user_profiles(id) ON DELETE RESTRICT,
  reopened_at timestamptz NULL,
  reopened_by uuid NULL
    REFERENCES hasad.user_profiles(id) ON DELETE RESTRICT,
  reopen_count integer NOT NULL DEFAULT 0,
  CONSTRAINT fiscal_years_company_id_id_key UNIQUE (company_id, id),
  CONSTRAINT fiscal_years_company_start_date_key UNIQUE (company_id, start_date),
  CONSTRAINT fiscal_years_status_check CHECK (status IN ('open', 'closed')),
  CONSTRAINT fiscal_years_reopen_count_check CHECK (reopen_count >= 0),
  CONSTRAINT fiscal_years_start_date_check
    CHECK (extract(month FROM start_date) = 1 AND extract(day FROM start_date) = 1),
  CONSTRAINT fiscal_years_end_date_check
    CHECK (end_date = (start_date + interval '1 year - 1 day')::date)
);

CREATE INDEX fiscal_years_company_status_idx
  ON hasad.fiscal_years (company_id, status);

CREATE TABLE hasad.fiscal_periods (
  id uuid PRIMARY KEY,
  company_id uuid NOT NULL
    REFERENCES hasad.companies(id) ON DELETE RESTRICT,
  fiscal_year_id uuid NOT NULL,
  period_no smallint NOT NULL,
  start_date date NOT NULL,
  end_date date NOT NULL,
  status text NOT NULL DEFAULT 'open',
  closed_at timestamptz NULL,
  closed_by uuid NULL
    REFERENCES hasad.user_profiles(id) ON DELETE RESTRICT,
  reopened_at timestamptz NULL,
  reopened_by uuid NULL
    REFERENCES hasad.user_profiles(id) ON DELETE RESTRICT,
  reopen_count integer NOT NULL DEFAULT 0,
  CONSTRAINT fiscal_periods_company_id_id_key UNIQUE (company_id, id),
  CONSTRAINT fiscal_periods_year_period_no_key UNIQUE (fiscal_year_id, period_no),
  CONSTRAINT fiscal_periods_company_year_fkey
    FOREIGN KEY (company_id, fiscal_year_id)
    REFERENCES hasad.fiscal_years(company_id, id) ON DELETE RESTRICT,
  CONSTRAINT fiscal_periods_period_no_check CHECK (period_no BETWEEN 1 AND 12),
  CONSTRAINT fiscal_periods_end_date_check CHECK (end_date >= start_date),
  CONSTRAINT fiscal_periods_status_check CHECK (status IN ('open', 'closed')),
  CONSTRAINT fiscal_periods_reopen_count_check CHECK (reopen_count >= 0)
);

CREATE INDEX fiscal_periods_company_status_dates_idx
  ON hasad.fiscal_periods (company_id, status, start_date, end_date);

CREATE TABLE hasad.document_types (
  id uuid PRIMARY KEY,
  company_id uuid NOT NULL
    REFERENCES hasad.companies(id) ON DELETE RESTRICT,
  code text NOT NULL,
  name_ar text NOT NULL,
  issuance text NOT NULL,
  format_prefix text NULL,
  pad_length smallint NOT NULL DEFAULT 4,
  is_active boolean NOT NULL DEFAULT true,
  CONSTRAINT document_types_company_id_id_key UNIQUE (company_id, id),
  CONSTRAINT document_types_company_code_key UNIQUE (company_id, code),
  CONSTRAINT document_types_issuance_check CHECK (issuance IN ('posting', 'creation')),
  CONSTRAINT document_types_pad_length_check CHECK (pad_length BETWEEN 1 AND 10)
);

CREATE TABLE hasad.tax_rates (
  id uuid PRIMARY KEY,
  company_id uuid NOT NULL
    REFERENCES hasad.companies(id) ON DELETE RESTRICT,
  code text NOT NULL,
  rate numeric(6,3) NOT NULL,
  valid_from date NOT NULL,
  valid_to date NULL,
  is_active boolean NOT NULL DEFAULT true,
  CONSTRAINT tax_rates_company_id_id_key UNIQUE (company_id, id),
  CONSTRAINT tax_rates_company_code_valid_from_key UNIQUE (company_id, code, valid_from),
  CONSTRAINT tax_rates_rate_check CHECK (rate >= 0),
  CONSTRAINT tax_rates_valid_dates_check CHECK (valid_to IS NULL OR valid_to >= valid_from)
);

CREATE INDEX tax_rates_company_active_code_idx
  ON hasad.tax_rates (company_id, code)
  WHERE is_active;

CREATE TABLE hasad.doc_numbers (
  company_id uuid NOT NULL,
  document_type_id uuid NOT NULL,
  fiscal_year_id uuid NOT NULL,
  next_value bigint NOT NULL DEFAULT 1,
  CONSTRAINT doc_numbers_pkey PRIMARY KEY (company_id, document_type_id, fiscal_year_id),
  CONSTRAINT doc_numbers_company_document_type_fkey
    FOREIGN KEY (company_id, document_type_id)
    REFERENCES hasad.document_types(company_id, id) ON DELETE RESTRICT,
  CONSTRAINT doc_numbers_company_fiscal_year_fkey
    FOREIGN KEY (company_id, fiscal_year_id)
    REFERENCES hasad.fiscal_years(company_id, id) ON DELETE RESTRICT,
  CONSTRAINT doc_numbers_next_value_check CHECK (next_value > 0)
);

CREATE TABLE hasad.parties (
  id uuid PRIMARY KEY,
  company_id uuid NOT NULL
    REFERENCES hasad.companies(id) ON DELETE RESTRICT,
  code text NOT NULL,
  name_ar text NOT NULL,
  name_en text NULL,
  party_type text NOT NULL,
  is_customer boolean NOT NULL DEFAULT false,
  is_supplier boolean NOT NULL DEFAULT false,
  tax_id text NULL,
  phone text NULL,
  email text NULL,
  address text NULL,
  payment_terms_days integer NULL,
  is_active boolean NOT NULL DEFAULT true,
  CONSTRAINT parties_company_id_id_key UNIQUE (company_id, id),
  CONSTRAINT parties_company_code_key UNIQUE (company_id, code),
  CONSTRAINT parties_party_type_check CHECK (party_type IN ('individual', 'company')),
  CONSTRAINT parties_payment_terms_days_check
    CHECK (payment_terms_days IS NULL OR payment_terms_days >= 0)
);

CREATE INDEX parties_company_name_ar_idx
  ON hasad.parties (company_id, lower(name_ar));

CREATE INDEX parties_company_customer_idx
  ON hasad.parties (company_id)
  WHERE is_customer;

CREATE INDEX parties_company_supplier_idx
  ON hasad.parties (company_id)
  WHERE is_supplier;

ALTER TABLE hasad.company_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE hasad.company_settings FORCE ROW LEVEL SECURITY;
ALTER TABLE hasad.accounts ENABLE ROW LEVEL SECURITY;
ALTER TABLE hasad.accounts FORCE ROW LEVEL SECURITY;
ALTER TABLE hasad.module_account_map ENABLE ROW LEVEL SECURITY;
ALTER TABLE hasad.module_account_map FORCE ROW LEVEL SECURITY;
ALTER TABLE hasad.fiscal_years ENABLE ROW LEVEL SECURITY;
ALTER TABLE hasad.fiscal_years FORCE ROW LEVEL SECURITY;
ALTER TABLE hasad.fiscal_periods ENABLE ROW LEVEL SECURITY;
ALTER TABLE hasad.fiscal_periods FORCE ROW LEVEL SECURITY;
ALTER TABLE hasad.document_types ENABLE ROW LEVEL SECURITY;
ALTER TABLE hasad.document_types FORCE ROW LEVEL SECURITY;
ALTER TABLE hasad.tax_rates ENABLE ROW LEVEL SECURITY;
ALTER TABLE hasad.tax_rates FORCE ROW LEVEL SECURITY;
ALTER TABLE hasad.doc_numbers ENABLE ROW LEVEL SECURITY;
ALTER TABLE hasad.doc_numbers FORCE ROW LEVEL SECURITY;
ALTER TABLE hasad.parties ENABLE ROW LEVEL SECURITY;
ALTER TABLE hasad.parties FORCE ROW LEVEL SECURITY;

COMMIT;
