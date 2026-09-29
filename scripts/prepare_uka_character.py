#!/usr/bin/env python3
"""Pinned, attributed Uka source -> portable XCP illustrated companion.

The source's A-pose and coordinated hand posture are retained. VMD curves are
sampled with their authored Bezier timing; quiet additional gestures are baked,
including the independent sleeve rig, before a mobile player ever sees them.
"""
from pathlib import Path
import copy, hashlib, json, shutil, subprocess
import numpy as np
from pmx_to_glb import convert_pmx
from prepare_anime_characters import GLB, paths, normalize, multiply, slerp, smooth, axis_q, MOTIONS
from vmd_motion import read_vmd, sample_bone

ROOT=Path(__file__).resolve().parents[1]
SOURCE=ROOT/'.local/sources/adult-anime-research/uka'
FOLDER=ROOT/'character-packages/imported/anime-uka'
SCALE=.08
SHAPES=['まばたき','にこり','笑い','困る眉','真面目','怒り眉','あ','い','う','え','お','にやり','にっこり','悲しい総','耳収納']


def build():
    lock=json.loads((ROOT/'.local/sources/adult-anime-research/uka-source.json').read_text())
    for row in lock['files']:
        path=SOURCE/row['path']
        if hashlib.sha256(path.read_bytes()).hexdigest()!=row['sha256']:
            raise ValueError('Changed Uka source: '+row['path'])
    (ROOT/'assets/characters/uka-sources.lock.json').write_text(json.dumps(lock,ensure_ascii=False,indent=2)+'\n')
    FOLDER.mkdir(parents=True,exist_ok=True)
    meta=convert_pmx(SOURCE/'MS_Uka.pmx',FOLDER/'model.glb',scale=SCALE,morph_names=SHAPES)
    b=GLB(FOLDER/'model.glb');g=b.doc;p=paths(g);bones=meta['bones'];named={x['name']:x for x in bones}
    # Source PMX contains three optional expression decals with initial alpha=0.
    # They remain dormant; a toon cutout must not accidentally make them opaque.
    hidden={i for i,m in enumerate(g['materials'])if m['pbrMetallicRoughness']['baseColorFactor'][3]<.001}
    for mesh in g['meshes']:mesh['primitives']=[x for x in mesh['primitives']if x['material']not in hidden]
    textures=FOLDER/'textures';textures.mkdir(exist_ok=True)
    materials=[]
    for i,m in enumerate(g['materials']):
        src=meta['materials'][i];name=m['name'];index=src['texture'];file=''
        if index>=0:
            file=f'textures/base_{index}.png';shutil.copyfile(FOLDER/meta['textures'][index]['path'],FOLDER/file)
        kind='eye' if name=='目' else 'face' if '頭' in name else 'skin' if name=='手足' else 'hair' if name in ['髪','耳'] else 'cloth'
        color=m['pbrMetallicRoughness']['baseColorFactor']
        materials.append(dict(name=name,kind=kind,texture=file,normal='',matcap='',color=dict(zip('rgba',color)),
            shadeColor=dict(r=.86,g=.81,b=.85,a=1),alphaMode=m.get('alphaMode','OPAQUE'),cutoff=.25,matcapStrength=0))
    (FOLDER/'materials.json').write_text(json.dumps(dict(schemaVersion=1,materials=materials),ensure_ascii=False,indent=2)+'\n')
    shutil.rmtree(FOLDER/'model-textures')
    # Each renderer uploads only the joints it actually weights. The full author
    # hierarchy (including spring tips and sleeve controls) remains available.
    source_skin=g['skins'][0];source_bind=b.array(source_skin['inverseBindMatrices']);g['skins']=[]
    for mesh in meta['meshes']:
        primitives=g['meshes'][mesh['meshIndex']]['primitives'];attrs=primitives[0]['attributes']
        old=b.array(attrs['JOINTS_0']).astype(int);weights=b.array(attrs['WEIGHTS_0'])
        used=np.unique(old[weights>1e-6]);remap=np.zeros(len(source_skin['joints']),dtype=int);remap[used]=np.arange(len(used))
        ji=b.add(remap[old],'VEC4',5123)
        for primitive in primitives:primitive['attributes']['JOINTS_0']=ji
        node=g['nodes'][mesh['nodeIndex']];node['skin']=len(g['skins'])
        g['skins'].append(dict(name=mesh['name']+'Skin',skeleton=0,joints=[source_skin['joints'][i]for i in used],inverseBindMatrices=b.add(source_bind[used],'MAT4')))

    authored,_=read_vmd(SOURCE/'motion/stand.vmd')
    # Source is left-handed with identity bind axes. Reflecting Z negates the X
    # and Y quaternion components, with no Euler conversion or accumulated twist.
    reflect=np.array([-1,-1,1,1]);base={}
    for bone in bones:
        name=bone['name'];q=sample_bone(authored[name],np.array([0.]))[1][0] if name in authored else np.array([0.,0,0,1])
        base[name]=normalize(q*reflect)
    # Fixed lower body requires no live IK solver and guarantees no foot sliding.
    fixed=['全ての親','センター','グルーブ','下半身','下半身先']
    fixed += [n for n in base if any(s in n for s in ['足','ひざ','つま先','目'])]
    for name in fixed:base[name]=np.array([0.,0,0,1])
    def rotations(times,action):
        count=len(times);duration=times[-1];env=smooth(times/.7)*smooth((duration-times)/.8)
        result={n:np.tile(q,(count,1))for n,q in base.items()}
        for name in ['上半身','首','頭']:
            if name in authored:
                # Gentle authored breathing, with a longer cycle than the source.
                q=sample_bone(authored[name],np.mod(times*.8,4))[1]*reflect
                result[name]=slerp(base[name],q,env*.65)
        def add(name,axis,angle):
            if name in result:result[name]=multiply(result[name],axis_q(axis,np.asarray(angle)*env))
        add('上半身M',2,.65*np.sin(times*np.pi*2/10))
        add('首',2,-.35*np.sin(times*np.pi*2/10))
        add('頭',1,2.3*np.sin(times*np.pi*2/13))
        add('上半身2',0,.45*np.sin(times*np.pi*2/5))
        pulse=np.sin(np.pi*np.clip(times/max(.1,duration),0,1))**2
        if action=='Hello':
            add('右腕',2,-20*pulse);add('右ひじ',0,-24*pulse)
            add('右手首',1,12*np.sin(times*np.pi*3)*pulse)
        elif action=='Yes':add('頭',0,6*np.sin(times*np.pi*2)*pulse)
        elif action=='No':add('頭',1,12*np.sin(times*np.pi*2)*pulse)
        elif action=='Listen':add('頭',2,-5*pulse)
        elif action=='Think':add('頭',2,4*pulse);add('頭',0,-3*pulse)
        elif action=='Talk':
            add('左ひじ',0,-8*np.sin(times*np.pi*.7)*pulse);add('頭',0,2*np.sin(times*np.pi)*pulse)
        elif action=='Relax':add('上半身M',2,2*pulse);add('頭',2,-2*pulse)
        elif action=='Thanks':add('上半身2',0,4*pulse);add('頭',0,5*pulse)
        # Sleeve control bones are parallel IK proxies in PMX, not children of
        # the weighted arm. Bake the matching FK rotations so hands never leave
        # rigid, T-posed sleeves when no MMD solver is present on the phone.
        for side in ['左','右']:
            for proxy,parts in [('腕袖',['腕']),('ひじ袖',['腕捩','ひじ']),('手首袖',['手捩','手首'])]:
                if side+proxy in result:
                    q=np.tile([0.,0,0,1],(count,1))
                    for part in parts:q=multiply(q,result[side+part])
                    result[side+proxy]=q
        visiting=set();solved=set()
        def grant(i):
            if i in solved:return result[bones[i]['name']]
            if i in visiting:raise ValueError('Cyclic PMX rotation grant')
            visiting.add(i);bone=bones[i];name=bone['name'];source=bone.get('grant')
            if source and source['rotation'] and source['bone']>=0:
                inherited=grant(source['bone']);weight=source['weight']
                if weight<0:inherited=inherited*np.array([-1,-1,-1,1]);weight=-weight
                result[name]=multiply(result[name],slerp(np.array([0,0,0,1]),inherited,weight))
            visiting.remove(i);solved.add(i);return result[name]
        for i in range(len(bones)):grant(i)
        return {n:normalize(q)for n,q in result.items()}
    g['animations']=[]
    for action,*_ in MOTIONS:
        duration=30 if action=='Idle' else 4.6 if action in ['Hello','Talk','Relax'] else 3.2
        times=np.linspace(0,duration,round(duration*30)+1);clip=dict(name=action,samplers=[],channels=[]);ti=b.add(times,'SCALAR')
        def channel(node,path,values,kind):
            oi=b.add(values,kind);clip['channels'].append(dict(sampler=len(clip['samplers']),target=dict(node=node,path=path)))
            clip['samplers'].append(dict(input=ti,output=oi,interpolation='LINEAR'))
        for name,q in rotations(times,action).items():
            for j in range(1,len(q)):
                if np.dot(q[j-1],q[j])<0:q[j]*=-1
            # Avoid thousands of redundant curves on rigid physics helper bones.
            if np.max(np.abs(q-[0,0,0,1]))>1e-6:channel(named[name]['nodeIndex'],'rotation',q,'VEC4')
        for mesh in meta['meshes']:
            shapes=mesh['targetNames']
            if 'まばたき'not in shapes:continue
            weights=np.zeros((len(times),len(shapes)))
            for at in ([2.8,7.3,11.6,11.96,17.2,22.4,27.5]if action=='Idle' else [2.5]):
                phase=times-at;value=np.where(phase<0,smooth((phase+.085)/.085),1-smooth(phase/.2))
                weights[:,shapes.index('まばたき')]=np.maximum(weights[:,shapes.index('まばたき')],value)
            channel(mesh['nodeIndex'],'weights',weights.flatten(),'SCALAR')
        g['animations'].append(clip)
    # Albedo files are imported once by Unity as ASTC. Do not carry a second set
    # of embedded RGBA copies from glTF into a mobile build or its import cache.
    for material in g['materials']:
        material['pbrMetallicRoughness'].pop('baseColorTexture',None)
    g.pop('textures',None);g.pop('images',None);g.pop('samplers',None)
    keep=sorted({a['bufferView']for a in g['accessors']});view_map={old:i for i,old in enumerate(keep)}
    payload=bytearray();views=[]
    for old in keep:
        view=copy.deepcopy(g['bufferViews'][old]);start=view.get('byteOffset',0)
        payload.extend(b'\0'*(-len(payload)%4));view['byteOffset']=len(payload)
        payload.extend(b.data[start:start+view['byteLength']]);views.append(view)
    for a in g['accessors']:a['bufferView']=view_map[a['bufferView']]
    g['bufferViews']=views;b.data=payload
    b.write(FOLDER/'model.glb')
    # A data-only spring chain. Head/body colliders are conservative; extra cloak
    # bones receive inertia without wind and have a smaller angular envelope.
    springs=[]
    for bone in bones:
        name=bone['name'];node=bone['nodeIndex']
        if not any(s in name for s in ['髪','アホ毛','クローク','尾1_']):continue
        children=g['nodes'][node].get('children',[])
        if len(children)!=1:continue
        child=children[0]
        if np.linalg.norm(g['nodes'][child].get('translation',[0,0,0]))<.001:continue
        springs.append(dict(bone=p[node],tip=p[child],radius=.004,angle=12 if '髪'in name or 'アホ毛'in name else 6))
    def collider(name,x,y,z,radius):return dict(bone=p[named[name]['nodeIndex']],offset=dict(x=x,y=y,z=z),radius=radius)
    colliders=[collider('頭',0,.015,-.004,.085),collider('上半身2',0,-.005,0,.135),collider('首',0,0,0,.056)]
    (FOLDER/'secondary-motion.json').write_text(json.dumps(dict(schemaVersion=1,strands=springs,colliders=colliders),ensure_ascii=False,indent=2)+'\n')
    manifest=copy.deepcopy(json.loads((ROOT/'character-packages/imported/anime-vita/character.json').read_text()))
    manifest.update(id='anime-uka',packageId='app.starry.characters.anime-uka',packageVersion='1.0.0',files=[])
    manifest['display'].update(name='优可',originalName='Uka · CG Cybernetic Avatar',
        description='茶色发丝、层叠长衣的安静伙伴。喜欢灯下读书，也喜欢认真听你说起日常。清淡的笑意和细小的回应，让相处慢慢变得熟悉。',
        invitation='今天的故事，愿意说给我听吗？',tagline='灯下相伴，听你慢慢说',symbol='moon',thumbnail='Anime_uka',cardIdentifier='card-anime-uka',openIdentifier='open-anime-uka',order=25)
    manifest['source']=dict(format='glb',model='model.glb',scale=1,yaw=0)
    manifest['rig']=dict(head=p[named['頭']['nodeIndex']],neck=p[named['首']['nodeIndex']],leftEye=p[named['左目']['nodeIndex']],rightEye=p[named['右目']['nodeIndex']],headRenderer='Root/Face',conversationStart=.66)
    manifest['interactions']=[dict(id='head',bone=manifest['rig']['head'],renderer='Root/Face',radius=.105,eventName='interaction.head.tap')]
    def bindings(shape,weight=1):
        return [dict(renderer=m['path'],shape=shape,weight=weight)for m in meta['meshes']if shape in m['targetNames']]
    manifest['expressions']=[dict(id=semantic,bindings=bindings(shape,weight))for semantic,shape,weight in [('joy','にこり',.45),('care','にっこり',.25),('sad','困る眉',.45),('anger','怒り眉',.35),('blink','まばたき',1)]]
    manifest['speech']=dict(mode='amplitude',amplitude=bindings('あ',.55),visemes=[dict(id=v,bindings=bindings(s,.65))for v,s in [('aa','あ'),('ih','い'),('ou','う'),('ee','え'),('oh','お')]])
    manifest['parameters']=[]
    manifest['compatibility']['optional']=[x for x in manifest['compatibility']['optional']if x!='core.parameters@1']
    manifest['license']=dict(name='CC-BY-4.0',authors=['Nagoya Institute of Technology','Moonshot R&D Goal 1 Avatar Symbiotic Society'],notice='LICENSE.txt',source='https://github.com/mmdagent-ex/uka/tree/'+lock['revision'])
    notice='CG-CA Uka (c) 2023-2024 by Nagoya Institute of Technology, Moonshot R&D Goal 1 Avatar Symbiotic Society\nhttps://creativecommons.org/licenses/by/4.0/\n\nStarry adaptation: PMX to glTF, skinned mobile toon materials, authored VMD breathing, baked gentle gestures, sleeve proxy FK, bounded hair/cloak motion. No affiliation or endorsement is implied. Source appearance and attribution are retained.\n\n'+(SOURCE/'README.md').read_text()
    (FOLDER/'LICENSE.txt').write_text(notice);(FOLDER/'character.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
    report=dict(id='anime-uka',source=meta['source'],geometry=meta['counts'],springSegments=len(springs),clips=len(g['animations']),approximations=meta['approximations'])
    (FOLDER/'README.md').write_text('# 优可 / Uka\n\n'+json.dumps(report,ensure_ascii=False,indent=2)+'\n\nRebuild: `.local/character-venv/bin/python scripts/prepare_uka_character.py`. Source lock: `assets/characters/uka-sources.lock.json`.\n')
    subprocess.run([str(ROOT/'.local/character-sdk-venv/bin/python'),str(ROOT/'character-sdk/tools/character_tool.py'),'seal',str(FOLDER)],check=True)
    print(json.dumps(report,ensure_ascii=False,indent=2))


if __name__=='__main__':build()
