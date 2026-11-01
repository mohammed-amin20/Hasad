with open(r'local_audit\DEV_INVENTORY_20261021_192155.txt') as f:
    for i,l in enumerate(f):
        if 'policy' in l.lower():
            print(i+1, repr(l))
            if i > 200:
                break
