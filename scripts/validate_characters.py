#!/usr/bin/env python3
import json,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT/'character-sdk/tools'))
from character_tool import validate
seen=set();display_ids=set();rows=[]
for kind in ['builtins','imported']:
 for folder in sorted((ROOT/'character-packages'/kind).iterdir()):
  if not folder.is_dir(): continue
  m,warnings=validate(folder,builtin=kind=='builtins')
  if m['id'] in seen: raise ValueError('Duplicate catalog ID: '+m['id'])
  seen.add(m['id'])
  for key in ['thumbnail','cardIdentifier','openIdentifier']:
   value=m['display'][key]
   if (key,value) in display_ids: raise ValueError('Duplicate display resource identity: '+value)
   display_ids.add((key,value))
  rows.append(dict(id=m['id'],status='PASS',warnings=warnings))
print(json.dumps(rows,ensure_ascii=False,indent=2))
