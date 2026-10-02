#!/usr/bin/env python3
"""Check active metadata and the actual built native bundle, without network calls."""
import argparse
import json
from pathlib import Path
import subprocess
from filter_character_resources import active_resources

ROOT=Path(__file__).resolve().parents[1]

def check(app=None):
    source=ROOT/'ios/CharacterHost/Resources'
    resources=Path(app) if app else source
    def read(name): return json.loads((resources/(name+'.json')).read_text())
    active=set(json.loads((ROOT/'assets/characters/active-roster.json').read_text())['characters'])
    catalog=read('CharacterCatalog')['characters']
    assert {c['id'] for c in catalog}==active and len(catalog)==len(active)
    collections=read('CharacterCollections')['collections']
    full={c['modelID'] for c in collections if not c.get('previewOnly')}
    assert {c['modelID'] for c in collections}==active
    assert {c['id'] for c in read('CharacterPublicProfiles')['characters']}==full
    assert {c['characterID'] for c in read('CharacterOpenings')['characters']}==full
    assert {c['runtimeID'] for c in read('CharacterCoverCatalog')['covers']}==active
    assert set(read('CharacterSourceCredits'))==active
    assert set(read('MarketplaceCatalog')['characters'])==active
    atmosphere={c['id'] for c in read('CharacterAtmospheres')['characters']}
    assert atmosphere<=active
    prefabs=ROOT/'unity/CharacterRuntime/Assets/Resources/Characters'
    assert {p.stem for p in prefabs.glob('*.prefab')}==active
    backgrounds=ROOT/'unity/CharacterRuntime/Assets/Resources/Atmospheres'
    assert {p.name for p in backgrounds.iterdir() if p.is_dir()}==atmosphere
    if app:
        art,audio=active_resources(ROOT)
        assert {p.stem for p in resources.glob('Opening_*.pcm')}==audio
        music={t['asset'] for c in collections for t in c['music']}
        assert {p.stem for p in resources.glob('Music_*.caf')}==music
        assets=json.loads(subprocess.check_output(['xcrun','assetutil','--info',str(resources/'Assets.car')]))
        names={a['Name'] for a in assets if 'Name' in a}
        bundled_roles={n for n in names if n.startswith(('Anime_','Avatar_','Cover_','Package_'))}
        assert bundled_roles<=art, 'Inactive character artwork remains in Assets.car: '+str(bundled_roles-art)
        assert {c['display']['thumbnail'] for c in catalog}<=names
        assert {c['asset'] for c in read('CharacterCoverCatalog')['covers']}<=names
        assert {c['avatar'] for c in read('CharacterCoverCatalog')['covers'] if 'avatar' in c}<=names
        assert 'FirstCompanionBackdrop' not in names and 'RobotThumbnail' not in names
    print(f'Active resource check PASS: {len(active)} roles, {len(full)} full companions, {len(active)-len(full)} previews'+('; actual compiled artwork/audio checked' if app else ''))

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--app',type=Path)
    check(parser.parse_args().app)
