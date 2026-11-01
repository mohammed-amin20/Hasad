-- =============================================================================
-- Hasad ERP V2 / Unit S3 — READ-ONLY POST-POSTING VERIFICATION
-- Target: Supabase DEV sxasnunzspkuwbxiddqd
-- Status: REVIEW / LOCAL PREPARATION ONLY — NOT EXECUTED ON DEV
-- =============================================================================
--
-- PURPOSE
--   Verifies a real S3 posting smoke test AFTER the owner has separately
--   authorized running `hasad.post_sales_invoice`. It checks the official
--   invoice number, the posted journal entry (balance, legs, accounts,
--   numbering), the inventory issue (movements, values, links, stock level),
--   the audit trail, idempotency, and reversal state. It returns PASS / FAIL /
--   WARN per check plus one OVERALL row. It writes nothing.
--
-- HOW TO USE
--   1. Run `security/candidates/s3_posting_smoke_precheck_readonly.sql` first
--      and pick the invoice whose verdict is
--      'READY_FOR_ZERO_TAX_POSTING_TEST'.
--   2. Post it through the owner-authorized path.
--   3. Replace ONLY the UUID on the `params` line below with that invoice id.
--   4. Run this file. Every check must be PASS or WARN, and OVERALL must be
--      PASS. Any FAIL is a real accounting/inventory defect: stop and report.
--
-- SAFETY
--   * Exactly ONE SELECT statement. No DDL/DML, no writes, no function calls,
--     no temporary tables, no credentials.
--   * It reads the POSTED state only; it never calls `post_sales_invoice`.
--   * WARN means "informational / expected deviation to review", not a write.
--   * FORCE RLS: if the executing role is neither the table owner nor
--     BYPASSRLS, this query will return FAILs because rows are hidden. Run it
--     in the DEV SQL editor (postgres) or a BYPASSRLS diagnostic role.
--
-- CONTRACT REFERENCE
--   security/candidates/dev_s3_post_sales_invoice_candidate.sql
--   reason = 'sales invoice ' || doc_no
--   audit  = 'sale.invoice_posted', 'number.issued', 'stock.posted'
--   move   = movement_type 'sales_issue', direction 'out', source_document_type
--            'sales_invoice', seq = max(seq)+1 per product, journal_line_id =
--            inventory-credit line id (NULL when COGS value is zero).
--   The deployed DEV body cannot be read from this workstation, so the JE is
--   located by idempotency_key (with a reason-match preference) instead of a
--   source-document column that `journal_entries` does not have.
-- =============================================================================

WITH
params AS (
  -- ========================== EDIT ONLY THIS LINE ==========================
  SELECT '00000000-0000-0000-0000-000000000000'::uuid AS document_id
  -- ========================================================================
),
doc AS (
  SELECT sd.*
  FROM hasad.sales_documents sd
  WHERE sd.id = (SELECT document_id FROM params)
),
env AS (
  SELECT
    d.id              AS document_id,
    d.company_id,
    d.doc_type_id,
    d.fiscal_year_id,
    fy.start_date     AS fy_start,
    fy.end_date       AS fy_end,
    fy.status         AS fy_status,
    per.id            AS period_id,
    per.period_no     AS period_no,
    per.status        AS period_status,
    sit.format_prefix AS si_prefix,
    sit.pad_length    AS si_pad,
    jet.id            AS je_type_id,
    jet.format_prefix AS je_prefix,
    jet.pad_length    AS je_pad,
    (SELECT count(*) FROM hasad.document_types t
      WHERE t.company_id = d.company_id AND t.code = 'JE') AS je_type_count,
    dn_si.next_value  AS si_next,
    dn_je.next_value  AS je_next
  FROM doc d
  LEFT JOIN hasad.fiscal_years fy
    ON fy.company_id = d.company_id AND fy.id = d.fiscal_year_id
  LEFT JOIN LATERAL (
    SELECT p.* FROM hasad.fiscal_periods p
    WHERE p.company_id = d.company_id
      AND p.fiscal_year_id = d.fiscal_year_id
      AND d.doc_date BETWEEN p.start_date AND p.end_date
    ORDER BY p.period_no LIMIT 1
  ) per ON true
  LEFT JOIN hasad.document_types sit
    ON sit.company_id = d.company_id AND sit.id = d.doc_type_id
  LEFT JOIN LATERAL (
    SELECT t.* FROM hasad.document_types t
    WHERE t.company_id = d.company_id AND t.code = 'JE'
    ORDER BY t.id LIMIT 1
  ) jet ON true
  LEFT JOIN hasad.doc_numbers dn_si
    ON dn_si.company_id = d.company_id
   AND dn_si.document_type_id = sit.id
   AND dn_si.fiscal_year_id = d.fiscal_year_id
  LEFT JOIN hasad.doc_numbers dn_je
    ON dn_je.company_id = d.company_id
   AND dn_je.document_type_id = jet.id
   AND dn_je.fiscal_year_id = d.fiscal_year_id
),
-- The journal entry: prefer the documented reason, then fall back to the
-- idempotency key. `journal_entries` has no source-document column.
je_raw AS (
  SELECT je.*
  FROM hasad.journal_entries je
  JOIN doc d
    ON d.company_id = je.company_id
   AND je.idempotency_key = d.idempotency_key
),
je AS (
  SELECT *
  FROM (
    SELECT j.*,
           row_number() OVER (
             ORDER BY (j.reason = 'sales invoice ' || coalesce((SELECT doc_no FROM doc), '')) DESC NULLS LAST,
                      j.posted_at NULLS LAST, j.id
           ) AS rn
    FROM je_raw j
  ) x
  WHERE rn = 1
),
jel AS (
  SELECT jl.*, a.code AS account_code, a.name_ar AS account_name
  FROM hasad.journal_lines jl
  JOIN je ON je.id = jl.entry_id AND je.company_id = jl.company_id
  LEFT JOIN hasad.accounts a
    ON a.id = jl.account_id AND a.company_id = jl.company_id
),
jl_agg AS (
  SELECT count(*) AS n, coalesce(sum(debit), 0) AS dr, coalesce(sum(credit), 0) AS cr
  FROM jel
),
map AS (
  SELECT m.account_role, m.account_id, a.code
  FROM hasad.module_account_map m
  JOIN hasad.accounts a
    ON a.id = m.account_id AND a.company_id = m.company_id AND a.is_active
  WHERE m.company_id = (SELECT company_id FROM doc)
    AND m.module = 'sales'
),
line_rows AS (
  SELECT
    l.id, l.line_no, l.product_id, l.warehouse_id, l.qty,
    l.net, l.tax, l.gross,
    coalesce(p.track_inventory, false) AS track_inventory
  FROM hasad.sales_document_lines l
  LEFT JOIN hasad.products p
    ON p.id = l.product_id AND p.company_id = l.company_id
  WHERE l.company_id = (SELECT company_id FROM doc)
    AND l.document_id = (SELECT id FROM doc)
),
-- One movement is expected per stocked line that had a stock row at posting.
issue_lines AS (
  SELECT lr.*
  FROM line_rows lr
  WHERE lr.track_inventory
    AND lr.product_id IS NOT NULL
    AND EXISTS (
      SELECT 1 FROM hasad.stock_levels sl
      WHERE sl.company_id = (SELECT company_id FROM doc)
        AND sl.product_id = lr.product_id
        AND sl.warehouse_id = lr.warehouse_id
    )
),
mv AS (
  SELECT sm.*
  FROM hasad.stock_movements sm
  JOIN doc d
    ON sm.company_id = d.company_id
   AND sm.source_document_type = 'sales_invoice'
   AND sm.source_document_id = d.id
),
mv_agg AS (
  SELECT count(*) AS n, coalesce(sum(value), 0) AS total_value FROM mv
),
mv_missing AS (
  SELECT count(*) AS n
  FROM issue_lines il
  WHERE NOT EXISTS (
    SELECT 1 FROM mv
    WHERE mv.product_id = il.product_id
      AND mv.warehouse_id = il.warehouse_id
      AND mv.qty = il.qty
      AND mv.direction = 'out'
  )
),
mv_extra AS (
  SELECT count(*) AS n
  FROM mv
  WHERE NOT EXISTS (
    SELECT 1 FROM issue_lines il
    WHERE il.product_id = mv.product_id
      AND il.warehouse_id = mv.warehouse_id
      AND il.qty = mv.qty
  )
),
mv_bad AS (
  SELECT count(*) AS n
  FROM mv
  WHERE mv.direction <> 'out'
     OR mv.movement_type <> 'sales_issue'
     OR mv.qty <= 0
     OR mv.unit_cost < 0
     OR mv.value IS DISTINCT FROM round(mv.qty * mv.unit_cost, 2)
),
-- The inventory-credit journal line (only exists when the COGS value is > 0).
inv_line AS (
  SELECT jl.id
  FROM jel jl
  WHERE jl.account_id = (SELECT account_id FROM map WHERE account_role = 'INVENTORY_CONTROL')
    AND jl.credit > 0
  ORDER BY jl.line_no
  LIMIT 1
),
mv_link_bad AS (
  SELECT count(*) AS n
  FROM mv
  WHERE (
    (SELECT total_value FROM mv_agg) > 0
    AND mv.journal_line_id IS DISTINCT FROM (SELECT id FROM inv_line)
  )
  OR (
    (SELECT total_value FROM mv_agg) = 0
    AND mv.journal_line_id IS NOT NULL
  )
),
affected AS (
  SELECT DISTINCT product_id, warehouse_id FROM mv
),
stock_bad AS (
  SELECT
    count(*) FILTER (WHERE sl.qty IS NULL OR sl.qty < 0) AS negative_or_missing,
    count(*) FILTER (
      WHERE sl.qty IS DISTINCT FROM (
        SELECT coalesce(sum(CASE WHEN sm.direction = 'in' THEN sm.qty ELSE -sm.qty END), 0)
        FROM hasad.stock_movements sm
        WHERE sm.company_id = (SELECT company_id FROM doc)
          AND sm.product_id = a.product_id
          AND sm.warehouse_id = a.warehouse_id
      )
    ) AS ledger_mismatch
  FROM affected a
  LEFT JOIN hasad.stock_levels sl
    ON sl.company_id = (SELECT company_id FROM doc)
   AND sl.product_id = a.product_id
   AND sl.warehouse_id = a.warehouse_id
),
aud AS (
  SELECT
    count(*) FILTER (
      WHERE action = 'sale.invoice_posted'
        AND details->>'doc_no' = (SELECT doc_no FROM doc)
        AND entity_id = (SELECT id FROM doc)
    ) AS posted_rows,
    count(*) FILTER (
      WHERE action = 'sale.invoice_posted'
        AND details->>'journal_entry_id' = (SELECT id::text FROM je)
    ) AS posted_je_link_rows,
    count(*) FILTER (
      WHERE action = 'number.issued'
        AND details->>'doc_no' = (SELECT doc_no FROM doc)
    ) AS number_rows,
    count(*) FILTER (
      WHERE action = 'stock.posted'
        AND entity_id IN (SELECT id FROM mv)
    ) AS stock_rows
  FROM hasad.audit_log
  WHERE company_id = (SELECT company_id FROM doc)
    AND (
      entity_id = (SELECT id FROM doc)
      OR (action = 'stock.posted' AND entity_id IN (SELECT id FROM mv))
    )
),
reversal AS (
  SELECT count(*) AS n
  FROM hasad.journal_entries r
  WHERE r.company_id = (SELECT company_id FROM doc)
    AND r.reversal_of_id = (SELECT id FROM je)
),
linked_notes AS (
  SELECT count(*) AS n
  FROM hasad.sales_documents n
  WHERE n.company_id = (SELECT company_id FROM doc)
    AND n.original_document_id = (SELECT id FROM doc)
    AND n.status = 'posted'
),
-- All aggregates in one row so that every check is a one-row SELECT. NULLs
-- appear only when the invoice itself is missing, and each check handles that.
agg AS (
  SELECT
    1 AS anchor,
    (SELECT count(*) FROM doc)                              AS doc_found,
    (SELECT status FROM doc)                                AS doc_status,
    (SELECT doc_kind FROM doc)                              AS doc_kind,
    (SELECT doc_no FROM doc)                                AS doc_no,
    (SELECT doc_date FROM doc)                              AS doc_date,
    (SELECT idempotency_key FROM doc)                       AS idempotency_key,
    (SELECT net FROM doc)                                   AS net,
    (SELECT tax FROM doc)                                   AS tax,
    (SELECT gross FROM doc)                                 AS gross,
    (SELECT posted_at FROM doc)                             AS posted_at,
    (SELECT posted_by FROM doc)                             AS posted_by,
    (SELECT sum(net) FROM line_rows)                        AS line_net,
    (SELECT sum(tax) FROM line_rows)                        AS line_tax,
    (SELECT sum(gross) FROM line_rows)                      AS line_gross,
    (SELECT count(*) FROM line_rows)                        AS line_count,
    (SELECT fy_start FROM env)                              AS fy_start,
    (SELECT fy_end FROM env)                                AS fy_end,
    (SELECT fy_status FROM env)                             AS fy_status,
    (SELECT period_id FROM env)                             AS period_id,
    (SELECT period_status FROM env)                         AS period_status,
    (SELECT si_prefix FROM env)                             AS si_prefix,
    (SELECT si_pad FROM env)                                AS si_pad,
    (SELECT je_prefix FROM env)                             AS je_prefix,
    (SELECT je_pad FROM env)                                AS je_pad,
    (SELECT je_type_count FROM env)                         AS je_type_count,
    (SELECT si_next FROM env)                               AS si_next,
    (SELECT je_next FROM env)                               AS je_next,
    CASE
      WHEN (SELECT si_prefix FROM env) IS NOT NULL
       AND (SELECT fy_start FROM env) IS NOT NULL
      THEN (SELECT si_prefix FROM env) || '-'
           || extract(year FROM (SELECT fy_start FROM env))::int::text || '-'
    END                                                     AS si_expected_prefix,
    CASE
      WHEN (SELECT je_prefix FROM env) IS NOT NULL
       AND (SELECT fy_start FROM env) IS NOT NULL
      THEN (SELECT je_prefix FROM env) || '-'
           || extract(year FROM (SELECT fy_start FROM env))::int::text || '-'
    END                                                     AS je_expected_prefix,
    (SELECT count(*) FROM je)                               AS je_found,
    (SELECT id FROM je)                                     AS je_id,
    (SELECT entry_no FROM je)                               AS je_no,
    (SELECT status FROM je)                                 AS je_status,
    (SELECT entry_kind FROM je)                             AS je_kind,
    (SELECT entry_date FROM je)                             AS je_date,
    (SELECT fiscal_year_id FROM je)                         AS je_fy,
    (SELECT period_id FROM je)                              AS je_period,
    (SELECT idempotency_key FROM je)                        AS je_idem,
    (SELECT reason FROM je)                                 AS je_reason,
    (SELECT posted_by FROM je)                              AS je_posted_by,
    (SELECT count(*) FROM je_raw)                           AS je_row_count,
    (SELECT n FROM jl_agg)                                  AS jl_count,
    (SELECT dr FROM jl_agg)                                 AS jl_dr,
    (SELECT cr FROM jl_agg)                                 AS jl_cr,
    (SELECT account_id FROM map WHERE account_role = 'AR_CONTROL')         AS ar_id,
    (SELECT account_id FROM map WHERE account_role = 'SALES_REVENUE')      AS rev_id,
    (SELECT account_id FROM map WHERE account_role = 'VAT_OUTPUT')         AS vat_id,
    (SELECT account_id FROM map WHERE account_role = 'COGS')               AS cogs_id,
    (SELECT account_id FROM map WHERE account_role = 'INVENTORY_CONTROL')  AS inv_id,
    (SELECT coalesce(sum(debit), 0)  FROM jel WHERE account_id = (SELECT account_id FROM map WHERE account_role = 'AR_CONTROL'))        AS ar_debit,
    (SELECT coalesce(sum(credit), 0) FROM jel WHERE account_id = (SELECT account_id FROM map WHERE account_role = 'AR_CONTROL'))        AS ar_credit,
    (SELECT coalesce(sum(debit), 0)  FROM jel WHERE account_id = (SELECT account_id FROM map WHERE account_role = 'SALES_REVENUE'))     AS rev_debit,
    (SELECT coalesce(sum(credit), 0) FROM jel WHERE account_id = (SELECT account_id FROM map WHERE account_role = 'SALES_REVENUE'))     AS rev_credit,
    (SELECT coalesce(sum(debit), 0)  FROM jel WHERE account_id = (SELECT account_id FROM map WHERE account_role = 'VAT_OUTPUT'))        AS vat_debit,
    (SELECT coalesce(sum(credit), 0) FROM jel WHERE account_id = (SELECT account_id FROM map WHERE account_role = 'VAT_OUTPUT'))        AS vat_credit,
    (SELECT coalesce(sum(debit), 0)  FROM jel WHERE account_id = (SELECT account_id FROM map WHERE account_role = 'COGS'))              AS cogs_debit,
    (SELECT coalesce(sum(credit), 0) FROM jel WHERE account_id = (SELECT account_id FROM map WHERE account_role = 'COGS'))              AS cogs_credit,
    (SELECT coalesce(sum(debit), 0)  FROM jel WHERE account_id = (SELECT account_id FROM map WHERE account_role = 'INVENTORY_CONTROL')) AS inv_debit,
    (SELECT coalesce(sum(credit), 0) FROM jel WHERE account_id = (SELECT account_id FROM map WHERE account_role = 'INVENTORY_CONTROL')) AS inv_credit,
    (SELECT count(*) FROM jel jl
      WHERE jl.account_id = (SELECT account_id FROM map WHERE account_role = 'AR_CONTROL')
        AND jl.debit = (SELECT gross FROM doc)
        AND jl.credit = 0
        AND jl.party_id = (SELECT party_id FROM doc))        AS ar_party_match,
    (SELECT count(*) FROM mv)                               AS mv_count,
    (SELECT total_value FROM mv_agg)                        AS mv_value,
    (SELECT count(*) FROM issue_lines)                      AS issue_line_count,
    (SELECT n FROM mv_missing)                              AS mv_missing,
    (SELECT n FROM mv_extra)                                AS mv_extra,
    (SELECT n FROM mv_bad)                                  AS mv_bad,
    (SELECT n FROM mv_link_bad)                             AS mv_link_bad,
    (SELECT negative_or_missing FROM stock_bad)             AS stock_negative,
    (SELECT ledger_mismatch FROM stock_bad)                 AS stock_ledger_mismatch,
    (SELECT posted_rows FROM aud)                           AS audit_posted,
    (SELECT posted_je_link_rows FROM aud)                   AS audit_posted_je_link,
    (SELECT number_rows FROM aud)                           AS audit_number,
    (SELECT stock_rows FROM aud)                            AS audit_stock,
    (SELECT n FROM reversal)                                AS reversal_rows,
    (SELECT n FROM linked_notes)                            AS linked_note_rows,
    (SELECT count(*) FROM hasad.sales_documents x
      WHERE x.company_id = (SELECT company_id FROM doc)
        AND x.doc_no = (SELECT doc_no FROM doc))            AS doc_no_duplicates,
    (SELECT count(*) FROM hasad.journal_entries x
      WHERE x.company_id = (SELECT company_id FROM doc)
        AND x.entry_no = (SELECT entry_no FROM je))             AS je_no_duplicates,
    (SELECT count(*) FROM hasad.journal_entries x
      WHERE x.company_id = (SELECT company_id FROM doc)
        AND x.idempotency_key = (SELECT idempotency_key FROM doc)) AS idem_rows
),
typed AS (
  SELECT
    a.*,
    CASE
      WHEN a.si_expected_prefix IS NOT NULL
       AND a.doc_no LIKE a.si_expected_prefix || '%'
      THEN substring(a.doc_no FROM length(a.si_expected_prefix) + 1)
    END AS si_suffix,
    CASE
      WHEN a.je_expected_prefix IS NOT NULL
       AND a.je_no LIKE a.je_expected_prefix || '%'
      THEN substring(a.je_no FROM length(a.je_expected_prefix) + 1)
    END AS je_suffix
  FROM agg a
),
checks AS (
  SELECT 1 AS check_no, 'DOCUMENT_FOUND_AND_POSTED' AS check_name,
    CASE WHEN t.doc_found = 1
              AND t.doc_status = 'posted'
              AND t.doc_kind = 'invoice'
              AND t.doc_no IS NOT NULL
              AND t.posted_at IS NOT NULL
              AND t.posted_by IS NOT NULL
              AND t.idempotency_key IS NOT NULL
         THEN 'PASS' ELSE 'FAIL' END AS status,
    jsonb_build_object('found', t.doc_found, 'status', t.doc_status, 'doc_kind', t.doc_kind,
                       'doc_no', t.doc_no, 'posted_at', t.posted_at,
                       'posted_by', t.posted_by, 'idempotency_key', t.idempotency_key) AS detail
  FROM typed t
  UNION ALL
  SELECT 2, 'DOCUMENT_AMOUNTS_CONSISTENT',
    CASE WHEN t.gross IS NOT NULL AND t.gross = t.net + t.tax AND t.gross > 0
              AND t.net = t.line_net AND t.tax = t.line_tax AND t.gross = t.line_gross
         THEN 'PASS' ELSE 'FAIL' END,
    jsonb_build_object('net', t.net, 'tax', t.tax, 'gross', t.gross,
                       'line_net', t.line_net, 'line_tax', t.line_tax, 'line_gross', t.line_gross)
  FROM typed t
  UNION ALL
  SELECT 3, 'INVOICE_NUMBER_FORMAT',
    CASE WHEN t.doc_no IS NOT NULL
              AND t.si_expected_prefix IS NOT NULL
              AND t.si_suffix IS NOT NULL
              AND t.si_suffix ~ '^[0-9]+$'
              AND length(t.si_suffix) = coalesce(t.si_pad, 4)
              AND t.si_suffix = lpad(t.si_suffix, coalesce(t.si_pad, 4), '0')
         THEN 'PASS' ELSE 'FAIL' END,
    jsonb_build_object('doc_no', t.doc_no, 'expected_prefix', t.si_expected_prefix,
                       'suffix', t.si_suffix, 'pad_length', t.si_pad)
  FROM typed t
  UNION ALL
  SELECT 4, 'INVOICE_COUNTER_ADVANCED',
    CASE WHEN t.si_suffix ~ '^[0-9]+$'
              AND t.si_next IS NOT NULL
              AND t.si_next = (CASE WHEN t.si_suffix ~ '^[0-9]+$' THEN t.si_suffix::bigint END) + 1
         THEN 'PASS' ELSE 'FAIL' END,
    jsonb_build_object('suffix', t.si_suffix, 'doc_numbers_next_value', t.si_next,
                       'expected_next_value', CASE WHEN t.si_suffix ~ '^[0-9]+$'
                                                   THEN t.si_suffix::bigint + 1 END)
  FROM typed t
  UNION ALL
  SELECT 5, 'INVOICE_NUMBER_UNIQUE',
    CASE WHEN t.doc_no_duplicates = 1 THEN 'PASS' ELSE 'FAIL' END,
    jsonb_build_object('documents_with_this_doc_no', t.doc_no_duplicates)
  FROM typed t
  UNION ALL
  SELECT 6, 'JOURNAL_ENTRY_FOUND',
    CASE WHEN t.je_found = 1 AND t.je_row_count = 1 THEN 'PASS'
         WHEN t.je_found = 1 AND t.je_row_count > 1 THEN 'FAIL'
         ELSE 'FAIL' END,
    jsonb_build_object('entries_with_idempotency_key', t.je_row_count,
                       'idempotency_key', t.idempotency_key, 'je_id', t.je_id, 'je_no', t.je_no)
  FROM typed t
  UNION ALL
  SELECT 7, 'JOURNAL_ENTRY_FIELDS',
    CASE WHEN t.je_found = 1
              AND t.je_status = 'posted'
              AND t.je_kind = 'standard'
              AND t.je_date = t.doc_date
              AND t.je_fy = (SELECT fiscal_year_id FROM doc)
              AND t.je_period = t.period_id
              AND t.je_idem = t.idempotency_key
              AND t.je_posted_by = t.posted_by
              AND t.je_reason = 'sales invoice ' || t.doc_no
         THEN 'PASS' ELSE 'FAIL' END,
    jsonb_build_object('status', t.je_status, 'entry_kind', t.je_kind,
                       'entry_date', t.je_date, 'doc_date', t.doc_date,
                       'period_id', t.je_period, 'expected_period_id', t.period_id,
                       'reason', t.je_reason, 'posted_by', t.je_posted_by,
                       'expected_posted_by', t.posted_by)
  FROM typed t
  UNION ALL
  SELECT 8, 'JOURNAL_NUMBER_FORMAT',
    CASE WHEN t.je_no IS NOT NULL
              AND t.je_expected_prefix IS NOT NULL
              AND t.je_suffix IS NOT NULL
              AND t.je_suffix ~ '^[0-9]+$'
              AND length(t.je_suffix) = coalesce(t.je_pad, 4)
              AND t.je_suffix = lpad(t.je_suffix, coalesce(t.je_pad, 4), '0')
         THEN 'PASS' ELSE 'FAIL' END,
    jsonb_build_object('entry_no', t.je_no, 'expected_prefix', t.je_expected_prefix,
                       'suffix', t.je_suffix, 'pad_length', t.je_pad,
                       'je_document_types', t.je_type_count)
  FROM typed t
  UNION ALL
  SELECT 9, 'JOURNAL_NUMBER_UNIQUE',
    CASE WHEN t.je_no_duplicates = 1 THEN 'PASS' ELSE 'FAIL' END,
    jsonb_build_object('entries_with_this_entry_no', t.je_no_duplicates)
  FROM typed t
  UNION ALL
  SELECT 10, 'JOURNAL_BALANCED',
    CASE WHEN t.jl_count > 0 AND t.jl_dr = t.jl_cr AND t.jl_dr > 0
         THEN 'PASS' ELSE 'FAIL' END,
    jsonb_build_object('line_count', t.jl_count, 'total_debit', t.jl_dr,
                       'total_credit', t.jl_cr, 'difference', coalesce(t.jl_dr, 0) - coalesce(t.jl_cr, 0))
  FROM typed t
  UNION ALL
  SELECT 11, 'AR_LEG',
    CASE WHEN t.ar_id IS NOT NULL
              AND t.ar_debit = t.gross AND t.ar_credit = 0
              AND t.ar_party_match = 1
         THEN 'PASS' ELSE 'FAIL' END,
    jsonb_build_object('ar_account_id', t.ar_id, 'debit', t.ar_debit,
                       'credit', t.ar_credit, 'expected_debit', t.gross,
                       'party_matched_lines', t.ar_party_match)
  FROM typed t
  UNION ALL
  SELECT 12, 'REVENUE_LEG',
    CASE WHEN t.rev_id IS NOT NULL
              AND t.rev_credit = t.net AND t.rev_debit = 0
         THEN 'PASS' ELSE 'FAIL' END,
    jsonb_build_object('revenue_account_id', t.rev_id, 'debit', t.rev_debit,
                       'credit', t.rev_credit, 'expected_credit', t.net)
  FROM typed t
  UNION ALL
  SELECT 13, 'VAT_RULE_ZERO_TAX',
    CASE WHEN coalesce(t.tax, -1) = 0
              AND t.vat_credit = 0 AND t.vat_debit = 0
         THEN 'PASS'
         WHEN t.tax > 0 AND t.vat_credit = t.tax AND t.vat_debit = 0
         THEN 'WARN'
         ELSE 'FAIL' END,
    jsonb_build_object('document_tax', t.tax, 'vat_debit', t.vat_debit,
                       'vat_credit', t.vat_credit, 'vat_account_id', t.vat_id,
                       'note', 'zero-tax smoke test expects no VAT leg')
  FROM typed t
  UNION ALL
  SELECT 14, 'COGS_AND_INVENTORY_LEGS',
    CASE WHEN t.mv_value = 0
              AND coalesce(t.cogs_debit, 0) = 0 AND coalesce(t.inv_credit, 0) = 0
              AND coalesce(t.cogs_credit, 0) = 0 AND coalesce(t.inv_debit, 0) = 0
         THEN 'PASS'
         WHEN t.mv_value > 0
              AND t.cogs_id IS NOT NULL AND t.inv_id IS NOT NULL
              AND t.cogs_debit = t.mv_value AND t.inv_credit = t.mv_value
              AND t.cogs_credit = 0 AND t.inv_debit = 0
         THEN 'PASS'
         ELSE 'FAIL' END,
    jsonb_build_object('movement_value', t.mv_value, 'cogs_debit', t.cogs_debit,
                       'cogs_credit', t.cogs_credit, 'inventory_debit', t.inv_debit,
                       'inventory_credit', t.inv_credit, 'cogs_id', t.cogs_id, 'inv_id', t.inv_id)
  FROM typed t
  UNION ALL
  SELECT 15, 'JOURNAL_LINE_DESCRIPTIONS',
    CASE WHEN t.jl_count > 0
              AND NOT EXISTS (
                SELECT 1 FROM jel jl
                WHERE jl.description IS NULL
                   OR right(jl.description, length(' / ' || t.doc_no)) <> ' / ' || t.doc_no
              )
         THEN 'PASS' ELSE 'WARN' END,
    jsonb_build_object('doc_no', t.doc_no,
                       'descriptions', (SELECT jsonb_agg(jl.description ORDER BY jl.line_no) FROM jel jl))
  FROM typed t
  UNION ALL
  SELECT 16, 'MOVEMENT_COUNT',
    CASE WHEN t.mv_count = t.issue_line_count THEN 'PASS' ELSE 'FAIL' END,
    jsonb_build_object('movements', t.mv_count, 'expected_from_stocked_lines', t.issue_line_count)
  FROM typed t
  UNION ALL
  SELECT 17, 'MOVEMENT_CONTENT',
    CASE WHEN t.mv_missing = 0 AND t.mv_extra = 0 AND t.mv_count = t.issue_line_count
         THEN 'PASS' ELSE 'FAIL' END,
    jsonb_build_object('stocked_lines_without_movement', t.mv_missing,
                       'movements_without_stocked_line', t.mv_extra)
  FROM typed t
  UNION ALL
  SELECT 18, 'MOVEMENT_VALUES',
    CASE WHEN t.mv_count > 0 AND t.mv_bad = 0 THEN 'PASS'
         WHEN t.mv_count = 0 THEN 'PASS'
         ELSE 'FAIL' END,
    jsonb_build_object('invalid_movements', t.mv_bad,
                       'expected', 'value = round(qty*unit_cost,2), direction=out, type=sales_issue')
  FROM typed t
  UNION ALL
  SELECT 19, 'MOVEMENT_JOURNAL_LINK',
    CASE WHEN t.mv_count = 0 THEN 'PASS'
              WHEN t.mv_link_bad = 0 THEN 'PASS'
              ELSE 'WARN' END,
    jsonb_build_object('movements_with_wrong_or_null_journal_line', t.mv_link_bad,
                       'inventory_credit_line_id', (SELECT id FROM inv_line),
                       'note', 'movement journal_line_id is NULL when COGS value is 0 (documented risk)')
  FROM typed t
  UNION ALL
  SELECT 20, 'STOCK_LEVELS_NON_NEGATIVE',
    CASE WHEN t.stock_negative = 0 THEN 'PASS' ELSE 'FAIL' END,
    jsonb_build_object('affected_pairs_with_negative_or_missing_stock', t.stock_negative)
  FROM typed t
  UNION ALL
  SELECT 21, 'STOCK_LEDGER_IDENTITY',
    CASE WHEN t.stock_ledger_mismatch = 0 THEN 'PASS' ELSE 'WARN' END,
    jsonb_build_object('pairs_where_stock_level_differs_from_movement_sum', t.stock_ledger_mismatch,
                       'note', 'WARN only: pre-existing DEV stock may not have opening movements')
  FROM typed t
  UNION ALL
  SELECT 22, 'AUDIT_INVOICE_POSTED',
    CASE WHEN t.audit_posted = 1 AND t.audit_posted_je_link = 1 THEN 'PASS' ELSE 'FAIL' END,
    jsonb_build_object('sale_invoice_posted_rows', t.audit_posted,
                       'rows_linked_to_journal_entry', t.audit_posted_je_link)
  FROM typed t
  UNION ALL
  SELECT 23, 'AUDIT_NUMBER_ISSUED',
    CASE WHEN t.audit_number = 1 THEN 'PASS' ELSE 'FAIL' END,
    jsonb_build_object('number_issued_rows', t.audit_number, 'doc_no', t.doc_no)
  FROM typed t
  UNION ALL
  SELECT 24, 'AUDIT_STOCK_POSTED',
    CASE WHEN t.audit_stock = t.mv_count THEN 'PASS' ELSE 'FAIL' END,
    jsonb_build_object('stock_posted_rows', t.audit_stock, 'movements', t.mv_count)
  FROM typed t
  UNION ALL
  SELECT 25, 'IDEMPOTENCY_SINGLE_USE',
    CASE WHEN t.idem_rows = 1 AND t.je_row_count = 1 AND t.doc_no_duplicates = 1
         THEN 'PASS' ELSE 'FAIL' END,
    jsonb_build_object('journal_entries_with_idempotency_key', t.idem_rows,
                       'journal_entries_for_this_document', t.je_row_count,
                       'documents_with_this_doc_no', t.doc_no_duplicates)
  FROM typed t
  UNION ALL
  SELECT 26, 'NOT_REVERSED',
    CASE WHEN t.reversal_rows = 0 AND t.linked_note_rows = 0 THEN 'PASS'
         WHEN t.reversal_rows = 0 AND t.linked_note_rows > 0 THEN 'WARN'
         ELSE 'FAIL' END,
    jsonb_build_object('reversal_entries', t.reversal_rows,
                       'posted_linked_notes', t.linked_note_rows)
  FROM typed t
)
SELECT check_no, check_name, status, detail
FROM checks
UNION ALL
SELECT
  99 AS check_no,
  'OVERALL'::text AS check_name,
  CASE
    WHEN count(*) FILTER (WHERE status = 'FAIL') > 0 THEN 'FAIL'
    WHEN count(*) FILTER (WHERE status = 'WARN') > 0 THEN 'WARN'
    ELSE 'PASS'
  END AS status,
  jsonb_build_object(
    'document_id', (SELECT document_id FROM params),
    'pass', count(*) FILTER (WHERE status = 'PASS'),
    'warn', count(*) FILTER (WHERE status = 'WARN'),
    'fail', count(*) FILTER (WHERE status = 'FAIL')
  ) AS detail
FROM checks
ORDER BY check_no;
