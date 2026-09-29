#!/usr/bin/env python3
"""Create a self-contained authoring kit without engine caches or restricted built-in assets."""
from pathlib import Path
import hashlib,json,zipfile
ROOT=Path(__file__).resolve().parents[1]
out=ROOT/'docs/character-standard/deliverables';out.mkdir(parents=True,exist_ok=True)
files=[]
for prefix in ['character-sdk','docs/character-standard']:
 for file in (ROOT/prefix).rglob('*'):
  if not file.is_file() or '__pycache__' in file.parts or 'deliverables' in file.parts:continue
  if file.suffix in ('.pyc','.DS_Store'):continue
  files.append(file)
files += [ROOT/'scripts/import_character.py',ROOT/'scripts/validate_characters.py',ROOT/'docs/verification/character-platform/README.md',ROOT/'docs/verification/character-platform/sdk-tests.txt']
files += [ROOT/'docs/verification/posture/README.md',ROOT/'docs/verification/posture/sdk-tests.txt',ROOT/'docs/verification/posture/engine-review.json',ROOT/'docs/verification/posture/transition-contact-audit.json']
path=out/'StarryNight-Character-SDK-1.1.zip'
with zipfile.ZipFile(path,'w',zipfile.ZIP_DEFLATED) as archive:
 for file in sorted(files):archive.write(file,str(file.relative_to(ROOT)))
checks=dict(file=path.name,bytes=path.stat().st_size,sha256=hashlib.sha256(path.read_bytes()).hexdigest(),files=len(files))
(out/'sdk-integrity.json').write_text(json.dumps(checks,indent=2)+'\n')
print(json.dumps(checks,indent=2))
