#!/usr/bin/env python3
"""Activate locally reviewed model previews, retaining their incomplete-effects status.

Every active character must pass preflight before any package is replaced. Source
archives are untouched, previous packages are retained privately, and this does
not certify device rendering or complete VRChat feature support.
"""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT/'character-sdk/tools'))
from character_tool import validate


def read(path):
    return json.loads(path.read_text())


def digest(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def write(path, value):
    temporary = path.with_name(path.name+'.tmp')
    temporary.write_text(json.dumps(value, ensure_ascii=False, indent=2)+'\n')
    temporary.replace(path)


def authored_options(manifest):
    # AI hints are deliberately removed from model-only candidates.
    return [{k:v for k,v in option.items() if k != 'ai'}
            for option in manifest.get('performance', {}).get('options', [])]


def preflight(output):
    roster = read(ROOT/'assets/characters/active-roster.json')['characters']
    collections=read(ROOT/'ios/CharacterHost/Resources/CharacterCollections.json')['collections']
    preview_ids={c['modelID'] for c in collections if c.get('previewOnly') is True}
    status = {row['id']:row for row in read(output/'status.json')['characters']}
    checked = []
    for identity in roster:
        if identity not in preview_ids:
            validate(ROOT/'character-packages/imported'/identity)
            continue
        row = status[identity]
        if row['status'] != 'candidate-prepared':
            raise ValueError('Candidate is not prepared: '+identity)
        folder = output/identity
        manifest, _ = validate(folder)
        sha = digest(folder/'character.json')
        if manifest['id'] != identity or row['manifestSHA256'] != sha:
            raise ValueError('Candidate identity/hash mismatch: '+identity)
        pending = read(folder/'model-review-status.json')
        if pending.get('complete') is not False or pending.get('modelOnly') is not True:
            raise ValueError('Preview must retain explicit incomplete status: '+identity)
        if manifest['speech']['mode'] != 'none' or any('ai' in o for o in manifest.get('performance', {}).get('options', [])):
            raise ValueError('Model preview contains speech or AI bindings: '+identity)
        old = ROOT/'character-packages/imported'/identity
        origin = read(folder/'model-review-origin.json')
        if digest(old/'character.json') not in (origin['sourceManifestSHA256'], sha):
            raise ValueError('Active package changed after candidate preparation: '+identity)
        motion = read(output/'render'/f'{identity}-motion.json')
        if motion.get('manifestSHA256') != sha or motion.get('frames', 0) < 240:
            raise ValueError('Fresh Unity motion review is required: '+identity)
        if motion.get('blinkBindings') != row['blinkBindings'] or motion.get('strands') != row['physicsStrands']:
            raise ValueError('Unity motion bindings differ from candidate: '+identity)
        if motion['strands'] < 1 or motion.get('maximumRotationDegrees', 0) <= .00001:
            raise ValueError('Unity secondary motion is frozen: '+identity)
        for suffix in ['', '-eyelids']:
            image = output/'render'/f'{identity}{suffix}.png'
            if not image.is_file() or image.stat().st_size < 1024:
                raise ValueError('Unity rendered evidence is missing: '+identity+suffix)
        rendered = read(output/'render'/f'{identity}-render.json')
        if rendered.get('manifestSHA256') != sha or rendered.get('nonemptyPixels') is not True:
            raise ValueError('Fresh nonempty pixel review is required: '+identity)
        if rendered.get('defaultSHA256') != digest(output/'render'/f'{identity}.png') or rendered.get('eyelidsSHA256') != digest(output/'render'/f'{identity}-eyelids.png'):
            raise ValueError('Rendered pixels changed after Unity review: '+identity)
        if 'core.avatar-controls@1' in manifest['compatibility'].get('optional', []):
            controls = read(output/'render'/f'{identity}-controls.json')
            expected = {o['control']['id'] for o in authored_options(manifest)}
            if controls.get('manifestSHA256') != sha or {c['id'] for c in controls['controls']} != expected:
                raise ValueError('Unity control review does not cover this package: '+identity)
            if not all(c.get('resetRestored') for c in controls['controls']):
                raise ValueError('Unity control reset failed: '+identity)
        elif authored_options(manifest) != authored_options(read(old/'character.json')):
            raise ValueError('Legacy authored performances changed without review: '+identity)
        checked.append(dict(id=identity, manifestSHA256=sha, complete=False,
                            deviceVerified=False, unityMotionReview=motion))
    return checked


def clone_file(source, target):
    # APFS clones avoid a second full copy of large local model assets.
    result = subprocess.run(['cp', '-c', '-p', str(source), str(target)], capture_output=True)
    if result.returncode:
        shutil.copy2(source, target)
    return target


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--apply', action='store_true', help='Replace declared preview packages after successful review; preserve complete characters')
    args = parser.parse_args()
    output = ROOT/'.local/vrchat-batch/model-review'
    checked = preflight(output)
    print('MODEL_REVIEW_PREFLIGHT_PASS', len(checked), flush=True)
    if not args.apply:
        return
    collections_path = ROOT/'ios/CharacterHost/Resources/CharacterCollections.json'
    collections = read(collections_path)
    for row in checked:
        collection = next(c for c in collections['collections'] if c['modelID'] == row['id'])
        collection['modelPackageVersion'] = read(output/row['id']/'character.json')['packageVersion']
    work = ROOT/'.local/vrchat-batch/model-review-activation'/str(time.time_ns())
    work.mkdir(parents=True)
    shutil.copy2(collections_path, work/'CharacterCollections.previous.json')
    for row in checked:
        shutil.copytree(output/row['id'], work/'prepared'/row['id'], copy_function=clone_file)
    replaced = []
    try:
        for row in checked:
            identity = row['id']
            target = ROOT/'character-packages/imported'/identity
            backup = work/'previous'/identity
            backup.parent.mkdir(parents=True, exist_ok=True)
            target.rename(backup)
            replaced.append(identity)
            (work/'prepared'/identity).rename(target)
        write(collections_path, collections)
        write(work/'activation.json', dict(schemaVersion=1, mode='model-review',
              complete=False, deviceVerified=False, characters=checked))
    except BaseException:
        for identity in reversed(replaced):
            target = ROOT/'character-packages/imported'/identity
            if target.exists():
                target.rename(work/'prepared'/identity)
            (work/'previous'/identity).rename(target)
        shutil.copy2(work/'CharacterCollections.previous.json', collections_path)
        raise
    print('MODEL_REVIEW_ACTIVATED', len(checked), str(work.relative_to(ROOT)),
          '(fresh Unity export and device verification still required)', flush=True)


if __name__ == '__main__':
    main()
