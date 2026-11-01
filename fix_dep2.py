p=r'scripts/cleanup/04_drop_functions.sql'
s=open(p,encoding='utf-8').read()
old=\"    LEFT JOIN pg_namespace n2 ON n2.oid = COALESCE(c2.relnamespace, CASE WHEN d.classid = 'pg_proc'::regclass THEN (SELECT nspname FROM pg_namespace WHERE oid = (SELECT pronamespace FROM pg_proc WHERE oid = d.objid)) END)\n    LEFT JOIN pg_proc p2 ON p2.oid = d.objid AND d.classid = 'pg_proc'::regclass\"
new=\"    LEFT JOIN pg_namespace nc ON nc.oid = c2.relnamespace\n    LEFT JOIN pg_proc p2 ON p2.oid = d.objid AND d.classid = 'pg_proc'::regclass\n    LEFT JOIN pg_namespace np ON np.oid = p2.pronamespace\"
if old not in s:
    print('not found')
else:
    open(p,'w',encoding='utf-8').write(s.replace(old,new))
    print('replaced')
