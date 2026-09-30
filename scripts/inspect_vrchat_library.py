#!/usr/bin/env python3
"""Resume isolated Unity inspection from an explicit reviewed batch plan."""
import argparse
import json
from pathlib import Path
import shutil
import subprocess
import sys
from vrchat_batch_stage import prepare, ROOT
from vrchat_batch_audit import dump, sha256
from vrchat_conversion_signature import inspection_signature


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--plan',type=Path,default=ROOT/'.local/vrchat-batch/plan.json')
    p.add_argument('--only',help='Comma-separated role IDs')
    p.add_argument('--reserve-gib',type=float,default=12)
    a=p.parse_args()
    plan=json.loads(a.plan.read_text())
    status=ROOT/'.local/vrchat-batch/inspection-status.json'
    previous=json.loads(status.read_text()).get('characters',[]) if status.exists() else []
    results={r['role']:r for r in previous};failed=False
    def record(result):
        results[result['role']]=result
        dump(status,dict(schemaVersion=1,characters=list(results.values())))
    tool_digest=inspection_signature()
    for row in plan['models']:
        if a.only and row['role'] not in a.only.split(','):continue
        if row['status']!='source-selected':continue
        stage=ROOT/'.local/vrchat-batch/stages'/row['role']
        output=stage/'Inspection/Portable'/row['role']
        stamp=output/'inspection-stamp.json'
        signature=dict(sourceSHA256=row['sourceSHA256'],toolSHA256=tool_digest,prefab=row['prefab'])
        if row.get('additionalPackages'):signature['additionalPackages']=row['additionalPackages']
        if row.get('dependencyAssets'):signature['dependencyAssets']=row['dependencyAssets']
        if stamp.exists() and json.loads(stamp.read_text())==signature:
            record(dict(role=row['role'],status='inspected',cached=True));continue
        free=shutil.disk_usage(ROOT).free/1024**3
        if free<a.reserve_gib:
            record(dict(role=row['role'],status='deferred',error='disk-reserve'));failed=True
            print('DISK_RESERVE_REACHED',round(free,1),flush=True);break
        print('INSPECT_BEGIN',row['role'],'freeGiB',round(free,1),flush=True)
        try:
            prepare(Path(row['sourceReport']),row['package'],stage,[{k:row[k] for k in ('role','fbx','prefab')}],row.get('additionalPackages',[]),row.get('dependencyAssets',[]))
            log=ROOT/'.local/logs'/('vrchat-portable-'+row['role']+'.log')
            subprocess.run(['unity','run',str(stage),'--timeout','900','--','-nographics','-executeMethod','VrcPortableGeometry.Export','-logFile',str(log)],check=True)
            if not all((output/name).is_file() for name in ('geometry.json','geometry.bin','motions.json')):
                raise ValueError('Unity exited without complete geometry/motion output')
            if 'VRC_PORTABLE_EXPORTED '+row['role'] not in log.read_text(errors='replace'):
                raise ValueError('Unity did not report completed export')
            dump(stamp,signature)
            record(dict(role=row['role'],status='inspected',cached=False))
            print('INSPECT_PASS',row['role'],flush=True)
        except Exception as e:
            record(dict(role=row['role'],status='failed',error=str(e)));failed=True
            print('INSPECT_FAILED',row['role'],str(e),flush=True)
    if failed:raise SystemExit(1)


if __name__=='__main__':main()
