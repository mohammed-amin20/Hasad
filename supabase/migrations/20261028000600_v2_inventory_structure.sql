-- Hasad ERP V2 — Inventory (STRUCTURAL CANDIDATE — NOT DEPLOYABLE)
-- Target: Supabase DEV sxasnunzspkuwbxiddqd (NO PUSH WITHOUT EXPLICIT OWNER APPROVAL)
-- Depends on: 20261027000400 and prior
--
-- Scope (proposed): warehouses, product_categories, units_of_measure, products,
-- product_uom_conversions, stock_levels, stock_movements, stock_counts, stock_count_lines
-- Source: docs/17_ERP_STRUCTURAL_READINESS_PACKAGE.md §E2
--
-- Conventions: ON DELETE RESTRICT, composite tenant FKs where needed,
-- ENABLE+FORCE RLS, zero policies/grants/functions/triggers/seeds/RPCs.
-- Precision numeric(19,4)/(19,6) as proposed; no costing/locking logic.

BEGIN;

CREATE TABLE hasad.warehouses (
  id uuid PRIMARY KEY,
  company_id uuid NOT NULL
    REFERENCES hasad.companies(id) ON DELETE RESTRICT,
  code text NOT NULL,
  name_ar text NOT NULL,
  is_active boolean NOT NULL DEFAULT true,
  CONSTRAINT warehouses_company_id_id_key UNIQUE (company_id, id),
  CONSTRAINT warehouses_company_code_key UNIQUE (company_id, code)
);

CREATE TABLE hasad.product_categories (
  id uuid PRIMARY KEY,
  company_id uuid NOT NULL
    REFERENCES hasad.companies(id) ON DELETE RESTRICT,
  code text NOT NULL,
  name_ar text NOT NULL,
  is_active boolean NOT NULL DEFAULT true,
  CONSTRAINT product_categories_company_id_id_key UNIQUE (company_id, id),
  CONSTRAINT product_categories_company_code_key UNIQUE (company_id, code)
);

CREATE TABLE hasad.units_of_measure (
  id uuid PRIMARY KEY,
  company_id uuid NOT NULL
    REFERENCES hasad.companies(id) ON DELETE RESTRICT,
  code text NOT NULL,
  name_ar text NOT NULL,
  is_base boolean NOT NULL DEFAULT false,
  is_active boolean NOT NULL DEFAULT true,
  CONSTRAINT units_of_measure_company_id_id_key UNIQUE (company_id, id),
  CONSTRAINT units_of_measure_company_code_key UNIQUE (company_id, code)
);

CREATE TABLE hasad.products (
  id uuid PRIMARY KEY,
  company_id uuid NOT NULL
    REFERENCES hasad.companies(id) ON DELETE RESTRICT,
  code text NOT NULL,
  name_ar text NOT NULL,
  name_en text NULL,
  barcode text NULL,
  category_id uuid NULL,
  base_uom_id uuid NOT NULL,
  track_inventory boolean NOT NULL DEFAULT true,
  is_active boolean NOT NULL DEFAULT true,
  CONSTRAINT products_company_id_id_key UNIQUE (company_id, id),
  CONSTRAINT products_company_code_key UNIQUE (company_id, code),
  CONSTRAINT products_barcode_key UNIQUE (barcode),
  CONSTRAINT products_company_category_fkey
    FOREIGN KEY (company_id, category_id)
    REFERENCES hasad.product_categories(company_id, id) ON DELETE RESTRICT,
  CONSTRAINT products_company_uom_fkey
    FOREIGN KEY (company_id, base_uom_id)
    REFERENCES hasad.units_of_measure(company_id, id) ON DELETE RESTRICT
);

CREATE TABLE hasad.product_uom_conversions (
  id uuid PRIMARY KEY,
  company_id uuid NOT NULL
    REFERENCES hasad.companies(id) ON DELETE RESTRICT,
  product_id uuid NOT NULL,
  uom_id uuid NOT NULL,
  factor numeric(19,6) NOT NULL,
  CONSTRAINT product_uom_conversions_company_id_id_key UNIQUE (company_id, id),
  CONSTRAINT product_uom_conversions_company_product_uom_key UNIQUE (company_id, product_id, uom_id),
  CONSTRAINT product_uom_conversions_company_product_fkey
    FOREIGN KEY (company_id, product_id)
    REFERENCES hasad.products(company_id, id) ON DELETE RESTRICT,
  CONSTRAINT product_uom_conversions_company_uom_fkey
    FOREIGN KEY (company_id, uom_id)
    REFERENCES hasad.units_of_measure(company_id, id) ON DELETE RESTRICT,
  CONSTRAINT product_uom_conversions_factor_check CHECK (factor > 0)
);

CREATE TABLE hasad.stock_levels (
  company_id uuid NOT NULL
    REFERENCES hasad.companies(id) ON DELETE RESTRICT,
  product_id uuid NOT NULL,
  warehouse_id uuid NOT NULL,
  qty numeric(19,4) NOT NULL DEFAULT 0,
  last_unit_cost numeric(19,4) NOT NULL DEFAULT 0,
  CONSTRAINT stock_levels_pkey PRIMARY KEY (company_id, product_id, warehouse_id),
  CONSTRAINT stock_levels_company_product_fkey
    FOREIGN KEY (company_id, product_id)
    REFERENCES hasad.products(company_id, id) ON DELETE RESTRICT,
  CONSTRAINT stock_levels_company_warehouse_fkey
    FOREIGN KEY (company_id, warehouse_id)
    REFERENCES hasad.warehouses(company_id, id) ON DELETE RESTRICT,
  CONSTRAINT stock_levels_qty_check CHECK (qty >= 0),
  CONSTRAINT stock_levels_cost_check CHECK (last_unit_cost >= 0)
);

CREATE TABLE hasad.stock_movements (
  id uuid PRIMARY KEY,
  company_id uuid NOT NULL
    REFERENCES hasad.companies(id) ON DELETE RESTRICT,
  product_id uuid NOT NULL,
  warehouse_id uuid NOT NULL,
  movement_type text NOT NULL,
  direction text NOT NULL,
  qty numeric(19,4) NOT NULL,
  unit_cost numeric(19,4) NOT NULL,
  value numeric(18,2) NOT NULL,
  seq bigint NOT NULL,
  source_document_type text NULL,
  source_document_id uuid NULL,
  journal_line_id uuid NULL,
  posted_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT stock_movements_company_id_id_key UNIQUE (company_id, id),
  CONSTRAINT stock_movements_product_seq_key UNIQUE (product_id, seq),
  CONSTRAINT stock_movements_company_product_fkey
    FOREIGN KEY (company_id, product_id)
    REFERENCES hasad.products(company_id, id) ON DELETE RESTRICT,
  CONSTRAINT stock_movements_company_warehouse_fkey
    FOREIGN KEY (company_id, warehouse_id)
    REFERENCES hasad.warehouses(company_id, id) ON DELETE RESTRICT,
  CONSTRAINT stock_movements_direction_check CHECK (direction IN ('in','out')),
  CONSTRAINT stock_movements_qty_check CHECK (qty > 0),
  CONSTRAINT stock_movements_cost_check CHECK (unit_cost >= 0)
);

CREATE INDEX stock_movements_company_product_wh_idx ON hasad.stock_movements (company_id, product_id, warehouse_id, posted_at);
CREATE INDEX stock_movements_source_idx ON hasad.stock_movements (source_document_type, source_document_id);

CREATE TABLE hasad.stock_counts (
  id uuid PRIMARY KEY,
  company_id uuid NOT NULL
    REFERENCES hasad.companies(id) ON DELETE RESTRICT,
  warehouse_id uuid NOT NULL,
  count_date date NOT NULL,
  status text NOT NULL DEFAULT 'open',
  CONSTRAINT stock_counts_company_id_id_key UNIQUE (company_id, id),
  CONSTRAINT stock_counts_company_warehouse_fkey
    FOREIGN KEY (company_id, warehouse_id)
    REFERENCES hasad.warehouses(company_id, id) ON DELETE RESTRICT,
  CONSTRAINT stock_counts_status_check CHECK (status IN ('open','posted'))
);

CREATE TABLE hasad.stock_count_lines (
  id uuid PRIMARY KEY,
  company_id uuid NOT NULL
    REFERENCES hasad.companies(id) ON DELETE RESTRICT,
  count_id uuid NOT NULL,
  product_id uuid NOT NULL,
  counted_qty numeric(19,4) NOT NULL,
  CONSTRAINT stock_count_lines_company_id_id_key UNIQUE (company_id, id),
  CONSTRAINT stock_count_lines_count_product_key UNIQUE (count_id, product_id),
  CONSTRAINT stock_count_lines_company_count_fkey
    FOREIGN KEY (company_id, count_id)
    REFERENCES hasad.stock_counts(company_id, id) ON DELETE RESTRICT,
  CONSTRAINT stock_count_lines_company_product_fkey
    FOREIGN KEY (company_id, product_id)
    REFERENCES hasad.products(company_id, id) ON DELETE RESTRICT,
  CONSTRAINT stock_count_lines_qty_check CHECK (counted_qty >= 0)
);

CREATE INDEX stock_count_lines_product_idx ON hasad.stock_count_lines (product_id);

ALTER TABLE hasad.warehouses ENABLE ROW LEVEL SECURITY;
ALTER TABLE hasad.warehouses FORCE ROW LEVEL SECURITY;
ALTER TABLE hasad.product_categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE hasad.product_categories FORCE ROW LEVEL SECURITY;
ALTER TABLE hasad.units_of_measure ENABLE ROW LEVEL SECURITY;
ALTER TABLE hasad.units_of_measure FORCE ROW LEVEL SECURITY;
ALTER TABLE hasad.products ENABLE ROW LEVEL SECURITY;
ALTER TABLE hasad.products FORCE ROW LEVEL SECURITY;
ALTER TABLE hasad.product_uom_conversions ENABLE ROW LEVEL SECURITY;
ALTER TABLE hasad.product_uom_conversions FORCE ROW LEVEL SECURITY;
ALTER TABLE hasad.stock_levels ENABLE ROW LEVEL SECURITY;
ALTER TABLE hasad.stock_levels FORCE ROW LEVEL SECURITY;
ALTER TABLE hasad.stock_movements ENABLE ROW LEVEL SECURITY;
ALTER TABLE hasad.stock_movements FORCE ROW LEVEL SECURITY;
ALTER TABLE hasad.stock_counts ENABLE ROW LEVEL SECURITY;
ALTER TABLE hasad.stock_counts FORCE ROW LEVEL SECURITY;
ALTER TABLE hasad.stock_count_lines ENABLE ROW LEVEL SECURITY;
ALTER TABLE hasad.stock_count_lines FORCE ROW LEVEL SECURITY;

COMMIT;
