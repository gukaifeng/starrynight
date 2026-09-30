#!/usr/bin/env python3
"""Review fresh source graphs before expensive conversion; never activates avatars.

Detailed GUID/path evidence stays private. Missing source motion and unsupported
build-time assembly must not be confused with an author supplying zero features.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import zipfile
from vrchat_controls import build
from package_vrchat_library import control_dependencies,missing_motion_dependencies,NEUTRAL_HAND_PROXY,require_selected_inspection
from prepare_vrc_reference_data import SHA256 as SDK_SHA256
from vrchat_conversion_signature import digest

ROOT=Path(__file__).resolve().parents[1]


def official_reference_paths(archive,expected_hash=SDK_SHA256):
    """Classify SDK references without extracting or bundling platform motions."""
    if not archive.exists():return {}
    if digest(archive)!=expected_hash:raise ValueError('Official SDK reference archive hash mismatch')
    paths={}
    with zipfile.ZipFile(archive) as source:
        for name in source.namelist():
            if not name.endswith('.meta'):continue
            match=re.search(r'^guid: ([a-f0-9]{32})$',source.read(name).decode(errors='replace'),re.M)
            if match:paths[match[1]]=name[:-5]
    return paths


def main():
    parser=argparse.ArgumentParser();parser.add_argument('--only');args=parser.parse_args()
    folder=ROOT/'.local/vrchat-batch';plan=json.loads((folder/'plan.json').read_text())
    path=folder/'capability-preflight.json';prior=json.loads(path.read_text()).get('characters',[]) if path.exists() else []
    results={r['role']:r for r in prior}
    signature=hashlib.sha256((ROOT/'scripts/vrchat_controls.py').read_bytes()).hexdigest()
    sdk=official_reference_paths(ROOT/'.local/dependencies/vrc-avatars-3.10.5.zip')
    for row in plan['models']:
        role=row['role']
        if args.only and role not in args.only.split(','):continue
        result=dict(role=role,sourceSHA256=row['sourceSHA256'],readerSHA256=signature,selectedPrefab=row.get('prefab'))
        try:
            if row['status']!='source-selected':raise ValueError(row['status'])
            stage=folder/'stages'/role;snapshot=stage/'Inspection/Portable'/role
            inspection_error=None
            try:require_selected_inspection(row,snapshot)
            except ValueError as error:inspection_error=str(error)
            result['inspectionCurrent']=inspection_error is None
            if inspection_error:result['inspectionRefreshRequired']=inspection_error
            geometry=json.loads((snapshot/'geometry.json').read_text())
            if geometry.get('prefab')!=row['prefab']:raise ValueError('Source selection changed; inspect the new prefab before checking its sampled motions')
            controls,_=build(stage,geometry)
            result.update(controls=len(controls['controls']),externalBlends=sum(':' in b['id'] for g in controls['controllers'] for b in g['blends']),
                sourceRequirements=controls['limitations'])
            motions=json.loads((snapshot/'motions.json').read_text())
            missing=missing_motion_dependencies(controls,motions)-{NEUTRAL_HAND_PROXY}
            result['unavailableMotions']=dict(officialSDK=[dict(guid=g,path=sdk[g]) for g in sorted(missing) if g in sdk],
                unresolved=[g for g in sorted(missing) if g not in sdk],sdkIndexAvailable=bool(sdk))
            control_dependencies(controls,motions)
            unresolved=[v for v in controls['limitations'] if v['kind'].startswith(('missing-','unsupported-','unknown-'))]
            if unresolved:raise ValueError('Source requires adapter/dependency review: '+','.join(sorted({v['kind'] for v in unresolved})))
            if inspection_error:raise ValueError(inspection_error)
            material=folder/'converted'/role/'portable-conversion.json'
            if material.exists():
                previous=json.loads(material.read_text())
                result['priorMaterialIssues']=previous.get('materialLimitations',[])
                if result['priorMaterialIssues']:raise ValueError('Prior conversion has unresolved material references; inspect or reconvert before activation')
            result.update(status='graph-ready',note='Not a rendering, source completeness, package budget, AI, or device performance approval.')
        except Exception as error:result.update(status='deferred',reason=str(error))
        results[role]=result
        path.write_text(json.dumps(dict(schemaVersion=1,characters=list(results.values())),ensure_ascii=False,indent=2)+'\n')
        print(role,result['status'],result.get('reason','')[:110],flush=True)

if __name__=='__main__':main()
