with open('local_audit/DEV_INVENTORY_20261021_192155.txt', encoding='utf-8', errors='ignore') as f:
    s = f.read()
import re
matches = re.findall(r'^public\s*\|[^\n]+', s, re.M)
pol = []
allowlist = {'accounts','commission_dues','customers','employee_movements','employees','expenses','invoice_counters','invoice_items','invoices','journal_entries','journal_entry_lines','payments','processed_requests','products','reminder_log','salaries','stock_moves','suppliers','tenant_settings','tenants','user_tenants','users'}
for m in matches:
    parts = [p.strip() for p in m.split('|')]
    if len(parts) < 3: continue
    schema, table, polname = parts[0], parts[1], parts[2]
    if schema != 'public': continue
    if not table or not polname: continue
    if table not in allowlist: continue
    if any(x in polname.lower() for x in ['policy_cmd_is', 'create_policy', 'pg_policies']): continue
    if polname in ['schemaname','relname','tablename','policyname','cmd','permissive','qual','with_check','name','definition','policy_name']: continue
    if 'trg_' in m or 'EXECUTE FUNCTION' in m: continue
    pol.append((schema,table,polname))
seen=set(); res=[]
for p in pol:
    k=(p[1],p[2])
    if k not in seen:
        seen.add(k); res.append(p)
for r in res:
    print(r[0]+'|'+r[1]+'|'+r[2])
print('---COUNT:'+str(len(res))+'---')
