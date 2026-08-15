#!/usr/bin/env python3
import argparse, ipaddress, sys, yaml

def main():
    p=argparse.ArgumentParser(); sub=p.add_subparsers(dest='cmd',required=True)
    v=sub.add_parser('validate'); v.add_argument('--file',required=True); v.add_argument('--platform',required=True)
    c=sub.add_parser('cidr'); c.add_argument('--file',required=True); c.add_argument('--tenancy',required=True)
    a=p.parse_args(); reg=yaml.safe_load(open(a.file)); plat=yaml.safe_load(open(a.platform))
    if a.cmd=='cidr': print(reg['tenancies'][a.tenancy]['network']['cidr']); return
    pool=ipaddress.ip_network(plat['network']['pool']); seen=[]; errors=[]
    names=list(reg.get('tenancies',{}))
    if not names: errors.append('registry contains no tenancies')
    for name,t in reg['tenancies'].items():
        for key in ('tenancy_id','profile','environment','region','capabilities','network'): 
            if key not in t: errors.append(f'{name}: missing {key}')
        try: n=ipaddress.ip_network(t['network']['cidr'])
        except ValueError: errors.append(f'{name}: invalid CIDR'); continue
        if not n.subnet_of(pool): errors.append(f'{name}: CIDR is outside pool {pool}')
        if n.prefixlen != plat['network']['tenancy_prefix']: errors.append(f'{name}: expected /{plat["network"]["tenancy_prefix"]}')
        for other,on in seen:
            if n.overlaps(on): errors.append(f'{name}: CIDR overlaps {other}')
        seen.append((name,n))
        if t.get('environment') in ('dev','prod','security') and t.get('public_access'): errors.append(f'{name}: protected environment cannot be public')
    if errors:
        print('\n'.join(errors),file=sys.stderr); sys.exit(1)
    print(f'valid: {len(names)} tenancies; no CIDR overlap; pool={pool}')
if __name__=='__main__': main()
