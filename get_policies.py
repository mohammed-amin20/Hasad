with open(r'local_audit\DEV_INVENTORY_20261021_192155.txt', encoding='utf-8', errors='ignore') as f:
    lines = f.readlines()

# Look for policies section
# Based on what I saw around line 1400+, policies start after "policies" count appears
pol = []
for i,l in enumerate(lines):
    if 'policies' in l.lower() and '53' in l:
        # start collecting from next lines
        for j in range(i+1, min(i+500, len(lines))):
            lj = lines[j]
            if '|' in lj and lj.strip().startswith('public'):
                if 'trigger' in lj.lower() and 'trg_' in lj:
                    break
                parts = [p.strip() for p in lj.split('|')]
                if len(parts) >= 3:
                    schema, table, polname = parts[0], parts[1], parts[2]
                    if schema == 'public' and table and polname and polname and not polname.startswith('-'):
                        if polname not in ['schemaname', 'relname', 'tablename', 'policyname', 'cmd', 'permissive', 'qual', 'with_check']:
                            if not any(p[1]==table and p[2]==polname for p in pol):
                                pol.append((schema, table, polname))
            elif 'trigger' in lj.lower() and 'trg_' in lj:
                break
        break

for p in pol:
    print(f'{p[0]}|{p[1]}|{p[2]}')
print(f'---COUNT:{len(pol)}---')
