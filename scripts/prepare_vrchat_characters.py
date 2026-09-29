#!/usr/bin/env python3
"""Audited Mochiyama FBX/prefab data -> standalone XCP. No VRChat SDK ships.

Use the isolated Unity Inspector first; bare FBX visibility is NOT authoritative.
Only private local preview is permitted by this integration recipe. New avatars
need a reviewed config/appearance/rig mapping, not a guessed universal conversion.
"""
from __future__ import annotations
import argparse, copy, hashlib, json, subprocess
from pathlib import Path
import numpy as np
import bpy
from prepare_anime_characters import GLB, ROOT, paths
from prepare_portrait_vrm import write_json

STAGE=ROOT/'.local/vrchat-stage'
REPORTS=ROOT/'docs/verification/vrchat-import'
ROLES=[dict(key='kipfel',id='anime-kipfel',name='琪宝',original='Kipfel 1.0.3',environment='garden',
 description='戴着软帽、带着小尾巴的花园伙伴。喜欢散步、小点心，也喜欢听你说今天的小事。',
 invitation='你来啦。要不要一起在花园坐一会儿？',tagline='把今天的小事，慢慢说给我听'),
 dict(key='mamehinata',id='anime-mamehinata',name='豆日向',original='まめひなた 1.53',environment='sunroom',
 description='穿着宽松外套的犬耳伙伴。把日常的小发现装进口袋，愿意陪你度过轻松的一刻。',
 invitation='欢迎回来，给你留了一点暖暖的阳光。',tagline='窗边有阳光，这里有我')]
# Source-only roles: original performance profiles own all face expressions.
# Both source Avatar Descriptors explicitly bind these speech visemes.
VISEMES={'aa':'vrc.v.aa','ih':'vrc.v.ih','ou':'vrc.v.ou','ee':'vrc.v.e','oh':'vrc.v.oh'}
SOURCE_FACE_SHAPES={
    'kipfel':{'eye_close','eye_joy','mouth_smile','eyebrow_joy','eye_nagomi','eye_sad','mouth_sad','eyebrow_sad','eye_angry','eyebrow_angry'},
    'mamehinata':{'Auto_Blink','まばたき','笑い','にっこり','にこり','なごみ','口角上げ','悲しい','口角下げ','怒り','つり目'},
}

def sha(path):return hashlib.sha256(Path(path).read_bytes()).hexdigest()

def export_geometry(role,inspection,folder,recipe):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    source=STAGE/inspection['fbx']
    bpy.ops.import_scene.fbx(filepath=str(source),automatic_bone_orientation=False,use_anim=False)
    skins={s['name']:s for s in inspection['skins']}
    from vrchat_performance_export import requested_shapes
    needed=requested_shapes(recipe)
    # Preserve original face morphs as source data even though the project's
    # artificial blink schedule and mixed expression recipes are gone. Removing
    # host behavior must not remove any of these already-imported source shapes.
    keep=set(VISEMES.values())|SOURCE_FACE_SHAPES[role['key']]
    needed.setdefault('Body',set()).update(keep)
    bake_report=[]; omitted=[]
    for obj in list(bpy.data.objects):
        if obj.type!='MESH':continue
        spec=skins.get(obj.name)
        if not spec:raise ValueError('Mesh lacks prefab inspection: '+obj.name)
        retained=needed.get(obj.name,set())
        keys=obj.data.shape_keys
        if keys:
            # Bake source default deformations into every key so neutral at zero
            # remains the author's dressed prefab, including clothing mask shapes.
            base=np.array([v.co[:] for v in keys.key_blocks[0].data])
            delta=np.zeros_like(base)
            defaults={n:w/100 for n,w in zip(spec['shapes'],spec['weights']) if w}
            for name,w in defaults.items():
                if name not in keys.key_blocks:raise ValueError('Default morph missing: '+name)
                if name not in retained:delta+=(np.array([v.co[:] for v in keys.key_blocks[name].data])-base)*w
            for key in list(keys.key_blocks):
                coords=np.array([v.co[:] for v in key.data])+delta
                key.data.foreach_set('co',coords.astype(np.float32).ravel());key.value=defaults.get(key.name,0) if key.name in retained else 0
            for key in list(keys.key_blocks)[1:]:
                if key.name not in retained:obj.shape_key_remove(key)
            if len(obj.data.shape_keys.key_blocks)==1:obj.shape_key_clear()
            bake_report.append(dict(mesh=obj.name,defaults=defaults,retained=sorted(retained)))
        # Retain FBX names; the render adapter keys off authored material names.
        # Export skips unused OH_Outline_Material slots automatically (zero faces).
        for mat in obj.data.materials:
            if not mat:continue
            mat.use_nodes=True
            bsdf=mat.node_tree.nodes.get('Principled BSDF')
            for link in list(mat.node_tree.links):mat.node_tree.links.remove(link)
            mat.node_tree.links.new(bsdf.outputs['BSDF'],mat.node_tree.nodes.get('Material Output').inputs['Surface'])
            bsdf.inputs['Base Color'].default_value=(1,1,1,1)
            bsdf.inputs['Metallic'].default_value=0
            bsdf.inputs['Roughness'].default_value=.85
    body=bpy.data.objects['Body']
    actual=set(k.name for k in body.data.shape_keys.key_blocks)
    if keep-actual:raise ValueError('Expression morphs missing: '+str(keep-actual))
    raw=folder/'geometry.glb'
    bpy.ops.export_scene.gltf(filepath=str(raw),export_format='GLB',export_animations=False,
        export_yup=True,export_texcoords=True,export_normals=True,export_tangents=False,
        export_materials='EXPORT',export_skins=True,export_all_influences=False,
        export_morph=True,export_morph_normal=True,export_morph_tangent=False,
        export_morph_animation=False,export_bake_animation=False,
        export_use_gltfpack=False,export_keep_originals=False)
    b=GLB(raw);raw.unlink();g=b.doc
    # Blender's sparse morph export requires materialization for the portable SDK.
    for i,a in enumerate(list(g['accessors'])):
        if 'sparse' not in a:continue
        s=a['sparse'];width={'SCALAR':1,'VEC2':2,'VEC3':3,'VEC4':4,'MAT4':16}[a['type']]
        values=np.zeros((a['count'],width),np.float32)
        if 'bufferView' in a:
            v=g['bufferViews'][a['bufferView']];values[:]=np.frombuffer(b.data,dtype='<f4',count=a['count']*width,offset=v.get('byteOffset',0)+a.get('byteOffset',0)).reshape(-1,width)
        iv=g['bufferViews'][s['indices']['bufferView']];vv=g['bufferViews'][s['values']['bufferView']]
        index=np.frombuffer(b.data,dtype={5121:'u1',5123:'<u2',5125:'<u4'}[s['indices']['componentType']],count=s['count'],offset=iv.get('byteOffset',0)+s['indices'].get('byteOffset',0)).copy()
        vals=np.frombuffer(b.data,dtype='<f4',count=s['count']*width,offset=vv.get('byteOffset',0)+s['values'].get('byteOffset',0)).reshape(-1,width).copy()
        values[index]=vals;new=b.add(values,a['type']);g['accessors'][i]=g['accessors'][new]
    # Normalize the asset's metre units in the data, including inverse bind
    # translations. Keep runtime roots at scale 1: skinned-mesh bounds and mobile
    # head interaction then share one physical coordinate system.
    positions=set()
    for mesh in g['meshes']:
        for pr in mesh['primitives']:
            positions.add(pr['attributes']['POSITION'])
            for target in pr.get('targets',[]):
                if 'POSITION' in target:positions.add(target['POSITION'])
    for index in positions:
        value=b.array(index)*2; replacement=b.add(value,'VEC3');g['accessors'][index]=g['accessors'][replacement]
    for skin in g.get('skins',[]):
        index=skin['inverseBindMatrices'];value=b.array(index);value[:,12:15]*=2
        replacement=b.add(value,'MAT4');g['accessors'][index]=g['accessors'][replacement]
    for node in g['nodes']:
        if 'translation' in node:node['translation']=[x*2 for x in node['translation']]
    return b,dict(omittedMeshes=omitted,bakedDefaultShapes=bake_report,fbxSHA256=sha(source),metreNormalization=2)

def secondary(g,role,folder):
    p=paths(g);byname={n['name']:i for i,n in enumerate(g['nodes'])}
    physics=REPORTS/'source-physics.json'
    if not physics.exists():raise ValueError('Run source PhysBone resolution first')
    # Stable metadata reader supplied by source audit. Runtime sidecar deliberately
    # approximates author chains with bounded standalone dynamics, not SDK code.
    from vrchat_physics import runtime_secondary
    result,report=runtime_secondary(role['key'],g,json.loads(physics.read_text()))
    from vrchat_autonomy import configure_wind
    report['environmentWind']=configure_wind(result)
    write_json(folder/'secondary-motion.json',result)
    return report

def package(role,index,geometry_only=False,output_root=None):
    folder=(output_root or ROOT/'character-packages/imported')/role['id'];folder.mkdir(parents=True,exist_ok=True)
    inspection=json.loads((STAGE/'Inspection'/f"{role['key']}-prefab.json").read_text())
    if not inspection['humanValid']:raise ValueError('Source humanoid invalid')
    from vrchat_performance_export import source_recipe,append_source_motions,convert_profile,append_source_idle
    recipe=source_recipe(role['key'])
    b,report=export_geometry(role,inspection,folder,recipe);g=b.doc;p=paths(g)
    if geometry_only:
        b.write(folder/'geometry-preview.glb');return report
    from vrchat_render_materials import prepare_materials
    materials=prepare_materials(REPORTS/'source-materials.json',inspection,folder,include_hidden=True)
    existing={m['name']:i for i,m in enumerate(g['materials'])}
    # A Unity renderer can repeat the final submesh with an extra material.
    # Keep author overlay passes (e.g. Kipfel front-hair fake shadow) explicit.
    for mesh in g['meshes']:
        spec=next((s for s in inspection['skins'] if s['name']==mesh['name']),None)
        if spec is None:continue
        for name in materials['rendererSlots'][spec['path']]:
            if name in materials['skippedOverlayMaterials']:continue
            if name not in existing:
                existing[name]=len(g['materials']);g['materials'].append(dict(name=name,pbrMetallicRoughness=dict(baseColorFactor=[1,1,1,1],metallicFactor=0,roughnessFactor=.85)))
                pr=copy.deepcopy(mesh['primitives'][-1]);pr['material']=existing[name];mesh['primitives'].append(pr)
    missing={m['name'] for m in g['materials']}-{m['name'] for m in materials['materials']}
    if missing:raise ValueError('Unmapped GLB materials: '+str(missing))
    for m in g['materials']:m.pop('extensions',None)
    # The host supplies the approved mobile shader from the sidecar, data only.
    g.pop('extensionsUsed',None);g.pop('extensionsRequired',None)
    byname={n['name']:i for i,n in enumerate(g['nodes'])}
    human={x['human'][0].lower()+x['human'][1:]:byname[x['path'].split('/')[-1]] for x in inspection['human']}
    face=byname['Body']
    # These two roles retain only the author's motions. Never invoke the shared
    # Overte/VRMA conversation recipe, its added breathing or blink schedule.
    g['animations']=[]
    motions,motion_notes=append_source_motions(b,role['key'])
    performance,performance_notes=convert_profile(b,inspection,recipe,motions)
    report['sourceIdle']=append_source_idle(b,role['key'],motions,performance)
    from vrchat_autonomy import append_visible_idle
    report['sourceIdle']['adaptation']=append_visible_idle(b,role['key'],report['sourceIdle'])
    durations={'Idle':report['sourceIdle']['duration']}
    report['secondaryMotion']=secondary(g,role,folder)
    g['asset']['generator']='Starry VRChat data adapter 2.2 / preserved source motions + declared visible idle / Blender 4.5 / no VRChat SDK'
    b.write(folder/'model.glb')
    manifest=json.loads((ROOT/'character-packages/imported/anime-vita/character.json').read_text())
    manifest.update(id=role['id'],packageId='app.starry.characters.'+role['id'],packageVersion='2.2.0')
    manifest['performance']=performance
    manifest['compatibility']['required']=['core.animation@1']
    manifest['compatibility']['optional']=['core.speech.amplitude@1','core.speech.viseme@1','core.secondary-motion@1','core.performance@1']
    manifest['actions']=[dict(id='Idle',clip='Idle',semantic='idle',label='自然待机',symbol='figure.stand',button=False,framing='conversation',gaze='release')]
    manifest['display']=dict(name=role['name'],originalName=role['original']+' · もち山金魚',description=role['description'],invitation=role['invitation'],tagline=role['tagline'],symbol='leaf',thumbnail='Anime_'+role['key'],cardIdentifier='card-'+role['id'],openIdentifier='open-'+role['id'],style='anime',thumbnailScale=1,order=90+index*10)
    manifest['source']=dict(format='glb',model='model.glb',scale=1,yaw=0)
    manifest['rig']=dict(head=p[human['head']],neck=p[human['neck']],leftEye=p[human['leftEye']],rightEye=p[human['rightEye']],headRenderer=p[face],conversationStart=.52)
    manifest['rig']['portraitWidthScale']=1.4 if role['key']=='mamehinata' else 1
    manifest['gaze']=dict(yaw=30,up=12,down=16,eyeYaw=6,eyeUp=4,eyeDown=5)
    def bind(shape,weight):return dict(renderer=p[face],shape=shape,weight=weight)
    manifest['expressions']=[];manifest['effects']=[];manifest['interactions']=[];manifest['behaviors']=[]
    manifest['speech']=dict(mode='amplitude',proceduralHeadMotion=False,amplitude=[bind(VISEMES['aa'],.55)],visemes=[dict(id=k,bindings=[bind(v,.7)]) for k,v in VISEMES.items()])
    manifest['parameters']=[]
    manifest['license']=dict(name='Mochiyama avatar terms (private preview)',authors=['もち山金魚 / MOCHIYAMA'],notice='LICENSE.txt',source='https://mochiyama.booth.pm/')
    manifest['files']=[]
    manifest['extensions']['app.starry.private-preview']=dict(version=1,redistributionAllowed=False,appearanceEditingAllowed=False,metadata='source-meta.json')
    meta=dict(original=role['original'],author='もち山金魚',use='private-local-preview-only',publicDistribution='Contact original licensor; current terms v1.60 software integration distribution needs separate permission',sdkIncluded=False,sourceReport='docs/verification/vrchat-import/source-audit.json',fbxSHA256=report['fbxSHA256'],animationPolicy='original-source-only',sourceIdle=report['sourceIdle'])
    write_json(folder/'source-meta.json',meta)
    (folder/'LICENSE.txt').write_text('PRIVATE LOCAL PREVIEW ONLY — DO NOT REDISTRIBUTE\n\nOriginal avatar and animations: '+role['original']+' by もち山金魚 / MOCHIYAMA.\nhttps://mochiyama.booth.pm/\nPersonal use, modifications and format conversion: see original author terms.\nCurrent 2026-09-07 terms v1.60 require contacting the licensor for software integration distribution.\nNo VRChat SDK assets, components, default animations or DLLs are included.\nThis is a standalone technical adaptation of user-provided assets for private local testing.\nDo not publish the source/converted packages or distribute the app with these avatars without appropriate authorization.\nOriginal purchase/acquisition terms must be checked separately before public distribution.\n\nThis package contains only source-avatar motion data. The previous third-party Overte/Hanami conversation motions are no longer included; their source archives and historical attribution remain unchanged outside this package.\n')
    (folder/'NOTICE.md').write_text('# Source-only avatar conversion\n\nAuthor: もち山金魚 / MOCHIYAMA.\n\nOriginal stand and additive breath are composed at their original timings and amplitudes. Original facial, hand, ear, tail and appearance options are retained. No host head-shake, conversational body gestures, procedural head/eye follow, artificial blink schedule, body sway, breathing or ambient hair breeze is added.\n\nPhysBone chain and collider data use a bounded standalone inertia approximation; this is not the original VRChat physics solver. Original archives and source samples are preserved.\n')
    report.update(id=role['id'],actions=durations,performanceOptions=len(performance['options']),sourceMotionClips=len(motions),performanceLimitations=performance_notes+motion_notes,materials=len(g['materials']),triangles=sum(len(b.array(pr['indices']))//3 for m in g['meshes'] for pr in m['primitives']),glbBytes=(folder/'model.glb').stat().st_size,materialLimitations=materials['limitations'],privatePreview=True)
    from vrchat_autonomy import profile,provenance,notice
    manifest['compatibility']['optional'].append('core.autonomy@1')
    manifest['autonomy']=profile(role['key'],manifest,report['sourceIdle'])
    report['autonomy']=provenance(role['key'])
    meta.update(animationPolicy='source-motions-with-declared-natural-idle-adaptation',autonomy=report['autonomy'])
    write_json(folder/'source-meta.json',meta)
    (folder/'NOTICE.md').write_text(notice(role['key']))
    write_json(folder/'conversion-report.json',report)
    write_json(folder/'character.json',manifest)
    subprocess.run([str(ROOT/'.local/character-sdk-venv/bin/python'),str(ROOT/'character-sdk/tools/character_tool.py'),'seal',str(folder)],check=True)
    return report

def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--only',choices=[r['key'] for r in ROLES]);parser.add_argument('--geometry-only',action='store_true',help='Export a local untextured geometry preview without integration (diagnostics).');parser.add_argument('--output-root',type=Path,help='Alternate output for isolated replay; default character-packages/imported.');args=parser.parse_args()
    reports=[package(r,i,args.geometry_only,args.output_root) for i,r in enumerate(ROLES) if not args.only or args.only==r['key']]
    if not args.geometry_only and args.output_root is None:
        write_json(REPORTS/'conversion-report.json',dict(schemaVersion=1,characters=reports))
        # Keep already-authored private audio/scene choices while advancing the
        # package reference; otherwise the host correctly rejects a stale bundle.
        collection_path=ROOT/'ios/CharacterHost/Resources/CharacterCollections.json'
        collections=json.loads(collection_path.read_text())
        for role in ROLES:
            if args.only and args.only!=role['key']:continue
            manifest=json.loads((ROOT/'character-packages/imported'/role['id']/'character.json').read_text())
            existing=next((c for c in collections['collections'] if c['modelID']==role['id']),None)
            if existing:
                existing['modelPackageID']=manifest['packageId']
                existing['modelPackageVersion']=manifest['packageVersion']
                existing['actions']=[a['id'] for a in manifest['actions'] if a['button']]
        write_json(collection_path,collections)
    print(json.dumps(reports,ensure_ascii=False,indent=2))
if __name__=='__main__':main()
