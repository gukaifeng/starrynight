#!/usr/bin/env python3
"""Bailian authoring, never a launch-time generation job. Private, resumable outputs.

Run with .local/character-ai-venv/bin/python. Default is a no-cost plan; --generate
explicitly enables calls. A completed fingerprint is reused; failed/ambiguous jobs
require --retry-failed, so an interrupted run never silently charges twice.
"""
import argparse
import base64
import hashlib
import json
import mimetypes
from pathlib import Path
import sys
import time
from urllib.parse import urlparse
import httpx

ROOT = Path(__file__).resolve().parents[1]
SERVER_ROOT=ROOT.parent/'starrynight-server'
if not (SERVER_ROOT/'services/character_ai/profiles.py').is_file():
    raise SystemExit('Character media authoring requires the separate ../starrynight-server checkout')
sys.path.insert(0, str(SERVER_ROOT))
from services.character_ai.config import Settings
from services.character_ai.profiles import PROFILES

OUTPUT = ROOT / '.local/character-media'
SIZES = {'cover': '1536*2048', 'avatar': '1024*1024', 'background': '2048*2048'}

def digest(data): return hashlib.sha256(data).hexdigest()
def save(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + '.tmp')
    temporary.write_bytes(data)
    temporary.replace(path)

def reference(role):
    folder = ROOT / 'ios/StarryNight/Assets.xcassets' / ('Cover_' + role.replace('-', '_') + '.imageset')
    files = sorted(folder.glob('source.*'))
    if not files:
        plan=json.loads((ROOT/'.local/vrchat-batch/plan.json').read_text())
        row=next((r for r in plan['models'] if r['id']==role),None)
        if row and row.get('cover'):
            source=Path(plan['sourceRoot'])/row['sourceFolder']/row['cover']
            if source.is_file():return source
    if len(files) != 1: raise ValueError('Missing unique author reference: ' + role)
    return files[0]

def prompt(recipe, kind):
    profile = PROFILES[recipe['id']]
    persona = json.dumps({k:v for k,v in profile.items() if k in ('name','personality','background','interests','occupation')}, ensure_ascii=False)
    # Structured biographies make image models render a character-sheet table.
    # Translate only useful visual context into prose; keep the full biography
    # for dialogue/music. Names and profile field labels must not become text.
    traits = profile.get('personality', {}).get('traits', [])
    visual_mood = '、'.join(traits) if isinstance(traits,list) else str(traits)
    identity = '绘制纯插画，画面中不出现任何文字、字母、说明栏、表格、标题或人物设定卡。参考图只用于角色身份、造型和配色，不复制参考图的文字或排版。重新创作一张独立的精致二次元插画，细腻的3D立绘质感，柔软但清晰的发丝、布料、眼睛高光，可信柔光和环境反射。保持角色年龄观感、原服饰及辨识度，亲切自然、适合全年龄。' + recipe['appearance'] + '。神态氛围：' + visual_mood
    if kind == 'cover':
        return identity + '。竖版沉浸式角色封面。上半身特写，头顶与耳朵完整，脸在画面水平中心、垂直约32%处，人物占画面70%，目光自然看向观者，轻微微笑，松弛而灵动。场景：' + recipe['setting'] + '。背景略虚化但保留丰富细节，用光突出脸部。无文字、无标志、无边框、无分栏。'
    if kind == 'avatar':
        return identity + '。正方形头像，单人头肩近景，脸部水平垂直居中，完整耳朵和发饰，圆形裁切时眼睛与面部完整。自然看向观者，温暖微笑，眼睛有精细反射，轮廓柔光。背景取自' + recipe['setting'] + '，深色柔和虚化，角色与背景色彩和谐但轮廓鲜明。无文字、无边框、无标志。'
    if kind == 'background':
        return '纯环境概念设计，空无一人的精致二次元游戏场景，2.5D电影级环境插画。只画建筑、植物、家具和空间，细腻材质、可信透视、柔和光照、多层纵深。场景：' + recipe['setting'] + '。主要色彩：' + ','.join(recipe['palette']) + '。构图中央40%是空旷地面与通透空间，重要家具在两侧，正中没有桌子、椅子等遮挡。柔光从左前上方照入，前景、主景、远景自然分层。正方形母版，中央竖向裁切与横向展示都成立。绝对无人、无动物、无人物肖像、无文字、无标志、无水印。'
    return '创作一段60秒纯音乐，用于和虚构二次元角色聊天时的背景，不需要人声。角色设定：' + persona + '。造型颜色：' + recipe['appearance'] + '。环境：' + recipe['setting'] + '。音乐方向：' + recipe['music'] + '。无人声、歌词、对白，不模仿现有歌曲，旋律适度稀疏，音量平稳，柔和首尾便于循环。'

def request_payload(recipe, kind, model, ref):
    text = prompt(recipe, kind)
    if kind == 'music': return {'model':model,'input':{'prompt':text,'is_instrumental':True,'format':'wav'}}
    content = [{'text':text}]
    # Reference editing tends to preserve the person, even with an explicit
    # exclusion. Environments use text-to-image with the authored palette and
    # setting instead. The live 3D character is composited over this empty scene.
    if kind != 'background':
        encoded = 'data:' + (mimetypes.guess_type(ref.name)[0] or 'image/png') + ';base64,' + base64.b64encode(ref.read_bytes()).decode()
        content.insert(0, {'image':encoded})
    parameters = {'size':SIZES[kind], 'n':1,'prompt_extend':False,'watermark':False}
    if kind == 'background': parameters['negative_prompt'] = '人物，人形，女孩，男孩，动物，脸，肖像，照片，雕像，文字，水印，标志'
    else: parameters['negative_prompt'] = '文字，英文，标题，水印，标志，表格，人物设定表，分栏，排版，信息卡'
    return {'model':model,'input':{'messages':[{'role':'user','content':content}]}, 'parameters':parameters}

def download(client, url):
    # Provider results may still use HTTP OSS links. Fetch over HTTPS only, and
    # don't follow arbitrary redirects or attach provider credentials to storage.
    parsed = urlparse(url)
    if parsed.scheme not in ('http','https') or not (parsed.hostname or '').endswith(('.aliyuncs.com','.alicdn.com')):
        raise ValueError('Unexpected output host')
    url = parsed._replace(scheme='https').geturl()
    content = bytearray()
    with client.stream('GET', url) as response:
        response.raise_for_status()
        for chunk in response.iter_bytes():
            content.extend(chunk)
            if len(content) > 120_000_000: raise ValueError('Generated asset exceeds size limit')
    return bytes(content)

def generate(recipe, kind, catalog, settings, client, retry=False):
    role = recipe['id']; ref = reference(role); model = catalog['musicModel' if kind == 'music' else 'imageModel']
    record = dict(schemaVersion=1,role=role,kind=kind,model=model,prompt=prompt(recipe,kind),referenceSHA256=digest(ref.read_bytes()),size=SIZES.get(kind))
    if kind == 'background': record['referenceUsed'] = False
    fingerprint = digest(json.dumps(record, sort_keys=True, ensure_ascii=False).encode())
    folder = OUTPUT / role; path = folder / (kind + ('.wav' if kind == 'music' else '.png')); receipt = folder / (kind + '.json')
    old = json.loads(receipt.read_text()) if receipt.exists() else {}
    if old.get('fingerprint') == fingerprint:
        if old.get('status') == 'complete' and path.exists() and digest(path.read_bytes()) == old.get('sha256'):
            print(role,kind,'cached',flush=True); return
        if not retry: raise RuntimeError(role+' '+kind+' is unresolved; inspect receipt before --retry-failed')
    elif path.exists() and old.get('status') == 'complete':
        # Retain previous successful outputs when the recipe changes.
        backup = folder / 'revisions' / (old['fingerprint'] + path.suffix)
        save(backup, path.read_bytes())
        save(backup.with_suffix('.json'), receipt.read_bytes())
    record.update(fingerprint=fingerprint,status='submitted',created=time.time())
    save(receipt, json.dumps(record,ensure_ascii=False,indent=2).encode())
    endpoint = '/api/v1/services/audio/music/generation' if kind == 'music' else '/api/v1/services/aigc/multimodal-generation/generation'
    started = time.monotonic()
    try:
        response = client.post(settings.host+endpoint,headers={'Authorization':'Bearer '+settings.api_key},json=request_payload(recipe,kind,model,ref))
        result = response.json()
        record.update(requestID=result.get('request_id'),httpStatus=response.status_code,usage=result.get('usage'))
        if response.status_code >= 400: raise RuntimeError(str(response.status_code)+':'+str(result.get('code','PROVIDER_ERROR')))
        if kind == 'music': url = result['output']['audio']['url']
        else: url = next(c['image'] for choice in result['output']['choices'] for c in choice['message']['content'] if c.get('image'))
        payload = download(client,url)
        if kind != 'music' and not payload.startswith(b'\x89PNG\r\n\x1a\n'): raise ValueError('Invalid PNG')
        if kind == 'music' and not payload.startswith(b'RIFF'): raise ValueError('Invalid WAVE')
        save(path, payload)
        record.update(status='complete',sha256=digest(payload),bytes=len(payload),seconds=round(time.monotonic()-started,2))
        print(role,kind,record['status'],record['seconds'],len(payload),flush=True)
    except Exception as error:
        record.update(status='failed',error=str(error)[:120])
        raise
    finally: save(receipt,json.dumps(record,ensure_ascii=False,indent=2).encode())

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--only',nargs='+');parser.add_argument('--kinds',nargs='+',choices=[*SIZES,'music'],default=list(SIZES))
    parser.add_argument('--generate',action='store_true');parser.add_argument('--retry-failed',action='store_true')
    args=parser.parse_args();catalog=json.loads((ROOT/'assets/characters/media-recipes.json').read_text())
    roster=json.loads((ROOT/'assets/characters/active-roster.json').read_text())['characters']
    recipes=[r for r in catalog['characters'] if r['id'] in (args.only or roster)]
    if args.only and set(args.only)-{r['id'] for r in recipes}: parser.error('Unknown character')
    settings=Settings.load()
    with httpx.Client(timeout=httpx.Timeout(240,connect=15),follow_redirects=False) as client:
        for recipe in recipes:
            for kind in args.kinds:
                if args.generate:
                    if not settings.paid_enabled or not settings.api_key: raise RuntimeError('Paid provider not configured')
                    generate(recipe,kind,catalog,settings,client,args.retry_failed)
                else: print(recipe['id'],kind,SIZES.get(kind,'instrumental'),prompt(recipe,kind))

if __name__ == '__main__': main()
