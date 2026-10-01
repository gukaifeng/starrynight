#!/usr/bin/env python3
"""Build complete, sealed XCP candidates from the audited portable snapshots.

Candidates stay private and outside the active roster until Unity rendering and
binding checks pass. A missing dependency fails one role, not the whole batch.
"""
from __future__ import annotations
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys
import shutil
from vrchat_portable_convert import write_json
from vrchat_conversion_signature import signature,require_reusable,inspection_signature

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'character-sdk/tools'))
from character_tool import seal, validate

NEUTRAL_HAND_PROXY='14980fc5fe40191418954549174fe63e'
# These platform references represent the source's neutral body/finger baseline,
# already supplied by the explicitly labeled host standing adapter. No movement
# or emote proxy may be included in this allowlist.
NEUTRAL_BASELINE_PROXIES={NEUTRAL_HAND_PROXY,'91e5518865a04934b82b8aba11398609','61a99b5de5e4b6d4c8ed51d9dfd9ddc7'}

def blink_binding_name(descriptor,names,controls):
    eyelids=descriptor.get('customEyeLookSettings',{}).get('eyelidsBlendshapes','')
    if isinstance(eyelids,str) and re.fullmatch('[0-9a-fA-F]{8,}',eyelids):
        index=int.from_bytes(bytes.fromhex(eyelids[:8]),'little',signed=True)
        if 0<=index<len(names):return names[index]
    # Preserve author-controlled blinking. For avatars with no such layer, use
    # only an existing canonical VRChat eyelid morph, never a guessed bone pose.
    if any(re.search(r'blink|まばたき|瞬き',l['name'],re.I) for g in controls['controllers'] for l in g['layers']):return None
    canonical=[n for n in names if re.fullmatch(r'vrc[._]blink',n,re.I)]
    return canonical[0] if len(canonical)==1 else None


def missing_motion_dependencies(controls,motions):
    ids={m['guid'] for m in motions['motions']};missing=set()
    for graph in controls['controllers']:
        known=ids|{b['id'] for b in graph['blends']}|{'','0'}
        refs={s['motion'] for s in graph['states']}|{c['motion'] for b in graph['blends'] for c in b['children']}
        missing|=refs-known
    return missing


def control_dependencies(controls,motions):
    # Explicit, reviewed substitution for the SDK-only relaxed-hand proxy.
    # Use this model's own neutral fingers, never a different avatar's curves.
    for graph in controls['controllers']:
        if any(l['synced']!=-1 for l in graph['layers']):raise ValueError('Synced Animator layer needs a reviewed adapter')
        if any(m['behaviors'] for m in graph['machines']):raise ValueError('Machine-level behavior needs a reviewed adapter')
    missing=missing_motion_dependencies(controls,motions)
    fallback=missing & NEUTRAL_BASELINE_PROXIES
    if missing-fallback:raise ValueError('Missing reachable motion dependencies: '+str(sorted(missing-fallback)))
    controls['baselineFallbackMotions']=sorted(fallback)
    if fallback:
        controls['limitations']=[x for x in controls['limitations'] if x['kind']!='host-neutral-hand-adaptation']
        controls['limitations'].append(dict(kind='host-neutral-hand-adaptation',detail='SDK neutral hand/standing proxy assets are not distributed. Reset uses this source prefab neutral fingers and the declared host standing baseline.'))


def require_selected_inspection(row, snapshot):
    """A changed source selection cannot reuse the previous variant's snapshot."""
    stamp_path=snapshot/'inspection-stamp.json'
    stamp=json.loads(stamp_path.read_text()) if stamp_path.exists() else {}
    geometry=json.loads((snapshot/'geometry.json').read_text())
    if (stamp.get('sourceSHA256')!=row['sourceSHA256'] or stamp.get('prefab')!=row['prefab'] or
        geometry.get('prefab')!=row['prefab'] or
        stamp.get('additionalPackages',[])!=row.get('additionalPackages',[]) or
        stamp.get('dependencyAssets',[])!=row.get('dependencyAssets',[]) or
        stamp.get('toolSHA256')!=inspection_signature()):
        raise ValueError('Selected source/Prefab/Inspector changed; rerun inspect_vrchat_library.py')


PREVIEW_OPTIONAL_TEXTURES={'_Shadow2ndColorTex','_ShadowColorTex','_RimColorTex',
    '_MatCapBlendMask','_MatCapTex','_ShadowBorderMask','_ShadowStrengthMask',
    '_OutlineTex','_RimShadeMask'}
PREVIEW_OPTIONAL_SCREEN_SHADERS={'watchLCD','pSLAG_Mat','pSLAG_UI',
    'fTLG_ON_UIStandby','fTLG_ON_UIOnOff','fTLG_ON_UI'}

def assemble(row,folder,stage,order,allow_preview_shading=False):
    geometry=json.loads((stage/'Inspection/Portable'/row['role']/'geometry.json').read_text())
    desc=json.loads((folder/'avatar-descriptor.json').read_text())
    controls=json.loads((folder/'avatar-controls.json').read_text())
    report=json.loads((folder/'portable-conversion.json').read_text())
    control_dependencies(controls,json.loads((folder/'avatar-motions.json').read_text()))
    required_missing=[x for x in controls['limitations'] if x['kind'].startswith(('missing-','unsupported-','unknown-'))]
    if required_missing:raise ValueError('Missing source control dependencies: '+json.dumps(required_missing,ensure_ascii=False))
    limitations=report['materialLimitations']
    material_names={m['name'].removeprefix('mat_'):m['sourceName']
                    for m in json.loads((folder/'materials.json').read_text())['materials']}
    preview_shading=(allow_preview_shading and limitations and all(
        (item.get('reason')=='Unresolved source texture' and
         item.get('property') in PREVIEW_OPTIONAL_TEXTURES) or
        (item.get('reason')=='Runtime RenderTexture cannot be bundled as an image' and
         ((row['role']=='milfy' and item.get('sourceName')=='SmartPhone_Screen') or
          (row['role']=='eku' and item.get('sourceName')=='Takt_Screen')) and
         item.get('property')=='_Main2ndTex') or
        (item.get('reason')=='Unresolved shader; lilToon fallback requires visual comparison' and
         ((row['role']=='shizuku' and material_names.get(item.get('material')) in PREVIEW_OPTIONAL_SCREEN_SHADERS) or
          (row['role']=='eku' and material_names.get(item.get('material')) in {'Fresnel','Cone'}))) or
        item.get('reason')=='Unity utility mesh uses built-in or missing material; neutral local-preview fallback'
        for item in limitations))
    if limitations and not preview_shading:
        raise ValueError('Material dependency requires review: '+json.dumps(limitations[:4],ensure_ascii=False))
    if report['nonlinearMorphFrames']:raise ValueError('Nonlinear morph frames require a dedicated adapter')
    write_json(folder/'avatar-controls.json',controls)
    physics=json.loads((folder/'physics-source.json').read_text())
    if physics['source'].get('unresolved'):raise ValueError('Source physics references are unresolved')
    human={h['human']:'Avatar/'+h['path'] for h in geometry['human']}
    if 'Head' not in human:raise ValueError('Source humanoid Head binding is missing')
    visemes=desc.get('VisemeBlendShapes',[])
    skin=max(geometry['skins'],key=lambda s:(sum(x['name'] in visemes for x in s['shapes']),len(s['shapes'])))
    names=[s['name'] for s in skin['shapes']];renderer='Avatar/'+skin['path']
    def binding(name,weight=1):return dict(renderer=renderer,shape=name,weight=weight)
    speech=dict(mode='none',proceduralHeadMotion=False,amplitude=[],visemes=[])
    for label,index in [('aa',10),('ih',12),('ou',14),('ee',11),('oh',13)]:
        if len(visemes)>index and visemes[index] in names:speech['visemes'].append(dict(id=label,bindings=[binding(visemes[index],.7)]))
    if speech['visemes']:
        speech['mode']='amplitude';speech['amplitude']=speech['visemes'][0]['bindings']
    groups=[];group_ids={};options=[]
    from vrchat_ai_semantics import hints
    semantic_hints,semantic_evidence=hints(controls,json.loads((folder/'avatar-motions.json').read_text()))
    group_labels={'Costume':'原作服装','Kemono':'耳朵与尾巴','Breasts Size':'原作体型','Option':'表情点缀','原作手势':'表情与手势'}
    labels={'Kemono_ear':'兽耳','Kemono_tail':'尾巴','Sailor-Jersey':'水手服外套','Bottoms':'短裤','Legwarmer':'腿套','Socks':'袜子','Sneaker':'鞋子','Breasts Big':'体型增加','Breasts Small':'体型减小','heart':'爱心眼','shiitake':'星星眼','guruguru':'转圈眼','shy':'害羞','hoppe':'腮红','pale_blue':'脸色发白'}
    for c in controls['controls']:
        if c['group'] not in group_ids:
            identity='menu-'+hashlib.sha256(c['group'].encode()).hexdigest()[:16];group_ids[c['group']]=identity
            groups.append(dict(id=identity,label=group_labels.get(c['group'],c['group'])[:128],symbol='slider.horizontal.3'))
        option=dict(id=c['id'],group=group_ids[c['group']],label=labels.get(c['label'],c['label'])[:128],kind='toggle',description='原作菜单 · '+c['group'],
            duration=0,loop=False,defaultOn=c['kind']!='slider' and abs(float(c['initial'])-float(c['value']))<1e-5,
            bones=[],morphs=[],offMorphs=[],morphTracks=[],visibility=[],offVisibility=[],control=c)
        # Reviewed source FX ties these hand parameters to facial expressions.
        # Clothes/body variants stay manual; automatic acting never toggles them.
        face={2:('soft_smile','露出轻柔的笑意',['neutral','happy','curious','worried']),
              5:('confused','露出晕乎乎的表情',['confused']),7:('bright_smile','眼睛变得亮晶晶',['happy','excited'])}
        # Source FX evidence: Chiffon F_doya/F_joy/F_marushiro, Karin
        # Karin_wink/Karin_niyari/Karin_sad. Identical hand enums do NOT
        # imply identical facial expressions across authors/characters.
        face.update({3:('proud','露出小小得意的表情',['playful','happy']),4:('excited','露出开心的神情',['happy','excited']),
                     6:('surprised','眼睛变成惊讶的圆眼',['surprised'])} if row['role']=='chiffon' else
                    {3:('playful','俏皮地眨起一只眼睛',['playful','happy']),4:('teasing_smile','露出俏皮的笑意',['happy','playful']),
                     6:('sad','露出难过的神情',['sad','worried','serious'])})
        if row['role'] in ('chiffon','karin') and c['parameter'] in ('GestureLeft','GestureRight') and c['value'] in face:
            intent,effect,moods=face[c['value']]
            option['ai']=dict(kind='expression',intent=intent,effects=[effect],moods=moods,automatic=True,speechCompatible=True,cooldownSeconds=5,conflicts=[])
        elif c['id'] in semantic_hints:option['ai']=semantic_hints[c['id']]
        options.append(option)
    write_json(folder/'ai-expression-evidence.json',dict(schemaVersion=1,controls=semantic_evidence))
    if len(groups)>32 or len(options)>256:raise ValueError('Menu exceeds current verified UI control budget: '+str((len(groups),len(options))))
    optional=['core.secondary-motion@2']
    if speech['amplitude']:optional+=['core.speech.amplitude@1','core.speech.viseme@1']
    required=['core.animation@1','core.avatar-controls@1']
    if options:required.append('core.performance@2')
    original=row['role'].capitalize()+' '+str(row['version'] or '')
    m=dict(schemaVersion=1,id=row['id'],packageId='app.starry.characters.'+row['id'],packageVersion='3.1.0',
        display=dict(name=row['name'],originalName=original.strip(),description='在星夜遇见'+row['name']+'，保留原作造型和角色表现。',invitation='一起聊聊此刻的心情。',tagline='让每一次相遇，都有新的故事',symbol='sparkles',thumbnail='Anime_'+row['role'],cardIdentifier='card-'+row['id'],openIdentifier='open-'+row['id'],style='anime',thumbnailScale=1,order=order),
        compatibility=dict(apiMajor=1,minApiMinor=1,required=required,optional=optional),source=dict(format='glb',model='model.glb',scale=1,yaw=0),
        rig=dict(head=human['Head'],neck=human.get('Neck',''),leftEye=human.get('LeftEye',''),rightEye=human.get('RightEye',''),headRenderer=renderer,conversationStart=.49,portraitWidthScale=1),
        gaze=dict(yaw=30,up=12,down=16,eyeYaw=6,eyeUp=4,eyeDown=5),
        actions=[dict(id='Idle',clip='Idle',semantic='idle',label='待机',symbol='figure.stand',button=False,framing='conversation',gaze='release')],
        expressions=[],speech=speech,effects=[],interactions=[],behaviors=[],parameters=[],
        license=dict(name='Original author avatar terms — private local conversion',authors=['こまど / komado（あまとうさぎ）' if row['role'] in ('chiffon','karin') else original.strip()+' 原作者（见来源包条款）'],notice='LICENSE.txt',source=Path(json.loads(Path(row['sourceReport']).read_text())['source']).as_uri()),
        files=[],extensions={'app.starry.avatar-controls':dict(version=1,file='avatar-controls.json'),
        'app.starry.secondary-motion':dict(version=2,file='secondary-motion.json'),
        'app.starry.private-preview':dict(version=1,redistributionAllowed=False,appearanceEditingAllowed=False,metadata='source-meta.json')})
    if options:
        defaults=[]
        for s in geometry['skins']:
            path='Avatar/'+s['path']
            # Eku's inactive spatial-screen accessory has two paths beyond the
            # portable profile limit. Its disabled source state is preserved
            # by the model; do not shorten paths used by authored animations.
            if row['role']=='eku' and not s['active'] and 'SpatialScreen' in path and len(path.encode('utf-16-le'))//2>128:
                continue
            defaults.append(dict(path=path,visible=s['active'] and s['enabled']))
        m['performance']=dict(schemaVersion=2,groups=groups,options=options,defaults=defaults)
    blink=blink_binding_name(desc,names,controls)
    if blink:
        optional.append('core.autonomy@1')
        m['autonomy']=dict(schemaVersion=1,blink=dict(bindings=[binding(blink)],intervals=[3.2,4.7,5.8,3.9,4.4],closeSeconds=.16,closedSeconds=.035,openSeconds=.26,firstDelay=1.8,suppressGroups=[],suppressOptions=[]))
    if 'performance' in m and len(m['performance']['defaults'])>64:raise ValueError('Renderer visibility budget requires review')
    authored=ROOT/'ios/CharacterHost/Resources/CharacterPublicProfiles.json'
    profile=next((entry for entry in json.loads(authored.read_text())['characters'] if entry['id']==row['id']),None) if authored.exists() else None
    if profile:
        m['display'].update(name=profile['name'],description=profile['story'],
            invitation=profile['invitation'],tagline=profile['occupation'])
    terms=[]
    audit=json.loads(Path(row['sourceReport']).read_text())
    for package in audit['inventory']['packages']:
        for asset in package['assets']:
            if asset.get('metadataPath') and asset['extension'] in ('.txt','.md') and re.search(r'license|terms|利用規約|規約|readme',asset['path'],re.I):
                terms.append(asset['path']+'\n'+Path(asset['metadataPath']).read_text(errors='replace'))
    (folder/'LICENSE.txt').write_text('Private user-supplied avatar conversion. No public redistribution permission is implied.\nSource SHA256: '+row['sourceSHA256']+'\n\n'+'\n\n'.join(terms))
    write_json(folder/'source-meta.json',dict(schemaVersion=1,sourceVersion=row['version'],sourceSHA256=row['sourceSHA256'],sourceArchive=row['archive'],prefab=row['prefab'],variants=row['variants'],baseline=report['baseline'],localOnly=True,
        previewShadingLimitations=limitations if preview_shading else [],
        blinkAdaptation=dict(sourceMorph=blink,timing='host-controlled') if blink else None))
    (folder/'NOTICE.md').write_text('# Private avatar candidate\n\nOriginal geometry, textures and character controls remain subject to their authors’ terms. '+
        'The host uses the MIT-licensed lilToon renderer. VRChat scripts, SDK binaries, platform animations and arbitrary callbacks are not bundled.\n\n'+
        'See portable-conversion.json and physics-source.json for explicit adaptation limits. This package has not passed device performance testing merely because it is sealed.\n'+
        ('\nLocal preview only: unresolved optional shading textures are listed in source-meta.json. Visual approval is required before activation.\n' if preview_shading else ''))
    write_json(folder/'character.json',m);seal(folder);validate(folder)
    return dict(role=row['role'],id=row['id'],status='packaged',controls=len(options),groups=len(groups),bytes=sum(p.stat().st_size for p in folder.rglob('*') if p.is_file()),baseline=report['baseline'])


def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--only');parser.add_argument('--reuse-conversion',action='store_true');parser.add_argument('--preview-optional-shading',action='store_true');args=parser.parse_args()
    plan=json.loads((ROOT/'.local/vrchat-batch/plan.json').read_text());results=[]
    status=ROOT/'.local/vrchat-batch/package-status.json'
    previous={r['role']:r for r in json.loads(status.read_text()).get('characters',[])} if status.exists() else {}
    for order,row in enumerate(plan['models'],100):
        if args.only and row['role'] not in args.only.split(','):continue
        if row['status']!='source-selected':
            result=dict(role=row['role'],status='skipped',reason=row['status'])
            results.append(result);previous[row['role']]=result
            write_json(status,dict(schemaVersion=1,characters=list(previous.values())));continue
        stage=ROOT/'.local/vrchat-batch/stages'/row['role'];output=ROOT/'.local/vrchat-batch/converted'/row['role']
        try:
            if not (stage/'Inspection/Portable'/row['role']/'host-standing.json').exists():raise ValueError('Current Unity inspection is not complete')
            require_selected_inspection(row,stage/'Inspection/Portable'/row['role'])
            if args.reuse_conversion:
                receipt=json.loads((output/'portable-conversion.json').read_text())
                require_reusable(receipt.get('conversionSignature'),signature(stage,row['role']))
            if not args.reuse_conversion:
                with (ROOT/'.local/logs'/('vrchat-convert-'+row['role']+'.log')).open('w') as log:
                    subprocess.run([sys.executable,str(ROOT/'scripts/vrchat_portable_convert.py'),'--stage',str(stage),'--role',row['role'],'--output',str(output)],check=True,stdout=log,stderr=subprocess.STDOUT)
            result=assemble(row,output,stage,order,args.preview_optional_shading);print('XCP_CANDIDATE',row['role'],result['controls'],result['bytes'],flush=True)
        except Exception as error:
            result=dict(role=row['role'],status='needs-review',reason=str(error));print('XCP_DEFERRED',row['role'],str(error),flush=True)
        results.append(result);previous[row['role']]=result;write_json(status,dict(schemaVersion=1,characters=list(previous.values())))
    if any(x['status']=='needs-review' for x in results):raise SystemExit(1)


if __name__=='__main__':main()
