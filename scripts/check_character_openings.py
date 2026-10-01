#!/usr/bin/env python3
"""Offline integrity check for bundled first-meeting scripts and speech.

Preview-only avatars intentionally have no AI opening or paid speech asset.
New authored openings are produced by the independent server/media workflow.
"""
import hashlib
import json
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
RES=ROOT/'ios/CharacterHost/Resources'

def check():
    recipes=json.loads((ROOT/'assets/characters/openings.json').read_text())
    catalog=json.loads((RES/'CharacterOpenings.json').read_text())
    collections=json.loads((RES/'CharacterCollections.json').read_text())['collections']
    live={c['modelID'] for c in collections if not c.get('previewOnly')}
    assert set(recipes['characters'])==live
    assert {c['characterID'] for c in catalog['characters']}==live
    assert catalog['revision']==recipes['revision']
    for role in catalog['characters']:
        identity=role['characterID']
        variants=role['variants']
        authored=recipes['characters'][identity]
        assert len(variants)==len(authored)==3
        assert [v['text'] for v in variants]==[e if isinstance(e,str) else e['text'] for e in authored]
        assert len({v['text'] for v in variants})==3
        for variant in variants+role.get('legacyVariants',[]):
            assert variant['audioReady'] and variant['duration']>0
            payload=(RES/(variant['audio']+'.pcm')).read_bytes()
            assert len(payload)%2==0 and len(payload)>48000
            assert hashlib.sha256(payload).hexdigest()==variant['audioSHA256']
    print(f'Opening assets PASS: {len(live)} conversational roles; {len(collections)-len(live)} local-only previews; no network calls')

if __name__=='__main__':check()
