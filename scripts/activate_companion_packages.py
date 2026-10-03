#!/usr/bin/env python3
"""Promote sixteen companions after real Unity control/face/render review.

Keep complete rollback packages and native metadata privately. This validates
Editor behavior, not device FPS or provider availability; those checks follow.
"""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import sys
import time
from prepare_companion_packages import clone

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'character-sdk/tools'))
from character_tool import validate
OUT=ROOT/'.local/vrchat-batch/companions-16'
def read(p):return json.loads(p.read_text())
def sha(p):return hashlib.file_digest(p.open('rb'),'sha256').hexdigest()

def preflight():
    roster=read(ROOT/'assets/characters/active-roster.json')['characters'];checked=[]
    for role in roster:
        folder=OUT/role;manifest,_=validate(folder);digest=sha(folder/'character.json')
        active=ROOT/'character-packages/imported'/role
        assert read(folder/'companion-origin.json')['activeManifestSHA256']==sha(active/'character.json'),role+' active package changed'
        options=manifest['performance']['options']
        for kind,expected in [('controls',{o['id'] for o in options if o.get('control')}),
                              ('faces',{o['id'] for o in options if o['group']=='source-face'})]:
            report=read(OUT/'render'/f'{role}-{kind}.json')
            assert report['manifestSHA256']==digest,role+' review is stale'
            assert {c['id'] for c in report['controls']}==expected,role+' review coverage differs'
            assert all(c['resetRestored'] for c in report['controls']),role+' source reset failed'
        motion=read(OUT/'render'/f'{role}-motion.json')
        assert motion['manifestSHA256']==digest and motion['frames']>=240
        assert motion['strands']>0 and motion['maximumRotationDegrees']>.00001
        render=read(OUT/'render'/f'{role}-render.json')
        assert render['manifestSHA256']==digest and render['nonemptyPixels']
        for label,suffix in [('default',''),('eyelids','-eyelids')]:
            assert sha(OUT/'render'/f'{role}{suffix}.png')==render[label+'SHA256']
        assert manifest['speech']['mode']=='amplitude' and manifest['speech']['visemes']
        checked.append(dict(id=role,manifestSHA256=digest,
                            controls=sum(bool(o.get('control')) for o in options),
                            sourceFaces=sum(o['group']=='source-face' for o in options)))
    return checked

def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--apply',action='store_true');args=p.parse_args()
    checked=preflight();print('COMPANION_PREFLIGHT_PASS',len(checked),flush=True)
    if not args.apply:return
    backup=ROOT/'.local/vrchat-batch/companion-activation'/str(time.time_ns());backup.mkdir(parents=True)
    native=ROOT/'ios/StarryNight/Resources';old_catalog=native/'CharacterCatalog.json'
    shutil.copy2(old_catalog,backup/'CharacterCatalog.previous.json')
    for row in checked:
        shutil.copytree(OUT/row['id'],backup/'prepared'/row['id'],copy_function=clone)
    replaced=[]
    try:
        for row in checked:
            role=row['id'];target=ROOT/'character-packages/imported'/role
            previous=backup/'previous'/role;previous.parent.mkdir(parents=True,exist_ok=True)
            target.rename(previous);replaced.append(role);(backup/'prepared'/role).rename(target)
        shutil.copy2(OUT/'CharacterCatalog.json',old_catalog)
        (backup/'activation.json').write_text(json.dumps(dict(characters=checked,deviceVerified=False))+'\n')
    except BaseException:
        for role in reversed(replaced):
            target=ROOT/'character-packages/imported'/role
            if target.exists():target.rename(backup/'prepared'/role)
            (backup/'previous'/role).rename(target)
        shutil.copy2(backup/'CharacterCatalog.previous.json',old_catalog)
        raise
    print('COMPANIONS_ACTIVATED',len(checked),'rollback:',str(backup.relative_to(ROOT)),flush=True)

if __name__=='__main__':main()
