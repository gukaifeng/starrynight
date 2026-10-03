#!/usr/bin/env python3
"""Portable character preflight, seal, package and compatibility comparison."""
import argparse
import hashlib
import json
import re
from pathlib import Path, PurePosixPath
import struct
import sys
import zipfile

CAPABILITIES = {'core.animation@1', 'core.gaze@1', 'core.expression@1', 'core.speech.amplitude@1',
                'core.speech.viseme@1', 'core.interaction@1', 'core.effects@1', 'core.parameters@1',
                'core.behavior@1', 'core.posture@1', 'core.secondary-motion@1', 'core.secondary-motion@2', 'core.secondary-motion@3', 'core.secondary-motion@4', 'core.avatar-controls@1', 'core.avatar-controls@2', 'core.source-motions@1', 'core.materials.liltoon@1', 'core.performance@1', 'core.performance@2', 'core.performance@3', 'core.autonomy@1', 'legacy.human-studio@1'}
CHANNELS = {'body', 'expression', 'effect', 'gaze', 'posture'}
MAX_BYTES = 256 * 1024 * 1024
FORBIDDEN = {'.cs','.dll','.dylib','.so','.exe','.shader','.compute','.sh','.py','.js','.unitypackage'}

def read_json(path):
    def unique(pairs):
        out = {}
        for key, value in pairs:
            if key in out: raise ValueError(f'duplicate JSON key: {key}')
            out[key] = value
        return out
    return json.loads(Path(path).read_text(encoding='utf-8'), object_pairs_hook=unique,
                      parse_constant=lambda value: (_ for _ in ()).throw(ValueError('nonfinite JSON: '+value)))

def safe_path(root, value):
    p = PurePosixPath(value)
    if not value or p.is_absolute() or '..' in p.parts or '\\' in value or ':' in value:
        raise ValueError('unsafe package path: '+value)
    candidate = root / value
    if not candidate.resolve().is_relative_to(root.resolve()) or any(x.is_symlink() for x in [candidate,*candidate.parents]):
        raise ValueError('symlinks / escaped package path: '+value)
    return candidate

def glb_document(path):
    data = path.read_bytes()
    if len(data)<20 or data[:4]!=b'glTF': raise ValueError('model must be GLB 2.0')
    version,length=struct.unpack_from('<II',data,4)
    if version!=2 or length!=len(data): raise ValueError('invalid GLB version / length')
    size,kind=struct.unpack_from('<II',data,12)
    if kind!=0x4E4F534A or 20+size>length: raise ValueError('GLB JSON chunk invalid')
    doc=json.loads(data[20:20+size])
    for item in doc.get('buffers',[])+doc.get('images',[]):
        if 'uri' in item: raise ValueError('GLB must embed buffers and textures; external URIs are not accepted')
    supported={'KHR_materials_unlit','KHR_texture_transform','KHR_materials_emissive_strength'}
    unknown=set(doc.get('extensionsRequired',[]))-supported
    if unknown: raise ValueError('unsupported required GLB extensions: '+str(sorted(unknown)))
    return doc

def node_scale_factors(doc):
    """Lengths of the transformed local axes, matching collider radius space."""
    import math
    nodes=doc.get('nodes',[]);parents={c:i for i,n in enumerate(nodes) for c in n.get('children',[])}
    world={};visiting=set()
    def matrix(i):
        if i in world:return world[i]
        if i in visiting:raise ValueError('cyclic GLB scale hierarchy')
        visiting.add(i);n=nodes[i]
        if 'matrix' in n:
            values=n['matrix']
            if len(values)!=16 or not all(math.isfinite(v) for v in values):raise ValueError('invalid GLB transform matrix')
            local=[[values[c*4+r] for c in range(3)] for r in range(3)]
        else:
            q=n.get('rotation',[0,0,0,1]);scale=n.get('scale',[1,1,1])
            if len(q)!=4 or len(scale)!=3 or not all(math.isfinite(v) for v in q+scale):raise ValueError('invalid GLB transform scale/rotation')
            x,y,z,w=q
            rotation=[[1-2*(y*y+z*z),2*(x*y-z*w),2*(x*z+y*w)],
                      [2*(x*y+z*w),1-2*(x*x+z*z),2*(y*z-x*w)],
                      [2*(x*z-y*w),2*(y*z+x*w),1-2*(x*x+y*y)]]
            local=[[rotation[r][c]*scale[c] for c in range(3)] for r in range(3)]
        if i in parents:
            parent=matrix(parents[i]);local=[[sum(parent[r][k]*local[k][c] for k in range(3)) for c in range(3)] for r in range(3)]
        world[i]=local;visiting.remove(i);return local
    return {i:[math.sqrt(sum(matrix(i)[r][c]**2 for r in range(3))) for c in range(3)] for i in range(len(nodes))}


def inspect_glb(path):
    doc=glb_document(path);nodes=doc.get('nodes',[]);parents={}
    for parent,node in enumerate(nodes):
        for child in node.get('children',[]): parents[child]=parent
    def node_path(index):
        names=[];seen=set()
        while True:
            if index in seen: raise ValueError('cyclic node hierarchy')
            seen.add(index);names.append(nodes[index].get('name','<unnamed>'))
            if index not in parents: break
            index=parents[index]
        return '/'.join(reversed(names))
    rows=[];scales=node_scale_factors(doc)
    for index,node in enumerate(nodes):
        row={'path':node_path(index),'scaleFactors':scales[index]}
        if 'mesh' in node:
            mesh=doc['meshes'][node['mesh']]
            row['morphs']=mesh.get('extras',{}).get('targetNames',[])
            row['materials']=[doc['materials'][primitive['material']].get('name','') if 'material' in primitive else '' for primitive in mesh['primitives']]
        rows.append(row)
    return {'animations':[a.get('name','') for a in doc.get('animations',[])],'nodes':rows,
            'note':'Source glTF node paths. Verify exact instantiated paths with Unity binding validation; unnamed/duplicate nodes can be renamed by the importer.'}

def validate(folder, builtin=False):
    try:
        from jsonschema import Draft202012Validator
    except ImportError as error:
        raise ValueError('Install SDK dependencies: python3 -m pip install -r character-sdk/requirements.txt') from error
    root=Path(folder).resolve(); manifest=read_json(root/'character.json')
    schema=read_json(Path(__file__).resolve().parents[1]/'schemas/character.schema.json')
    failures=list(Draft202012Validator(schema).iter_errors(manifest))
    if failures: raise ValueError('; '.join('/'.join(map(str,e.path))+': '+e.message for e in failures[:8]))
    m=manifest; warnings=[]
    if m['compatibility']['minApiMinor']>1: raise ValueError('runtime API minor version is too old')
    required=set(m['compatibility']['required'])
    if required-CAPABILITIES: raise ValueError('unknown required capabilities: '+str(sorted(required-CAPABILITIES)))
    warnings.extend('ignored optional capability '+v for v in set(m['compatibility']['optional'])-CAPABILITIES)
    if not builtin and any(v.startswith('legacy.') for v in required|set(m['compatibility']['optional'])):
        raise ValueError('legacy adapters are reserved for shipped migration assets')
    for key in ['actions','expressions','effects','interactions','behaviors','parameters']:
        ids=[v['id'] for v in m[key]]
        if len(ids)!=len(set(ids)): raise ValueError('duplicate IDs in '+key)
    actions={x['id'] for x in m['actions']}
    if 'Idle' not in actions: raise ValueError('an Idle action is required')
    if any(x['id']=='neutral' for x in m['expressions']): raise ValueError('neutral expression ID is reserved for release')
    if next(x for x in m['actions'] if x['id']=='Idle')['button']: raise ValueError('Idle cannot be an action button')
    if not m['rig']['head'] or not m['rig']['headRenderer']: raise ValueError('head and head renderer bindings are required')
    if bool(m['rig']['leftEye'])!=bool(m['rig']['rightEye']): raise ValueError('eyes must be supplied as a pair')
    available_capabilities=required|set(m['compatibility']['optional'])
    targets={'body':actions-{'Idle'}, 'expression':({'neutral'}|{x['id'] for x in m['expressions']}) if m['expressions'] else set(),
             'effect':{x['id'] for x in m['effects']},'gaze':{'camera','release'} if 'core.gaze@1' in available_capabilities else set(),'posture':{p['id'] for p in m.get('posture',{}).get('poses',[])}}
    posture_clips=validate_postures(m)
    for rule in m['behaviors']:
        for cue in rule['cues']:
            channel=cue['channel']
            if channel not in CHANNELS:
                if cue['required']: raise ValueError('unsupported required cue channel: '+channel)
                warnings.append('ignored optional cue channel '+channel); continue
            if cue['target'] not in targets[channel] and cue.get('fallback') not in targets[channel]:
                if cue['required']: raise ValueError('unresolved required cue '+rule['id']+'/'+cue['target'])
                warnings.append('optional cue will skip '+rule['id']+'/'+cue['target'])
    speech={(b['renderer'],b['shape']) for b in m['speech']['amplitude']}
    for v in m['speech']['visemes']: speech.update((b['renderer'],b['shape']) for b in v['bindings'])
    for expression in m['expressions']:
        if not expression['bindings']: raise ValueError('empty expression '+expression['id'])
        if speech & {(b['renderer'],b['shape']) for b in expression['bindings']}:
            raise ValueError('expression overlaps a speech-owned morph: '+expression['id'])
    for p in m['parameters']:
        if not p['min']<p['max']: raise ValueError('parameter range is empty: '+p['id'])
        if not p['min']<=p['initial']<=p['max']: raise ValueError('parameter default out of range: '+p['id'])
        if p['kind'] in ('color','variant') and len(p['options'])<2: raise ValueError('parameter needs options: '+p['id'])
        if p['kind']=='color' and any(not __import__('re').fullmatch(r'#[0-9A-Fa-f]{6}',value) for value in p['options']): raise ValueError('color options must be RGB hex')
        if p['kind']=='morph' and (p['min']!=0 or p['max']!=1): raise ValueError('morph parameters use normalized range 0..1')
        if p['kind']=='color' and any(b['property']!='baseColor' for b in p['bindings']): raise ValueError('portable color bindings use baseColor')
        if p['kind'] in ('color','variant') and (p['min']!=0 or p['max']!=len(p['options'])-1): raise ValueError('options must cover integer range 0..N-1')
        if p['kind']=='variant' and len(p['bindings'])!=len(p['options']): raise ValueError('variant option/binding count differs')
    expression_shapes={(b['renderer'],b['shape']) for e in m['expressions'] for b in e['bindings']}
    appearance=set()
    for p in m['parameters']:
        if p['kind']=='morph':
            for b in p['bindings']:
                for shape in [b['property'],b.get('negativeShape')]:
                    if shape: appearance.add((b['path'],shape))
    if appearance & (speech|expression_shapes): raise ValueError('appearance overlaps transient expression / speech morphs')
    if m['speech']['mode']=='amplitude' and not m['speech']['amplitude']: raise ValueError('amplitude mode needs bindings')
    if m['speech']['mode']=='viseme' and not m['speech']['visemes']: raise ValueError('viseme mode needs bindings')
    if 'core.animation@1' not in required: raise ValueError('core.animation@1 must be required')
    if m['behaviors'] and 'core.behavior@1' not in available_capabilities: raise ValueError('behavior rules need core.behavior@1')
    for path in [m['rig']['head'],m['rig']['neck'],m['rig']['leftEye'],m['rig']['rightEye'],m['rig']['headRenderer']]:
        if path: safe_path(root,path)
    if m['source']['format']=='builtin':
        if not builtin: raise ValueError('external character packages must provide GLB, not a builtin adapter')
        return m,warnings
    total=0; declared=set()
    for item in m['files']:
        path=safe_path(root,item['path']); declared.add(item['path'])
        if path.suffix.lower() in FORBIDDEN: raise ValueError('executable content is not a character asset: '+item['path'])
        if not path.is_file() or path.stat().st_size!=item['bytes']: raise ValueError('file missing or size mismatch: '+item['path'])
        if hashlib.sha256(path.read_bytes()).hexdigest()!=item['sha256']: raise ValueError('hash mismatch: '+item['path'])
        total+=item['bytes']
    if len(declared)!=len(m['files']): raise ValueError('duplicate files')
    if total>MAX_BYTES: raise ValueError('package exceeds 256 MiB source limit')
    actual={str(p.relative_to(root)) for p in root.rglob('*') if p.is_file() and p!=root/'character.json'}
    if actual!=declared: raise ValueError('unlisted / missing files: '+str(sorted(actual^declared)))
    for required_file in [m['source']['model'],m['license']['notice']]:
        if required_file not in declared: raise ValueError('required file missing from integrity list: '+required_file)
    doc=glb_document(safe_path(root,m['source']['model']))
    clip_list=[x.get('name','') for x in doc.get('animations',[])]
    if len(clip_list)!=len(set(clip_list)): raise ValueError('GLB animation names must be unique')
    clip_names=set(clip_list)
    for a in m['actions']:
        if a['clip'] not in clip_names: raise ValueError('animation absent from GLB: '+a['clip'])
    for clip in posture_clips:
        if clip not in clip_names: raise ValueError('posture animation absent from GLB: '+clip)
    validate_performances(m, safe_path(root,m['source']['model']))
    validate_autonomy(m, safe_path(root,m['source']['model']))
    from portable_avatar import validate as validate_avatar
    validate_avatar(root,m,read_json,safe_path,inspect_glb)
    vertices=sum(doc['accessors'][p['attributes']['POSITION']]['count'] for mesh in doc.get('meshes',[]) for p in mesh['primitives'])
    primitives=sum(len(mesh['primitives']) for mesh in doc.get('meshes',[]))
    # Portable author avatars retain alternate clothes/accessories. Count all
    # primitives for the storage ceiling; runtime active draws/FPS are reviewed
    # separately. 33 stored primitives must not reject a 30-draw default outfit.
    full_materials='core.materials.liltoon@1' in required
    if full_materials:
        from portable_avatar import validate_materials
        validate_materials(root,m,read_json,safe_path)
    primitive_limit=64 if bool({'core.avatar-controls@1','core.avatar-controls@2'} & required) or full_materials else 32
    if vertices>300000 or primitives>primitive_limit: raise ValueError(f'mobile source budget exceeded (300k vertices / {primitive_limit} primitives)')
    if any(len(s.get('joints',[]))>256 for s in doc.get('skins',[])): raise ValueError('skin exceeds 256 joints')
    warnings.append(f'geometry preflight: {vertices} vertices, {primitives} primitives; device FPS still needs measurement')
    return m,warnings

def validate_autonomy(m, model):
    p=m.get('autonomy')
    declared='core.autonomy@1' in m['compatibility']['required']+m['compatibility']['optional']
    if not p:
        if declared:raise ValueError('autonomy capability needs a profile')
        return
    if 'core.autonomy@1' not in m['compatibility']['required']+m['compatibility']['optional']:
        raise ValueError('autonomy must declare core.autonomy@1')
    data=inspect_glb(model);nodes={n['path']:n for n in data['nodes']}
    bindings=p['blink']['bindings']
    if len({(b['renderer'],b['shape']) for b in bindings})!=len(bindings):raise ValueError('duplicate autonomy lid')
    for b in bindings:
        if b['shape'] not in nodes.get(b['renderer'],{}).get('morphs',[]):raise ValueError('autonomy lid missing: '+b['shape'])
    speech={(b['renderer'],b['shape']) for b in m['speech']['amplitude']}
    speech|={(b['renderer'],b['shape']) for v in m['speech']['visemes'] for b in v['bindings']}
    if speech & {(b['renderer'],b['shape']) for b in bindings}:raise ValueError('autonomy blink overlaps speech')
    options={o['id']:o for o in m.get('performance',{}).get('options',[])}
    if any(i not in options for i in p['blink']['suppressOptions']):raise ValueError('autonomy suppression option missing')
    r=p.get('breathing')
    if r:
        if r['clip'] not in data['animations'] or any(b not in nodes for b in r['bones']):raise ValueError('autonomy breath binding missing')
        if any(options.get(i,{}).get('group')!='pose' or options[i].get('additive') for i in r['poseOptions']):raise ValueError('autonomy pose option invalid')


def validate_performances(m,model):
    """Mirror CharacterPerformanceContract before checking generated GLB bindings.

    Performance paths are bounded to 128 UTF-16 code units by the runtime, even
    though older shared schema definitions allow longer paths for other domains.
    """
    import math
    profile=m.get('performance')
    if profile is None:return
    def fail(message):raise ValueError('performance '+message)
    def name(value):
        return isinstance(value,str) and bool(value.strip()) and len(value.encode('utf-16-le',errors='surrogatepass'))//2<=128
    def path(value):
        return name(value) and not value.startswith('/') and '\\' not in value and all(p and p not in ('.','..') for p in value.split('/'))
    def bounded(values,limit,label):
        if not isinstance(values,list) or len(values)>limit:fail(label+' array is invalid or exceeds '+str(limit))
        return values
    def number(value,minimum,maximum):
        return isinstance(value,(int,float)) and not isinstance(value,bool) and minimum<=value<=maximum and math.isfinite(value)
    def distinct(values,label):
        if len(values)!=len(set(values)):fail('duplicate '+label)
    def shapes(values,label):
        values=bounded(values,256,label)
        for b in values:
            if not isinstance(b,dict) or not path(b.get('renderer')) or not name(b.get('shape')) or not number(b.get('weight'),0,1):
                fail(label+' binding path/name/weight is invalid (names and paths <=128 UTF-16 units)')
        distinct([(b['renderer'],b['shape']) for b in values],label+' binding')
    def visible(values,label):
        values=bounded(values,64,label)
        if any(not isinstance(b,dict) or not path(b.get('path')) for b in values):
            fail(label+' path is invalid (paths <=128 UTF-16 units)')
        distinct([b['path'] for b in values],label+' binding')
    if not isinstance(profile,dict) or profile.get('schemaVersion') not in (1,2,3):fail('schema is invalid')
    groups=bounded(profile.get('groups'),{1:6,2:32,3:128}[profile['schemaVersion']],'groups');options=bounded(profile.get('options'),2048 if profile['schemaVersion']==3 else 256,'options')
    visible(profile.get('defaults'),'defaults')
    allowed={'expression','pose','hands','ears','tail','appearance'}
    def valid_group(g):
        if not isinstance(g,dict) or not name(g.get('label')):return False
        if profile['schemaVersion']==1:return g.get('id') in allowed
        return isinstance(g.get('id'),str) and re.fullmatch(r'[a-z][a-z0-9_.-]{0,63}',g['id']) is not None
    if any(not valid_group(g) for g in groups):fail('group is invalid')
    group_ids=[g['id'] for g in groups];distinct(group_ids,'group')
    if any(not isinstance(o,dict) or not name(o.get('id')) for o in options):fail('option id is invalid')
    ids=[o['id'] for o in options];distinct(ids,'option')
    if 'core.performance@'+str(profile['schemaVersion']) not in set(m['compatibility']['required']+m['compatibility']['optional']):
        fail('profile must declare matching core.performance version')
    if profile['schemaVersion']>=2 and 'core.performance@'+str(profile['schemaVersion']) not in m['compatibility']['required']:
        fail('extensible groups require core.performance@2 in required capabilities')
    track_count=0
    for o in options:
        kind=o.get('kind','preset');bones=bounded(o.get('bones',[]),256,'bones');tracks=bounded(o.get('morphTracks',[]),256,'morphTracks')
        hint=o.get('ai')
        if hint is not None:
            if not isinstance(hint,dict) or not name(hint.get('intent')):fail('AI intent is invalid')
            effects=bounded(hint.get('effects'),8,'AI effects')
            if not effects or any(not name(e) for e in effects):fail('AI effects are invalid')
            moods=bounded(hint.get('moods',[]),16,'AI moods');conflicts=bounded(hint.get('conflicts',[]),32,'AI conflicts')
            if any(not name(v) for v in moods) or any(v not in group_ids or v==o.get('group') for v in conflicts):fail('AI moods/conflicts are invalid')
            if hint.get('kind','action') not in ('expression','action'):fail('AI performance kind is invalid')
            if not isinstance(hint.get('automatic'),bool) or not isinstance(hint.get('speechCompatible'),bool) or not number(hint.get('cooldownSeconds',3),0,300):fail('AI policy is invalid')
        if o.get('group') not in group_ids or not name(o.get('label')) or kind not in {'preset','motion','toggle'} or not number(o.get('duration',0),0,120):fail('option fields are invalid: '+o['id'])
        if any(not path(b) for b in bones):fail('bone path is invalid (paths <=128 UTF-16 units): '+o['id'])
        distinct(bones,'bone binding')
        if o.get('clip') and (not name(o['clip']) or not bones):fail('clip needs a valid name and bone bindings: '+o['id'])
        if kind=='motion' and not o.get('clip') and not tracks:fail('motion needs clip or morph tracks: '+o['id'])
        if o.get('offClip') and (kind!='toggle' or not name(o['offClip']) or not bones):fail('offClip requires toggle and valid clip/bones: '+o['id'])
        if o.get('next'):
            target=next((x for x in options if x['id']==o['next']),None)
            if kind!='motion' or o.get('loop',False) or target is None or target['id']==o['id'] or target.get('group')!=o['group'] or target.get('kind','preset')=='toggle':fail('invalid continuation: '+o['id'])
        for field in ('morphs','offMorphs'):shapes(o.get(field,[]),field)
        for field in ('visibility','offVisibility'):visible(o.get(field,[]),field)
        if kind!='toggle' and (o.get('offMorphs') or o.get('offVisibility')):fail('off bindings require toggle: '+o['id'])
        track_count+=len(tracks)
        if track_count>256:fail('profile exceeds 256 morph tracks')
        for track in tracks:
            if not isinstance(track,dict) or not path(track.get('renderer')) or not name(track.get('shape')):fail('morph track path/name is invalid (<=128 UTF-16 units)')
            keys=bounded(track.get('keys'),7201,'morph keys')
            if not keys:fail('morph track must contain keys')
            previous=-1
            for key in keys:
                if not isinstance(key,dict) or not number(key.get('time'),0,120) or key['time']<=previous or not number(key.get('value'),0,1):fail('morph key time/value is invalid; times must strictly increase')
                previous=key['time']
        distinct([(t['renderer'],t['shape']) for t in tracks],'morph track binding')
    for group in group_ids:
        if sum(o.get('group')==group and o.get('kind','preset')!='toggle' and bool(o.get('defaultOn',False)) for o in options)>1:
            fail('conflicting non-toggle defaults in group: '+group)
    inspected=inspect_glb(model);nodes={n['path']:n for n in inspected['nodes']};clips=set(inspected['animations'])
    for o in options:
        for key in ('clip','offClip'):
            if o.get(key) and o[key] not in clips:fail('clip absent from GLB: '+o[key])
        for bone in o.get('bones',[]):
            if bone not in nodes:fail('bone absent: '+bone)
        for field in ('morphs','offMorphs','morphTracks'):
            for b in o.get(field,[]):
                if b['shape'] not in nodes.get(b['renderer'],{}).get('morphs',[]):fail(field+' shape absent: '+b['renderer']+'/'+b['shape'])
        for field in ('visibility','offVisibility'):
            for b in o.get(field,[]):
                if 'materials' not in nodes.get(b['path'],{}):fail('renderer absent: '+b['path'])
    for b in profile['defaults']:
        if 'materials' not in nodes.get(b['path'],{}):fail('default renderer absent: '+b['path'])

def validate_postures(m):
    profile=m.get('posture'); clips=set()
    required=set(m['compatibility']['required'])
    if not profile:
        if 'core.posture@1' in required: raise ValueError('posture capability needs a profile')
        return clips
    if 'core.posture@1' not in required or m['compatibility']['minApiMinor']<1:
        raise ValueError('posture profiles require core.posture@1 and API minor 1')
    poses=profile['poses'];ids=[p['id'] for p in poses]
    if len(ids)!=len(set(ids)) or 'stand' not in ids: raise ValueError('posture IDs must be unique and include stand')
    if next(p for p in poses if p['id']=='stand')['clip']!='Idle': raise ValueError('standing posture must use Idle')
    for bone in profile['bones']:
        if not bone: raise ValueError('posture bones cannot animate the character placement root')
    for pose in poses:
        clips.add(pose['clip']);ps=pose['parameters'];pids=[p['id'] for p in ps]
        if len(pids)!=len(set(pids)): raise ValueError('duplicate posture parameter: '+pose['id'])
        for p in ps:
            if not p['min']<p['max'] or not p['min']<=p['initial']<=p['max']: raise ValueError('invalid posture parameter range: '+p['id'])
            if p['unit']=='normalized' and (p['min']<0 or p['max']>1): raise ValueError('normalized posture parameters stay in 0..1')
            clips.update([p['lowClip'],p['highClip']])
        aids=[a['action'] for a in pose['actions']]
        if len(aids)!=len(set(aids)) or not set(aids)<={a['id'] for a in m['actions']} - {'Idle'}: raise ValueError('invalid posture action map: '+pose['id'])
        clips.update(a['clip'] for a in pose['actions'])
    if len(clips)>256: raise ValueError('posture clip budget exceeds 256')
    return clips

def posture_compatibility(old,new):
    changes=[]
    old_poses={p['id']:p for p in old.get('posture',{}).get('poses',[])}
    new_poses={p['id']:p for p in new.get('posture',{}).get('poses',[])}
    for id,p in old_poses.items():
        if id not in new_poses: changes.append('posture removed: '+id);continue
        q=new_poses[id]
        if p['support']!=q['support']: changes.append('posture support changed: '+id)
        new_params={v['id']:v for v in q['parameters']}
        for v in p['parameters']:
            n=new_params.get(v['id'])
            if n is None or any(v[k]!=n[k] for k in ['unit','min','max','initial']): changes.append('posture saved-value semantics changed: '+id+'/'+v['id'])
        if {a['action'] for a in p['actions']}-{a['action'] for a in q['actions']}: changes.append('posture action removed: '+id)
    return changes

def seal(folder):
    root=Path(folder).resolve(); m=read_json(root/'character.json'); rows=[]
    for path in sorted(root.rglob('*')):
        if path.is_symlink(): raise ValueError('no symlinks in source packages')
        if not path.is_file() or path==root/'character.json': continue
        data=path.read_bytes(); rows.append(dict(path=str(path.relative_to(root)),bytes=len(data),sha256=hashlib.sha256(data).hexdigest()))
    m['files']=rows; (root/'character.json').write_text(json.dumps(m,ensure_ascii=False,indent=2)+'\n')

def unpack(archive, destination):
    destination=Path(destination).resolve()
    if destination.exists(): raise ValueError('extract destination must be new')
    with zipfile.ZipFile(archive) as z:
        infos=z.infolist()
        if len(infos)>512 or sum(i.file_size for i in infos)>MAX_BYTES: raise ValueError('archive budget exceeded')
        seen=set()
        for info in infos:
            safe_path(destination,info.filename)
            if info.filename in seen or (info.external_attr>>16)&0o170000==0o120000: raise ValueError('duplicate archive entry / symlink')
            seen.add(info.filename)
        destination.mkdir(parents=True)
        for info in infos:
            target=safe_path(destination,info.filename)
            if info.is_dir(): target.mkdir(parents=True,exist_ok=True)
            else: target.parent.mkdir(parents=True,exist_ok=True); target.write_bytes(z.read(info))
    return destination

def main():
    p=argparse.ArgumentParser(description=__doc__); sub=p.add_subparsers(dest='command',required=True)
    for name in ['validate','seal','pack']:
        command=sub.add_parser(name); command.add_argument('folder',type=Path)
        if name=='validate': command.add_argument('--builtin',action='store_true')
        if name=='pack': command.add_argument('output',type=Path)
    inspect=sub.add_parser('inspect'); inspect.add_argument('model',type=Path)
    compare=sub.add_parser('compare'); compare.add_argument('old',type=Path); compare.add_argument('new',type=Path)
    args=p.parse_args()
    try:
        if args.command=='inspect':
            print(json.dumps(inspect_glb(args.model),ensure_ascii=False,indent=2));return 0
        if args.command=='compare':
            old,new=read_json(args.old),read_json(args.new)
            changes=[]
            changes.extend(posture_compatibility(old,new))
            old_version=tuple(map(int,old['packageVersion'].split('.')));new_version=tuple(map(int,new['packageVersion'].split('.')))
            if new_version<old_version: changes.append('package version downgrade requires explicit migration review')
            if new_version==old_version and old!=new: changes.append('content changed without a packageVersion bump')
            if old.get('schemaVersion')!=new.get('schemaVersion') or old['compatibility']['apiMajor']!=new['compatibility']['apiMajor']: changes.append('major contract version changed')
            if old['packageId']!=new['packageId']: changes.append('publisher/package identity changed')
            if new['compatibility']['minApiMinor']>old['compatibility']['minApiMinor']: changes.append('higher runtime minor required')
            if old['id']!=new['id']: changes.append('identity changed: creates a separate user profile')
            for key in ['actions','expressions','parameters','effects','interactions']:
                removed={x['id'] for x in old[key]}-{x['id'] for x in new[key]}
                if removed: changes.append(key+' removed: '+', '.join(sorted(removed)))
            old_params={x['id']:x for x in old['parameters']}
            for param in new['parameters']:
                previous=old_params.get(param['id'])
                if previous and any(previous.get(k)!=param.get(k) for k in ['kind','min','max','options']): changes.append('parameter saved-value semantics changed: '+param['id'])
            added=set(new['compatibility']['required'])-set(old['compatibility']['required'])
            if added: changes.append('new required capabilities: '+', '.join(sorted(added)))
            print(json.dumps(dict(compatible=not changes,review=changes),ensure_ascii=False,indent=2)); return 1 if changes else 0
        if args.command=='seal': seal(args.folder)
        m,warnings=validate(args.folder,getattr(args,'builtin',False))
        if args.command=='pack':
            if args.output.resolve().is_relative_to(args.folder.resolve()): raise ValueError('archive output must be outside the package')
            with zipfile.ZipFile(args.output,'w',zipfile.ZIP_DEFLATED) as z:
                for path in sorted(args.folder.rglob('*')):
                    if path.is_file(): z.write(path,str(path.relative_to(args.folder)))
        print(json.dumps(dict(status='PASS',id=m['id'],version=m['packageVersion'],warnings=warnings),ensure_ascii=False,indent=2)); return 0
    except (ValueError,OSError,KeyError,zipfile.BadZipFile) as e:
        print(json.dumps(dict(status='FAIL',error=str(e)),ensure_ascii=False),file=sys.stderr); return 1

if __name__=='__main__': sys.exit(main())
