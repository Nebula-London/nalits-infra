#!/usr/bin/env python3
import argparse,yaml
p=argparse.ArgumentParser(); p.add_argument('--registry',required=True); p.add_argument('--out',required=True); a=p.parse_args()
r=yaml.safe_load(open(a.registry)); out={}
for name,t in r['tenancies'].items():
    out[name]={}
    for vm in t.get('vms',[]): out[name][vm['name']]={'role':vm['role'],'environment':t['environment'],'capabilities':t['capabilities'],'network':t['network']['cidr']}
with open(a.out,'w') as f: yaml.safe_dump(out,f,sort_keys=False)
