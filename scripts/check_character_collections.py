#!/usr/bin/env python3
"""Validate private character option bundles before either simulator/device build."""
import json
import hashlib
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

def validate(resources=None, audit_path=None):
    resources = Path(resources) if resources else ROOT / 'ios/CharacterHost/Resources'
    audit_path = Path(audit_path) if audit_path else ROOT / 'docs/verification/character-music/audio-audit.json'
    models = {c['id']: c for c in json.loads((resources / 'CharacterCatalog.json').read_text())['characters']}
    scenes = {c['id'] for c in json.loads((resources / 'EnvironmentCatalog.json').read_text())['environments']}
    data = json.loads((resources / 'CharacterCollections.json').read_text())
    assert data['schemaVersion'] == 1, 'Unsupported collection schema'
    assert {c['modelID'] for c in data['collections']} == set(models), 'Each role needs a collection'
    assert len(data['collections']) == len(models), 'Duplicate role collection'
    option_ids = set()
    music_assets, music_hashes, music_ids = set(), set(), set()
    audit = json.loads(audit_path.read_text())
    audited_tracks = {track['id']: track for track in audit['tracks'] if track['sourceModelID'] in models}
    assert len(audited_tracks) == sum(t['sourceModelID'] in models for t in audit['tracks']), 'Duplicate audio audit ID'
    for c in data['collections']:
        model = models[c['modelID']]
        assert c['schemaVersion'] == 1 and c['version'], 'Invalid collection version'
        assert (c['modelPackageID'], c['modelPackageVersion']) == (model['packageId'], model['packageVersion'])
        assert set(c['actions']) <= {a['id'] for a in model['actions'] if a['button']}, 'Unknown action'
        assert set(c['environments']) <= scenes and c['defaultEnvironment'] in c['environments'], 'Invalid scene/default'
        if c.get('previewOnly'):
            assert c['voices'] and len(c['voices']) == 1 and c['defaultVoice'] == c['voices'][0]['id']
            assert c['music'] == [] and c['defaultMusic'] == ''
            assert c['voices'][0]['id'].startswith(c['modelID'] + '/')
            continue
        for kind, default in [('voices', 'defaultVoice'), ('music', 'defaultMusic')]:
            ids = {o['id'] for o in c[kind]}
            assert len(ids) == len(c[kind]) and c[default] in ids, 'Duplicate or missing option/default'
            assert not ids & option_ids, 'Option ID belongs to another collection'
            assert all(i.startswith(c['modelID']+'/') for i in ids), 'Unscoped option ID'
            option_ids |= ids
        for voice in c['voices']:
            assert voice['engine'] in ('melo-zh-v1','aliyun-character-v1') and .7 <= voice['speed'] <= 1.4
        for track in c['music']:
            assert len(c['music']) == 1, 'Each character owns exactly one theme'
            assert track.get('sourceModelID') == c['modelID'], 'Music source belongs to another role'
            assert track.get('assetExtension') == 'caf', 'Bundled role music must use lossless CAF'
            assert re.fullmatch(r'Music_[a-z0-9_]+', track['asset']), 'Unsafe asset basename'
            prefix = 'Music_' + c['modelID'].replace('-', '_') + '_'
            assert track['asset'].startswith(prefix), 'Music asset belongs to another role'
            file = resources / (track['asset'] + '.caf')
            assert file.is_file(), 'Missing music file'
            payload = file.read_bytes()
            assert payload[:4] == b'caff', 'Invalid CAF asset'
            actual_hash = hashlib.sha256(payload).hexdigest()
            assert track.get('sha256') == actual_hash, 'Music asset hash differs from collection'
            assert track['asset'] not in music_assets, 'Two role options share a recording'
            music_assets.add(track['asset']); music_hashes.add(actual_hash); music_ids.add(track['id'])
            authored = audited_tracks.get(track['id'])
            assert authored and authored['sourceModelID'] == c['modelID'], 'Missing role-specific authoring evidence'
            assert authored['asset'] == track['asset'] and authored['sha256'] == actual_hash, 'Audio audit does not match resource'
            if track.get('reuseSourceModelID'):
                donor=next((t for t in audit['tracks'] if t['sourceModelID']==track['reuseSourceModelID']),None)
                assert donor and donor['sha256']==actual_hash and authored.get('reuseSourceModelID')==track['reuseSourceModelID'], 'Undeclared/unverified recording reuse'
                assert authored['provenance']['kind']=='approved-existing-recording-reuse'
            assert authored['bytes'] == len(payload) and abs(track['duration'] - authored['duration']) < .0001
            assert authored['roundtripPCMIdentical'] and authored['sampleRate'] == 32000 and authored['channels'] == 2
            assert 0 < authored['peak'] < .461 and .012 < authored['rms'] < .08, 'Unbounded music level'
            assert authored['seamStep'] < .002 and authored['seamSlopeStep'] < .003 and authored['dc'] < .00002, 'Unsafe loop join'
    assert music_ids == set(audited_tracks), 'Audio evidence/catalog options differ'
    for recording in music_hashes:
        owners={t.get('reuseSourceModelID',t['sourceModelID']) for t in audited_tracks.values() if t['sha256']==recording}
        assert len(owners)==1, 'Duplicate recording without a common verified reuse source'
    for field in ['pcmSha256', 'scoreSha256']:
        assert len({track[field] for track in audited_tracks.values() if not track.get('reuseSourceModelID')}) == sum(not track.get('reuseSourceModelID') for track in audited_tracks.values()), 'Shared PCM or score under distinct names'
    print(f"Character collection v1 integrity PASS: {len(models)} isolated collections, {len(option_ids)} scoped audio options; "
          f"{len(music_ids)} role-bound lossless recordings (explicit approved reuse allowed), ownership/hashes/loop checks PASS.")

if __name__ == '__main__':
    validate()
