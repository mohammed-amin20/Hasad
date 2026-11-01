-- =====================================================================
-- Hasad ERP V2 - Supabase DEV read-only metadata inventory
-- =====================================================================
-- Target (non-secret): Supabase DEV project sxasnunzspkuwbxiddqd,
-- connected through the already verified pooler endpoint that the runner
-- reads from supabase/.temp/pooler-url.
--
-- Safety contract:
--   * Catalog metadata only. No application row data is ever selected.
--   * One explicit BEGIN TRANSACTION READ ONLY / ROLLBACK pair wraps every
--     catalog query. Nothing before BEGIN except session-local SETs.
--   * Fail-closed server-side guard: if either the session default or the
--     current transaction is not read-only, a plpgsql RAISE EXCEPTION
--     aborts the run (psql stops immediately via ON_ERROR_STOP).
--   * psql meta-commands used: only \set and \echo.
--   * Migration-history tables are checked through catalog existence
--     lookups only; their contents are never read.
-- =====================================================================

\set ON_ERROR_STOP on

-- Session-local defaults only (no database state is touched).
SET default_transaction_read_only = on;
SET statement_timeout = '60s';
SET idle_in_transaction_session_timeout = '120s';

BEGIN TRANSACTION READ ONLY;

-- ---------------------------------------------------------------------
-- Fail-closed read-only guard (valid plpgsql; aborts this transaction
-- and the psql run if the transaction is not genuinely read-only).
-- ---------------------------------------------------------------------
DO $hasad_readonly_guard$
BEGIN
  IF current_setting('transaction_read_only') <> 'on' THEN
    RAISE EXCEPTION 'FAIL-CLOSED: transaction_read_only = %, expected on',
      current_setting('transaction_read_only');
  END IF;
  IF current_setting('default_transaction_read_only') <> 'on' THEN
    RAISE EXCEPTION 'FAIL-CLOSED: default_transaction_read_only = %, expected on',
      current_setting('default_transaction_read_only');
  END IF;
END
$hasad_readonly_guard$;

-- ---------------------------------------------------------------------
-- 01. Run context
-- ---------------------------------------------------------------------
\echo '==== 01. RUN CONTEXT ===='
SELECT current_database() AS database_name,
       current_user AS connected_role,
       current_setting('transaction_read_only') AS transaction_read_only,
       current_setting('default_transaction_read_only') AS default_transaction_read_only,
       current_setting('server_version') AS server_version,
       clock_timestamp() AS captured_at;

-- ---------------------------------------------------------------------
-- 02. Schemas and ownership
-- ---------------------------------------------------------------------
\echo '==== 02. SCHEMAS AND OWNERSHIP ===='
SELECT n.nspname AS schema_name,
       pg_get_userbyid(n.nspowner) AS schema_owner,
       (n.nspacl IS NOT NULL) AS has_explicit_acl
FROM pg_namespace n
WHERE n.nspname NOT LIKE 'pg\_temp\_%'
  AND n.nspname NOT LIKE 'pg\_toast%'
ORDER BY n.nspname;

\echo '==== 02b. V2 SCHEMA PRESENCE (hasad / hasad_api) ===='
SELECT q.schema_name,
       EXISTS (SELECT 1
               FROM pg_namespace n
               WHERE n.nspname = q.schema_name) AS schema_exists
FROM (VALUES ('hasad'), ('hasad_api')) AS q(schema_name)
ORDER BY q.schema_name;

-- ---------------------------------------------------------------------
-- 03. Public schema relations (tables / views / materialized views /
--     foreign tables / partitioned tables). Row counts are catalog
--     estimates only; no table rows are read.
-- ---------------------------------------------------------------------
\echo '==== 03. PUBLIC SCHEMA RELATIONS ===='
SELECT c.relname AS object_name,
       CASE c.relkind
         WHEN 'r' THEN 'table'
         WHEN 'p' THEN 'partitioned_table'
         WHEN 'v' THEN 'view'
         WHEN 'm' THEN 'materialized_view'
         WHEN 'f' THEN 'foreign_table'
       END AS object_type,
       c.relpersistence AS persistence,
       c.relrowsecurity AS rls_enabled,
       c.relforcerowsecurity AS rls_forced,
       CASE WHEN c.reltuples >= 0 THEN c.reltuples::bigint ELSE NULL END
         AS estimated_rows,
       pg_size_pretty(pg_total_relation_size(c.oid)) AS total_size
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public'
  AND c.relkind IN ('r', 'p', 'v', 'm', 'f')
ORDER BY c.relname;

\echo '==== 03b. PUBLIC VIEW DEFINITIONS ===='
SELECT c.relname AS view_name,
       pg_get_viewdef(c.oid, true) AS definition
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public'
  AND c.relkind IN ('v', 'm')
ORDER BY c.relname;

-- ---------------------------------------------------------------------
-- 04. Functions / routines with full signatures (non-system schemas)
-- ---------------------------------------------------------------------
\echo '==== 04. FUNCTIONS AND ROUTINES ===='
SELECT n.nspname AS schema_name,
       p.proname AS function_name,
       pg_get_function_identity_arguments(p.oid) AS arguments,
       pg_get_function_result(p.oid) AS return_type,
       l.lanname AS language,
       p.prokind AS kind,
       p.provolatile AS volatility,
       p.prosecdef AS security_definer,
       pg_get_userbyid(p.proowner) AS owner
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
JOIN pg_language l ON l.oid = p.prolang
WHERE n.nspname NOT IN ('pg_catalog', 'information_schema')
ORDER BY n.nspname, p.proname, arguments;

-- ---------------------------------------------------------------------
-- 05. Row Level Security policies (names and definitions)
-- ---------------------------------------------------------------------
\echo '==== 05. ROW LEVEL SECURITY POLICIES ===='
SELECT n.nspname AS schema_name,
       c.relname AS object_name,
       pol.polname AS policy_name,
       CASE pol.polcmd
         WHEN 'r' THEN 'SELECT'
         WHEN 'a' THEN 'INSERT'
         WHEN 'w' THEN 'UPDATE'
         WHEN 'd' THEN 'DELETE'
         WHEN '*' THEN 'ALL'
       END AS command,
       pol.polpermissive AS permissive,
       pg_get_expr(pol.polqual, pol.polrelid) AS using_expression,
       pg_get_expr(pol.polwithcheck, pol.polrelid) AS with_check_expression
FROM pg_policy pol
JOIN pg_class c ON c.oid = pol.polrelid
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public'
ORDER BY c.relname, pol.polname;

-- ---------------------------------------------------------------------
-- 06. Triggers (non-internal)
-- ---------------------------------------------------------------------
\echo '==== 06. TRIGGERS ===='
SELECT n.nspname AS schema_name,
       c.relname AS object_name,
       t.tgname AS trigger_name,
       t.tgenabled AS enabled,
       pg_get_triggerdef(t.oid) AS definition
FROM pg_trigger t
JOIN pg_class c ON c.oid = t.tgrelid
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public'
  AND NOT t.tgisinternal
ORDER BY c.relname, t.tgname;

-- ---------------------------------------------------------------------
-- 07. Sequences (structure only, values not read)
-- ---------------------------------------------------------------------
\echo '==== 07. SEQUENCES ===='
SELECT n.nspname AS schema_name,
       c.relname AS sequence_name,
       pg_get_userbyid(c.relowner) AS sequence_owner,
       pg_size_pretty(pg_relation_size(c.oid)) AS size
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public'
  AND c.relkind = 'S'
ORDER BY c.relname;

-- ---------------------------------------------------------------------
-- 08. Indexes
-- ---------------------------------------------------------------------
\echo '==== 08. INDEXES ===='
SELECT n.nspname AS schema_name,
       c.relname AS table_name,
       i.indexrelid::regclass AS index_name,
       pg_get_indexdef(i.indexrelid) AS index_definition,
       i.indisprimary AS is_primary,
       i.indisunique AS is_unique,
       i.indisvalid AS is_valid,
       i.indisready AS is_ready
FROM pg_index i
JOIN pg_class c ON c.oid = i.indrelid
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public'
ORDER BY c.relname, index_name;

-- ---------------------------------------------------------------------
-- 09. Constraints (primary / unique / check / exclusion / foreign key)
-- ---------------------------------------------------------------------
\echo '==== 09. CONSTRAINTS ===='
SELECT n.nspname AS schema_name,
       c.relname AS object_name,
       con.conname AS constraint_name,
       CASE con.contype
         WHEN 'p' THEN 'primary_key'
         WHEN 'f' THEN 'foreign_key'
         WHEN 'u' THEN 'unique'
         WHEN 'c' THEN 'check'
         WHEN 'x' THEN 'exclusion'
         WHEN 't' THEN 'trigger'
         WHEN 'd' THEN 'domain'
       END AS constraint_type,
       pg_get_constraintdef(con.oid) AS definition,
       con.condeferrable AS deferrable,
       con.convalidated AS validated
FROM pg_constraint con
JOIN pg_class c ON c.oid = con.conrelid
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public'
ORDER BY c.relname, con.conname;

-- ---------------------------------------------------------------------
-- 10. Schema and object grants (explicit ACLs, or effective defaults)
-- ---------------------------------------------------------------------
\echo '==== 10a. SCHEMA GRANTS ===='
SELECT n.nspname AS schema_name,
       CASE WHEN e.grantee = 0 THEN 'PUBLIC'
            ELSE pg_get_userbyid(e.grantee) END AS grantee,
       pg_get_userbyid(e.grantor) AS grantor,
       e.privilege_type,
       e.is_grantable,
       (n.nspacl IS NULL) AS using_default_acl
FROM pg_namespace n
CROSS JOIN LATERAL aclexplode(COALESCE(n.nspacl, acldefault('n', n.nspowner))) e
WHERE n.nspname NOT LIKE 'pg\_temp\_%'
  AND n.nspname NOT LIKE 'pg\_toast%'
ORDER BY n.nspname, grantee, e.privilege_type;

\echo '==== 10b. RELATION GRANTS (public schema) ===='
SELECT n.nspname AS schema_name,
       c.relname AS object_name,
       CASE c.relkind
         WHEN 'r' THEN 'table'
         WHEN 'p' THEN 'partitioned_table'
         WHEN 'v' THEN 'view'
         WHEN 'm' THEN 'materialized_view'
         WHEN 'f' THEN 'foreign_table'
         WHEN 'S' THEN 'sequence'
       END AS object_type,
       CASE WHEN e.grantee = 0 THEN 'PUBLIC'
            ELSE pg_get_userbyid(e.grantee) END AS grantee,
       pg_get_userbyid(e.grantor) AS grantor,
       e.privilege_type,
       e.is_grantable,
       (c.relacl IS NULL) AS using_default_acl
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
CROSS JOIN LATERAL aclexplode(COALESCE(c.relacl,
       acldefault(CASE WHEN c.relkind = 'S' THEN 'S'::"char"
                       ELSE 'r'::"char" END, c.relowner))) e
WHERE n.nspname = 'public'
  AND c.relkind IN ('r', 'p', 'v', 'm', 'f', 'S')
ORDER BY c.relname, grantee, e.privilege_type;

\echo '==== 10c. ROUTINE GRANTS (non-system schemas) ===='
SELECT n.nspname AS schema_name,
       p.proname AS function_name,
       pg_get_function_identity_arguments(p.oid) AS arguments,
       CASE WHEN e.grantee = 0 THEN 'PUBLIC'
            ELSE pg_get_userbyid(e.grantee) END AS grantee,
       pg_get_userbyid(e.grantor) AS grantor,
       e.privilege_type,
       e.is_grantable,
       (p.proacl IS NULL) AS using_default_acl
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
CROSS JOIN LATERAL aclexplode(COALESCE(p.proacl, acldefault('f', p.proowner))) e
WHERE n.nspname NOT IN ('pg_catalog', 'information_schema')
ORDER BY n.nspname, p.proname, grantee, e.privilege_type;

\echo '==== 10d. DEFAULT PRIVILEGES ===='
SELECT pg_get_userbyid(d.defaclrole) AS role_name,
       COALESCE(n.nspname, '(database)') AS schema_name,
       d.defaclobjtype AS object_type,
       d.defaclacl AS default_acl
FROM pg_default_acl d
LEFT JOIN pg_namespace n ON n.oid = d.defaclnamespace
ORDER BY role_name, schema_name, d.defaclobjtype;

-- ---------------------------------------------------------------------
-- 11. Dependencies relevant to safe legacy cleanup
-- ---------------------------------------------------------------------
\echo '==== 11a. OBJECTS DEPENDING ON PUBLIC RELATIONS (cleanup ordering input) ===='
SELECT pg_describe_object(d.classid, d.objid, d.objsubid) AS dependent_object,
       d.deptype AS dependency_type,
       pg_describe_object(d.refclassid, d.refobjid, d.refobjsubid)
         AS on_public_object
FROM pg_depend d
JOIN pg_class c ON c.oid = d.refobjid
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE d.refclassid = 'pg_class'::regclass
  AND n.nspname = 'public'
  AND d.deptype NOT IN ('i', 'p')
ORDER BY dependency_type, dependent_object;

\echo '==== 11b. DEPENDENCIES OF OBJECTS IN PUBLIC SCHEMA ===='
SELECT pg_describe_object(d.classid, d.objid, d.objsubid) AS public_object,
       d.deptype AS dependency_type,
       pg_describe_object(d.refclassid, d.refobjid, d.refobjsubid) AS depends_on
FROM pg_depend d
WHERE d.deptype NOT IN ('i', 'p')
  AND ( ( d.classid = 'pg_class'::regclass
          AND EXISTS (SELECT 1
                      FROM pg_class c
                      JOIN pg_namespace n ON n.oid = c.relnamespace
                      WHERE c.oid = d.objid
                        AND n.nspname = 'public') )
     OR ( d.classid = 'pg_proc'::regclass
          AND EXISTS (SELECT 1
                      FROM pg_proc p
                      JOIN pg_namespace n ON n.oid = p.pronamespace
                      WHERE p.oid = d.objid
                        AND n.nspname = 'public') ) )
ORDER BY dependency_type, public_object;

-- ---------------------------------------------------------------------
-- 12. Extensions
-- ---------------------------------------------------------------------
\echo '==== 12. EXTENSIONS ===='
SELECT e.extname AS extension_name,
       e.extversion AS version,
       n.nspname AS extension_schema,
       pg_get_userbyid(e.extowner) AS owner
FROM pg_extension e
JOIN pg_namespace n ON n.oid = e.extnamespace
ORDER BY e.extname;

-- ---------------------------------------------------------------------
-- 13. Migration-history table existence (catalog lookups only; the
--     candidate tables are never selected from).
-- ---------------------------------------------------------------------
\echo '==== 13. MIGRATION-HISTORY TABLE EXISTENCE ===='
SELECT q.schema_name,
       q.table_name,
       EXISTS (SELECT 1
               FROM pg_class c
               JOIN pg_namespace n ON n.oid = c.relnamespace
               WHERE n.nspname = q.schema_name
                 AND c.relname = q.table_name) AS table_exists
FROM (VALUES ('supabase_migrations', 'schema_migrations'),
             ('supabase', 'schema_migrations'),
             ('public', 'schema_migrations')) AS q(schema_name, table_name)
ORDER BY q.schema_name;

\echo '==== END OF READ-ONLY INVENTORY - ROLLBACK FOLLOWS ===='
ROLLBACK;
\echo '==== ROLLBACK COMPLETE - NO DATABASE STATE WAS CHANGED ===='
