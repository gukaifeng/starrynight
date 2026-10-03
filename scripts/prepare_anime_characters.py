#!/usr/bin/env python3
"""Reproducible VRoid CC0 + Overte Apache-2.0 -> portable, animated XCP packages.

Run with .local/character-venv/bin/python. Source files are pinned in the lock file;
--fetch downloads only those public URLs and checks their SHA-256 before use.
No downloaded code runs and no VRM/FBX interpreter ships in the mobile player.
"""
from __future__ import annotations
import argparse, copy, hashlib, json, math, struct, subprocess, urllib.request
from collections import defaultdict
from pathlib import Path
import numpy as np

ROOT = Path(__file__).resolve().parents[1]
SOURCES = ROOT / '.local/sources/anime-ensemble'
LOCK = ROOT / 'assets/characters/anime-sources.lock.json'
DTYPES = {5121:'u1',5123:'<u2',5125:'<u4',5126:'<f4'}
WIDTH = {'SCALAR':1,'VEC2':2,'VEC3':3,'VEC4':4,'MAT4':16}
ROLES = [
    dict(id='anime-vita', file='Vita.vrm', name='小光', original='Vita · VRoid CC0',
         description='银白短发、异色眼睛的幻想伙伴。对夜空和新鲜事充满好奇，喜欢和你交换今天的小发现。',
         invitation='今天，有什么让你眼睛一亮的事？', tagline='把小小的发现，说给我听', symbol='sparkle', environment='studio', speed=1.02),
    dict(id='anime-shino', file='Sendagaya_Shino.vrm', name='小诗', original='Sendagaya Shino · VRoid CC0',
         description='深蓝长发的安静伙伴。喜欢书、微风和慢一点的日常，愿意认真听完你的每一句话。',
         invitation='不用急，我们慢慢聊。', tagline='有些心事，适合慢慢说', symbol='book.closed', environment='sunroom', speed=.90),
    dict(id='anime-fumiriya', file='Sakurada_Fumiriya.vrm', name='晴川', original='Sakurada Fumiriya · VRoid CC0',
         description='短发蓝眼的清爽少年。喜欢散步、音乐和轻松的闲聊，也会陪你认真想一个难题。',
         invitation='走了一天，来这里歇一会儿吧。', tagline='陪你聊日常，也陪你想远方', symbol='wind', environment='courtyard', speed=.96),
]
# Each is an actual authored Overte animation, distributed as Apache-2.0 VRMA by
# Hanami. Keep the source's joint timing; bake endpoint alignment and retargeting.
MOTIONS = [
    ('Idle','idle','待机','idle','figure.stand','follow'),
    ('Hello','raise-hand','抬手招呼','greeting','hand.wave','follow'),
    ('Yes','nod','轻轻点头','agreement','checkmark','soft'),
    ('No','shake','摇摇头','disagreement','arrow.left.and.right','soft'),
    ('Listen','neutral','侧耳倾听','listening','ear','soft'),
    ('Think','think','想一想','thinking','sparkle','soft'),
    ('Talk','idle-talking','轻声讲述','speaking','quote.bubble','follow'),
    ('Relax','relaxed','放松一下','relaxed','leaf','release'),
    ('Thanks','nod-5','认真回应','gratitude','heart','soft'),
]

class GLB:
    def __init__(self,path):
        raw=path.read_bytes(); size=struct.unpack_from('<I',raw,12)[0]
        assert raw[:4]==b'glTF' and len(raw)==struct.unpack_from('<I',raw,8)[0]
        self.doc=json.loads(raw[20:20+size]); self.data=bytearray(raw[28+size:])
    def array(self,index):
        a=self.doc['accessors'][index]; v=self.doc['bufferViews'][a['bufferView']]
        assert 'sparse' not in a and 'byteStride' not in v
        return np.frombuffer(self.data,dtype=DTYPES[a['componentType']],count=a['count']*WIDTH[a['type']],offset=v.get('byteOffset',0)+a.get('byteOffset',0)).reshape(a['count'],WIDTH[a['type']]).copy()
    def add(self,values,kind,component=5126):
        values=np.asarray(values,dtype=DTYPES[component]).reshape(-1,WIDTH[kind]); self.data.extend(b'\0'*(-len(self.data)%4))
        view=len(self.doc['bufferViews']); self.doc['bufferViews'].append(dict(buffer=0,byteOffset=len(self.data),byteLength=values.nbytes));self.data.extend(values.tobytes())
        result=len(self.doc['accessors']);self.doc['accessors'].append(dict(bufferView=view,componentType=component,count=len(values),type=kind,min=values.min(axis=0).tolist(),max=values.max(axis=0).tolist()));return result
    def write(self,path):
        self.data.extend(b'\0'*(-len(self.data)%4));self.doc['buffers']=[dict(byteLength=len(self.data))]
        encoded=json.dumps(self.doc,separators=(',',':'),ensure_ascii=False).encode();encoded+=b' '*(-len(encoded)%4)
        path.write_bytes(struct.pack('<4sII',b'glTF',2,28+len(encoded)+len(self.data))+struct.pack('<II',len(encoded),0x4e4f534a)+encoded+struct.pack('<II',len(self.data),0x004e4942)+self.data)

def normalize(q):return q/np.maximum(1e-12,np.linalg.norm(q,axis=-1,keepdims=True))
def slerp(a,b,t):
    a,b=np.broadcast_arrays(a,b);b=np.where(np.sum(a*b,axis=-1,keepdims=True)<0,-b,b)
    dot=np.clip(np.sum(a*b,axis=-1,keepdims=True),-1,1);theta=np.arccos(dot);t=np.asarray(t)[...,None]
    sine=np.sin(theta);return normalize(np.where(sine>1e-5,(np.sin((1-t)*theta)*a+np.sin(t*theta)*b)/np.maximum(sine,1e-12),(1-t)*a+t*b))
def smooth(t):
    t=np.clip(t,0,1);return t*t*t*(10+t*(-15+6*t))
def multiply(a,b):
    a,b=np.broadcast_arrays(a,b);xyz=a[...,3:]*b[...,:3]+b[...,3:]*a[...,:3]+np.cross(a[...,:3],b[...,:3]);return np.concatenate([xyz,a[...,3:]*b[...,3:]-np.sum(a[...,:3]*b[...,:3],axis=-1,keepdims=True)],axis=-1)
def axis_q(axis,degrees):
    out=np.zeros((len(np.atleast_1d(degrees)),4));r=np.radians(np.atleast_1d(degrees))/2;out[:,axis]=np.sin(r);out[:,3]=np.cos(r);return out

def paths(g):
    parents={c:i for i,n in enumerate(g['nodes'])for c in n.get('children',[])}
    def path(i):return (path(parents[i])+'/' if i in parents else '')+g['nodes'][i]['name']
    return {i:path(i) for i in range(len(g['nodes']))}

def motion_tracks(name):
    b=GLB(SOURCES/(name+'.vrma'));g=b.doc;human={v['node']:k for k,v in g['extensions']['VRMC_vrm_animation']['humanoid']['humanBones'].items()};out={}
    parents={c:i for i,n in enumerate(g['nodes'])for c in n.get('children',[])};world={}
    def rest(i):
        if i not in world:world[i]=normalize(multiply(rest(parents[i]) if i in parents else np.array([0,0,0,1]),np.array(g['nodes'][i].get('rotation',[0,0,0,1]))))
        return world[i]
    for ch in g['animations'][0]['channels']:
        if ch['target']['node'] not in human:continue
        s=g['animations'][0]['samplers'][ch['sampler']];assert s.get('interpolation','LINEAR')=='LINEAR'
        node=ch['target']['node'];values=b.array(s['output'])
        if ch['target']['path']=='rotation':
            parent=parents.get(node)
            while parent is not None and parent not in human:parent=parents.get(parent)
            # Same normalization as pixiv/three-vrm VRMAnimationLoaderPlugin:
            # parentWorldRest * localKey * inverse(boneWorldRest). Directly
            # copying local rotations is wrong for FBX-derived VRMA bone axes.
            values=normalize(multiply(multiply(rest(parent) if parent is not None else np.array([0,0,0,1]),values),rest(node)*[-1,-1,-1,1]))
        out[(human[node],ch['target']['path'])]=(b.array(s['input'])[:,0],values)
    return out

def resample(track,times,rotation=True):
    t,v=track;left=np.clip(np.searchsorted(t,times,side='right')-1,0,len(t)-2);weight=np.clip((times-t[left])/np.maximum(1e-9,t[left+1]-t[left]),0,1)
    return slerp(v[left],v[left+1],weight) if rotation else v[left]*(1-weight[:,None])+v[left+1]*weight[:,None]

def package(role,index):
    b=GLB(SOURCES/role['file']);g=b.doc;vrm=g['extensions']['VRM'];assert vrm['meta']['licenseName']=='CC0'
    human={x['bone']:x['node']for x in vrm['humanoid']['humanBones']};p=paths(g)
    for side in ['left','right']:
        human[side+'ThumbMetacarpal']=human[side+'ThumbProximal'];human[side+'ThumbProximal']=human[side+'ThumbIntermediate']
    # All mapped VRoid joints use a normalized identity bind orientation. Refuse
    # silently retargeting arbitrary VRMs that need a different basis converter.
    for i in set(human.values()):assert np.linalg.norm(np.array(g['nodes'][i].get('rotation',[0,0,0,1]))-[0,0,0,1])<1e-5
    folder=ROOT/'character-packages/imported'/role['id'];folder.mkdir(parents=True,exist_ok=True)
    before=sum(len(m['primitives'])for m in g['meshes'])
    for mesh in g['meshes']:
        if 'extras' in mesh['primitives'][0]:mesh['extras']=copy.deepcopy(mesh['primitives'][0]['extras'])
        groups=defaultdict(list)
        for prim in mesh['primitives']:
            key=json.dumps({k:v for k,v in prim.items()if k!='indices'},sort_keys=True);groups[key].append(prim)
        merged=[]
        for prims in groups.values():
            prim=copy.deepcopy(prims[0]);prim['indices']=b.add(np.concatenate([b.array(x['indices'])for x in prims]),'SCALAR',5125);merged.append(prim)
        mesh['primitives']=merged
    # Move VRM-only expression names to standard glTF mesh extras. Strip the
    # runtime VRM extension; this app owns gaze, speech, and secondary motion.
    g.pop('extensions',None);g.pop('extensionsRequired',None);g.pop('extensionsUsed',None)
    for material in g['materials']:
        material.pop('extensions',None);material['doubleSided']=True
        material.get('pbrMetallicRoughness',{})['metallicFactor']=0
        # Opaque hair uses depth, predictable shadows, and fewer transparent layers.
        if 'Hair' in material['name'] and material.get('alphaMode')=='BLEND':material.update(alphaMode='MASK',alphaCutoff=.25)
    # Reuse identical PNG bytes through Unity's TextureImporter, which supplies
    # actual mobile ASTC + mipmaps. Embedded glTF textures alone remain RGBA32.
    textures=folder/'textures';textures.mkdir(exist_ok=True);materials=[]
    def extract_texture(index,kind):
        if index is None or index<0:return ''
        image=g['images'][g['textures'][index]['source']];view=g['bufferViews'][image['bufferView']]
        file=f'textures/{kind}_{index}.png';start=view.get('byteOffset',0)
        (folder/file).write_bytes(b.data[start:start+view['byteLength']]);return file
    authored={m['name']:m for m in vrm['materialProperties']}
    for material in g['materials']:
        pm=material['pbrMetallicRoughness'];texture=pm.get('baseColorTexture')
        file=extract_texture(texture['index'],'base') if texture else ''
        original=authored[material['name']];maps=original['textureProperties'];shade=original['vectorProperties'].get('_ShadeColor',[.82,.8,.87,1])
        color=pm.get('baseColorFactor',[1,1,1,1]);materials.append(dict(name=material['name'],texture=file,
            normal=extract_texture(maps.get('_BumpMap'),'normal'),matcap=extract_texture(maps.get('_SphereAdd'),'matcap') if 'HAIR' in material['name'] else '',
            shadeColor=dict(r=shade[0],g=shade[1],b=shade[2],a=shade[3]),
            color=dict(r=color[0],g=color[1],b=color[2],a=color[3]),alphaMode=material.get('alphaMode','OPAQUE'),cutoff=material.get('alphaCutoff',.5)))
    (folder/'materials.json').write_text(json.dumps(dict(schemaVersion=1,materials=materials),indent=2)+'\n')
    g['asset']['generator']='Starry XCP converter 1.1 / VRoid CC0 + Overte Apache-2.0'
    g['animations']=[];idle=motion_tracks('idle');hip=np.array(g['nodes'][human['hips']]['translation']);source_hip=idle[('hips','translation')][1][0];ratio=hip[1]/source_hip[1]
    # VRM 0 faces -Z. VRMA 1 uses +Z: conjugate by a Y half-turn. glTFast then
    # performs its normal glTF -> Unity handedness conversion exactly once.
    baseline={bone:resample(track,np.array([0]))[0]*np.array([-1,1,-1,1])for (bone,kind),track in idle.items()if kind=='rotation' and bone in human and 'Eye' not in bone}
    durations={}
    for action,name,*_ in MOTIONS:
        tracks=motion_tracks(name);source_duration=max(t[-1] for t,v in tracks.values())
        duration=30.0 if action=='Idle' else source_duration
        relaxed=motion_tracks('relaxed') if action=='Idle' else None
        # Keep the complete gesture; modest retiming makes the raised-hand greeting
        # conversational without cutting through its recovery phase.
        speed=1.30 if name=='raise-hand' else 1
        durations[action]=float(duration/speed);times=np.linspace(0,duration,int(math.ceil(duration*30))+1)
        blend=smooth(times/.48)*smooth((duration-times)/.58) if action!='Idle' else np.ones_like(times)
        clip=dict(name=action,samplers=[],channels=[]);time_index=b.add(times/speed,'SCALAR')
        for bone,node in human.items():
            if 'Eye' in bone or bone not in baseline:continue
            sample_times=np.mod(times,source_duration) if action=='Idle' else times
            q=resample(tracks.get((bone,'rotation'),idle[(bone,'rotation')]),sample_times)*np.array([-1,1,-1,1])
            if action=='Idle':
                # Reuse the authored idle's coordinated joints, then blend in two
                # small, slow portions of an authored relaxed posture. A 30-second
                # cycle avoids the mannequin-like identical ten-second repetition.
                loop=smooth(sample_times/.5)*smooth((source_duration-sample_times)/.5)
                q=slerp(baseline[bone],q,loop)
                if bone in ['spine','chest','upperChest','neck','head','leftShoulder','rightShoulder','leftUpperArm','rightUpperArm','leftLowerArm','rightLowerArm','leftHand','rightHand'] and (bone,'rotation') in relaxed:
                    rt=relaxed[(bone,'rotation')]
                    rq=resample(rt,np.mod(times*.42,rt[0][-1]))*np.array([-1,1,-1,1])
                    weight=(smooth((times-3)/3)*smooth((13-times)/3)+smooth((times-17)/3)*smooth((28-times)/4))*.24
                    q=slerp(q,rq,weight)
                if bone in ['chest','spine']:
                    breath=np.sin(times/5*np.pi*2)*(.65 if bone=='chest' else -.18)
                    q=multiply(axis_q(0,breath),q)
            # Feet remain planted during conversational gestures. Preserve the
            # author's upper-body timings and elbow/shoulder coordination.
            if any(x in bone for x in ['UpperLeg','LowerLeg','Foot','Toes']) or bone=='hips':q=np.tile(baseline[bone],(len(times),1))
            if action!='Idle':q=slerp(baseline[bone],q,blend)
            else:q=slerp(baseline[bone],q,smooth(times/.5)*smooth((duration-times)/.5))
            # Add a small constant shoulder clearance, not a moving correction;
            # fingers therefore never start inside the long skirt or blazer.
            if bone in ['leftUpperArm','rightUpperArm']:
                q=multiply(axis_q(2,np.full(len(times),-5 if bone.startswith('left') else 5)),q)
            q=normalize(q)
            for j in range(1,len(q)):
                if np.dot(q[j-1],q[j])<0:q[j]*=-1
            out=b.add(q,'VEC4');clip['channels'].append(dict(sampler=len(clip['samplers']),target=dict(node=node,path='rotation')));clip['samplers'].append(dict(input=time_index,output=out,interpolation='LINEAR'))
        # A static pelvis avoids foot sliding after proportion retargeting; chest
        # and spine from the authored motion still produce breathing and weight.
        out=b.add(np.tile(hip,(len(times),1)),'VEC3');clip['channels'].append(dict(sampler=len(clip['samplers']),target=dict(node=human['hips'],path='translation')));clip['samplers'].append(dict(input=time_index,output=out,interpolation='LINEAR'))
        # Quiet blinks live on a separate morph from emotion and mouth movement.
        face=g['meshes'][0];shapes=face['extras']['targetNames'];blink=next(x['binds'][0]['index']for x in vrm['blendShapeMaster']['blendShapeGroups']if x['presetName']=='blink')
        weights=np.zeros((len(times),len(shapes)))
        for at in ([2.4,6.8,10.5,10.86,15.7,20.3,26.1] if action=='Idle' else [2.4,6.8]):
            phase=times/speed-at
            blink_value=np.where(phase<0,smooth((phase+.09)/.09),1-smooth(phase/.18))
            weights[:,blink]=np.maximum(weights[:,blink],blink_value)
        out=b.add(weights.flatten(),'SCALAR');clip['channels'].append(dict(sampler=len(clip['samplers']),target=dict(node=0,path='weights')));clip['samplers'].append(dict(input=time_index,output=out,interpolation='LINEAR'));g['animations'].append(clip)
    b.write(folder/'model.glb')
    # Data-only, bounded secondary motion. No scripts are admitted to a model pack.
    springs=[]
    for group in vrm['secondaryAnimation']['boneGroups']:
        if group.get('comment')=='Bust':continue
        def visit(i):
            for child in g['nodes'][i].get('children',[]):
                if np.linalg.norm(g['nodes'][child].get('translation',[0,0,0]))>.0001:
                    springs.append(dict(bone=p[i],tip=p[child],radius=min(.018,group.get('hitRadius',.01)),angle=8 if 'Skirt' in p[i] else 16))
                visit(child)
        for bone in group['bones']:visit(bone)
    unique={s['bone']:s for s in springs};colliders=[]
    for group in vrm['secondaryAnimation']['colliderGroups']:
        for c in group['colliders']:
            # glTFast changes X handedness for local positions, as do these offsets.
            o=c['offset'];colliders.append(dict(bone=p[group['node']],offset=dict(x=-o['x'],y=o['y'],z=o['z']),radius=c['radius']))
    (folder/'secondary-motion.json').write_text(json.dumps(dict(schemaVersion=1,strands=list(unique.values()),colliders=colliders),indent=2)+'\n')
    presets={x['presetName']:x for x in vrm['blendShapeMaster']['blendShapeGroups']if x['presetName']!='unknown'}
    def binding(preset,weight=1):return [dict(renderer=p[next(i for i,n in enumerate(g['nodes'])if n.get('mesh')==v['mesh'])],shape=g['meshes'][v['mesh']]['extras']['targetNames'][v['index']],weight=v['weight']/100*weight)for v in presets[preset]['binds']]
    def cue(channel,target,duration=2.5):return dict(channel=channel,target=target,fallback='neutral' if channel=='expression' else '',delay=0,duration=duration,intensity=1,required=True)
    def rule(id,event,body='',expression='',priority=35,cooldown=6,emotion=''):
        return dict(id=id,eventName=event,emotion=emotion,priority=priority,cooldown=cooldown,probability=1,minIntensity=0,cues=([cue('body',body)]if body else [])+([cue('expression',expression)]if expression else []))
    manifest=dict(schemaVersion=1,id=role['id'],packageId='app.starry.characters.'+role['id'],packageVersion='1.1.0',
        display=dict(name=role['name'],originalName=role['original'],description=role['description'],invitation=role['invitation'],tagline=role['tagline'],symbol=role['symbol'],thumbnail='Anime_'+role['id'].split('-')[1],cardIdentifier='card-'+role['id'],openIdentifier='open-'+role['id'],style='anime',thumbnailScale=1,order=40+index*10),
        compatibility=dict(apiMajor=1,minApiMinor=1,required=['core.animation@1','core.gaze@1','core.behavior@1'],optional=['core.expression@1','core.speech.amplitude@1','core.speech.viseme@1','core.interaction@1','core.effects@1','core.parameters@1','core.secondary-motion@1']),
        source=dict(format='glb',model='model.glb',scale=1,yaw=180),rig=dict(head=p[human['head']],neck=p[human['neck']],leftEye=p[human['leftEye']],rightEye=p[human['rightEye']],headRenderer='Face',conversationStart=.58),
        gaze=dict(yaw=38,up=16,down=20,eyeYaw=9,eyeUp=6,eyeDown=8),
        actions=[dict(id=a,clip=a,semantic=semantic,label=label,symbol=symbol,button=a!='Idle',framing='conversation',gaze=gaze)for a,n,label,semantic,symbol,gaze in MOTIONS],
        expressions=[dict(id=e,bindings=binding(preset,weight))for e,preset,weight in [('joy','joy',.65),('care','fun',.4),('sad','sorrow',.65),('anger','angry',.5),('blink','blink',1)]],
        speech=dict(mode='amplitude',amplitude=binding('a',.65),visemes=[dict(id=v,bindings=binding(preset,.75))for v,preset in [('aa','a'),('ih','i'),('ou','u'),('ee','e'),('oh','o')]]),
        effects=[dict(id='joy',kind='sparkles',anchor='head',color='#D6EAFF',count=8),dict(id='care',kind='hearts',anchor='chest',color='#F5B9C1',count=5)],
        interactions=[dict(id='head',bone=p[human['head']],renderer='Face',radius=.12,eventName='interaction.head.tap')],
        behaviors=[rule('head-touch','interaction.head.tap','No','joy',75,.8),rule('hello','dialogue.greeting','Hello','joy'),rule('thanks','dialogue.gratitude','Thanks','care'),rule('listen','state.listening','Listen','care',20,12),rule('thinking','state.thinking','Think','',20,12),rule('happy','dialogue.reply','Yes','joy',35,10,'joy'),rule('comfort','dialogue.reply','Listen','care',35,10,'care')],
        parameters=[],license=dict(name='CC0-1.0 AND Apache-2.0',authors=['pixiv Inc. / VRoid Project','High Fidelity, Inc.','Vircadia contributors','Overte e.V.','Undi95 / Hanami (animation conversion)'],notice='LICENSE.txt',source='https://github.com/madjin/vrm-samples/tree/e16eb187100149a315ad92c3c9968f1d5baa6c7d/vroid/beta'),files=[],
        extensions={'app.starry.secondary-motion':dict(version=1,file='secondary-motion.json')})
    # Texture tint variants preserve the detailed authored skin/cloth maps.
    for label,mesh_index,match,options in [('发色氛围',2,'Hair',['#FFFFFF','#DADFFB','#F4D5DE']),('服装色调',1,'CLOTH',['#FFFFFF','#CDDCEB','#E5D5CA'])]:
        mesh=g['meshes'][mesh_index];slots=[i for i,pr in enumerate(mesh['primitives'])if match.lower() in g['materials'][pr['material']]['name'].lower()]
        if mesh_index==2:
            # Preserve the source's darker backing and highlight accents. The
            # adjustable foreground tint starts at its real sRGB authored value.
            slots=[i for i in slots if '_HAIR_01' in g['materials'][mesh['primitives'][i]['material']]['name']]
            if slots:
                rgb=g['materials'][mesh['primitives'][slots[0]]['material']]['pbrMetallicRoughness']['baseColorFactor'][:3]
                options[0]='#'+''.join(f'{round(255*(12.92*x if x<=.0031308 else 1.055*x**(1/2.4)-.055)):02X}' for x in rgb)
        if slots:
            node=next(i for i,n in enumerate(g['nodes'])if n.get('mesh')==mesh_index)
            manifest['parameters'].append(dict(id='hair-tone' if mesh_index==2 else 'outfit-tone',label=label,kind='color',section='外观',min=0,max=2,initial=0,options=options,bindings=[dict(path=p[node],property='baseColor',negativeShape='',materialSlot=i)for i in slots]))
    notice=('Starry character adaptation: '+role['name']+' / '+role['original']+'\n\nModels: pixiv Inc. / VRoid Project, CC0-1.0.\nhttps://vroid.pixiv.help/hc/en-us/articles/4402614652569\nhttps://creativecommons.org/publicdomain/zero/1.0/\nThe downloaded VRM metadata explicitly says CC0. These are the legacy CC0 models, not AvatarSample A/B/C.\n\nAnimations: selected Overte-derived VRMA assets, Apache-2.0, distributed by Hanami.\nOnly animation data is used; no Hanami application code is included.\nhttps://github.com/Undi95/Hanami/blob/6787685c8d40e4e79bffbb0d389b478f32ef88d6/vrma/NOTICE.md\nChanges by Starry (2026-09-29): VRM 0 basis/proportion retargeting; planted legs; shoulder clearance; eased starts/ends; raised-hand retiming; blink morph tracks; merged identical-material primitives.\n\n'+(SOURCES/'Overte-LICENSE').read_text()+'\n\n'+(SOURCES/'APACHE-2.0.txt').read_text())
    (folder/'LICENSE.txt').write_text(notice);(folder/'NOTICE.md').write_text((SOURCES/'Hanami-NOTICE.md').read_text())
    report=dict(id=role['id'],source=role['file'],primitivesBefore=before,primitivesAfter=sum(len(m['primitives'])for m in g['meshes']),triangles=sum(len(b.array(pr['indices']))//3 for m in g['meshes']for pr in m['primitives']),bytes=(folder/'model.glb').stat().st_size,springSegments=len(unique),actions=durations)
    (folder/'README.md').write_text('# '+role['name']+' · XCP 1.1\n\n'+role['description']+'\n\n来源、锁定版本、SHA-256：`assets/characters/anime-sources.lock.json`。重建：`.local/character-venv/bin/python scripts/prepare_anime_characters.py --fetch`。\n\n'+json.dumps(report,ensure_ascii=False,indent=2)+'\n\n所有动画是连续插值曲线，源采样 30 Hz，不把源采样率等同于屏幕刷新率。当前支持站姿会话，不声明坐/蹲/躺。保留脚底，弱化夸张位移，合理限幅注视；触头轻摇头。secondary-motion.json 是可选 v1 数据扩展，旧宿主可保持静态头发降级。运行时资产完全离线。\n')
    (folder/'character.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
    subprocess.run([str(ROOT/'.local/character-sdk-venv/bin/python'),str(ROOT/'character-sdk/tools/character_tool.py'),'seal',str(folder)],check=True)
    return manifest,report

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--fetch',action='store_true');args=parser.parse_args();SOURCES.mkdir(parents=True,exist_ok=True)
    for item in json.loads(LOCK.read_text())['sources']:
        path=SOURCES/item['file']
        if args.fetch and not path.exists():path.write_bytes(urllib.request.urlopen(item['url'],timeout=60).read())
        if not path.exists() or hashlib.sha256(path.read_bytes()).hexdigest()!=item['sha256']:raise ValueError('Missing or changed pinned source: '+item['file'])
    collections=ROOT/'ios/StarryNight/Resources/CharacterCollections.json';c=json.loads(collections.read_text());reports=[]
    for i,role in enumerate(ROLES):
        manifest,report=package(role,i);reports.append(report);id=role['id'];existing=next((x for x in c['collections'] if x['modelID']==id),None);c['collections']=[x for x in c['collections']if x['modelID']!=id]
        environments=list(dict.fromkeys([role['environment'],'garden','seaside']))
        c['collections'].append(dict(schemaVersion=1,id='app.starry.collections.'+id,version='1.0.0',modelID=id,modelPackageID=manifest['packageId'],modelPackageVersion=manifest['packageVersion'],actions=[x[0]for x in MOTIONS if x[0]!='Idle'],environments=environments,voices=[dict(id=id+'/natural',title='自然聊',detail='日常节奏',engine='melo-zh-v1',speed=role['speed']),dict(id=id+'/soft',title='慢慢说',detail='放缓一点',engine='melo-zh-v1',speed=.86)],music=[dict(id=id+'/moon',asset='MoonlitTide',title='月下微光',detail='角色配套轻音乐',symbol='moon.stars'),dict(id=id+'/breeze',asset='IslandAfternoon',title='微风日常',detail='角色配套轻音乐',symbol='wind')],defaultEnvironment=role['environment'],defaultVoice=id+'/natural',defaultMusic=id+'/moon'))
        if existing and all(track.get('sourceModelID') == id for track in existing['music']):
            c['collections'][-1].update(music=existing['music'],defaultMusic=existing['defaultMusic'],version=existing['version'])
    collections.write_text(json.dumps(c,ensure_ascii=False,indent=2)+'\n');out=ROOT/'docs/verification/anime-ensemble';out.mkdir(parents=True,exist_ok=True);(out/'source-build.json').write_text(json.dumps(reports,ensure_ascii=False,indent=2)+'\n');print(json.dumps(reports,ensure_ascii=False,indent=2))
if __name__=='__main__':main()
