#!/usr/bin/env python3
"""Verify authored images and native/Unity bindings without provider calls."""
import hashlib
import json
import re
import struct
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def read(path):
    return json.loads(path.read_text())


def verify_png(path, receipt, size):
    payload = path.read_bytes()
    assert receipt['status'] == 'complete', f'Unfinished image: {path.name}'
    assert payload.startswith(b'\x89PNG\r\n\x1a\n'), f'Not PNG: {path.name}'
    assert struct.unpack('>II', payload[16:24]) == size, f'Unexpected image size: {path.name}'
    assert hashlib.sha256(payload).hexdigest() == receipt['sha256'], f'Image hash mismatch: {path.name}'


def validate(root=ROOT):
    roster = set(read(root / 'assets/characters/active-roster.json')['characters'])
    native = root / 'ios/StarryNight/Resources'
    unity = root / 'unity/CharacterRuntime/Assets/Resources'
    catalog = read(native / 'CharacterAtmospheres.json')
    assert catalog == read(unity / 'CharacterAtmospheres.json'), 'Native/Unity atmosphere catalogs differ'
    assert catalog['schemaVersion'] == 1
    roles = {entry['id']: entry for entry in catalog['characters']}
    # Preview-only roles retain author-supplied covers and the existing 3D room;
    # they must not acquire generated media merely to pass a release check.
    recipes=read(root / 'assets/characters/media-recipes.json')['characters']
    authored={r['id'] for r in recipes} & roster
    adaptation_path=root/'assets/characters/companion-adaptations.json'
    reused={r:e['atmosphereSource'] for r,e in read(adaptation_path)['characters'].items() if e['atmosphereSource']!=r} if adaptation_path.exists() else {}
    assert set(roles) == authored | (set(reused)&roster) and len(roles) == len(catalog['characters']), 'Authored atmosphere roster differs'
    covers = {entry['runtimeID']: entry for entry in read(native / 'CharacterCoverCatalog.json')['covers']}
    assert set(covers) == roster, 'Cover roster differs'
    hashes = set()
    for role, entry in roles.items():
        assert entry['effect'] in ('firefly', 'sunbeam', 'petal', 'stardust')
        assert 0.2 <= entry['density'] <= 1.2
        assert len(entry['palette']) >= 2 and all(re.fullmatch(r'#[0-9A-Fa-f]{6}', value) for value in entry['palette'])
        assert entry['background'] == f'Atmospheres/{role}/background'
        if role in reused:
            donor=roles[reused[role]]
            assert entry.get('reuseSourceModelID')==reused[role] and entry['backgroundSHA256']==donor['backgroundSHA256'], 'Unverified background reuse'
            assert hashlib.sha256((unity/(entry['background']+'.png')).read_bytes()).hexdigest()==donor['backgroundSHA256']
            continue
        folder = root / '.local/character-media' / role
        for kind, size in [('cover', (1536, 2048)), ('avatar', (1024, 1024)), ('background', (2048, 2048))]:
            receipt = read(folder / f'{kind}.json')
            assert receipt['role'] == role and receipt['kind'] == kind, 'Wrong image owner'
            verify_png(folder / f'{kind}.png', receipt, size)
            assert receipt['sha256'] not in hashes, 'Two assets share identical content'
            hashes.add(receipt['sha256'])
            if kind == 'background':
                verify_png(unity / (entry['background'] + '.png'), receipt, size)
                assert entry['backgroundSHA256'] == receipt['sha256']
            else:
                key = 'asset' if kind == 'cover' else 'avatar'
                name = covers[role][key]
                assert name == kind.capitalize() + '_' + role.replace('-', '_')
                images = root / 'ios/StarryNight/Assets.xcassets' / (name + '.imageset')
                assert read(images / 'Contents.json')['images'] == [{'filename': 'generated.png', 'idiom': 'universal'}]
                verify_png(images / 'generated.png', receipt, size)
                if kind == 'cover':
                    assert covers[role]['source'] == 'bailian-generated'
                    assert covers[role]['sourceSHA256'] == receipt['sha256']
    print(f'Character media PASS: {len(authored)} previously generated media sets, {len(set(reused)&roster)} explicit background reuses, {len(hashes)} verified generated images.')


if __name__ == '__main__':
    validate()
