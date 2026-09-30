#!/usr/bin/env python3
"""Read-only body-motion inventory from original avatar animation samples.

Run after the source capability audit and Unity sampling described in the
VRChat import skill. Samples and output remain local; never republish curves.
Static bone offsets are not movement. Measure variation against the first
sample, not the rest skeleton, and treat q and -q as the same rotation.
"""
import argparse
import hashlib
import json
import math
from pathlib import Path
from vrchat_source_paths import resolve_source_path

ROOT = Path(__file__).resolve().parents[1]
BODY = {'Hips', 'Spine', 'Chest', 'Neck', 'Head'}


def normalized(value):
    q = [value[k] for k in 'xyzw']
    length = math.sqrt(sum(v*v for v in q))
    if length < 1e-9:
        raise ValueError('Invalid zero-length quaternion')
    return [v/length for v in q]


def variation(track):
    rotations = [normalized(q) for q in track['rotations']]
    positions = [[p[k] for k in 'xyz'] for p in track['positions']]
    angle = max((math.degrees(2*math.acos(min(1., abs(sum(a*b for a,b in zip(rotations[0],q))))))
                 for q in rotations), default=0.)
    distance = max((math.dist(positions[0],p) for p in positions), default=0.)
    return dict(rotationDegrees=round(angle,6), translationMetres=round(distance,8))


def audit(root):
    inventory = root/'docs/verification/vrchat-performance/source-capabilities.json'
    sources = {c['role']:c for c in json.loads(inventory.read_text())['characters']}
    archives = json.loads((root/'docs/verification/vrchat-import/source-audit.json').read_text())['archives']
    result = dict(schemaVersion=1, method='Variation from first original sample, normalized quaternion short arc; not a frame-rate or visual-quality test.', characters=[])
    for role in ('kipfel','mamehinata'):
        archive = next(a for a in archives if a['archiveSHA256']==sources[role]['archiveSHA256'])
        resolve_source_path(archive['sourceArchive'],expected_sha256=archive['archiveSHA256'],project_root=root)
        entries = {a['guid']:a for package in archive['unityPackages'] for a in package['assets']}
        for clip in sources[role]['sourceClips']:
            entry = entries[clip['guid']]
            if entry['sha256'] != clip['sha256']:
                raise ValueError('Source inventories disagree: '+clip['path'])
            resolve_source_path(entry['extractedPath'],expected_sha256=clip['sha256'],
                                extraction_root=archive['extractionRoot'],project_root=root)
        path = root/'.local/vrchat-stage/Inspection/Performances'/f'{role}.json'
        data = json.loads(path.read_text())
        clips = []
        original_paths = {c['path'] for c in sources[role]['sourceClips']}
        for motion in data['motions']:
            if motion['path'] not in original_paths:
                raise ValueError('Sample does not refer to an original clip: '+motion['path'])
            body = {}
            for track in motion['tracks']:
                bone = track['path'].rsplit('/',1)[-1]
                if bone in BODY:
                    delta = variation(track)
                    if delta['rotationDegrees'] > .01 or delta['translationMetres'] > .00001:
                        body[bone] = delta
            clips.append(dict(name=motion['name'],duration=motion['duration'],loop=motion['loop'],
                              movingBody=body,staticTimeline=motion['duration']==0))
        result['characters'].append(dict(role=role,sourceClipCount=sources[role]['sourceClipCount'],
            originalArchivesAndClipHashesVerified=True,
            sourceArchiveSHA256=sources[role]['archiveSHA256'],
            sampleSHA256=hashlib.sha256(path.read_bytes()).hexdigest(),sampledTransformClips=len(clips),clips=clips))
    return result


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output',type=Path,default=ROOT/'.local/checks/character-settings/source-idle-audit.json')
    args = parser.parse_args()
    result = audit(ROOT)
    args.output.parent.mkdir(parents=True,exist_ok=True)
    args.output.write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n')
    for character in result['characters']:
        print(character['role'],f"{character['sourceClipCount']} original clips; {character['sampledTransformClips']} sampled Transform clips")
        for clip in character['clips']:
            if clip['movingBody']:
                print(' ',clip['name'],clip['duration'],'seconds',json.dumps(clip['movingBody']))
