#!/usr/bin/env python3
"""Convert author expression menus and Mecanim data to the portable control IR.

Only data is read. Controller callbacks, scripts, and animation events never run.
Unsupported platform behavior is retained in the capability report, not silently
claimed as a working character feature.
"""
from __future__ import annotations
import hashlib
import json
from pathlib import Path
import re
import yaml
from audit_vrchat_archives import unity_blocks


class UnityLoader(getattr(yaml,'CSafeLoader',yaml.SafeLoader)):
    # Unity stores booleans as 0/1. YAML 1.1's ON/OFF/yes coercion corrupts
    # perfectly valid state and parameter names in many author controllers.
    yaml_implicit_resolvers = {
        key: [(tag, pattern) for tag, pattern in values
              if tag != 'tag:yaml.org,2002:bool']
        for key, values in yaml.SafeLoader.yaml_implicit_resolvers.items()
    }


def documents(path):
    with Path(path).open('rb') as stream:header=stream.read(16)
    if Path(path).suffix.lower()=='.asset' and not header.startswith((b'%YAML',b'\xef\xbb\xbf%YAML',b'---')):
        from vrchat_binary_data import read_documents
        return read_documents(path)
    return {str(b['fileID']):dict(classID=b['classID'], **next(iter(yaml.load(re.sub(r'^(\s*(?:m_Mask|eyelidsBlendshapes): )([0-9a-fA-F]+)$',r'\1"\2"',b['text'],flags=re.M),Loader=UnityLoader).values())))
            for b in unity_blocks(Path(path).read_text(errors='replace')) if not b['stripped']}


def reference(value):
    return str((value or {}).get('fileID',0))


def controller_documents(guid,identity,read):
    """Resolve one controller's state graph across generated subcontainers.

    A GUID can contain several controllers, and states can live in a different
    file from their controller. Preserve GUID + fileID instead of picking the
    first controller or accidentally merging unrelated state graphs.
    """
    import copy
    source=read(guid);controller=source.get(str(identity))
    if not controller or controller.get('classID')!=91:
        raise ValueError('Missing exact controller subasset: '+guid+':'+str(identity))
    controller=copy.deepcopy(controller);result={}
    def scoped(ref,owner):
        if reference(ref)=='0':return {'fileID':0}
        source_guid=ref.get('guid') or owner;fileid=reference(ref)
        key=fileid if source_guid==guid else source_guid+':'+fileid
        if key in result:return {'fileID':key}
        row=read(source_guid).get(fileid)
        if not row:raise ValueError('Missing state graph subasset: '+source_guid+':'+fileid)
        row=copy.deepcopy(row);result[key]=row
        for name in ('m_DefaultState','m_DstState','m_DstStateMachine'):
            if name in row:row[name]=scoped(row[name],source_guid)
        for name in ('m_Transitions','m_StateMachineBehaviours','m_AnyStateTransitions','m_EntryTransitions'):
            if name in row:row[name]=[scoped(r,source_guid) for r in row[name]]
        for name,field in (('m_ChildStates','m_State'),('m_ChildStateMachines','m_StateMachine')):
            for child in row.get(name,[]):child[field]=scoped(child[field],source_guid)
        for link in row.get('m_StateMachineTransitions') or []:
            link['first']=scoped(link['first'],source_guid)
            link['second']=[scoped(r,source_guid) for r in link['second']]
        motion=row.get('m_Motion')
        if motion and reference(motion)!='0' and not motion.get('guid'):motion['guid']=source_guid
        return {'fileID':key}
    for layer in controller.get('m_AnimatorLayers',[]):
        layer['m_StateMachine']=scoped(layer['m_StateMachine'],guid)
    return controller,result


def prune_graph(graph):
    """Unity YAML often retains orphaned states from earlier author revisions.

    Export the graph reachable from actual layer roots, including state-machine
    exits. Orphaned SDK walking clips must not become false dependencies.
    """
    machines={m['id']:m for m in graph['machines']}; states={s['id']:s for s in graph['states']}
    transitions={t['id']:t for t in graph['transitions']}; blends={b['id']:b for b in graph['blends']}
    used_m=set(); used_s=set(); used_t=set(); used_b=set()
    def transition(identity):
        if identity in used_t:return
        t=transitions[identity];used_t.add(identity)
        if t['target']!='0':state(t['target'])
        if t['machine']!='0':machine(t['machine'])
    def motion(identity):
        if identity in blends and identity not in used_b:
            used_b.add(identity)
            for c in blends[identity]['children']:motion(c['motion'])
    def state(identity):
        if identity in used_s:return
        s=states[identity];used_s.add(identity);motion(s['motion'])
        for t in s['transitions']:transition(t)
    def machine(identity):
        if identity in used_m:return
        m=machines[identity];used_m.add(identity)
        for s in m['states']:state(s)
        for c in m['children']:machine(c)
        for t in m['any']+m['entry']:transition(t)
        for link in m['machineTransitions']:
            machine(link['machine'])
            for t in link['transitions']:transition(t)
    for layer in graph['layers']:machine(layer['root'])
    for key,used in [('machines',used_m),('states',used_s),('transitions',used_t),('blends',used_b)]:
        graph[key]=[v for v in graph[key] if v['id'] in used]
    return graph


def prefab_build_requirements(guid,read):
    """Inspect reachable prefab assembly directives without running source code."""
    visited=set();requirements=[]
    def visit(source):
        if not source or source in visited:return
        visited.add(source)
        for identity,d in read(source).items():
            if d.get('m_Enabled',1) and 'matchAvatarWriteDefaults' in d and 'layerType' in d and d.get('animator',{}).get('guid'):
                requirements.append(dict(kind='unsupported-build-merge-animator',prefab=source,component=identity,
                    controller=d['animator']['guid'],detail='Author controller is assembled at build time; flatten with a reviewed adapter before claiming controls are absent.'))
            visit(d.get('m_SourcePrefab',{}).get('guid'))
    visit(guid);return requirements


class BlendReader:
    """Resolve inline and external BlendTree subassets without losing fileID.

    The host receives the same portable graph, not extra Unity asset files.
    Source-qualified IDs prevent two .asset files' 20600000 roots colliding.
    """
    def __init__(self,controller,read,graph,motion_id=None):
        self.controller=controller;self.read=read;self.graph=graph;self.added=set();self.motion_id=motion_id

    def motion(self,ref,owner=None):
        ref=ref or {};owner=owner or self.controller
        source=ref.get('guid') or owner;fileid=reference(ref)
        data=self.read(source).get(fileid,{})
        if data.get('classID')==206:
            identity=fileid if source==self.controller else source+':'+fileid
            self.add(data,identity,source);return identity
        if self.motion_id and fileid!='0':return self.motion_id(source,fileid)
        return ref.get('guid') or (fileid if source==self.controller else source if fileid!='0' else '0')

    def add(self,d,identity,owner):
        if identity in self.added:return
        # Prune orphaned author history before the SDK enforces its 512 live
        # tree budget. This larger read budget only bounds raw source parsing.
        if len(self.added)>=4096:raise ValueError('Source blend graph exceeds import audit budget')
        self.added.add(identity)
        self.graph['blends'].append(dict(id=identity,name=d.get('m_Name') or '',kind=int(d.get('m_BlendType',0)),
            x=d.get('m_BlendParameter',''),y=d.get('m_BlendParameterY',''),automatic=bool(d.get('m_UseAutomaticThresholds',0)),
            minimum=float(d.get('m_MinThreshold',0)),maximum=float(d.get('m_MaxThreshold',1)),
            children=[dict(motion=self.motion(c.get('m_Motion'),owner),threshold=float(c.get('m_Threshold',0)),
                x=c.get('m_Position',{}).get('x',0),y=c.get('m_Position',{}).get('y',0),speed=float(c.get('m_TimeScale',1)),
                cycle=float(c.get('m_CycleOffset',0)),mirror=bool(c.get('m_Mirror',0)),parameter=c.get('m_DirectBlendParameter',''))
                for c in d.get('m_Childs',[])]))


def referenced_motion_ids(controls):
    """Leaf assets reachable from live states, retaining unknown dependencies."""
    result=set()
    for graph in controls['controllers']:
        trees={b['id']:b for b in graph['blends']}
        pending=[s['motion'] for s in graph['states']];seen=set()
        while pending:
            identity=pending.pop()
            if not identity or identity=='0' or identity in seen:continue
            seen.add(identity)
            if identity in trees:pending.extend(c['motion'] for c in trees[identity]['children'])
            else:result.add(identity)
    return result


def build(stage,geometry):
    audit=json.loads((stage/'source-audit.json').read_text())
    assets={a['guid']:a for ar in audit['archives'] for p in ar['unityPackages'] for a in p['assets']}
    by_path={a['path']:a for a in assets.values()}
    loaded={};notes=[]
    def read(guid):
        if guid not in loaded:
            a=assets.get(guid)
            loaded[guid]=documents(a.get('metadataPath') or a['extractedPath']) if a and a['extension'] in (
                '.prefab','.controller','.overridecontroller','.asset','.anim','.mask') else {}
        return loaded[guid]
    main=by_path[geometry['prefab']]
    notes.extend(prefab_build_requirements(main['guid'],lambda g:read(g) if g in assets and assets[g]['extension']=='.prefab' else {}))
    def descriptor(guid,visited):
        if guid in visited:return None
        visited.add(guid)
        docs=read(guid)
        found=next((d for d in docs.values() if 'VisemeBlendShapes' in d),None)
        if found:return found
        for d in docs.values():
            source=d.get('m_SourcePrefab',{}).get('guid')
            if source:
                found=descriptor(source,visited)
                if found:
                    found=dict(found)
                    # Root descriptor replacements on prefab variants are explicit.
                    for mod in d.get('m_Modification',{}).get('m_Modifications',[]):
                        key=mod.get('propertyPath','')
                        if key in ('expressionsMenu','expressionParameters'):
                            found[key]=mod.get('objectReference',{})
                    return found
        return None
    desc=descriptor(main['guid'],set())
    if not desc:raise ValueError('Effective avatar descriptor is missing')
    out=dict(schemaVersion=1,profile='mecanim-portable-v1',parameters=[],controls=[],controllers=[],masks=[],limitations=notes)
    param_ref=desc.get('expressionParameters',{});param_guid=param_ref.get('guid')
    if param_guid:
        if reference(param_ref) not in read(param_guid):notes.append(dict(kind='missing-expression-parameters',guid=param_guid,fileID=reference(param_ref)))
        for d in [read(param_guid).get(reference(param_ref),{})]:
            for p in d.get('parameters',[]):
                if p.get('name'):
                    out['parameters'].append(dict(name=p['name'],kind={0:'int',1:'float',2:'bool'}.get(p.get('valueType'),'float'),initial=p.get('defaultValue',0),saved=bool(p.get('saved',0))))
    params={p['name']:p for p in out['parameters']}
    def menu(ref,group,seen,gates=(),owner=''):
        guid=ref.get('guid') or owner;fileid=reference(ref);menu_key=(guid,fileid)
        if not guid or fileid=='0' or menu_key in seen:return
        if guid not in assets:
            notes.append(dict(kind='missing-menu',guid=guid));return
        if fileid not in read(guid):
            notes.append(dict(kind='missing-menu',guid=guid,fileID=fileid));return
        for d in [read(guid).get(fileid,{})]:
            for i,c in enumerate(d.get('controls',[])):
                label=str(c.get('name') or 'Control '+str(i+1))
                kind={101:1,102:2,103:3,201:4,202:5,203:6}.get(int(c.get('type',0)),int(c.get('type',0)))
                if kind==3:
                    name=c.get('parameter',{}).get('name','')
                    gate=[dict(parameter=name,value=float(c.get('value',1)))] if name else []
                    menu(c.get('subMenu',{}),group+[label],seen|{menu_key},tuple(list(gates)+gate),guid);continue
                if kind not in (1,2,4,5,6):
                    notes.append(dict(kind='unknown-menu-control',type=kind,label=label));continue
                names=[p.get('name','') for p in c.get('subParameters',[])] if kind in (4,5,6) else [c.get('parameter',{}).get('name','')]
                for axis,name in enumerate(names):
                    if not name:continue
                    menu_id=guid if fileid=='11400000' else guid+':'+fileid
                    control_key=menu_id+':'+str(i)+':'+str(axis)
                    if audit.get('bake'):
                        # NDMF assigns fresh container GUIDs during each bake.
                        # User-visible controls must survive a rebuild of the
                        # same authored menu; container IDs are provenance only.
                        control_key=json.dumps([geometry['role'],group,label,i,axis,name,kind,float(c.get('value',1))],ensure_ascii=False,separators=(',',':'))
                    identity=hashlib.sha256(control_key.encode()).hexdigest()[:20]
                    label_axis=label if len(names)==1 else label+' · '+['X','Y','Z','W'][axis]
                    main=c.get('parameter',{}).get('name','')
                    gate=[dict(parameter=main,value=float(c.get('value',1)))] if main and kind in (4,5,6) else []
                    out['controls'].append(dict(id='control-'+identity,label=label_axis,group=' / '.join(group) or '原作菜单',
                        parameter=name,kind='slider' if kind in (4,5,6) else 'button' if kind==1 else 'toggle',
                        value=float(c.get('value',1)),minimum=-1 if kind==4 else 0,maximum=1,
                        initial=params.get(name,{}).get('initial',0),sourceMenu=guid,sourceIndex=i,axis=axis,gates=list(gates)+gate))
    menu(desc.get('expressionsMenu',{}),[],set())
    used_masks={}
    def behavior(d):
        if 'disableLocomotion' in d or 'enterPoseSpace' in d:
            notes.append(dict(kind='host-stationary-tracking-context',script=d.get('m_Script',{}).get('guid'),
                source={k:v for k,v in d.items() if not k.startswith('m_') and k!='classID'},
                detail='The conversation host has neither world locomotion nor tracked-head pose space; original body animation remains evaluated.'))
            return None
        if 'parameters' in d and isinstance(d['parameters'],list) and any('type' in p and 'name' in p for p in d['parameters']):
            return dict(kind='parameter-driver',parameters=[dict(name=p.get('name',''),operation=int(p.get('type',0)),value=float(p.get('value',0)),minimum=float(p.get('valueMin',0)),maximum=float(p.get('valueMax',1)),chance=float(p.get('chance',1)),source=p.get('source',''),convertRange=bool(p.get('convertRange',0)),sourceMin=float(p.get('sourceMin',0)),sourceMax=float(p.get('sourceMax',1)),destMin=float(p.get('destMin',0)),destMax=float(p.get('destMax',1))) for p in d['parameters']],localOnly=bool(d.get('localOnly',0)))
        if 'goalWeight' in d and 'playable' not in d and 'layer' in d:
            return dict(kind='playable-weight',playable={0:4,1:5,2:3,3:2}[int(d['layer'])],layer=-1,weight=float(d['goalWeight']),duration=float(d.get('blendDuration',0)))
        if 'playable' in d and 'goalWeight' in d:
            return dict(kind='layer-weight',playable={0:4,1:5,2:3,3:2}[int(d['playable'])],layer=int(d.get('layer',-1)),weight=float(d['goalWeight']),duration=float(d.get('blendDuration',0)))
        if any(k.startswith('tracking') for k in d):
            return dict(kind='tracking',eyes=int(d.get('trackingEyes',0)),mouth=int(d.get('trackingMouth',0)),source={k:v for k,v in d.items() if k.startswith('tracking')})
        notes.append(dict(kind='unsupported-state-behaviour',script=d.get('m_Script',{}).get('guid'),fields=[k for k in d if not k.startswith('m_') and k!='classID']))
        return None
    for layer in desc.get('baseAnimationLayers',[])+desc.get('specialAnimationLayers',[]):
        if layer['type'] in audit.get('bake',{}).get('untouchedDefaultCalibrationLayers',[]):
            notes.append(dict(kind='host-source-default-calibration',playable=layer['type'],
                detail='Source delegates this T/IK calibration pose to the platform and has no merge into it. Official build materializes it; preserve original default delegation in the conversation host.'))
            continue
        controller_ref=layer.get('animatorController',{});guid=controller_ref.get('guid')
        if not guid or layer.get('isDefault',0):continue
        if read(guid).get(reference(controller_ref),{}).get('classID')!=91:
            notes.append(dict(kind='missing-controller',guid=guid));continue
        controller,docs=controller_documents(guid,reference(controller_ref),read)
        graph_id=guid if reference(controller_ref)=='9100000' else guid+':'+reference(controller_ref)
        graph=dict(id=graph_id,playable=int(layer['type']),parameters=[],layers=[],machines=[],states=[],transitions=[],blends=[])
        blend_reader=BlendReader(guid,lambda g:read(g) if g in assets and assets[g]['extension'] in ('.controller','.asset') else {},graph,
            lambda source,fileid:source+':'+fileid if assets.get(source,{}).get('extension') in ('.fbx','.asset','.controller') else source)
        for p in controller.get('m_AnimatorParameters',[]):
            name=p['m_Name'];kind={1:'float',3:'int',4:'bool',9:'trigger'}.get(p['m_Type'],'float')
            initial=p.get({'float':'m_DefaultFloat','int':'m_DefaultInt','bool':'m_DefaultBool','trigger':'m_DefaultBool'}[kind],0)
            if name not in params:
                params[name]=dict(name=name,kind=kind,initial=float(initial),saved=False);out['parameters'].append(params[name])
            graph['parameters'].append(name)
        for l in controller.get('m_AnimatorLayers',[]):
            mask_ref=l.get('m_Mask',{}) if reference(l.get('m_Mask'))!='0' else layer.get('mask',{})
            mask_guid=mask_ref.get('guid') or (guid if reference(mask_ref)!='0' else '')
            mask=(mask_guid if reference(mask_ref)=='31900000' else mask_guid+':'+reference(mask_ref)) if mask_guid else ''
            if mask:used_masks[mask]=(mask_guid,reference(mask_ref))
            graph['layers'].append(dict(name=l['m_Name'],root=reference(l['m_StateMachine']),weight=float(l.get('m_DefaultWeight',1)),additive=l.get('m_BlendingMode',0)==1,mask=mask,synced=int(l.get('m_SyncedLayerIndex',-1))))
        def behaviors(d):return [x for r in d.get('m_StateMachineBehaviours',[]) if (x:=behavior(docs.get(reference(r),{})))]
        for identity,d in docs.items():
            common=dict(id=identity,name=d.get('m_Name') or '')
            if d['classID']==1107:
                exits=[dict(machine=reference(x['first']),transitions=[reference(t) for t in x['second']]) for x in (d.get('m_StateMachineTransitions') or [])]
                graph['machines'].append(dict(**common,states=[reference(x['m_State']) for x in d.get('m_ChildStates',[])],children=[reference(x['m_StateMachine']) for x in d.get('m_ChildStateMachines',[])],default=reference(d.get('m_DefaultState')),any=[reference(x) for x in d.get('m_AnyStateTransitions',[])],entry=[reference(x) for x in d.get('m_EntryTransitions',[])],behaviors=behaviors(d),machineTransitions=exits))
            elif d['classID']==1102:
                motion=d.get('m_Motion',{})
                graph['states'].append(dict(**common,motion=blend_reader.motion(motion),speed=float(d.get('m_Speed',1)),cycle=float(d.get('m_CycleOffset',0)),writeDefaults=bool(d.get('m_WriteDefaultValues',1)),mirror=bool(d.get('m_Mirror',0)),timeParameter=d.get('m_TimeParameter','') if d.get('m_TimeParameterActive',0) else '',speedParameter=d.get('m_SpeedParameter','') if d.get('m_SpeedParameterActive',0) else '',transitions=[reference(x) for x in d.get('m_Transitions',[])],behaviors=behaviors(d)))
            elif d['classID'] in (1101,1109):
                graph['transitions'].append(dict(**common,target=reference(d.get('m_DstState')),machine=reference(d.get('m_DstStateMachine')),exit=bool(d.get('m_IsExit',0)),muted=bool(d.get('m_Mute',0)),solo=bool(d.get('m_Solo',0)),duration=float(d.get('m_TransitionDuration',0)),offset=float(d.get('m_TransitionOffset',0)),exitTime=float(d.get('m_ExitTime',0)),hasExitTime=bool(d.get('m_HasExitTime',0)),fixedDuration=bool(d.get('m_HasFixedDuration',1)),interrupt=int(d.get('m_InterruptionSource',0)),ordered=bool(d.get('m_OrderedInterruption',1)),self=bool(d.get('m_CanTransitionToSelf',1)),conditions=[dict(parameter=c['m_ConditionEvent'],mode=int(c['m_ConditionMode']),threshold=float(c.get('m_EventTreshold',0))) for c in d.get('m_Conditions',[])]))
            elif d['classID']==206:
                blend_reader.add(d,identity,guid)
        out['controllers'].append(prune_graph(graph))
    for identity,(guid,fileid) in sorted(used_masks.items()):
        mask=read(guid).get(fileid)
        if mask and mask.get('classID')!=319:mask=None
        sdk_mask=Path('.local/dependencies/vrc-avatar-masks')/(guid+'.mask')
        if not mask and sdk_mask.exists():
            mask=next((d for d in documents(sdk_mask).values() if d['classID']==319),None)
        if mask:
            body=mask.get('m_Mask', '')
            out['masks'].append(dict(id=identity,body=str(body),transforms=[dict(path=t['m_Path'] or '',active=bool(t['m_Weight'])) for t in mask.get('m_Elements',[])]))
        else:notes.append(dict(kind='missing-avatar-mask',guid=guid))
    for side in ('Left','Right'):
        name='Gesture'+side
        if name in params:
            for value,label in enumerate(('默认','握拳','张开','指向','比心手势','摇滚','手枪','赞')):
                out['controls'].append(dict(id='gesture-'+side.lower()+'-'+str(value),label=('左手' if side=='Left' else '右手')+' · '+label,group='原作手势',parameter=name,kind='toggle',value=value,initial=0,minimum=0,maximum=7))
    from vrchat_host_context import specialize
    motion_file=stage/'Inspection/Portable'/geometry['role']/'motions.json'
    motions=json.loads(motion_file.read_text()).get('motions',[]) if motion_file.exists() else []
    animated={c['property'] for m in motions for c in m.get('curves',[]) if c['component']=='UnityEngine.Animator'}
    return specialize(out,animated),desc
