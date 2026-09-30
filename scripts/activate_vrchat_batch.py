#!/usr/bin/env python3
"""Integrate an explicitly reviewed batch. Does not export, install, or certify it.

Private packages/art are copied locally; the public roster only contains IDs.
Existing conversations use stable IDs and are never reset by this operation.
"""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import sys
import time

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'character-sdk/tools'))
from character_tool import validate


def write(path,value):path.write_text(json.dumps(value,ensure_ascii=False,indent=2)+'\n')


def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--batch',required=True);args=parser.parse_args()
    batches=json.loads((ROOT/'assets/characters/import-batches.json').read_text())
    batch=next(b for b in batches['batches'] if b['id']==args.batch)
    plan=json.loads((ROOT/'.local/vrchat-batch/plan.json').read_text());rows={r['id']:r for r in plan['models']}
    res=ROOT/'ios/CharacterHost/Resources'
    collections=json.loads((res/'CharacterCollections.json').read_text())
    covers=json.loads((res/'CharacterCoverCatalog.json').read_text())
    roster=json.loads((ROOT/'assets/characters/active-roster.json').read_text())
    for identity in batch['characters']:
        row=rows[identity];source=ROOT/'.local/vrchat-batch/converted'/row['role']
        manifest,_=validate(source)
        review=json.loads((ROOT/'.local/vrchat-batch/render'/(row['role']+'-controls.json')).read_text())
        if review.get('role')!=row['role'] or review.get('manifestSHA256')!=hashlib.sha256((source/'character.json').read_bytes()).hexdigest():
            raise ValueError('Review is absent or belongs to an older package: '+identity)
        if {c['id'] for c in review['controls']}!={o['control']['id'] for o in manifest.get('performance',{}).get('options',[])}:
            raise ValueError('Review does not cover every source control: '+identity)
        if not review['controls'] or not all(c.get('resetRestored') for c in review['controls']):raise ValueError('Missing control/reset review: '+identity)
        art=Path(plan['sourceRoot'])/row['sourceFolder']/row['cover']
        if not art.is_file():raise ValueError('Missing supplied cover: '+identity)
        target=ROOT/'character-packages/imported'/identity
        if target.exists():
            backup=ROOT/'.local/vrchat-batch/previous'/str(time.time_ns())/identity
            backup.parent.mkdir(parents=True,exist_ok=True);target.rename(backup)
        shutil.copytree(source,target)
        if identity not in roster['characters']:roster['characters'].append(identity)
        if not any(c['modelID']==identity for c in collections['collections']):
            scene='garden' if row['role']=='chiffon' else 'sunroom'
            collections['collections'].append(dict(schemaVersion=1,id='app.starry.collections.'+identity,version='1.1.0',modelID=identity,
                modelPackageID=manifest['packageId'],modelPackageVersion=manifest['packageVersion'],actions=[],environments=[scene],
                voices=[dict(id=identity+'/natural',title='自然聊',detail='角色专属音色',engine='aliyun-character-v1',speed=1)],
                music=[dict(id=identity+'/theme')],defaultEnvironment=scene,defaultVoice=identity+'/natural',defaultMusic=identity+'/theme'))
        collection=next(c for c in collections['collections'] if c['modelID']==identity)
        collection['modelPackageVersion']=manifest['packageVersion']
        asset='Cover_'+identity.replace('-','_');folder=ROOT/'ios/CharacterHost/Assets.xcassets'/(asset+'.imageset');folder.mkdir(exist_ok=True)
        name='source'+art.suffix.lower();shutil.copy2(art,folder/name)
        write(folder/'Contents.json',dict(images=[dict(filename=name,idiom='universal')],info=dict(author='xcode',version=1)))
        covers['covers']=[c for c in covers['covers'] if c['runtimeID']!=identity]
        covers['covers'].append(dict(runtimeID=identity,asset=asset,environmentID=collection['defaultEnvironment'],focusX=.5,focusY=.3,frameBottom=.46,cameraYaw=0,
            source='author-supplied',sourceSHA256=hashlib.sha256(art.read_bytes()).hexdigest()))
    write(res/'CharacterCollections.json',collections);write(res/'CharacterCoverCatalog.json',covers)
    write(ROOT/'assets/characters/active-roster.json',roster)
    print('BATCH_INTEGRATED',batch['id'],','.join(batch['characters']),'(build/install still required)')


if __name__=='__main__':main()
