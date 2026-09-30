#!/usr/bin/env python3
"""Prepare an isolated official MA/NDMF bake, never the production project.

The source stage contains only audited data. Official dependency versions and
digests are pinned here; source-package scripts are still never loaded. Generated
SDK references must pass the normal portable dependency check before activation.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import urllib.request
import zipfile

ROOT=Path(__file__).resolve().parents[1]
PACKAGES=[
    ('nadena.dev.modular-avatar','1.18.7','a627cb84ac6012ecff719566e7f57cdda6452d74193922dffd01d19e7bf31ed9',
     'https://packages.vpm.nadena.dev/repositories/nadena.dev/packages/nadena.dev.modular-avatar/1.18.7/a627cb84ac6012ecff719566e7f57cdda6452d74193922dffd01d19e7bf31ed9.zip'),
    ('nadena.dev.ndmf','1.14.8','e1103ea150b9f1d49d415d632ed4da4e46cd8121a1f1f7ea917b155193a1ab83',
     'https://packages.vpm.nadena.dev/repositories/nadena.dev/packages/nadena.dev.ndmf/1.14.8/e1103ea150b9f1d49d415d632ed4da4e46cd8121a1f1f7ea917b155193a1ab83.zip'),
    ('com.vrchat.base','3.10.5','fbfb3e7a38778dcb55d7a860286819e6f0726d10d5039f61474bd1b9c629029e',
     'https://github.com/vrchat/packages/releases/download/3.10.5/com.vrchat.base-3.10.5.zip'),
    ('com.vrchat.avatars','3.10.5','03bdea0c24257070f0e7a73c9033742a1ce0f67463b12a6c2ad29608b1f33a77',
     'https://github.com/vrchat/packages/releases/download/3.10.5/com.vrchat.avatars-3.10.5.zip'),
]


def index_bake(stage,role):
    """Index the generated data graph without laundering SDK dependencies.

    Raw source provenance remains in the original stage and in the merged audit.
    In particular, SDK proxy clips are not added to this author-asset index.
    """
    from audit_vrchat_archives import enrich_package
    receipt=json.loads((stage/'Inspection/Baked'/(role+'.json')).read_text())
    if (receipt.get('status')!='requires-portable-inspection' or receipt.get('buildErrors')
        or receipt.get('invalidMeshes') or receipt.get('missingComponents')):
        raise ValueError('Baked output did not pass its source validation')
    source=ROOT/'.local/vrchat-batch/stages'/role
    audit=json.loads((source/'source-audit.json').read_text())
    rows=[]
    allowed={'.prefab','.asset','.controller','.anim','.mat','.mask'}
    for relative in receipt['dependencies']:
        if not relative.startswith(('Assets/ZZZ_GeneratedAssets/','Assets/StarryNightBaked/')):continue
        path=stage/relative;meta=Path(str(path)+'.meta')
        if not path.resolve().is_relative_to(stage.resolve()) or path.suffix.lower() not in allowed:
            raise ValueError('Unexpected generated dependency: '+relative)
        if not path.is_file() or not meta.is_file():raise ValueError('Missing generated data: '+relative)
        match=re.search(r'^guid: ([0-9a-f]{32})$',meta.read_text(),re.M)
        if not match:raise ValueError('Generated dependency lacks identity: '+relative)
        if not path.read_bytes().startswith(b'%YAML') and path.suffix.lower()!='.asset':
            raise ValueError('Unexpected non-text generated data: '+relative)
        rows.append(dict(guid=match[1],path=relative,extractedPath=str(path.resolve()),metaPath=str(meta.resolve()),
            extension=path.suffix.lower(),folder=False,bytes=path.stat().st_size,
            sha256=hashlib.sha256(path.read_bytes()).hexdigest(),provenance='official-modular-bake'))
    if not any(r['path']==receipt['bakedPrefab'] for r in rows):raise ValueError('Missing baked root')
    package=dict(kind='generated-data',assets=rows)
    enrich_package(package)
    audit['archives'].append(dict(kind='official-modular-bake',unityPackages=[package]))
    audit['bake']=dict(role=role,sourcePrefab=receipt['sourcePrefab'],bakedPrefab=receipt['bakedPrefab'],
        untouchedDefaultCalibrationLayers=receipt.get('untouchedDefaultCalibrationLayers',[]),
        receiptSHA256=hashlib.sha256((stage/'Inspection/Baked'/(role+'.json')).read_bytes()).hexdigest(),
        scope='Local conversion candidate; platform motions and all runtime capabilities still require review')
    from vrchat_binary_data import verify_native_references
    from vrchat_controls import documents
    evidence=json.loads((stage/'Inspection/Baked'/(role+'-references.json')).read_text())
    index={a['guid']:a for ar in audit['archives'] for p in ar['unityPackages'] for a in p['assets']}
    result=verify_native_references(evidence,index,documents)
    (stage/'Inspection/Baked/reference-validation.json').write_text(json.dumps(result,indent=2)+'\n')
    (stage/'source-audit.json').write_text(json.dumps(audit,ensure_ascii=False,indent=2)+'\n')
    return audit


def prepare(role,editor):
    if not role.isascii() or not role.replace('-','').isalnum():raise ValueError('Invalid role')
    source=ROOT/'.local/vrchat-batch/stages'/role
    if not (source/'source-audit.json').exists():raise ValueError('Audit and inspect the source stage first')
    if not re.fullmatch(r'\d+\.\d+\.\d+[fabp]\d+',editor):raise ValueError('Invalid pinned Editor version')
    stage=ROOT/'.local/vrchat-batch/bakes'/(role+'-'+editor)
    stage.mkdir(parents=True,exist_ok=True)
    source_digest=hashlib.sha256((source/'source-audit.json').read_bytes()).hexdigest()
    previous=stage/'bake-dependencies.json'
    if (stage/'Assets').exists() and (not previous.exists() or
        json.loads(previous.read_text()).get('sourceReceiptSHA256')!=source_digest):
        raise ValueError('Bake source changed; preserve this stage and create a separately reviewed stage')
    # A second project leaves the data-only inspection and original archives intact.
    if not (stage/'Assets').exists():
        shutil.copytree(source/'Assets',stage/'Assets')
    trusted={'VrcSourceInspector.cs','VrcPerformanceSampler.cs','VrcPortableGeometry.cs','VrcModularBake.cs'}
    for path in (stage/'Assets').rglob('*'):
        if path.suffix.lower() in {'.cs','.dll','.shader','.compute','.dylib'} and path.relative_to(stage/'Assets').as_posix() not in {'Editor/'+name for name in trusted}:
            raise ValueError('Unexpected executable in source data: '+str(path))
    for name in trusted:
        origin=ROOT/'scripts/vrchat'/name
        if origin.exists():shutil.copyfile(origin,stage/'Assets/Editor'/name)
    for name in ('InspectionConfig.json','source-audit.json'):
        shutil.copyfile(source/name,stage/name)
    (stage/'ProjectSettings').mkdir(exist_ok=True)
    (stage/'ProjectSettings/ProjectVersion.txt').write_text('m_EditorVersion: '+editor+'\n')
    (stage/'Packages').mkdir(exist_ok=True)
    dependencies={}
    for name,version,digest,url in PACKAGES:
        stem=('vrc-'+name.rsplit('.',1)[-1] if name.startswith('com.vrchat.') else name)+'-'+version
        archive=ROOT/'.local/dependencies'/(stem+'.zip')
        if not archive.exists():
            with urllib.request.urlopen(url,timeout=120) as response:archive.write_bytes(response.read())
        if hashlib.sha256(archive.read_bytes()).hexdigest()!=digest:raise ValueError('Package archive hash mismatch: '+name)
        target=ROOT/'.local/dependencies'/(stem+'-bake-verified')
        with zipfile.ZipFile(archive) as bundle:
            for item in bundle.infolist():
                path=target/item.filename
                if not path.resolve().is_relative_to(target.resolve()) or (item.external_attr>>16)&0o170000==0o120000:
                    raise ValueError('Unsafe official package member')
            bundle.extractall(target)
        dependencies[name]='file:'+str(target)
    # MA mesh processing must see the author's shader properties. Reuse the
    # reviewed renderer's exact upstream archive, never source-package code.
    from prepare_liltoon import VERSION as LIL_VERSION,SHA256 as LIL_SHA256
    archive=ROOT/'.local/dependencies'/('liltoon-'+LIL_VERSION+'-source.zip')
    if not archive.exists() or hashlib.sha256(archive.read_bytes()).hexdigest()!=LIL_SHA256:
        raise ValueError('Prepare the pinned lilToon archive before baking')
    target=ROOT/'.local/dependencies'/('liltoon-'+LIL_VERSION+'-bake-verified')
    with zipfile.ZipFile(archive) as bundle:
        prefix='lilToon-'+LIL_VERSION+'/Assets/lilToon/'
        for item in bundle.infolist():
            if not item.filename.startswith(prefix) or item.is_dir():continue
            path=target/item.filename[len(prefix):]
            if not path.resolve().is_relative_to(target.resolve()):raise ValueError('Unsafe renderer package path')
            path.parent.mkdir(parents=True,exist_ok=True);path.write_bytes(bundle.read(item))
    dependencies['jp.lilxyzw.liltoon']='file:'+str(target)
    dependencies.update({'com.unity.modules.'+name:'1.0.0' for name in (
        'animation','imageconversion','jsonserialize','audio','particlesystem','physics','physics2d','ui','uielements',
        'unitywebrequest','unitywebrequestassetbundle','unitywebrequestaudio','unitywebrequesttexture','unitywebrequestwww',
        'assetbundle','imgui','video','vr','xr','cloth','terrain','terrainphysics','androidjni')})
    # Unity 6 compatible UGUI; VRChat's 2022-era package declares 1.x.
    dependencies['com.unity.ugui']='2.0.0' if int(editor.split('.')[0])>=6000 else '1.0.0'
    (stage/'Packages/manifest.json').write_text(json.dumps(dict(dependencies=dependencies),indent=2)+'\n')
    (stage/'bake-dependencies.json').write_text(json.dumps(dict(schemaVersion=1,
        sourceReceiptSHA256=source_digest,editor=editor,
        renderer=dict(name='jp.lilxyzw.liltoon',version=LIL_VERSION,sha256=LIL_SHA256),
        packages=[dict(name=n,version=v,sha256=h,url=u) for n,v,h,u in PACKAGES]),indent=2)+'\n')
    return stage


def main():
    parser=argparse.ArgumentParser();parser.add_argument('--role',required=True);parser.add_argument('--prepare-only',action='store_true')
    parser.add_argument('--editor',default='2022.3.22f1',help='Pinned official source bake Editor; app production remains Unity 6')
    args=parser.parse_args();stage=prepare(args.role,args.editor)
    print('OFFICIAL_MODULAR_BAKE_PREPARED',stage,flush=True)
    if not args.prepare_only:
        subprocess.run(['unity','run',str(stage),'--timeout','900','--','-nographics','-executeMethod','VrcModularBake.Run',
            '-logFile',str(ROOT/'.local/logs'/('vrchat-modular-bake-'+args.role+'-'+args.editor+'.log'))],check=True)
        index_bake(stage,args.role)
        print('OFFICIAL_MODULAR_BAKE_INDEXED; portable capability review is still required',flush=True)


if __name__=='__main__':main()
