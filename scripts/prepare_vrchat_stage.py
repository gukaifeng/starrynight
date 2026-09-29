#!/usr/bin/env python3
"""Prepare an isolated data-only Unity stage and run the trusted Inspector.

Accepts an audited extraction report and explicit prefab/FBX specs. Production
Assets, original archives, downloaded C#/DLL/shaders are never modified/copied.
"""
import argparse,json,shutil,subprocess
from pathlib import Path
from vrchat_source_paths import resolve_source_path
ROOT=Path(__file__).resolve().parents[1]
ALLOWED={'.fbx','.prefab','.mat','.png','.jpg','.jpeg','.tga','.anim','.controller','.overridecontroller','.asset'}
DEFAULT=[dict(role='kipfel',fbx='Assets/MOCHIYAMA/Kipfel/FBX/Kipfel.fbx',prefab='Assets/MOCHIYAMA/Kipfel/Prefab/Kipfel.prefab'),dict(role='mamehinata',fbx='Assets/MOCHIYAMA/Mamehinata/FBX/Mamehinata.fbx',prefab='Assets/MOCHIYAMA/Mamehinata/Mamehinata_PC.prefab')]

def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--audit',type=Path,default=ROOT/'docs/verification/vrchat-import/source-audit.json');p.add_argument('--stage',type=Path,default=ROOT/'.local/vrchat-stage');p.add_argument('--specs',type=Path,help='JSON object with specs array (role,fbx,prefab). Default is the two audited Mochiyama avatars.');p.add_argument('--prepare-only',action='store_true');a=p.parse_args()
 stage=a.stage.resolve()
 if stage==ROOT or not stage.is_relative_to(ROOT/'.local'):raise ValueError('Stage must be beneath this project .local directory')
 assets=stage/'Assets';assets.mkdir(parents=True,exist_ok=True)
 # Fail closed if reusing a stage that contains downloaded executable code.
 for path in assets.rglob('*'):
  if path.suffix.lower() in {'.cs','.dll','.shader','.compute','.bundle','.dylib'} and path not in {assets/'Editor/VrcSourceInspector.cs',assets/'Editor/VrcPerformanceSampler.cs'}:raise ValueError('Unreviewed executable in stage: '+str(path))
 data=json.loads(a.audit.read_text());seen={};count=0
 for archive in data['archives']:
  for package in archive['unityPackages']:
   for item in package['assets']:
    if item['folder'] or item['extension'].lower() not in ALLOWED:continue
    relative=Path(item['path'])
    if relative.is_absolute() or '..' in relative.parts or relative.parts[0]!='Assets':raise ValueError('Unsafe Unity pathname')
    target=stage/relative;source=resolve_source_path(item['extractedPath'],extraction_root=archive['extractionRoot'])
    import hashlib
    digest=hashlib.sha256(source.read_bytes()).hexdigest()
    if digest!=item['sha256']:raise ValueError('Audited asset changed: '+str(source))
    if str(relative) in seen and seen[str(relative)]!=digest:raise ValueError('Colliding package asset: '+str(relative))
    seen[str(relative)]=digest;target.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(source,target)
    meta=resolve_source_path(item['metaPath'],extraction_root=archive['extractionRoot']) if item.get('metaPath') else None
    if meta and meta.exists():shutil.copyfile(meta,str(target)+'.meta')
    count+=1
 (assets/'Editor').mkdir(exist_ok=True);shutil.copyfile(ROOT/'scripts/vrchat/VrcSourceInspector.cs',assets/'Editor/VrcSourceInspector.cs')
 shutil.copyfile(ROOT/'scripts/vrchat/VrcPerformanceSampler.cs',assets/'Editor/VrcPerformanceSampler.cs')
 (stage/'Packages').mkdir(exist_ok=True);(stage/'Packages/manifest.json').write_text(json.dumps(dict(dependencies={f'com.unity.modules.{m}':'1.0.0' for m in ['animation','imageconversion','jsonserialize']}),indent=2)+'\n')
 (stage/'ProjectSettings').mkdir(exist_ok=True);(stage/'ProjectSettings/ProjectVersion.txt').write_text('m_EditorVersion: 6000.3.25f1\n')
 specs=json.loads(a.specs.read_text()) if a.specs else dict(specs=DEFAULT)
 (stage/'InspectionConfig.json').write_text(json.dumps(specs,indent=2)+'\n')
 print(f'Staged {count} audited data assets; source scripts/shaders/SDK excluded')
 if not a.prepare_only:
  logs=ROOT/'.local/logs';logs.mkdir(exist_ok=True)
  subprocess.run(['unity','run',str(stage),'--timeout','300','--','-nographics','-executeMethod','VrcSourceInspector.Export','-logFile',str(logs/'vrchat-stage-inspect.log')],check=True)
if __name__=='__main__':main()
