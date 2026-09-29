#!/usr/bin/env python3
from pathlib import Path
import zipfile,json,hashlib
ROOT=Path(__file__).resolve().parents[1];out=ROOT/'docs/environment-standard/deliverables';out.mkdir(exist_ok=True)
files=[]
for folder in ['environment-sdk','character-sdk','docs/environment-standard']:
 for p in (ROOT/folder).rglob('*'):
  if p.is_file() and '__pycache__' not in p.parts and 'deliverables' not in p.parts and p.name!='.DS_Store':files.append(p)
files += [ROOT/'scripts/import_environment.py',ROOT/'scripts/import_character.py',ROOT/'scripts/validate_environments.py']
path=out/'Xiaoban-Environment-SDK-1.0.1.zip'
with zipfile.ZipFile(path,'w',zipfile.ZIP_DEFLATED) as z:
 for p in sorted(files):z.write(p,p.relative_to(ROOT))
result=dict(file=path.name,bytes=path.stat().st_size,sha256=hashlib.sha256(path.read_bytes()).hexdigest(),files=len(files))
(out/'sdk-integrity.json').write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result))
