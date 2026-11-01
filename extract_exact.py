with open('local_audit/DEV_INVENTORY_20261021_192155.txt', encoding='utf-8', errors='ignore') as f:
    content = f.read()

# Find the section with (53 rows)
idx = content.find('(53 rows)')
if idx == -1:
    print('NOT FOUND')
    exit()

# Go backwards to find start of this table
# Look for line starting with public that is a policy row
# Scan backwards
start = content.rfind('\n', 0, idx)
# Go back further to find beginning of policies section
# Look for "policies" header or just start collecting from known pattern
# From earlier view, policies start around accounts|tenant_isolation_insert
pol_start = content.find('public      | accounts            | tenant_isolation_insert')
if pol_start == -1:
    pol_start = content.rfind('public      |', 0, idx - 5000)
    
# Extract from pol_start to idx
section = content[pol_start:idx]
# Parse lines
pols = []
for line in section.splitlines():
    if '|' not in line:
        continue
    if line.strip().startswith('public'):
        if 'trg_' in line or 'trigger' in line.lower() and 'trg_' in line:
            break
        parts = [p.strip() for p in line.split('|')]
        if len(parts) >= 3:
            schema = parts[0]
            table = parts[1]
            polname = parts[2]
            if schema == 'public' and table and polname:
                if polname not in ['schemaname','relname','tablename','policyname']:
                    if not any(p[1]==table and p[2]==polname for p in pols):
                        pols.append((schema,table,polname))

for p in pols:
    print(f'{p[0]}|{p[1]}|{p[2]}')
print(f'---COUNT:{len(pols)}---')
