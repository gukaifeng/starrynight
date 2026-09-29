#!/usr/bin/env python3
"""Validate, seal, pack and compare XEP 1.0 static environments."""
import argparse,hashlib,json,sys,zipfile
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[2]/'character-sdk/tools'))
from character_tool import read_json,safe_path,glb_document,unpack as unpack_archive,FORBIDDEN,MAX_BYTES
def unpack(archive,destination): return unpack_archive(Path(archive).resolve(),Path(destination).resolve())
CAPS={'environment.geometry@1','environment.lighting@1','environment.palette@1','environment.decor@1'}
def seal(folder):
 root=Path(folder).resolve();m=read_json(root/'environment.json');files=[]
 for p in sorted(root.rglob('*')):
  if p.is_file() and p!=root/'environment.json':
   safe_path(root,p.relative_to(root).as_posix());files.append(dict(path=p.relative_to(root).as_posix(),bytes=p.stat().st_size,sha256=hashlib.sha256(p.read_bytes()).hexdigest()))
 m['files']=files;(root/'environment.json').write_text(json.dumps(m,ensure_ascii=False,indent=2)+'\n')
def validate(folder,builtin=False):
 from jsonschema import Draft202012Validator
 root=Path(folder).resolve();m=read_json(root/'environment.json')
 Draft202012Validator(read_json(Path(__file__).resolve().parents[1]/'schemas/environment.schema.json')).validate(m)
 unknown=set(m['compatibility']['required'])-CAPS
 if unknown:raise ValueError('Unsupported required capabilities: '+str(sorted(unknown)))
 warnings=['Ignored optional capability: '+x for x in set(m['compatibility']['optional'])-CAPS]
 paths=set();total=0
 for f in m['files']:
  if f['path'] in paths or f['path']=='environment.json':raise ValueError('Duplicate/reserved resource path')
  paths.add(f['path']);p=safe_path(root,f['path'])
  if p.suffix.lower() in FORBIDDEN or p.suffix.lower() not in {'.glb','.png','.jpg','.jpeg','.webp','.txt','.md','.json','.csv'}:raise ValueError('Executable or unsupported resource content forbidden')
  if not p.is_file() or p.stat().st_size!=f['bytes'] or hashlib.sha256(p.read_bytes()).hexdigest()!=f['sha256']:raise ValueError('Resource integrity mismatch: '+f['path'])
  total+=f['bytes']
 actual={p.relative_to(root).as_posix() for p in root.rglob('*') if p.is_file() and p!=root/'environment.json'}
 for p in root.rglob('*'):
  if p.is_symlink():raise ValueError('Symlinks forbidden')
 if paths!=actual or total>MAX_BYTES or len(paths)>512:raise ValueError('File list or size budget invalid')
 if m['license']['file'] not in paths:raise ValueError('License file missing')
 if len({p['id'] for p in m['palettes']})!=len(m['palettes']):raise ValueError('Duplicate palette ID')
 for group in m['bindings'].values():
  if len(group)!=len(set(group)):raise ValueError('Duplicate binding')
  for path in group:
   if not path or any(x in ('','.','..') for x in path.split('/')) or '\\' in path:raise ValueError('Invalid node path')
 if m['source']['kind']=='builtin':
  if not builtin:raise ValueError('External environments must use GLB')
 else:
  if m['source']['model'] not in paths:raise ValueError('Model missing')
  doc=glb_document(safe_path(root,m['source']['model']))
  if doc.get('skins') or doc.get('animations') or any('targets' in p for mesh in doc.get('meshes',[]) for p in mesh.get('primitives',[])):raise ValueError('XEP 1.0 is static geometry; animation/skins/morphs need a future capability')
  primitives=[p for mesh in doc.get('meshes',[]) for p in mesh.get('primitives',[])]
  vertices=sum(doc['accessors'][p['attributes']['POSITION']]['count'] for p in primitives)
  if vertices>250000 or len(primitives)>48:raise ValueError('Environment geometry budget exceeded')
  if len(doc.get('nodes',[]))>512:raise ValueError('Too many nodes')
  warnings.append(f'Geometry: {vertices} vertices, {len(primitives)} primitives; final Unity bindings and stage clearance require engine validation')
 return m,warnings

def compare(old,new):
 errors=[]
 for k in ('id','packageId','schemaVersion'):
  if old[k]!=new[k]:errors.append(k+' changed')
 if set(new['compatibility']['required'])-set(old['compatibility']['required']):errors.append('Added required capability')
 old_ids={p['id'] for p in old['palettes']};new_ids={p['id'] for p in new['palettes']}
 if not old_ids.issubset(new_ids):errors.append('Removed saved palette ID')
 if old['stage']!=new['stage']:errors.append('Stage units/clearance changed')
 version=lambda s:tuple(map(int,s.split('.')))
 if version(new['packageVersion'])<version(old['packageVersion']):errors.append('Version downgrade')
 if old!=new and new['packageVersion']==old['packageVersion']:errors.append('Content changed without a version increment')
 if errors:raise ValueError('; '.join(errors))

def main():
 parser=argparse.ArgumentParser(description=__doc__);sub=parser.add_subparsers(dest='command',required=True)
 for name in ('seal','validate','pack'):
  p=sub.add_parser(name);p.add_argument('folder',type=Path);p.add_argument('--builtin',action='store_true')
  if name=='pack':p.add_argument('output',type=Path)
 p=sub.add_parser('compare');p.add_argument('old',type=Path);p.add_argument('new',type=Path)
 args=parser.parse_args()
 if args.command=='compare':compare(read_json(args.old),read_json(args.new));print('Compatible upgrade');return
 if args.command=='seal':seal(args.folder)
 m,warnings=validate(args.folder,args.builtin)
 if args.command=='pack':
  if args.output.resolve().is_relative_to(args.folder.resolve()):raise ValueError('Output must be outside source folder')
  args.output.parent.mkdir(parents=True,exist_ok=True)
  with zipfile.ZipFile(args.output,'w',zipfile.ZIP_DEFLATED) as z:
   for p in sorted(args.folder.rglob('*')):
    if p.is_file():z.write(p,p.relative_to(args.folder))
 print(json.dumps(dict(status='PASS',id=m['id'],warnings=warnings),ensure_ascii=False,indent=2))
if __name__=='__main__':main()
