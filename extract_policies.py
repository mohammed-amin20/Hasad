import re

with open('local_audit/DEV_INVENTORY_20261021_192155.txt', encoding='utf-8', errors='ignore') as f:
    content = f.read()

policies = re.findall(r'policy ([^\s|]+).*?on table ([^\s|]+)', content)
unique = sorted(set((p[1], p[0]) for p in policies))
print(f'Found {len(unique)} unique policies')
for t,p in unique:
    print(f'{t}|{p}')
