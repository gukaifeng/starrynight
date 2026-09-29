#!/usr/bin/env python3
from pathlib import Path
import sys,json
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'environment-sdk/tools'))
from environment_tool import validate
ids=set();thumbnails=set();results=[]
for category in ('builtins','imported'):
 for source in sorted((ROOT/'environment-packages'/category).glob('*')):
  if not source.is_dir():continue
  m,w=validate(source,category=='builtins')
  if m['id'] in ids or m['display']['thumbnail'] in thumbnails:raise ValueError('Duplicate scene ID / thumbnail')
  ids.add(m['id']);thumbnails.add(m['display']['thumbnail']);results.append(dict(id=m['id'],status='PASS',warnings=w))
print(json.dumps(results,ensure_ascii=False,indent=2))
