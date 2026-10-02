#!/usr/bin/env python3
"""Restore portable author controls and speech on the active sixteen packages.

No provider calls, original archives unchanged. Candidates and rollback copies
stay private. Keep reviewed geometry; Ramune uses the verified official MA bake.
"""
import argparse
import copy
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT/'character-sdk/tools'))
from character_tool import seal, validate, inspect_glb
from vrchat_conversation_projection import project
from vrchat_ai_semantics import hints, classify

OUT = ROOT/'.local/vrchat-batch/companions-16'
def read(path): return json.loads(path.read_text())
def write(path, value): path.write_text(json.dumps(value, ensure_ascii=False, indent=2)+'\n')
def sha(path): return hashlib.file_digest(path.open('rb'), 'sha256').hexdigest()
def clone(source, target):
    result = subprocess.run(['cp', '-c', '-p', str(source), str(target)], capture_output=True)
    if result.returncode: shutil.copy2(source, target)
    return target


def prepare(identity, profile, preview):
    old = ROOT/'character-packages/imported'/identity
    folder = OUT/identity
    if (folder/'companion-origin.json').exists():
        marker = read(folder/'companion-origin.json')
        if marker['activeManifestSHA256'] != sha(old/'character.json'):
            raise ValueError('Active package changed since candidate preparation: '+identity)
    folder.mkdir(parents=True, exist_ok=True)
    shutil.copytree(old, folder, copy_function=clone, dirs_exist_ok=True)
    manifest = read(folder/'character.json')
    origin = dict(id=identity, activeManifestSHA256=sha(old/'character.json'),
                  activeModelSHA256=sha(old/'model.glb'))
    role = identity.removeprefix('anime-')
    if preview:
        converted = ROOT/'.local/vrchat-batch/converted'/role
        if role == 'ramune':
            converted = ROOT/'.local/vrchat-batch/converted-modular/ramune'
            # Officially merged controller references were checked both by
            # Unity GUID/fileID and read-only binary decoding, before conversion.
            bake = ROOT/'.local/vrchat-batch/bakes/ramune-6000.3.25f1'
            origin['modularBake'] = dict(stage=str(bake.relative_to(ROOT)),
                referenceValidationSHA256=sha(bake/'Inspection/Baked/reference-validation.json'))
            for name in ('model.glb', 'avatar-geometry.json', 'avatar-descriptor.json',
                         'materials.json', 'secondary-motion.json', 'physics-source.json'):
                clone(converted/name, folder/name)
            shutil.copytree(converted/'textures', folder/'textures', copy_function=clone, dirs_exist_ok=True)
        source_controls = read(converted/'avatar-controls.json')
        motions = read(converted/'avatar-motions.json')
        controls, evidence = project(source_controls, motions)
        write(folder/'avatar-controls.json', controls)
        used_motions={s['motion'] for g in controls['controllers'] for s in g['states']} | {c['motion'] for g in controls['controllers'] for b in g['blends'] for c in b['children']}
        runtime_motions=dict(motions,motions=[m for m in motions['motions'] if m['guid'] in used_motions])
        runtime_motions=copy.deepcopy(runtime_motions)
        for motion in runtime_motions['motions']:
            for track in motion['tracks']:
                if len(motion['times'])>2 and all(all(v==track[k][0] for v in track[k]) for k in ('positions','rotations','scales')):
                    track['times']=[motion['times'][0],motion['times'][-1]]
                    for k in ('positions','rotations','scales'):track[k]=[track[k][0],track[k][-1]]
        (folder/'avatar-motions.json').write_text(json.dumps(runtime_motions,ensure_ascii=False,separators=(',',':'))+'\n')
        semantic, semantic_evidence = hints(controls, motions)
        write(folder/'ai-expression-evidence.json', dict(schemaVersion=1, controls=semantic_evidence))
        groups, options, group_ids = [], [], {}
        for c in controls['controls']:
            if c['group'] not in group_ids:
                gid = 'menu-'+hashlib.sha256(c['group'].encode()).hexdigest()[:16]
                group_ids[c['group']] = gid
                groups.append(dict(id=gid, label=c['group'][:128], symbol='slider.horizontal.3'))
            option = dict(id=c['id'], group=group_ids[c['group']], label=c['label'][:128],
                kind='toggle', description='作者原包菜单 · '+c['group'], duration=0,
                loop=False, defaultOn=c['kind']!='slider' and abs(c['initial']-c['value'])<1e-5,
                bones=[], morphs=[], offMorphs=[], morphTracks=[], visibility=[], offVisibility=[], control=c)
            if c['id'] in semantic: option['ai'] = semantic[c['id']]
            options.append(option)
        # Independently expose authored facial presets even when a platform
        # motion elsewhere in their controller layer prevents that layer from
        # running. Preserve all original clips privately; this projects only
        # the actual face weights and does not claim a replacement body motion.
        model = inspect_glb(folder/'model.glb')
        shapes = {n['path']:set(n.get('morphs', [])) for n in model['nodes']}
        head = manifest['rig']['headRenderer']
        seen_faces, recovered_faces = set(), []
        for motion in motions['motions']:
            hint = classify(motion)
            if not hint: continue
            curves = [c for c in motion.get('curves', []) if c['component']=='UnityEngine.SkinnedMeshRenderer'
                      and c['property'].startswith('blendShape.') and 'Avatar/'+c['path']==head]
            # A sampled facial snapshot must not silently discard an animated
            # face sequence. Only static source presets enter this projection.
            if not curves or any(max(k['value'] for k in c['keys'])-min(k['value'] for k in c['keys'])>.01 for c in curves if c['keys']):
                continue
            bindings = [dict(renderer=head, shape=c['property'][11:], weight=max(0, min(1,c['keys'][-1]['value']/100)))
                        for c in curves if c['keys'] and c['keys'][-1]['value']>0 and c['property'][11:] in shapes.get(head, set())]
            signature = tuple(sorted((b['shape'], round(b['weight'],5)) for b in bindings))
            if not bindings or len(bindings)>64 or signature in seen_faces: continue
            seen_faces.add(signature)
            oid = 'source-face-'+hashlib.sha256(motion['guid'].encode()).hexdigest()[:20]
            options.append(dict(id=oid, group='source-face', label=motion['name'][:128], kind='preset',
                description='原作静态表情曲线 · '+motion['name'], duration=0, loop=False, defaultOn=False,
                bones=[], morphs=bindings, offMorphs=[], morphTracks=[], visibility=[], offVisibility=[], ai=hint))
            recovered_faces.append(dict(id=oid, guid=motion['guid'], name=motion['name']))
        if recovered_faces: groups.insert(0, dict(id='source-face', label='原作表情', symbol='face.smiling'))
        defaults = [d for d in manifest.get('performance', {}).get('defaults', [])
                    if any(n['path']==d['path'] and 'materials' in n for n in model['nodes'])]
        manifest['performance'] = dict(schemaVersion=3, groups=groups, options=options, defaults=defaults)
        secondary=read(folder/'secondary-motion.json');sv=secondary['schemaVersion']
        secondary['controls']=[c for c in secondary.get('controls',[]) if c['option'] in {o['id'] for o in options}]
        write(folder/'secondary-motion.json',secondary)
        manifest['compatibility']['optional']=[c for c in manifest['compatibility']['optional'] if not c.startswith('core.secondary-motion@')]+[f'core.secondary-motion@{sv}']
        manifest['extensions']['app.starry.secondary-motion']['version']=sv
        required = [c for c in manifest['compatibility']['required'] if not c.startswith(('core.performance@','core.avatar-controls@'))]
        required += ['core.avatar-controls@2','core.performance@3']
        manifest['compatibility']['required'] = required
        manifest['compatibility']['optional'] = [c for c in manifest['compatibility']['optional'] if not c.startswith(('core.avatar-controls@','core.speech.'))]
        geometry = read(folder/'avatar-geometry.json')
        desc = read(folder/'avatar-descriptor.json')
        visemes = desc.get('VisemeBlendShapes', [])
        skin = max(geometry['skins'], key=lambda s:len(shapes.get('Avatar/'+s['path'],set()) & set(visemes)))
        renderer = 'Avatar/'+skin['path']; speech = dict(mode='none', proceduralHeadMotion=False, amplitude=[], visemes=[])
        for label,index in [('aa',10),('ih',12),('ou',14),('ee',11),('oh',13)]:
            if len(visemes)>index and visemes[index] in shapes.get(renderer, set()):
                speech['visemes'].append(dict(id=label, bindings=[dict(renderer=renderer, shape=visemes[index], weight=.7)]))
        if speech['visemes']:
            speech['mode']='amplitude';speech['amplitude']=speech['visemes'][0]['bindings']
            manifest['compatibility']['optional'] += ['core.speech.amplitude@1','core.speech.viseme@1']
        manifest['speech']=speech
        evidence.update(id=identity, originalMotionCount=len(motions['motions']), runtimeMotionCount=len(runtime_motions['motions']), archivedUnreferencedMotions=[dict(guid=m['guid'],name=m['name']) for m in motions['motions'] if m['guid'] not in used_motions], restoredFacePresets=recovered_faces,
                        authoringOnly=True, deviceVerified=False,
                        pendingSourceComponents=read(old/'model-review-status.json').get('remaining', []))
        write(folder/'companion-source-coverage.json', evidence)
        manifest['extensions']['app.starry.avatar-controls'] = dict(version=2, file='avatar-controls.json')
        manifest['extensions']['app.starry.source-coverage'] = dict(version=1, file='companion-source-coverage.json')
        for key in ('app.starry.model-review',): manifest['extensions'].pop(key, None)
        for name in ('model-review-origin.json', 'model-review-status.json'):
            if (folder/name).exists(): (folder/name).unlink()
    manifest['packageVersion']='3.3.0'
    manifest['display'].update(name=profile['name'], description=profile['story'], invitation=profile['invitation'], tagline=profile['occupation'])
    manifest['extensions']['app.starry.private-preview'].update(modelOnly=False, visualOnly=False)
    write(folder/'companion-origin.json', origin)
    write(folder/'character.json', manifest); seal(folder); validate(folder)
    options=manifest.get('performance', {}).get('options', [])
    return dict(id=identity, preview=False, controls=sum(bool(o.get('control')) for o in options),
                facialPresets=sum(not o.get('control') for o in options), automatic=sum(o.get('ai',{}).get('automatic',False) for o in options),
                speech=manifest['speech']['mode'], manifestSHA256=sha(folder/'character.json'))


def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--only',nargs='+');args=parser.parse_args()
    OUT.mkdir(parents=True,exist_ok=True)
    roster=read(ROOT/'assets/characters/active-roster.json')['characters']
    profiles={p['id']:p for p in read(ROOT/'ios/CharacterHost/Resources/CharacterPublicProfiles.json')['characters']}
    collections={p['modelID']:p for p in read(ROOT/'ios/CharacterHost/Resources/CharacterCollections.json')['collections']}
    selected=[i for i in roster if not args.only or i in args.only]
    results=[]
    for identity in selected:
        result=prepare(identity,profiles[identity],collections[identity].get('previewOnly',False));results.append(result)
        print(json.dumps(result),flush=True)
    write(OUT/'status.json',dict(schemaVersion=1,characters=results))
    write(OUT/'review-request.json',dict(entries=[dict(role=r['id'], source=str(OUT/r['id']),
        geometry=str(OUT/r['id']/'avatar-geometry.json')) for r in results], outputRoot=str(OUT/'render'), reuseImportedMirror=True))
    write(OUT/'CharacterCatalog.json',dict(schemaVersion=1,characters=[read(OUT/i/'character.json') for i in roster]))

if __name__=='__main__':main()
