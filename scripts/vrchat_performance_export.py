"""Convert trusted Unity Avatar samples into portable glTF Transform clips.

The installed glTFast importer mirrors X (not Z). Normalize each source joint
through its parent's world rest basis and the target bone's bind basis; this
also removes the FBX armature's -90-degree wrapper without double rotation.
"""
import json,copy
from pathlib import Path
import numpy as np
from prepare_anime_characters import ROOT, multiply, normalize, paths
from prepare_portrait_vrm import world_rest_rotations

MIRROR_Q=np.array([1.,-1.,-1.,1.])
MIRROR_P=np.array([-1.,1.,1.])
INVERSE=np.array([-1.,-1.,-1.,1.])

def source_recipe(role, catalog_path=None, samples_path=None):
    catalog=json.loads(Path(catalog_path or ROOT/'docs/verification/vrchat-performance/catalog.json').read_text())
    recipe=copy.deepcopy(next(c for c in catalog['characters'] if c['role']==role))
    samples=json.loads(Path(samples_path or ROOT/'.local/vrchat-stage/Inspection/Performances'/f'{role}.json').read_text())
    recipe['sampledMorphs']={m['path']:m['tracks'] for m in samples['morphMotions']}
    return recipe

def requested_shapes(recipe):
    keep={}
    for option in recipe['performance']['options']:
        for key in ('sourceClip','sourceOffClip'):
            for track in recipe['sampledMorphs'].get(option.get(key),[]):
                if max(track['values'])>1e-6 and not track['shape'].startswith('vrc.v.'):
                    keep.setdefault(track['renderer'].split('/')[-1],set()).add(track['shape'])
    return keep

def convert_profile(b,inspection,recipe,motion_map,morph_scales=None):
    g=b.doc;p=paths(g);by_name={n['name']:i for i,n in enumerate(g['nodes'])};notes=[]
    profile=copy.deepcopy(recipe['performance']);profile['schemaVersion']=1;profile.pop('version',None)
    profile['defaults']=[dict(path=p[by_name[s['name']]],visible=bool(s['active'] and s['enabled'])) for s in inspection['skins']]
    def renderer(path):
        index=by_name.get(path.split('/')[-1]);n=g['nodes'][index] if index is not None else {}
        return (index,n) if 'mesh' in n else (None,None)
    def shapes(values):
        result=[]
        for value in values:
            index,node=renderer(value['renderer'])
            if index is None or value['shape'].startswith('vrc.v.'):continue
            available=g['meshes'][node['mesh']].get('extras',{}).get('targetNames',[])
            gain=(morph_scales or {}).get((value['renderer'].split('/')[-1],value['shape']),1)
            if value['shape'] in available:result.append(dict(renderer=p[index],shape=value['shape'],weight=float(np.clip(value['weight']/100/gain,0,1))))
        return result
    def visibility(values,option):
        result={}
        for value in values:
            index,node=renderer(value['path'])
            if index is None:
                notes.append(dict(option=option,sourcePath=value['path'],reason='Source helper/SDK object or separate prefab is not a renderer in the converted FBX'));continue
            result[p[index]]=bool(value['visible'])
        return [dict(path=k,visible=v) for k,v in result.items()]
    options=[]
    for option in profile['options']:
        source=option.pop('sourceClip');off=option.pop('sourceOffClip',None);option.pop('sourceMorphCurves',None)
        option['morphs']=shapes(option.get('morphs',[]));option['offMorphs']=shapes(option.get('offMorphs',[]))
        option['visibility']=visibility(option.get('visibility',[]),option['id']);option['offVisibility']=visibility(option.get('offVisibility',[]),option['id'])
        option['morphTracks']=[]
        for track in recipe['sampledMorphs'].get(source,[]):
            index,node=renderer(track['renderer'])
            if index is None or track['shape'].startswith('vrc.v.'):continue
            available=g['meshes'][node['mesh']].get('extras',{}).get('targetNames',[])
            if track['shape'] not in available or max(track['values'])-min(track['values'])<1e-5:continue
            gain=(morph_scales or {}).get((track['renderer'].split('/')[-1],track['shape']),1)
            if max(track['values'])/gain>1.0001 or min(track['values'])/gain<-.0001:
                notes.append(dict(option=option['id'],shape=track['shape'],reason='Source morph overdrive limited to normalized 0..1',sourceMin=min(track['values']),sourceMax=max(track['values'])))
            option['morphTracks'].append(dict(renderer=p[index],shape=track['shape'],keys=[dict(time=float(t),value=float(np.clip(v/gain,0,1))) for t,v in zip(track['times'],track['values'])]))
        if source in motion_map:
            motion=motion_map[source];option.update({k:motion[k] for k in ('clip','bones','duration','loop','additive')})
            if motion['sourceDuration']==0:option['loop']=True
        if off in motion_map:
            option['offClip']=motion_map[off]['clip'];option['bones']=sorted(set(option['bones']+motion_map[off]['bones']))
        if option['group']=='expression':option['kind']='preset'
        if option['group'] in ('ears','tail') and not option.get('loop'):
            option['kind']='preset'
        if option['id']=='kipfel-afk-stand-to-sleep':option['next']='kipfel-afk-sleep-loop'
        if not any(option.get(k) for k in ['clip','offClip','morphs','morphTracks','visibility','offMorphs','offVisibility']):
            notes.append(dict(option=option['id'],sourceClip=source,reason='No available visual binding after main-FBX conversion; not shown as a working control'));continue
        option['description']='';options.append(option)
    profile['options']=options
    profile['groups']=[dict(id=v['id'],label=v['label'],symbol={'expression':'face.smiling','pose':'figure.stand','hands':'hand.wave','ears':'ear','tail':'wind','appearance':'sparkles'}[v['id']]) for v in profile['groups'] if any(o['group']==v['id'] for o in options)]
    return profile,notes

def vector(value,axes):return np.array([value[x] for x in axes],dtype=np.float64)
def rotate(q,v):
    q=normalize(q);xyz=q[:3]
    return v+2*np.cross(xyz,np.cross(xyz,v)+q[3]*v)

def append_source_motions(b,role):
    source=json.loads((ROOT/'.local/vrchat-stage/Inspection/Performances'/f'{role}.json').read_text())
    g=b.doc;target_paths=paths(g);parents,world=world_rest_rotations(g)
    by_name={}
    for i,n in enumerate(g['nodes']):by_name.setdefault(n['name'],[]).append(i)
    def target(path):
        matches=by_name.get(path.split('/')[-1],[])
        if len(matches)!=1:raise ValueError('Ambiguous or missing author motion node: '+path)
        return matches[0]
    rest={x['path']:x for x in source['rest']};result={};notes=[];base_clips=list(g.get('animations',[]));affected=set()
    for motion in source['motions']:
        name='VRC_'+motion['name'];tracks=[];animation=dict(name=name,samplers=[],channels=[])
        additive=motion['name'].endswith('_breath')
        for track in motion['tracks']:
            node=target(track['path']);s=rest[track['path']]
            source_parent=vector(s['parentWorldRotation'],'xyzw')*MIRROR_Q
            source_world=vector(s['worldRotation'],'xyzw')*MIRROR_Q
            target_parent=world[parents[node]] if node in parents else np.array([0,0,0,1.])
            prefix=multiply(target_parent*INVERSE,source_parent)
            suffix=multiply(source_world*INVERSE,world[node])
            rotations=normalize(multiply(multiply(prefix,np.array([vector(q,'xyzw') for q in track['rotations']])*MIRROR_Q),suffix))
            source_rest=vector(s['rotation'],'xyzw')*MIRROR_Q
            test=normalize(multiply(multiply(prefix,source_rest),suffix))
            actual=np.array(g['nodes'][node].get('rotation',[0,0,0,1.]))
            if abs(np.dot(test,actual))<.99999:raise ValueError('Rest-basis conversion failed: '+track['path'])
            positions=np.array(g['nodes'][node].get('translation',[0,0,0.]))+rotate(prefix,(np.array([vector(v,'xyz') for v in track['positions']])-vector(s['position'],'xyz'))*MIRROR_P*2)
            times=np.array(track['times'],np.float32)
            if motion['duration']==0:times=np.array([0.,1.],np.float32)
            for i in range(1,len(rotations)):
                if np.dot(rotations[i-1],rotations[i])<0:rotations[i]*=-1
            # Additive breath clips contain an otherwise fixed Humanoid pose.
            # Export only actually varying channels; Unity's additive layer
            # uses the first key as reference, keeping the host idle intact.
            use_rotation=not additive or np.max(np.abs(rotations-rotations[0]))>1e-5
            use_position=(np.max(np.abs(positions-positions[0]))>1e-5 if additive else np.max(np.abs(positions-np.array(g['nodes'][node].get('translation',[0,0,0.]))))>1e-5)
            if not(use_rotation or use_position):continue
            inputs=b.add(times,'SCALAR');tracks.append(target_paths[node])
            for prop,values,kind,use in [('rotation',rotations,'VEC4',use_rotation),('translation',positions,'VEC3',use_position)]:
                if not use:continue
                if not np.isfinite(values).all():raise ValueError('Nonfinite source motion: '+name)
                output=b.add(values,kind)
                animation['channels'].append(dict(sampler=len(animation['samplers']),target=dict(node=node,path=prop)))
                animation['samplers'].append(dict(input=inputs,output=output,interpolation='LINEAR'))
                affected.add((node,prop))
        if not tracks:
            notes.append(dict(source=motion['path'],reason='No varying additive Transform channels'));continue
        g.setdefault('animations',[]).append(animation)
        result[motion['path']]=dict(clip=name,bones=tracks,duration=max(motion['duration'],1. if motion['duration']==0 else 0),loop=motion['loop'],additive=additive,sourceDuration=motion['duration'])
    # A stopped overlay must always have a keyed lower layer to blend back to,
    # including fingers, ears, tails and accessory bones absent from VRMA idle.
    for animation in base_clips:
        present={(c['target']['node'],c['target']['path']) for c in animation['channels']}
        duration=max(float(np.max(b.array(s['input']))) for s in animation['samplers'])
        inputs=b.add(np.array([0.,duration]),'SCALAR')
        for node,prop in sorted(affected-present):
            key='rotation' if prop=='rotation' else 'translation'
            value=np.array(g['nodes'][node].get(key,[0,0,0,1.] if key=='rotation' else [0,0,0.]))
            output=b.add(np.tile(value,(2,1)),'VEC4' if prop=='rotation' else 'VEC3')
            animation['channels'].append(dict(sampler=len(animation['samplers']),target=dict(node=node,path=prop)))
            animation['samplers'].append(dict(input=inputs,output=output,interpolation='LINEAR'))
    return result,notes


def append_source_idle(b,role,motions,profile):
    """Restore source standing + its additive breath without a host idle recipe.

    The default breath and the explicit breath option share this exact clip, so
    selecting the source option cannot double the additive movement. Other pose
    options retain their original clips and can fully replace the standing pose.
    Source clips, samples and archives remain intact for verification/reconversion.
    """
    names={
        'kipfel':('kipfel_stand_still','kipfel_breath'),
        'mamehinata':('Mamehinata_stand','Mamehinata_breath'),
    }
    stand_name,breath_name=names[role]
    def original(name):
        matches=[(path,data) for path,data in motions.items() if data['clip']=='VRC_'+name]
        if len(matches)!=1:raise ValueError('Original idle source missing: '+name)
        return matches[0]
    stand_path,stand=original(stand_name);breath_path,breath=original(breath_name)
    g=b.doc;p=paths(g);clips={a['name']:a for a in g['animations']}
    def channels(clip):
        result={}
        for channel in clip['channels']:
            sampler=clip['samplers'][channel['sampler']]
            result[(channel['target']['node'],channel['target']['path'])]=(b.array(sampler['input']),b.array(sampler['output']))
        return result
    standing=channels(clips[stand['clip']]);breathing=channels(clips[breath['clip']])
    if any(np.max(np.abs(value-value[0]))>1e-5 for times,value in standing.values()):
        raise ValueError('Original standing reference unexpectedly contains motion')
    # Key every transform touched by an original performance. This is a source
    # rest baseline, including the author's fingers/ears/props; no new motion.
    affected={(c['target']['node'],c['target']['path']) for a in g['animations'] for c in a['channels']}
    animation=dict(name='Idle',samplers=[],channels=[])
    composition=[];duration=breath['duration']
    for node,prop in sorted(affected):
        if prop not in ('rotation','translation','scale'):raise ValueError('Unexpected original idle channel: '+prop)
        default=[0,0,0,1.] if prop=='rotation' else [1,1,1.] if prop=='scale' else [0,0,0.]
        base=np.asarray(standing[(node,prop)][1][0] if (node,prop) in standing else g['nodes'][node].get(prop,default),dtype=np.float64)
        if (node,prop) in breathing:
            times,source=breathing[(node,prop)]
            source=np.asarray(source,dtype=np.float64)
            if prop=='rotation':
                delta=multiply(normalize(source[0])*INVERSE,normalize(source))
                values=normalize(multiply(base,delta))
                recovered=multiply(normalize(base)*INVERSE,values)
                error=float(np.max(np.abs(recovered-delta)))
            else:
                delta=source-source[0];values=base+delta
                error=float(np.max(np.abs((values-base)-delta)))
            if error>1e-6:raise ValueError('Source idle composition changed original movement')
            composition.append(dict(bone=p[node],property=prop,samples=len(times),maxReconstructionError=error))
        else:
            times=np.array([0.,duration]);values=np.tile(base,(2,1))
        output=b.add(values,'VEC4' if prop=='rotation' else 'VEC3')
        animation['channels'].append(dict(sampler=len(animation['samplers']),target=dict(node=node,path=prop)))
        animation['samplers'].append(dict(input=b.add(times,'SCALAR'),output=output,interpolation='LINEAR'))
    g['animations'].insert(0,animation)
    breath_option=next(o for o in profile['options'] if o.get('clip')==breath['clip'])
    breath_option.update(clip='Idle',bones=sorted({p[node] for node,prop in affected}),additive=False,duration=duration,loop=True)
    return dict(clip='Idle',duration=duration,sourceStand=stand_path,sourceBreath=breath_path,
        sourceStandClip=stand['clip'],sourceBreathClip=breath['clip'],
        method='Source stand + source additive breath, first-key reference; rotation stand * inverse(breath[0]) * breath[t], translation stand + breath[t] - breath[0].',
        timing='Original sampled source times, unchanged speed and amplitude; no smoothing, procedural breathing, blink schedule or extra gestures.',
        breathSelection='Shares Idle as a non-additive full-body source composition; never stacks breath twice.',
        channels=composition)
