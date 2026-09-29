#!/usr/bin/env python3
"""Import a validated XEP source package and regenerate both catalogs via Unity."""
from pathlib import Path
import argparse,json,shutil,sys,tempfile
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'environment-sdk/tools'))
from environment_tool import validate,unpack,compare,read_json
from import_character import editor_build
p=argparse.ArgumentParser(description=__doc__);p.add_argument('source',type=Path);p.add_argument('--replace',action='store_true');p.add_argument('--source-only',action='store_true');a=p.parse_args()
with tempfile.TemporaryDirectory(prefix='xiaoban-environment-') as tmp:
 tmp=Path(tmp);source=a.source.resolve()
 if source.is_file():source=unpack(source,tmp/'unpacked')
 m,w=validate(source);destination=ROOT/'environment-packages/imported'/m['id']
 if (ROOT/'environment-packages/builtins'/m['id']).exists():raise ValueError('Built-in ID collision')
 if destination.exists():
  if not a.replace:raise ValueError('Environment exists; use --replace after compatibility review')
  compare(read_json(destination/'environment.json'),m);shutil.copytree(destination,tmp/'previous');shutil.rmtree(destination)
 try:
  shutil.copytree(source,destination)
  if not a.source_only:editor_build()
 except Exception:
  if destination.exists():shutil.rmtree(destination)
  if (tmp/'previous').exists():shutil.copytree(tmp/'previous',destination)
  raise
 print(json.dumps(dict(status='PASS',id=m['id'],warnings=w),ensure_ascii=False))
