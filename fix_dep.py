import re
p=r'scripts/cleanup/04_drop_functions.sql'
s=open(p,encoding='utf-8').read()
start=s.find('  SELECT string_agg(\n           CASE\n             WHEN dep.nspname IN')
if start==-1:
    raise SystemExit('start')
end=s.find('   WHERE dep.nspname IS NOT NULL;', start)
if end==-1:
    raise SystemExit('end')
end2=s.find('\n', end)+1
new_block='''  SELECT string_agg(
           CASE
             WHEN COALESCE(dep.nspname, '') IN ('auth','storage','realtime','cron','extensions','net','vault','graphql','graphql_public','information_schema','pg_catalog','pgsodium','supabase_functions')
               THEN COALESCE(dep.nspname,'?')||'.'||COALESCE(dep.objname, dep.relname, '?')||':'||COALESCE(dep.deptype,'?')
             WHEN COALESCE(dep.nspname, '') = 'public' AND dep.relname IS NOT NULL
               THEN 'public.'||dep.relname||'('||COALESCE(dep.relkind,'?')||'):'||COALESCE(dep.deptype,'?')
             ELSE COALESCE(dep.nspname,'?')||'.'||COALESCE(dep.objname, dep.relname, '?')||'('||COALESCE(dep.objkind,'?')||'):'||COALESCE(dep.deptype,'?')
           END,
           '; ' ORDER BY COALESCE(dep.nspname,''), dep.relname, dep.objname
         )
   INTO v_depending
   FROM (
     SELECT DISTINCT
       COALESCE(nc.nspname, np.nspname) AS nspname,
       c2.relname,
       c2.relkind,
       p2.proname AS objname,
       CASE p2.prokind WHEN 'f' THEN 'func' WHEN 'p' THEN 'proc' WHEN 'a' THEN 'agg' WHEN 'w' THEN 'window' ELSE p2.prokind END AS objkind,
       d.deptype
     FROM pg_depend d
     JOIN pg_proc p1 ON p1.oid = d.refobjid
     JOIN pg_namespace n1 ON n1.oid = p1.pronamespace
     LEFT JOIN pg_class c2 ON c2.oid = d.objid AND d.classid = 'pg_class'::regclass
     LEFT JOIN pg_namespace nc ON nc.oid = c2.relnamespace
     LEFT JOIN pg_proc p2 ON p2.oid = d.objid AND d.classid = 'pg_proc'::regclass
     LEFT JOIN pg_namespace np ON np.oid = p2.pronamespace
     WHERE d.refclassid = 'pg_proc'::regclass
       AND d.deptype IN ('n','a')
       AND n1.nspname = 'public'
       AND (n1.nspname||'.'||p1.proname||'('||pg_get_function_identity_arguments(p1.oid)||')') = ANY (v_expected)
       AND NOT (
         d.classid = 'pg_proc'::regclass AND EXISTS (
           SELECT 1 FROM pg_proc p3 JOIN pg_namespace n3 ON n3.oid = p3.pronamespace
           WHERE p3.oid = d.objid AND n3.nspname = 'public'
             AND (n3.nspname||'.'||p3.proname||'('||pg_get_function_identity_arguments(p3.oid)||')') = ANY (v_expected)
         )
       )
       AND NOT (
         d.classid = 'pg_class'::regclass AND c2.relname IS NOT NULL AND nc.nspname = 'public' AND EXISTS (
           SELECT 1 FROM unnest(ARRAY[
             'accounts','commission_dues','customers','employee_movements','employees',
             'expenses','invoice_counters','invoice_items','invoices','journal_entries',
             'journal_entry_lines','payments','processed_requests','products','reminder_log',
             'salaries','stock_moves','suppliers','tenant_settings','tenants',
             'user_tenants','users'
           ]) AS t(name) WHERE t.name = c2.relname
         )
       )
   ) dep
   WHERE COALESCE(dep.nspname, '') <> '';
'''
open(p,'w',encoding='utf-8').write(s[:start]+new_block+s[end2:])
print('done')
