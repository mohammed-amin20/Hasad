-- =============================================================================
-- Hasad ERP V2 / Unit S3 — READ-ONLY PRE-POSTING SMOKE-TEST INSPECTION
-- Target: Supabase DEV sxasnunzspkuwbxiddqd (Abo Amen company only)
-- Status: REVIEW / LOCAL PREPARATION ONLY — NOT EXECUTED ON DEV
-- =============================================================================
--
-- PURPOSE
--   Lists every draft sales invoice for the single active Abo Amen company and
--   reports, per invoice, whether it can pass the deployed S3 posting contract
--   (`hasad.post_sales_invoice(uuid,uuid,uuid)`) as a ZERO-TAX October 2026
--   smoke test. It also reports the exact expected posting effects and the
--   expected official numbers, without writing anything.
--
-- SAFETY
--   * This file contains exactly ONE statement and it is a SELECT.
--   * It contains no DDL/DML, no function calls that write, no sequences, no
--     temporary tables, and no secrets. It never calls `post_sales_invoice`.
--   * It reads inventory (`stock_levels.last_unit_cost`) but does not change it.
--   * Run it in the DEV SQL editor under a separate, explicit read-only
--     authorization. Running it is optional for this deliverable.
--   * If the executing role is not BYPASSRLS and is not the table owner, FORCE
--     RLS hides rows and this report will look empty. The `environment` object
--     reports `current_user` and `rolbypassrls` so that case is diagnosable.
--
-- CONTRACT REFERENCE (local review copy, not proof of the DEV body)
--   security/candidates/dev_s3_post_sales_invoice_candidate.sql
--   The deployed DEV function body cannot be read from this workstation. Every
--   value below is therefore derived from data, and every check reproduces the
--   documented contract; a mismatch between the local candidate and the DEV
--   function is itself a blocker (see the Arabic report).
--
-- OUTPUT
--   One row per draft invoice (`row_type = 'INVOICE'`), ordered READY first,
--   followed by one `row_type = 'SUMMARY'` row.
--   `verdict = 'READY_FOR_ZERO_TAX_POSTING_TEST'` is the only suitable verdict
--   for this smoke test. `NOT_SUITABLE_TAXABLE_INVOICE` is blocked by policy
--   (D-023), not by data. Anything with a non-empty `blocking_reasons` is
--   BLOCKED and must not be posted.
-- =============================================================================

WITH
-- ---------------------------------------------------------------- selector --
abo_matches AS (
  SELECT DISTINCT cs.company_id
  FROM hasad.company_settings cs
  JOIN hasad.companies c ON c.id = cs.company_id AND c.status = 'active'
  WHERE lower(btrim(coalesce(cs.name_ar, '')))      IN (lower('أبو أمين'), lower('Abo Amen'))
     OR lower(btrim(coalesce(cs.name_en, '')))      IN (lower('أبو أمين'), lower('Abo Amen'))
     OR lower(btrim(coalesce(cs.display_name, ''))) IN (lower('أبو أمين'), lower('Abo Amen'))
),
target AS (
  SELECT
    CASE WHEN count(*) = 1 THEN (array_agg(company_id))[1] END AS company_id,
    count(*) AS match_count
  FROM abo_matches
),
-- ------------------------------------------------------------ environment --
env AS (
  SELECT
    t.company_id,
    t.match_count,
    cs.name_ar            AS company_name_ar,
    cs.vat_enabled,
    fy.id                 AS fy_id,
    fy.start_date         AS fy_start,
    fy.end_date           AS fy_end,
    fy.status             AS fy_status,
    per.id                AS period_id,
    per.period_no         AS period_no,
    per.start_date        AS period_start,
    per.end_date          AS period_end,
    per.status            AS period_status,
    si.id                 AS si_type_id,
    si.issuance           AS si_issuance,
    si.format_prefix      AS si_prefix,
    si.pad_length         AS si_pad,
    si.is_active          AS si_active,
    je.id                 AS je_type_id,
    je.issuance           AS je_issuance,
    je.format_prefix      AS je_prefix,
    je.pad_length         AS je_pad,
    je.is_active          AS je_active,
    dn_si.next_value      AS si_next_value,
    dn_je.next_value      AS je_next_value,
    (SELECT count(*) FROM hasad.document_types d
      WHERE d.company_id = t.company_id AND d.code = 'SI') AS si_type_count,
    (SELECT count(*) FROM hasad.document_types d
      WHERE d.company_id = t.company_id AND d.code = 'JE') AS je_type_count,
    (SELECT count(*) FROM hasad.tax_rates tr
      WHERE tr.company_id = t.company_id) AS tax_rate_rows,
    (SELECT a.code FROM hasad.module_account_map m
       JOIN hasad.accounts a ON a.id = m.account_id AND a.company_id = m.company_id AND a.is_active
      WHERE m.company_id = t.company_id AND m.module = 'sales'
        AND m.account_role = 'AR_CONTROL' ORDER BY a.code LIMIT 1) AS map_ar_code,
    (SELECT a.code FROM hasad.module_account_map m
       JOIN hasad.accounts a ON a.id = m.account_id AND a.company_id = m.company_id AND a.is_active
      WHERE m.company_id = t.company_id AND m.module = 'sales'
        AND m.account_role = 'SALES_REVENUE' ORDER BY a.code LIMIT 1) AS map_rev_code,
    (SELECT a.code FROM hasad.module_account_map m
       JOIN hasad.accounts a ON a.id = m.account_id AND a.company_id = m.company_id AND a.is_active
      WHERE m.company_id = t.company_id AND m.module = 'sales'
        AND m.account_role = 'VAT_OUTPUT' ORDER BY a.code LIMIT 1) AS map_vat_code,
    (SELECT a.code FROM hasad.module_account_map m
       JOIN hasad.accounts a ON a.id = m.account_id AND a.company_id = m.company_id AND a.is_active
      WHERE m.company_id = t.company_id AND m.module = 'sales'
        AND m.account_role = 'COGS' ORDER BY a.code LIMIT 1) AS map_cogs_code,
    (SELECT a.code FROM hasad.module_account_map m
       JOIN hasad.accounts a ON a.id = m.account_id AND a.company_id = m.company_id AND a.is_active
      WHERE m.company_id = t.company_id AND m.module = 'sales'
        AND m.account_role = 'INVENTORY_CONTROL' ORDER BY a.code LIMIT 1) AS map_inv_code,
    (SELECT rolsuper FROM pg_catalog.pg_roles r WHERE r.rolname = current_user) AS executor_super,
    (SELECT rolbypassrls FROM pg_catalog.pg_roles r WHERE r.rolname = current_user) AS executor_bypassrls,
    current_user AS executor_role
  FROM target t
  LEFT JOIN hasad.company_settings cs ON cs.company_id = t.company_id
  LEFT JOIN LATERAL (
    SELECT f.* FROM hasad.fiscal_years f
    WHERE f.company_id = t.company_id
      AND f.start_date = DATE '2026-01-01'
      AND f.end_date   = DATE '2026-12-31'
    ORDER BY f.id LIMIT 1
  ) fy ON true
  LEFT JOIN LATERAL (
    SELECT p.* FROM hasad.fiscal_periods p
    WHERE p.company_id = t.company_id
      AND p.fiscal_year_id = fy.id
      AND p.status = 'open'
      AND p.start_date <= DATE '2026-10-31'
      AND p.end_date   >= DATE '2026-10-01'
    ORDER BY p.period_no LIMIT 1
  ) per ON true
  LEFT JOIN LATERAL (
    SELECT d.* FROM hasad.document_types d
    WHERE d.company_id = t.company_id AND d.code = 'SI'
    ORDER BY d.id LIMIT 1
  ) si ON true
  LEFT JOIN LATERAL (
    SELECT d.* FROM hasad.document_types d
    WHERE d.company_id = t.company_id AND d.code = 'JE'
    ORDER BY d.id LIMIT 1
  ) je ON true
  LEFT JOIN hasad.doc_numbers dn_si
    ON dn_si.company_id = t.company_id
   AND dn_si.document_type_id = si.id
   AND dn_si.fiscal_year_id = fy.id
  LEFT JOIN hasad.doc_numbers dn_je
    ON dn_je.company_id = t.company_id
   AND dn_je.document_type_id = je.id
   AND dn_je.fiscal_year_id = fy.id
),
-- Environment block is emitted even when there is no draft invoice at all.
environment_json AS (
  SELECT jsonb_build_object(
    'company_id',          e.company_id,
    'company_name_ar',     e.company_name_ar,
    'selector_matches',    e.match_count,
    'executor_role',       e.executor_role,
    'executor_superuser',  e.executor_super,
    'executor_bypassrls',  e.executor_bypassrls,
    'vat_enabled',         e.vat_enabled,
    'tax_rate_rows',       e.tax_rate_rows,
    'fiscal_year',         jsonb_build_object(
                             'id', e.fy_id, 'start', e.fy_start,
                             'end', e.fy_end, 'status', e.fy_status),
    'open_period',         jsonb_build_object(
                             'id', e.period_id, 'period_no', e.period_no,
                             'start', e.period_start, 'end', e.period_end,
                             'status', e.period_status),
    'si_document_type',    jsonb_build_object(
                             'id', e.si_type_id, 'issuance', e.si_issuance,
                             'prefix', e.si_prefix, 'pad_length', e.si_pad,
                             'is_active', e.si_active),
    'je_document_type',    jsonb_build_object(
                             'id', e.je_type_id, 'issuance', e.je_issuance,
                             'prefix', e.je_prefix, 'pad_length', e.je_pad,
                             'is_active', e.je_active),
    'doc_numbers',         jsonb_build_object(
                             'si_next_value', e.si_next_value,
                             'je_next_value', e.je_next_value),
    'sales_mappings',      jsonb_build_object(
                             'AR_CONTROL',         e.map_ar_code,
                             'SALES_REVENUE',      e.map_rev_code,
                             'VAT_OUTPUT',         e.map_vat_code,
                             'COGS',               e.map_cogs_code,
                             'INVENTORY_CONTROL',  e.map_inv_code)
  ) AS environment
  FROM env e
),
-- -------------------------------------------------------------- draft docs --
drafts AS (
  SELECT sd.*
  FROM hasad.sales_documents sd
  JOIN target t ON t.company_id = sd.company_id AND t.match_count = 1
  WHERE sd.doc_kind = 'invoice'
    AND sd.status   = 'draft'
),
-- Recompute every line exactly like the posting contract, per vat_mode.
line_calc AS (
  SELECT
    l.id,
    l.company_id,
    l.document_id,
    l.line_no,
    l.product_id,
    l.warehouse_id,
    l.qty,
    l.unit_price,
    l.discount_amount,
    l.tax_rate,
    l.net,
    l.tax,
    l.gross,
    d.doc_date,
    d.vat_mode,
    round(l.qty * l.unit_price - l.discount_amount, 2) AS basis,
    CASE
      WHEN d.vat_mode = 'exclusive'
        THEN round(l.qty * l.unit_price - l.discount_amount, 2)
      ELSE round(
        round(l.qty * l.unit_price - l.discount_amount, 2)
        / (1 + coalesce(l.tax_rate, 0) / 100), 2)
    END AS calc_net,
    CASE
      WHEN d.vat_mode = 'exclusive'
        THEN round(round(l.qty * l.unit_price - l.discount_amount, 2)
                   * coalesce(l.tax_rate, 0) / 100, 2)
      ELSE round(l.qty * l.unit_price - l.discount_amount, 2)
           - round(round(l.qty * l.unit_price - l.discount_amount, 2)
                   / (1 + coalesce(l.tax_rate, 0) / 100), 2)
    END AS calc_tax,
    CASE
      WHEN d.vat_mode = 'exclusive'
        THEN round(round(l.qty * l.unit_price - l.discount_amount, 2)
                   + round(round(l.qty * l.unit_price - l.discount_amount, 2)
                           * coalesce(l.tax_rate, 0) / 100, 2), 2)
      ELSE round(l.qty * l.unit_price - l.discount_amount, 2)
    END AS calc_gross
  FROM hasad.sales_document_lines l
  JOIN drafts d ON d.id = l.document_id AND d.company_id = l.company_id
),
line_eval AS (
  SELECT
    lc.*,
    coalesce(p.track_inventory, false) AS track_inventory,
    p.is_active                        AS product_active,
    w.is_active                        AS warehouse_active,
    (
      lc.qty IS NULL OR lc.qty <= 0
      OR lc.unit_price IS NULL OR lc.unit_price < 0
      OR lc.discount_amount IS NULL OR lc.discount_amount < 0
      OR lc.tax_rate IS NULL OR lc.tax_rate < 0
    ) AS bad_amount,
    (
      (lc.qty IS NOT NULL AND lc.qty <> trunc(lc.qty, 4))
      OR (lc.unit_price IS NOT NULL AND lc.unit_price <> trunc(lc.unit_price, 4))
      OR (lc.discount_amount IS NOT NULL AND lc.discount_amount <> trunc(lc.discount_amount, 2))
      OR (lc.tax_rate IS NOT NULL AND lc.tax_rate <> trunc(lc.tax_rate, 3))
    ) AS bad_precision,
    (
      lc.net IS DISTINCT FROM lc.calc_net
      OR lc.tax IS DISTINCT FROM lc.calc_tax
      OR lc.gross IS DISTINCT FROM lc.calc_gross
    ) AS bad_totals,
    (lc.product_id IS NOT NULL AND (p.id IS NULL OR p.is_active IS NOT TRUE)) AS bad_product,
    (lc.product_id IS NOT NULL AND coalesce(p.track_inventory, false)
       AND lc.warehouse_id IS NULL) AS missing_warehouse,
    (lc.product_id IS NOT NULL AND coalesce(p.track_inventory, false)
       AND lc.warehouse_id IS NOT NULL
       AND (w.id IS NULL OR w.is_active IS NOT TRUE)) AS bad_warehouse,
    (coalesce(lc.tax_rate, 0) > 0 AND NOT EXISTS (
      SELECT 1 FROM hasad.tax_rates tr
      WHERE tr.company_id = lc.company_id
        AND tr.rate = lc.tax_rate
        AND tr.is_active
        AND tr.valid_from <= lc.doc_date
        AND (tr.valid_to IS NULL OR tr.valid_to >= lc.doc_date)
    )) AS missing_rate,
    sl.qty            AS stock_qty,
    sl.last_unit_cost AS last_unit_cost
  FROM line_calc lc
  LEFT JOIN hasad.products p
    ON p.id = lc.product_id AND p.company_id = lc.company_id
  LEFT JOIN hasad.warehouses w
    ON w.id = lc.warehouse_id AND w.company_id = lc.company_id
  LEFT JOIN hasad.stock_levels sl
    ON sl.company_id = lc.company_id
   AND sl.product_id = lc.product_id
   AND sl.warehouse_id = lc.warehouse_id
),
-- Aggregate per document (line integrity, totals, tax, stock demand).
doc_agg AS (
  SELECT
    company_id,
    document_id,
    count(*)                                             AS line_count,
    count(DISTINCT line_no)                              AS distinct_lines,
    min(line_no)                                         AS min_line,
    max(line_no)                                         AS max_line,
    count(*) FILTER (WHERE bad_amount)                   AS bad_amount_lines,
    count(*) FILTER (WHERE bad_precision)                AS bad_precision_lines,
    count(*) FILTER (WHERE bad_totals)                   AS bad_totals_lines,
    count(*) FILTER (WHERE bad_product)                  AS bad_product_lines,
    count(*) FILTER (WHERE missing_warehouse)            AS missing_warehouse_lines,
    count(*) FILTER (WHERE bad_warehouse)                AS bad_warehouse_lines,
    count(*) FILTER (WHERE missing_rate)                 AS missing_rate_lines,
    count(*) FILTER (WHERE coalesce(tax_rate, 0) > 0)    AS taxable_lines,
    count(*) FILTER (WHERE track_inventory)              AS stocked_lines,
    coalesce(sum(net),   0)::numeric(18,2)               AS line_net_sum,
    coalesce(sum(tax),   0)::numeric(18,2)               AS line_tax_sum,
    coalesce(sum(gross), 0)::numeric(18,2)               AS line_gross_sum
  FROM line_eval
  GROUP BY company_id, document_id
),
-- Stock availability per (document, product, warehouse).
stock_need AS (
  SELECT company_id, document_id, product_id, warehouse_id, sum(qty) AS required_qty
  FROM line_eval
  WHERE track_inventory AND product_id IS NOT NULL
  GROUP BY company_id, document_id, product_id, warehouse_id
),
stock_check AS (
  SELECT
    sn.company_id,
    sn.document_id,
    count(*)                                              AS stock_pairs,
    count(*) FILTER (WHERE sl.qty IS NULL OR sl.qty < sn.required_qty) AS shortage_pairs,
    jsonb_agg(jsonb_build_object(
      'product_id',      sn.product_id,
      'product_code',     p.code,
      'product_name',     p.name_ar,
      'warehouse_id',    sn.warehouse_id,
      'warehouse_code',   w.code,
      'warehouse_name',   w.name_ar,
      'required_qty',    sn.required_qty,
      'available_qty',   sl.qty,
      'shortage_qty',    CASE
                            WHEN sl.qty IS NULL THEN sn.required_qty
                            ELSE greatest(sn.required_qty - sl.qty, 0)
                          END,
      'last_unit_cost',  sl.last_unit_cost,
      'stock_ok',        (sl.qty IS NOT NULL AND sl.qty >= sn.required_qty)
    ) ORDER BY p.code NULLS LAST, w.code NULLS LAST) AS stock_detail
  FROM stock_need sn
  LEFT JOIN hasad.stock_levels sl
    ON sl.company_id = sn.company_id
   AND sl.product_id = sn.product_id
   AND sl.warehouse_id = sn.warehouse_id
  LEFT JOIN hasad.products p ON p.id = sn.product_id
  LEFT JOIN hasad.warehouses w ON w.id = sn.warehouse_id
  GROUP BY sn.company_id, sn.document_id
),
-- Weighted-average cost of the issue, using the same per-line rounding as S3.
cogs_calc AS (
  SELECT
    le.company_id,
    le.document_id,
    count(*)                                        AS costed_lines,
    coalesce(sum(round(le.qty * le.last_unit_cost, 2)), 0)::numeric(18,2) AS expected_cogs
  FROM line_eval le
  JOIN hasad.stock_levels sl
    ON sl.company_id = le.company_id
   AND sl.product_id = le.product_id
   AND sl.warehouse_id = le.warehouse_id
  WHERE le.track_inventory
  GROUP BY le.company_id, le.document_id
),
line_detail AS (
  SELECT
    le.company_id,
    le.document_id,
    jsonb_agg(jsonb_build_object(
      'line_no',            le.line_no,
      'product_id',         le.product_id,
      'product_code',        p.code,
      'product_name',        p.name_ar,
      'track_inventory',    le.track_inventory,
      'warehouse_id',       le.warehouse_id,
      'warehouse_code',      w.code,
      'warehouse_name',      w.name_ar,
      'qty',                le.qty,
      'unit_price',         le.unit_price,
      'discount_amount',    le.discount_amount,
      'tax_rate',           le.tax_rate,
      'net',                le.net,
      'tax',                le.tax,
      'gross',              le.gross,
      'stock_qty',          le.stock_qty,
      'last_unit_cost',     le.last_unit_cost,
      'line_expected_cost', CASE
                              WHEN le.track_inventory AND le.stock_qty IS NOT NULL
                                THEN round(le.qty * le.last_unit_cost, 2)
                            END
    ) ORDER BY le.line_no) AS line_detail
  FROM line_eval le
  LEFT JOIN hasad.products p ON p.id = le.product_id
  LEFT JOIN hasad.warehouses w ON w.id = le.warehouse_id
  GROUP BY le.company_id, le.document_id
),
-- Predicted official numbers (what the allocator would issue next).
predicted AS (
  SELECT
    e.company_id,
    CASE
      WHEN e.si_prefix IS NOT NULL AND btrim(e.si_prefix) <> ''
        THEN e.si_prefix || '-' || extract(year FROM e.fy_start)::int::text || '-'
             || lpad(coalesce(e.si_next_value, 1)::text, coalesce(e.si_pad, 4), '0')
    END AS predicted_si_no,
    CASE
      WHEN e.je_prefix IS NOT NULL AND btrim(e.je_prefix) <> ''
        THEN e.je_prefix || '-' || extract(year FROM e.fy_start)::int::text || '-'
             || lpad(coalesce(e.je_next_value, 1)::text, coalesce(e.je_pad, 4), '0')
    END AS predicted_je_no
  FROM env e
),
env_blockers AS (
  SELECT
    e.company_id,
    array_remove(ARRAY[
      CASE WHEN e.match_count <> 1
             THEN 'ABO_AMEN_SELECTOR_NOT_EXACTLY_ONE' END,
      CASE WHEN e.fy_id IS NULL
             THEN 'FISCAL_YEAR_2026_MISSING' END,
      CASE WHEN e.fy_id IS NOT NULL AND e.fy_status IS DISTINCT FROM 'open'
             THEN 'FISCAL_YEAR_NOT_OPEN' END,
      CASE WHEN e.period_id IS NULL
             THEN 'OPEN_OCTOBER_2026_PERIOD_MISSING' END,
      CASE WHEN e.si_type_id IS NULL
                OR e.si_issuance IS DISTINCT FROM 'posting'
                OR e.si_active IS NOT TRUE
             THEN 'SI_DOCUMENT_TYPE_INVALID' END,
      CASE WHEN e.si_prefix IS NULL OR btrim(e.si_prefix) = ''
             THEN 'SI_PREFIX_MISSING' END,
      CASE WHEN e.je_type_id IS NULL
                OR e.je_issuance IS DISTINCT FROM 'posting'
                OR e.je_active IS NOT TRUE
             THEN 'JE_DOCUMENT_TYPE_INVALID' END,
      CASE WHEN e.je_prefix IS NULL OR btrim(e.je_prefix) = ''
             THEN 'JE_PREFIX_MISSING' END,
      CASE WHEN e.map_ar_code IS NULL
             THEN 'MAPPING_AR_CONTROL_MISSING' END,
      CASE WHEN e.map_rev_code IS NULL
             THEN 'MAPPING_SALES_REVENUE_MISSING' END
    ]::text[], NULL) AS reasons
  FROM env e
),
-- One row per draft invoice with all contract checks.
invoice_report AS (
  SELECT
    d.company_id,
    e.company_name_ar,
    d.id                                   AS document_id,
    d.doc_date,
    d.vat_mode,
    d.party_id,
    pt.name_ar                             AS customer_name,
    d.doc_no                               AS existing_doc_no,
    d.idempotency_key,
    d.net,
    d.tax,
    d.gross,
    coalesce(da.line_count, 0)             AS line_count,
    coalesce(da.taxable_lines, 0)          AS taxable_lines,
    coalesce(da.stocked_lines, 0)          AS stocked_lines,
    (coalesce(d.tax, 0) = 0
     AND coalesce(da.line_tax_sum, 0) = 0
     AND coalesce(da.taxable_lines, 0) = 0) AS is_zero_tax,
    pr.predicted_si_no,
    pr.predicted_je_no,
    d.gross                                AS expected_ar_debit,
    d.net                                  AS expected_revenue_credit,
    d.tax                                  AS expected_vat_credit,
    coalesce(cc.expected_cogs, 0)           AS expected_cogs_debit,
    coalesce(cc.expected_cogs, 0)           AS expected_inventory_credit,
    (CASE WHEN d.gross > 0 THEN 1 ELSE 0 END
     + CASE WHEN d.net  > 0 THEN 1 ELSE 0 END
     + CASE WHEN d.tax  > 0 THEN 1 ELSE 0 END
     + CASE WHEN coalesce(cc.expected_cogs, 0) > 0 THEN 2 ELSE 0 END) AS expected_je_line_count,
    coalesce(da.stocked_lines, 0)          AS expected_movement_count,
    coalesce(sc.stock_pairs, 0)            AS stock_pairs,
    (coalesce(sc.shortage_pairs, 0) = 0)   AS stock_ok,
    coalesce(sc.stock_detail, '[]'::jsonb) AS stock_detail,
    array_remove(ARRAY[
      CASE WHEN d.idempotency_key IS NULL
             THEN 'IDEMPOTENCY_REQUIRED' END,
      CASE WHEN d.idempotency_key IS NOT NULL AND EXISTS (
             SELECT 1 FROM hasad.journal_entries je
             WHERE je.company_id = d.company_id
               AND je.idempotency_key = d.idempotency_key)
             THEN 'IDEMPOTENCY_ALREADY_USED_BY_JOURNAL_ENTRY' END,
      CASE WHEN d.doc_type_id IS DISTINCT FROM e.si_type_id
             THEN 'DOCUMENT_TYPE_NOT_AVAILABLE' END,
      CASE WHEN d.fiscal_year_id IS DISTINCT FROM e.fy_id
             THEN 'FISCAL_YEAR_MISMATCH' END,
      CASE WHEN e.fy_id IS NOT NULL
                AND d.doc_date NOT BETWEEN e.fy_start AND e.fy_end
             THEN 'FISCAL_YEAR_MISMATCH' END,
      CASE WHEN e.period_id IS NULL
                OR d.doc_date NOT BETWEEN e.period_start AND e.period_end
             THEN 'DOC_DATE_OUTSIDE_OPEN_PERIOD' END,
      CASE WHEN pt.id IS NULL OR pt.is_customer IS NOT TRUE OR pt.is_active IS NOT TRUE
             THEN 'PARTY_NOT_AVAILABLE' END,
      CASE WHEN d.doc_no IS NOT NULL
             THEN 'DOC_NO_ALREADY_SET' END,
      CASE WHEN d.posted_at IS NOT NULL OR d.posted_by IS NOT NULL
             THEN 'POSTED_FIELDS_NOT_NULL' END,
      CASE WHEN coalesce(da.line_count, 0) = 0
                OR da.line_count <> da.distinct_lines
                OR da.min_line <> 1
                OR da.max_line <> da.line_count
             THEN 'LINES_INVALID' END,
      CASE WHEN coalesce(da.bad_amount_lines, 0) > 0
             THEN 'LINE_AMOUNT_INVALID' END,
      CASE WHEN coalesce(da.bad_precision_lines, 0) > 0
             THEN 'LINE_PRECISION_INVALID' END,
      CASE WHEN coalesce(da.bad_totals_lines, 0) > 0
             THEN 'TOTALS_MISMATCH' END,
      CASE WHEN coalesce(da.bad_product_lines, 0) > 0
             THEN 'PRODUCT_NOT_AVAILABLE' END,
      CASE WHEN coalesce(da.missing_warehouse_lines, 0) > 0
             THEN 'WAREHOUSE_REQUIRED' END,
      CASE WHEN coalesce(da.bad_warehouse_lines, 0) > 0
             THEN 'WAREHOUSE_NOT_AVAILABLE' END,
      CASE WHEN coalesce(da.missing_rate_lines, 0) > 0
             THEN 'RATE_NOT_FOUND_FOR_DATE' END,
      CASE WHEN d.net   IS DISTINCT FROM da.line_net_sum
                OR d.tax   IS DISTINCT FROM da.line_tax_sum
                OR d.gross IS DISTINCT FROM da.line_gross_sum
                OR d.gross <> d.net + d.tax
             THEN 'TOTALS_MISMATCH' END,
      CASE WHEN d.gross <= 0
             THEN 'DOCUMENT_TOTAL_INVALID' END,
      CASE WHEN coalesce(sc.shortage_pairs, 0) > 0
             THEN 'STOCK_INSUFFICIENT' END,
      CASE WHEN d.tax > 0 AND e.map_vat_code IS NULL
             THEN 'MAPPING_VAT_OUTPUT_MISSING' END,
      CASE WHEN coalesce(sc.stock_pairs, 0) > 0 AND e.map_cogs_code IS NULL
             THEN 'MAPPING_COGS_MISSING' END,
      CASE WHEN coalesce(sc.stock_pairs, 0) > 0 AND e.map_inv_code IS NULL
             THEN 'MAPPING_INVENTORY_CONTROL_MISSING' END,
      CASE WHEN pr.predicted_si_no IS NOT NULL AND EXISTS (
             SELECT 1 FROM hasad.sales_documents x
             WHERE x.company_id = d.company_id AND x.doc_no = pr.predicted_si_no)
             THEN 'SI_NUMBER_COLLISION' END,
      CASE WHEN pr.predicted_je_no IS NOT NULL AND EXISTS (
             SELECT 1 FROM hasad.journal_entries je
             WHERE je.company_id = d.company_id AND je.entry_no = pr.predicted_je_no)
             THEN 'JE_NUMBER_COLLISION' END
    ]::text[], NULL) AS blocking_reasons,
    array_remove(ARRAY[
      CASE WHEN coalesce(d.tax, 0) > 0 OR coalesce(da.taxable_lines, 0) > 0
             THEN 'TAXABLE_INVOICE_NOT_APPROVED_D023' END,
      CASE WHEN e.vat_enabled IS DISTINCT FROM false
             THEN 'VAT_FLAG_NOT_FALSE' END,
      CASE WHEN coalesce(sc.stock_pairs, 0) > 0
                AND coalesce(cc.expected_cogs, 0) = 0
             THEN 'ZERO_COST_ISSUE_NO_COGS_LEG_AND_NULL_MOVEMENT_LINK' END,
      CASE WHEN e.tax_rate_rows > 0
             THEN 'TAX_RATE_ROWS_PRESENT_REVIEW_D023' END,
      CASE WHEN e.je_type_count > 1
             THEN 'MULTIPLE_JE_DOCUMENT_TYPES' END,
      CASE WHEN e.si_type_count > 1
             THEN 'MULTIPLE_SI_DOCUMENT_TYPES' END
    ]::text[], NULL) AS warnings,
    coalesce(ld.line_detail, '[]'::jsonb) AS line_detail,
    (SELECT environment FROM environment_json) AS environment,
    env_blockers.reasons AS environment_blockers
  FROM drafts d
  CROSS JOIN env e
  LEFT JOIN env_blockers ON env_blockers.company_id = d.company_id
  LEFT JOIN hasad.parties pt
    ON pt.id = d.party_id AND pt.company_id = d.company_id
  LEFT JOIN doc_agg da
    ON da.company_id = d.company_id AND da.document_id = d.id
  LEFT JOIN stock_check sc
    ON sc.company_id = d.company_id AND sc.document_id = d.id
  LEFT JOIN cogs_calc cc
    ON cc.company_id = d.company_id AND cc.document_id = d.id
  LEFT JOIN line_detail ld
    ON ld.company_id = d.company_id AND ld.document_id = d.id
  LEFT JOIN predicted pr ON pr.company_id = d.company_id
),
verdicts AS (
  SELECT
    ir.*,
    (ir.environment_blockers || ir.blocking_reasons) AS all_blockers,
    CASE
      WHEN cardinality(ir.environment_blockers || ir.blocking_reasons) > 0
        THEN 'BLOCKED'
      WHEN ir.is_zero_tax
        THEN 'READY_FOR_ZERO_TAX_POSTING_TEST'
      ELSE 'NOT_SUITABLE_TAXABLE_INVOICE'
    END AS verdict
  FROM invoice_report ir
)
SELECT *
FROM (
SELECT
  'INVOICE'::text                     AS row_type,
  v.verdict,
  v.company_id,
  v.company_name_ar,
  v.document_id,
  v.doc_date,
  v.customer_name,
  v.vat_mode,
  v.net,
  v.tax,
  v.gross,
  v.line_count,
  v.taxable_lines,
  v.stocked_lines,
  v.is_zero_tax,
  v.predicted_si_no                   AS expected_si_no,
  v.predicted_je_no                   AS expected_je_no,
  v.expected_ar_debit,
  v.expected_revenue_credit,
  v.expected_vat_credit,
  v.expected_cogs_debit,
  v.expected_inventory_credit,
  v.expected_je_line_count,
  v.expected_movement_count,
  v.stock_pairs,
  v.stock_ok,
  v.stock_detail,
  v.environment_blockers,
  v.blocking_reasons,
  v.warnings,
  v.line_detail,
  v.environment,
  v.idempotency_key,
  NULL::bigint                        AS draft_invoice_count,
  NULL::bigint                        AS ready_count,
  NULL::bigint                        AS not_suitable_taxable_count,
  NULL::bigint                        AS blocked_count
FROM verdicts v
UNION ALL
SELECT
  'SUMMARY'::text,
  CASE
    WHEN (SELECT match_count FROM target) <> 1 THEN 'BLOCKED'
    WHEN count(*) FILTER (WHERE verdict = 'READY_FOR_ZERO_TAX_POSTING_TEST') > 0
      THEN 'READY_FOR_ZERO_TAX_POSTING_TEST'
    WHEN count(*) FILTER (WHERE verdict = 'NOT_SUITABLE_TAXABLE_INVOICE') > 0
      THEN 'NOT_SUITABLE_TAXABLE_INVOICE'
    ELSE 'BLOCKED'
  END,
  (SELECT company_id FROM target),
  (SELECT company_name_ar FROM env),
  NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL,
  NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL,
  (SELECT reasons FROM env_blockers),
  CASE
    WHEN count(*) = 0 THEN ARRAY['NO_DRAFT_SALES_INVOICES_FOR_ABO_AMEN']::text[]
    ELSE ARRAY[]::text[]
  END,
  ARRAY[]::text[],
  '[]'::jsonb,
  (SELECT environment FROM environment_json),
  NULL::uuid,
  count(*)::bigint,
  count(*) FILTER (WHERE verdict = 'READY_FOR_ZERO_TAX_POSTING_TEST')::bigint,
  count(*) FILTER (WHERE verdict = 'NOT_SUITABLE_TAXABLE_INVOICE')::bigint,
  count(*) FILTER (WHERE verdict = 'BLOCKED')::bigint
FROM verdicts
) u
ORDER BY
  CASE WHEN u.row_type = 'SUMMARY' THEN 1 ELSE 0 END,
  CASE u.verdict
    WHEN 'READY_FOR_ZERO_TAX_POSTING_TEST'   THEN 0
    WHEN 'NOT_SUITABLE_TAXABLE_INVOICE'      THEN 1
    ELSE 2
  END,
  u.doc_date,
  u.document_id;
