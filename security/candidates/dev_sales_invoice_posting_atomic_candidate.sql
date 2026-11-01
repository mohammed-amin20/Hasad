-- Hasad ERP V2 / S2 — REVIEW ONLY, NOT DEPLOYABLE
-- Purpose: preserve the required atomic boundary for invoice posting.
-- No DDL/DML/GRANT/policy/role change is present in this file.
--
-- Proposed single operation (not created here):
--   hasad.post_sales_invoice(p_document_id uuid, p_idempotency_key uuid)
-- It must, in ONE database transaction: lock and validate the draft; resolve
-- authenticated active-company membership plus sales.post; resolve tax rates by
-- document date; assign a server number; calculate header/line facts; lock and
-- deduct per-warehouse stock using the approved moving-weighted-average rules;
-- insert stock movements with the invoice source; atomically update the invoice
-- to posted; write audit events; and return the original result on idempotent
-- replay. Flutter must never call post_stock_issue per line.
--
-- BLOCKERS: no approved sales posting/accounting map/audit payload contract;
-- no deployed sales policies or narrow writer owner; no verified tax-rate/doc-
-- type/fiscal-year configuration; and current stock functions cannot be safely
-- composed as independent client requests.
WITH required_objects(kind, object_name) AS (
  VALUES
    ('table', 'hasad.sales_documents'),
    ('table', 'hasad.sales_document_lines'),
    ('table', 'hasad.stock_levels'),
    ('table', 'hasad.stock_movements'),
    ('function', 'hasad.post_stock_issue'),
    ('permission', 'sales.post'),
    ('permission', 'inventory.post'),
    ('function_contract', 'post_sales_invoice(uuid,uuid)')
)
SELECT
  kind,
  object_name,
  CASE
    WHEN kind = 'table' THEN (pg_catalog.to_regclass(object_name) IS NOT NULL)::text
    WHEN kind = 'function' THEN EXISTS (
      SELECT 1 FROM pg_catalog.pg_proc p
      JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'hasad' AND p.proname = split_part(object_name, '.', 2)
    )::text
    ELSE 'REQUIRES_APPROVED_SERVER_CONTRACT'
  END AS review_state
FROM required_objects
ORDER BY kind, object_name;
