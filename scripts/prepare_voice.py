#!/usr/bin/env python3
"""Fetch pinned upstream ONNX weights. Cache is private to this workspace."""
import concurrent.futures, hashlib, json, pathlib, urllib.request, urllib.parse, shutil, time
ROOT = pathlib.Path(__file__).resolve().parents[1]
OUT = ROOT / '.local/voice-models'
lockfile = ROOT / 'local-services/voice/models.lock.json'
prior = json.loads(lockfile.read_text())['files'] if lockfile.exists() else []
locked = {(item['model'],item['path'],item['revision']):item['sha256'] for item in prior}
MODELS = {
 'sensevoice': ('csukuangfj/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17','2365baeacb507f821a0c8120fcee3d484dba7a07',lambda p: p in ['model.int8.onnx','tokens.txt','LICENSE','README.md','test_wavs/zh.wav','test_wavs/en.wav']),
 'melo': ('csukuangfj/vits-melo-tts-zh_en','a0d5c6a264c0ef92d70d8661d8cc502d79627cd6',lambda p: p in ['model.onnx','tokens.txt','lexicon.txt','LICENSE','README.md','date.fst','number.fst','phone.fst'] or p.startswith('dict/')),
}
import sys
if '--with-kokoro-benchmark' in sys.argv:
 MODELS['kokoro'] = ('csukuangfj/kokoro-int8-multi-lang-v1_1','155831f1b4ba23b1f5c058be6a61df90cefb2a37',lambda p: not p.startswith('.') and not p.endswith('.py') and not p.startswith('dict/'))
def fetch(task):
 name,repo,revision,entry=task; rel=entry['rfilename']; target=OUT/name/rel
 target.parent.mkdir(parents=True,exist_ok=True)
 upstream=entry.get('lfs',{}).get('sha256')
 expected=upstream or locked.get((name,rel,revision))
 if not target.exists() or (expected and hashlib.sha256(target.read_bytes()).hexdigest()!=expected):
  url=f"https://huggingface.co/{repo}/resolve/{revision}/{urllib.parse.quote(rel,safe='/')}"
  tmp=target.with_suffix(target.suffix+'.partial')
  for attempt in range(4):
   try:
    with urllib.request.urlopen(url,timeout=180) as response,tmp.open('wb') as output: shutil.copyfileobj(response,output)
    break
   except (OSError,TimeoutError):
    if attempt==3: raise
    time.sleep(2**attempt)
  digest=hashlib.sha256(tmp.read_bytes()).hexdigest()
  if expected and digest!=expected: raise RuntimeError('Upstream hash mismatch: '+rel)
  tmp.replace(target)
 digest=hashlib.sha256(target.read_bytes()).hexdigest()
 print(f'{name}/{rel}: {target.stat().st_size} bytes',flush=True)
 return {'model':name,'path':rel,'sha256':digest,'upstreamLFSHash':upstream,'bytes':target.stat().st_size,'repo':repo,'revision':revision}
tasks=[]
for name,(repo,revision,include) in MODELS.items():
 with urllib.request.urlopen(f'https://huggingface.co/api/models/{repo}/revision/{revision}?blobs=true',timeout=60) as response: metadata=json.load(response)
 for item in metadata['siblings']:
  if include(item['rfilename']): tasks.append((name,repo,revision,item))
with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool: files=list(pool.map(fetch,tasks))
manifest={'files':sorted([f for f in files if f['model']!='kokoro'],key=lambda x:(x['model'],x['path']))}
optional=[f for f in files if f['model']=='kokoro']
if optional: (ROOT/'local-services/voice/kokoro-benchmark.lock.json').write_text(json.dumps({'files':optional},ensure_ascii=False,indent=2)+'\n')
(ROOT/'local-services/voice/models.lock.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
for name in MODELS:
 dst=ROOT/'local-services/voice/licenses'/name; dst.mkdir(parents=True,exist_ok=True)
 for file in ['LICENSE','README.md']: shutil.copyfile(OUT/name/file,dst/file)
