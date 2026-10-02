#!/usr/bin/env python3
"""Give every active companion isolated collections using explicitly reused media.

Reuse is declared, not disguised as a newly generated asset. Covers and avatars
are untouched. No network or paid API calls.
"""
import copy
import hashlib
import json
from pathlib import Path
import shutil

ROOT=Path(__file__).resolve().parents[1]
def read(p):return json.loads(p.read_text())
def write(p,v):p.write_text(json.dumps(v,ensure_ascii=False,indent=2)+'\n')
def digest(p):return hashlib.sha256(p.read_bytes()).hexdigest()

def main():
    native=ROOT/'ios/CharacterHost/Resources';unity=ROOT/'unity/CharacterRuntime/Assets/Resources'
    roster=read(ROOT/'assets/characters/active-roster.json')['characters']
    adaptation=read(ROOT/'assets/characters/companion-adaptations.json')
    assert set(adaptation['characters'])==set(roster)
    catalog=read(native/'CharacterCatalog.json');models={c['id']:c for c in catalog['characters']}
    assert set(models)==set(roster)
    path=native/'CharacterCollections.json';collections=read(path)
    by_role={c['modelID']:copy.deepcopy(c) for c in collections['collections']}
    atmosphere=read(native/'CharacterAtmospheres.json');by_atmo={e['id']:copy.deepcopy(e) for e in atmosphere['characters']}
    audit_path=ROOT/'docs/verification/character-music/audio-audit.json';audit=read(audit_path)
    tracks={t['sourceModelID']:copy.deepcopy(t) for t in audit['tracks']}
    for role in roster:
        recipe=adaptation['characters'][role];collection=by_role[role];model=models[role]
        collection.update(modelPackageID=model['packageId'],modelPackageVersion=model['packageVersion'],version='1.3.0')
        collection.pop('previewOnly',None)
        voice=copy.deepcopy(by_role[recipe['voiceSource']]['voices'][0])
        voice.update(id=role+'/natural',title='轻声相伴',detail='复用已批准的角色音色')
        if recipe['voiceSource']!=role:voice['reuseSourceModelID']=recipe['voiceSource']
        collection['voices']=[voice];collection['defaultVoice']=voice['id']
        donor=recipe['musicSource'];track=copy.deepcopy(tracks[donor])
        asset='Music_'+role.replace('-','_')+'_theme'
        source=native/(track['asset']+'.caf');target=native/(asset+'.caf')
        assert source.is_file() and digest(source)==track['sha256']
        if source!=target:shutil.copyfile(source,target)
        track.update(id=role+'/theme',sourceModelID=role,asset=asset)
        if donor!=role:
            track['reuseSourceModelID']=donor
            track['provenance']=dict(kind='approved-existing-recording-reuse',sourceModelID=donor,
                original=tracks[donor]['provenance'],sourceAssetSHA256=track['sha256'])
        fields=['id','asset','assetExtension','sourceModelID','sha256','duration','title','detail','symbol']
        item={k:track[k] for k in fields}
        if donor!=role:item['reuseSourceModelID']=donor
        collection['music']=[item];collection['defaultMusic']=track['id']
        tracks[role]=track
        source_role=recipe['atmosphereSource'];entry=copy.deepcopy(by_atmo[source_role])
        entry.update(id=role,background=f'Atmospheres/{role}/background')
        if source_role!=role:
            entry['reuseSourceModelID']=source_role
            entry['imageModel']='existing-artwork-reuse'
            source=unity/f'Atmospheres/{source_role}/background.png';target=unity/(entry['background']+'.png')
            assert digest(source)==entry['backgroundSHA256']
            target.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(source,target)
        by_atmo[role]=entry
    collections['collections']=[by_role[r] for r in roster];write(path,collections)
    atmosphere['characters']=[by_atmo[r] for r in roster]
    write(native/'CharacterAtmospheres.json',atmosphere);write(unity/'CharacterAtmospheres.json',atmosphere)
    audit['tracks']=list(tracks.values());write(audit_path,audit)
    print('Prepared',len(roster),'isolated companions; covers/avatars unchanged; paid calls: 0')

if __name__=='__main__':main()
