#!/usr/bin/env python3
"""Inventory all authored motion data and add reversible, actor-local previews.

No source archive changes, image/provider calls or invented SDK animations.
Virtual preview controls are explicitly host adapters, not author menu entries.
"""
import argparse
import copy
import hashlib
import gzip
import json
from pathlib import Path
import shutil
import sys
import time

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'character-sdk/tools'))
from character_tool import inspect_glb, seal, validate
from prepare_companion_packages import clone
from vrchat_ai_semantics import classify

PARAMETER='Starry_SourceMotion'
CAPABILITY='core.source-motions@1'
OUT=ROOT/'.local/vrchat-batch/source-motion-library'
def read(p):return json.loads(p.read_text())
def write(p,v):p.write_text(json.dumps(v,ensure_ascii=False,separators=(',',':'),allow_nan=False)+'\n')
def compressed(p,v):p.write_bytes(gzip.compress((json.dumps(v,ensure_ascii=False,separators=(',',':'),allow_nan=False)+'\n').encode(),mtime=0))
def sha(p):return hashlib.file_digest(p.open('rb'),'sha256').hexdigest()
def read_motion(p):
    if p.exists():return read(p)
    with gzip.open(p.with_suffix(p.suffix+'.gz'),'rb') as stream:
        raw=stream.read(128*1024*1024+1)
    if len(raw)>128*1024*1024:raise ValueError('Expanded motion data exceeds 128 MiB: '+str(p))
    return json.loads(raw)


def project_motion(motion,geometry,model,head):
    """Keep actual visible bindings. Report every omitted source channel.

    Humanoid Animator muscle channels are redundant with the sampled bones.
    Platform behaviors, material properties, scene helpers and missing nodes
    are never converted into empty supported motions.
    """
    if motion['duration']>120:return None,[dict(path='',property='duration',reason='outside-120-second-preview-budget')]
    nodes={n['path'] for n in geometry['nodes']}
    skins={s['path'] for s in geometry['skins']}
    morphs={n['path'][7:]:set(n.get('morphs',[])) for n in model['nodes'] if n['path'].startswith('Avatar/')}
    result={k:copy.deepcopy(motion[k]) for k in ('guid','name','duration','loop','times')}
    if not result['name'].strip():result['name']='未命名片段 '+motion['guid'][:8]
    result.update(tracks=[],curves=[])
    omitted=[]
    if motion.get('omittedEventCount',0):
        omitted.append(dict(path='',property='AnimationEvent',reason='animation-events-are-not-executable',count=motion['omittedEventCount']))
    for t in motion.get('tracks',[]):
        if t['path'] not in nodes or not t['path']:
            omitted.append(dict(path=t['path'],property='transform',reason='missing-or-root-binding'));continue
        track=copy.deepcopy(t)
        times=track.get('times',motion['times'])
        if len(times)>2 and all(all(v==track[k][0] for v in track[k]) for k in ('positions','rotations','scales')):
            track['times']=[times[0],times[-1]]
            for k in ('positions','rotations','scales'):track[k]=[track[k][0],track[k][-1]]
        result['tracks'].append(track)
    for curve in motion.get('curves',[]):
        path,component,prop=curve['path'],curve['component'],curve['property']
        if component=='UnityEngine.Animator':
            # The Unity source sampler already resolved muscle curves into
            # the actual model's local transforms. Don't evaluate them twice.
            if motion.get('humanoid') and prop in motion.get('humanoidProperties',[]):continue
            omitted.append(dict(path=path,property=prop,reason='platform-parameter'));continue
        supported=(path in nodes and (
            component=='UnityEngine.SkinnedMeshRenderer' and prop.startswith('blendShape.') and prop[11:] in morphs.get(path,set()) or
            component in ('UnityEngine.SkinnedMeshRenderer','UnityEngine.MeshRenderer') and prop=='m_Enabled' and path in skins or
            component=='UnityEngine.GameObject' and prop=='m_IsActive' and bool(path)))
        if not supported:
            omitted.append(dict(path=path,property=prop,reason='unsupported-or-missing-binding'));continue
        # A source helper that disables the complete face is not an independent
        # visible preview. Preserve it in the audit and original controller.
        if prop in ('m_Enabled','m_IsActive') and (head==path or head.startswith(path+'/')) and any(k['value']<.5 for k in curve['keys']):
            omitted.append(dict(path=path,property=prop,reason='would-hide-required-face'));continue
        result['curves'].append(copy.deepcopy(curve))
    for c in motion.get('objects',[]):omitted.append(dict(path=c['path'],property=c['property'],reason='material-or-object-reference-kept-in-author-controller'))
    if not result['tracks'] and not result['curves']:return None,omitted
    human={h['path'] for h in geometry['human'] if not any(s in h['human'] for s in ('Thumb','Index','Middle','Ring','Little'))}
    has_body=any(t['path'] in human for t in result['tracks'])
    has_face=any(c['property'].startswith('blendShape.') for c in result['curves'])
    result['category']='source-body' if has_body else 'source-face-motion' if has_face else 'source-parts'
    hint=classify(motion)
    result['intent']=hint['intent'] if hint else ''
    result['sourcePath']=motion.get('path','')
    result['projectionComplete']=not omitted
    return result,omitted


def prepare(identity):
    active=ROOT/'character-packages/imported'/identity
    folder=OUT/identity
    if folder.exists():
        marker=read(folder/'source-motion-origin.json')
        active_hash=sha(active/'character.json')
        if marker['activeManifestSHA256']!=active_hash and sha(folder/'character.json')!=active_hash:
            raise ValueError('Active manifest changed independently: '+identity)
    else:shutil.copytree(active,folder,copy_function=clone)
    manifest=read(active/'character.json');controls=read(active/'avatar-controls.json')
    # Idempotent source upgrades never multiply the virtual options.
    controls['parameters']=[p for p in controls['parameters'] if p['name']!=PARAMETER]
    controls['controls']=[c for c in controls['controls'] if c['parameter']!=PARAMETER]
    manifest['performance']['options']=[o for o in manifest['performance']['options'] if o.get('control',{}).get('parameter')!=PARAMETER]
    manifest['performance']['groups']=[g for g in manifest['performance']['groups'] if not g['id'].startswith('source-library-')]
    original=ROOT/'.local/vrchat-batch/converted'/identity[6:]
    if identity=='anime-ramune':original=ROOT/'.local/vrchat-batch/converted-modular/ramune'
    source=original/'avatar-motions.json'
    if not source.exists():source=active/'avatar-motions.json'
    motions=read_motion(source)['motions'];geometry=read(active/'avatar-geometry.json');model=inspect_glb(active/'model.glb')
    audit=[];library=[]
    for motion in motions:
        projected,omitted=project_motion(motion,geometry,model,manifest['rig']['headRenderer'][7:])
        audit.append(dict(guid=motion['guid'],name=motion['name'],source=motion.get('path',''),
            included=projected is not None,complete=not omitted,omitted=omitted,omittedEventCount=motion.get('omittedEventCount',0)))
        if projected:library.append(projected)
    if len({m['guid'] for m in library})!=len(library):raise ValueError('Duplicate source GUID: '+identity)
    controls['parameters'].append(dict(name=PARAMETER,kind='int',initial=0,saved=False))
    groups={'source-body':'原作肢体与姿势','source-face-motion':'原作表情片段','source-parts':'原作手部与部件'}
    for category,label in groups.items():
        if any(m['category']==category for m in library):manifest['performance']['groups'].append(dict(id='source-library-'+category,label=label,symbol='film.stack'))
    for index,motion in enumerate(library,1):
        gid='source-library-'+motion['category'];label=motion['name'][:128]
        control=dict(id='source-motion-'+motion['guid'],group=groups[motion['category']],label=label,
            parameter=PARAMETER,kind='button',value=index,initial=0,minimum=0,maximum=max(1,len(library)),gates=[])
        controls['controls'].append(control)
        mode='静态姿势' if motion['duration']<=.05 else '循环片段' if motion['loop'] else '单次片段'
        manifest['performance']['options'].append(dict(id=control['id'],group=gid,label=label,kind='toggle',
            description='原包独立预览 · '+mode+(' · 部分通道不适用于当前宿主' if not motion['projectionComplete'] else ''),
            duration=motion['duration'],loop=motion['loop'],defaultOn=False,bones=[],morphs=[],offMorphs=[],morphTracks=[],visibility=[],offVisibility=[],control=control))
    manifest['performance']['schemaVersion']=3
    required=manifest['compatibility']['required']
    required[:]=[x for x in required if not x.startswith(('core.performance@','core.avatar-controls@'))]
    required.extend(['core.performance@3','core.avatar-controls@2'])
    if CAPABILITY not in required:required.append(CAPABILITY)
    controls.update(schemaVersion=2,profile='mecanim-portable-v2')
    manifest['extensions']['app.starry.source-motions']=dict(version=1,file='source-motions.json',origin='author-curves-host-preview')
    manifest['packageVersion']='3.4.0'
    # Source samples remain lossless. Compress data sidecars instead of raising
    # the package budget or reducing texture quality (Mao is near 256 MiB).
    compressed(folder/'source-motions.json.gz',dict(schemaVersion=1,parameter=PARAMETER,motions=library))
    compressed(folder/'avatar-motions.json.gz',read_motion(active/'avatar-motions.json'))
    for owned in ('source-motions.json','avatar-motions.json'):
        if (folder/owned).exists():(folder/owned).unlink()
    manifest['extensions']['app.starry.source-motions'].update(file='source-motions.json.gz',encoding='gzip-json')
    digest_source=source if source.exists() else source.with_suffix(source.suffix+'.gz')
    write(folder/'source-motion-audit.json',dict(schemaVersion=1,characterID=identity,sourceSHA256=sha(digest_source),motions=audit))
    write(folder/'source-motion-origin.json',dict(activeManifestSHA256=sha(active/'character.json'),activeModelSHA256=sha(active/'model.glb')))
    write(folder/'avatar-controls.json',controls);write(folder/'character.json',manifest);seal(folder);validate(folder)
    return dict(id=identity,sourceMotions=len(motions),playable=len(library),complete=sum(not r['omitted'] for r in audit if r['included']),
        unavailable=sum(not r['included'] for r in audit),manifestSHA256=sha(folder/'character.json'))


def activate(rows):
    backup=OUT/'activation'/str(time.time_ns());backup.mkdir(parents=True)
    catalog=ROOT/'ios/StarryNight/Resources/CharacterCatalog.json'
    collections=ROOT/'ios/StarryNight/Resources/CharacterCollections.json'
    shutil.copy2(catalog,backup/'CharacterCatalog.json');shutil.copy2(collections,backup/'CharacterCollections.json')
    for row in rows:
        active=ROOT/'character-packages/imported'/row['id']
        if sha(active/'character.json')!=read(OUT/row['id']/'source-motion-origin.json')['activeManifestSHA256']:raise ValueError('Stale activation: '+row['id'])
    moved=[]
    try:
        for row in rows:
            role=row['id'];active=ROOT/'character-packages/imported'/role
            active.rename(backup/role);moved.append(role)
            shutil.copytree(OUT/role,active,copy_function=clone)
        data=read(catalog)
        data['characters']=[read(ROOT/'character-packages/imported'/c['id']/'character.json') if c['id'] in {r['id'] for r in rows} else c for c in data['characters']]
        write(catalog,data)
        data=read(collections)
        for c in data['collections']:
            if c['modelID'] in {r['id'] for r in rows}:c['modelPackageVersion']='3.4.0'
        collections.write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n')
        write(backup/'activation.json',dict(characters=rows,deviceVerified=False))
    except BaseException:
        for role in reversed(moved):
            active=ROOT/'character-packages/imported'/role
            if active.exists():active.rename(backup/(role+'.failed'))
            (backup/role).rename(active)
        shutil.copy2(backup/'CharacterCatalog.json',catalog);shutil.copy2(backup/'CharacterCollections.json',collections);raise
    print('SOURCE_LIBRARY_ACTIVATED rollback='+str(backup.relative_to(ROOT)),flush=True)


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--apply',action='store_true');parser.add_argument('--only',nargs='+');args=parser.parse_args()
    OUT.mkdir(parents=True,exist_ok=True)
    roster=read(ROOT/'assets/characters/active-roster.json')['characters']
    rows=[]
    for identity in roster:
        if args.only and identity not in args.only:continue
        row=prepare(identity);rows.append(row);print(json.dumps(row),flush=True)
    write(OUT/'status.json',dict(schemaVersion=1,characters=rows))
    if args.apply:activate(rows)
