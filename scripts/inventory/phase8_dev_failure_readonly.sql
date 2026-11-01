-- Read-only Phase 8 deployment failure diagnosis. Catalog metadata only.
\set ON_ERROR_STOP on

SET default_transaction_read_only = on;
SET statement_timeout = '60s';
SET idle_in_transaction_session_timeout = '120s';
BEGIN TRANSACTION READ ONLY;

DO $guard$
BEGIN
  IF current_setting('transaction_read_only') <> 'on'
     OR current_setting('default_transaction_read_only') <> 'on' THEN
    RAISE EXCEPTION 'FAIL-CLOSED: read-only transaction guard failed';
  END IF;
END
$guard$;

\echo '==== RUN CONTEXT ===='
SELECT current_database() AS database_name,
       current_setting('transaction_read_only') AS transaction_read_only,
       current_setting('server_version') AS server_version;

\echo '==== HASAD RELATION COUNTS ===='
SELECT count(*) FILTER (WHERE c.relkind IN ('r','p')) AS table_count,
       count(*) FILTER (WHERE c.relkind = 'p') AS partitioned_table_count
FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'hasad' AND c.relkind IN ('r','p');

\echo '==== ALL HASAD RELATIONS (review for unexpected objects) ===='
SELECT c.relname AS relation_name,
       CASE c.relkind WHEN 'r' THEN 'table' WHEN 'p' THEN 'partitioned_table'
         WHEN 'v' THEN 'view' WHEN 'm' THEN 'materialized_view'
         WHEN 'S' THEN 'sequence' WHEN 'f' THEN 'foreign_table' ELSE c.relkind::text END AS kind
FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'hasad' AND c.relkind IN ('r','p','v','m','S','f')
ORDER BY c.relkind, c.relname;

\echo '==== PHASE 8 TABLE PRESENCE ===='
WITH expected(table_name, phase) AS (VALUES
 ('cashboxes','00800'), ('bank_accounts','00800'), ('payment_documents','00800'),
 ('payment_allocations','00800'), ('reconciliation_statements','00800'), ('reconciliation_items','00800'),
 ('expense_categories','00900'), ('expense_documents','00900'), ('expense_document_lines','00900'),
 ('expense_attachments','00900'), ('expense_receipt_dedup','00900')
)
SELECT e.phase, e.table_name, c.oid IS NOT NULL AS exists
FROM expected e
LEFT JOIN pg_namespace n ON n.nspname = 'hasad'
LEFT JOIN pg_class c ON c.relnamespace = n.oid AND c.relname = e.table_name AND c.relkind IN ('r','p')
ORDER BY e.phase, e.table_name;

\echo '==== PHASE 8 CONSTRAINTS (complete catalog listing) ===='
SELECT t.relname AS table_name, con.conname AS constraint_name,
       CASE con.contype WHEN 'p' THEN 'primary_key' WHEN 'f' THEN 'foreign_key'
         WHEN 'u' THEN 'unique' WHEN 'c' THEN 'check' WHEN 'x' THEN 'exclusion' ELSE con.contype::text END AS kind,
       CASE WHEN con.contype = 'f' THEN
         CASE con.confdeltype WHEN 'a' THEN 'NO ACTION' WHEN 'r' THEN 'RESTRICT'
           WHEN 'c' THEN 'CASCADE' WHEN 'n' THEN 'SET NULL' WHEN 'd' THEN 'SET DEFAULT' END
         ELSE NULL END AS on_delete,
       pg_get_constraintdef(con.oid, true) AS definition
FROM pg_constraint con JOIN pg_class t ON t.oid = con.conrelid
JOIN pg_namespace n ON n.oid = t.relnamespace
WHERE n.nspname = 'hasad' AND t.relname IN
 ('cashboxes','bank_accounts','payment_documents','payment_allocations','reconciliation_statements',
  'reconciliation_items','expense_categories','expense_documents','expense_document_lines',
  'expense_attachments','expense_receipt_dedup')
ORDER BY t.relname, con.conname;

\echo '==== PHASE 8 INDEXES (complete catalog listing) ===='
SELECT t.relname AS table_name, i.relname AS index_name,
       x.indisprimary AS is_primary, x.indisunique AS is_unique,
       x.indisvalid AS is_valid, x.indisready AS is_ready,
       pg_get_indexdef(i.oid) AS definition
FROM pg_index x JOIN pg_class t ON t.oid = x.indrelid
JOIN pg_class i ON i.oid = x.indexrelid
JOIN pg_namespace n ON n.oid = t.relnamespace
WHERE n.nspname = 'hasad' AND t.relname IN
 ('cashboxes','bank_accounts','payment_documents','payment_allocations','reconciliation_statements',
  'reconciliation_items','expense_categories','expense_documents','expense_document_lines',
  'expense_attachments','expense_receipt_dedup')
ORDER BY t.relname, i.relname;

\echo '==== PHASE 8 COLUMN COUNTS ===='
SELECT t.relname AS table_name, count(a.attnum) AS column_count
FROM pg_class t JOIN pg_namespace n ON n.oid = t.relnamespace
LEFT JOIN pg_attribute a ON a.attrelid = t.oid AND a.attnum > 0 AND NOT a.attisdropped
WHERE n.nspname = 'hasad' AND t.relname IN
 ('cashboxes','bank_accounts','payment_documents','payment_allocations','reconciliation_statements',
  'reconciliation_items','expense_categories','expense_documents','expense_document_lines',
  'expense_attachments','expense_receipt_dedup') AND t.relkind IN ('r','p')
GROUP BY t.relname ORDER BY t.relname;

\echo '==== PHASE 8 SECURITY STATE ===='
SELECT t.relname AS table_name, c.relrowsecurity AS rls_enabled,
       c.relforcerowsecurity AS rls_forced,
       (SELECT count(*) FROM pg_policy p WHERE p.polrelid = c.oid) AS policy_count,
       (SELECT count(*) FROM pg_trigger tr WHERE tr.tgrelid = c.oid AND NOT tr.tgisinternal) AS non_internal_trigger_count,
       (SELECT count(*) FROM information_schema.role_table_grants g
         WHERE g.table_schema = 'hasad' AND g.table_name = t.relname
           AND g.grantee <> current_user) AS grants_to_other_roles
FROM (VALUES ('cashboxes'),('bank_accounts'),('payment_documents'),('payment_allocations'),
 ('reconciliation_statements'),('reconciliation_items'),('expense_categories'),('expense_documents'),
 ('expense_document_lines'),('expense_attachments'),('expense_receipt_dedup')) AS t(relname)
LEFT JOIN pg_namespace n ON n.nspname = 'hasad'
LEFT JOIN pg_class c ON c.relnamespace = n.oid AND c.relname = t.relname AND c.relkind IN ('r','p')
ORDER BY t.relname;

\echo '==== PHASE 8 TABLE GRANTS (all explicit/default ACL entries) ===='
SELECT t.relname AS table_name, COALESCE(grantee.rolname, 'PUBLIC') AS grantee,
       acl.privilege_type, acl.is_grantable
FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
JOIN pg_class t ON t.oid = c.oid
CROSS JOIN LATERAL aclexplode(COALESCE(c.relacl, acldefault('r', c.relowner))) AS acl
LEFT JOIN pg_roles grantee ON grantee.oid = acl.grantee
WHERE n.nspname = 'hasad' AND t.relname IN
 ('cashboxes','bank_accounts','payment_documents','payment_allocations','reconciliation_statements',
  'reconciliation_items','expense_categories','expense_documents','expense_document_lines',
  'expense_attachments','expense_receipt_dedup')
ORDER BY t.relname, grantee, acl.privilege_type;

\echo '==== ROLLBACK ===='
ROLLBACK;
