#!/usr/bin/env python3
"""Install verified local AI artwork into native/Unity resources; no paid calls."""
import hashlib
import json
from pathlib import Path
import shutil

ROOT=Path(__file__).resolve().parents[1]
def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def install():
    recipes=json.loads((ROOT/'assets/characters/media-recipes.json').read_text())
    roster=json.loads((ROOT/'assets/characters/active-roster.json').read_text())['characters']
    native=ROOT/'ios/StarryNight/Resources'
    cover_path=native/'CharacterCoverCatalog.json';covers=json.loads(cover_path.read_text())
    entries={entry['runtimeID']:entry for entry in covers['covers']}
    media=[]
    for recipe in recipes['characters']:
        role=recipe['id']
        if role not in roster:continue
        folder=ROOT/'.local/character-media'/role
        receipts={}
        for kind in ('cover','avatar','background'):
            file=folder/(kind+'.png');receipt=json.loads((folder/(kind+'.json')).read_text())
            assert receipt['status']=='complete' and sha(file)==receipt['sha256'],f'Invalid {role}/{kind}'
            receipts[kind]=receipt
        for kind,prefix in [('cover','Cover_'),('avatar','Avatar_')]:
            name=prefix+role.replace('-','_');target=ROOT/'ios/StarryNight/Assets.xcassets'/(name+'.imageset')
            target.mkdir(parents=True,exist_ok=True);shutil.copyfile(folder/(kind+'.png'),target/'generated.png')
            (target/'Contents.json').write_text(json.dumps({'images':[{'filename':'generated.png','idiom':'universal'}],'info':{'author':'xcode','version':1}})+'\n')
        # Review focal points against the generated image, not the requested
        # prompt: a large hat shifts Kipfel's actual eye line toward the middle.
        entries[role].update(source='bailian-generated',sourceSHA256=receipts['cover']['sha256'],focusY=recipe.get('coverFocusY',0.4),avatar='Avatar_'+role.replace('-','_'))
        if 'headBounds' in recipe:entries[role]['headBounds']=recipe['headBounds']
        unity=ROOT/'unity/CharacterRuntime/Assets/Resources/Atmospheres'/role
        unity.mkdir(parents=True,exist_ok=True);shutil.copyfile(folder/'background.png',unity/'background.png')
        media.append(dict(id=role,title=recipe['title'],background='Atmospheres/'+role+'/background',effect=recipe['effect'],palette=recipe['palette'],density=recipe['density'],backgroundSHA256=receipts['background']['sha256'],imageModel=receipts['background']['model']))
    expected={r['id'] for r in recipes['characters']} & set(roster)
    assert {r['id'] for r in media}==expected,'Incomplete existing authored artwork set'
    text=json.dumps({'schemaVersion':1,'characters':media},ensure_ascii=False,indent=2)+'\n'
    (native/'CharacterAtmospheres.json').write_text(text)
    (ROOT/'unity/CharacterRuntime/Assets/Resources/CharacterAtmospheres.json').write_text(text)
    covers['covers']=[c for c in covers['covers'] if c['runtimeID'] in roster]
    cover_path.write_text(json.dumps(covers,ensure_ascii=False,indent=2)+'\n')
    print('Prepared AI covers, avatars and 2048px scene masters for',len(media),'characters')
if __name__=='__main__':install()
