-- Hasad ERP V2 — Phase 9A employee and organization master
-- LOCAL STRUCTURAL CANDIDATE — NOT DEPLOYABLE
-- Target identification only: Supabase DEV sxasnunzspkuwbxiddqd
-- Depends on: 20261029000900_v2_expenses_structure.sql and all prior V2 migrations
--
-- Scope exactly: hasad.departments, hasad.job_titles, hasad.employees.
-- P9A-G1 owner authorization (2026-10-28): local preparation and disposable-local
-- PostgreSQL testing only. No DEV/production execution is authorized.
--
-- No seeds, policies, grants, functions, triggers, RPCs, API exposure, Auth/Storage
-- changes, or changes to existing tables are included.

BEGIN;

CREATE TABLE hasad.departments (
  id uuid PRIMARY KEY,
  company_id uuid NOT NULL,
  code text NOT NULL,
  name_ar text NOT NULL,
  is_active boolean NOT NULL DEFAULT true,
  CONSTRAINT departments_company_fkey
    FOREIGN KEY (company_id)
    REFERENCES hasad.companies(id) ON DELETE RESTRICT,
  CONSTRAINT departments_company_id_id_key UNIQUE (company_id, id),
  CONSTRAINT departments_company_code_key UNIQUE (company_id, code),
  CONSTRAINT departments_code_nonblank_check CHECK (code ~ '[^[:space:]]'),
  CONSTRAINT departments_name_ar_nonblank_check CHECK (name_ar ~ '[^[:space:]]')
);

CREATE TABLE hasad.job_titles (
  id uuid PRIMARY KEY,
  company_id uuid NOT NULL,
  code text NOT NULL,
  name_ar text NOT NULL,
  is_active boolean NOT NULL DEFAULT true,
  CONSTRAINT job_titles_company_fkey
    FOREIGN KEY (company_id)
    REFERENCES hasad.companies(id) ON DELETE RESTRICT,
  CONSTRAINT job_titles_company_id_id_key UNIQUE (company_id, id),
  CONSTRAINT job_titles_company_code_key UNIQUE (company_id, code),
  CONSTRAINT job_titles_code_nonblank_check CHECK (code ~ '[^[:space:]]'),
  CONSTRAINT job_titles_name_ar_nonblank_check CHECK (name_ar ~ '[^[:space:]]')
);

CREATE TABLE hasad.employees (
  id uuid PRIMARY KEY,
  company_id uuid NOT NULL,
  employee_code text NOT NULL,
  name_ar text NOT NULL,
  status text NOT NULL,
  hire_date date NOT NULL,
  termination_date date NULL,
  department_id uuid NULL,
  job_title_id uuid NULL,
  CONSTRAINT employees_company_fkey
    FOREIGN KEY (company_id)
    REFERENCES hasad.companies(id) ON DELETE RESTRICT,
  CONSTRAINT employees_company_id_id_key UNIQUE (company_id, id),
  CONSTRAINT employees_company_employee_code_key UNIQUE (company_id, employee_code),
  CONSTRAINT employees_company_department_fkey
    FOREIGN KEY (company_id, department_id)
    REFERENCES hasad.departments(company_id, id) ON DELETE RESTRICT,
  CONSTRAINT employees_company_job_title_fkey
    FOREIGN KEY (company_id, job_title_id)
    REFERENCES hasad.job_titles(company_id, id) ON DELETE RESTRICT,
  CONSTRAINT employees_employee_code_nonblank_check CHECK (employee_code ~ '[^[:space:]]'),
  CONSTRAINT employees_name_ar_nonblank_check CHECK (name_ar ~ '[^[:space:]]'),
  CONSTRAINT employees_status_check CHECK (status IN ('active', 'suspended', 'terminated')),
  CONSTRAINT employees_termination_status_check CHECK (
    (status = 'terminated' AND termination_date IS NOT NULL)
    OR (status IN ('active', 'suspended') AND termination_date IS NULL)
  ),
  CONSTRAINT employees_termination_date_check CHECK (
    termination_date IS NULL OR termination_date >= hire_date
  )
);

ALTER TABLE hasad.departments ENABLE ROW LEVEL SECURITY;
ALTER TABLE hasad.departments FORCE ROW LEVEL SECURITY;
ALTER TABLE hasad.job_titles ENABLE ROW LEVEL SECURITY;
ALTER TABLE hasad.job_titles FORCE ROW LEVEL SECURITY;
ALTER TABLE hasad.employees ENABLE ROW LEVEL SECURITY;
ALTER TABLE hasad.employees FORCE ROW LEVEL SECURITY;

COMMIT;
