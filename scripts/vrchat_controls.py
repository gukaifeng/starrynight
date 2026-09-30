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


class UnityLoader(yaml.SafeLoader):
    # Unity stores booleans as 0/1. YAML 1.1's ON/OFF/yes coercion corrupts
    # perfectly valid state and parameter names in many author controllers.
    yaml_implicit_resolvers = {
        key: [(tag, pattern) for tag, pattern in values
              if tag != 'tag:yaml.org,2002:bool']
        for key, values in yaml.SafeLoader.yaml_implicit_resolvers.items()
    }


def documents(path):
    return {str(b['fileID']):dict(classID=b['classID'], **next(iter(yaml.load(re.sub(r'^(\s*(?:m_Mask|eyelidsBlendshapes): )([0-9a-fA-F]+)$',r'\1"\2"',b['text'],flags=re.M),Loader=UnityLoader).values())))
            for b in unity_blocks(Path(path).read_text(errors='replace')) if not b['stripped']}


def reference(value):
    return str((value or {}).get('fileID',0))


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


def build(stage,geometry):
    audit=json.loads((stage/'source-audit.json').read_text())
    assets={a['guid']:a for ar in audit['archives'] for p in ar['unityPackages'] for a in p['assets']}
    by_path={a['path']:a for a in assets.values()}
    loaded={};notes=[]
    def read(guid):
        if guid not in loaded:
            a=assets.get(guid)
            loaded[guid]=documents(a.get('metadataPath') or a['extractedPath']) if a else {}
        return loaded[guid]
    main=by_path[geometry['prefab']]
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
    param_guid=desc.get('expressionParameters',{}).get('guid')
    if param_guid:
        for d in read(param_guid).values():
            for p in d.get('parameters',[]):
                if p.get('name'):
                    out['parameters'].append(dict(name=p['name'],kind={0:'int',1:'float',2:'bool'}.get(p.get('valueType'),'float'),initial=p.get('defaultValue',0),saved=bool(p.get('saved',0))))
    params={p['name']:p for p in out['parameters']}
    def menu(guid,group,seen,gates=()):
        if not guid or guid in seen:return
        if guid not in assets:
            notes.append(dict(kind='missing-menu',guid=guid));return
        for d in read(guid).values():
            for i,c in enumerate(d.get('controls',[])):
                label=c.get('name') or 'Control '+str(i+1)
                kind={101:1,102:2,103:3,201:4,202:5,203:6}.get(int(c.get('type',0)),int(c.get('type',0)))
                if kind==3:
                    name=c.get('parameter',{}).get('name','')
                    gate=[dict(parameter=name,value=float(c.get('value',1)))] if name else []
                    menu(c.get('subMenu',{}).get('guid'),group+[label],seen|{guid},tuple(list(gates)+gate));continue
                if kind not in (1,2,4,5,6):
                    notes.append(dict(kind='unknown-menu-control',type=kind,label=label));continue
                names=[p.get('name','') for p in c.get('subParameters',[])] if kind in (4,5,6) else [c.get('parameter',{}).get('name','')]
                for axis,name in enumerate(names):
                    if not name:continue
                    identity=hashlib.sha256((guid+':'+str(i)+':'+str(axis)).encode()).hexdigest()[:20]
                    label_axis=label if len(names)==1 else label+' · '+['X','Y','Z','W'][axis]
                    main=c.get('parameter',{}).get('name','')
                    gate=[dict(parameter=main,value=float(c.get('value',1)))] if main and kind in (4,5,6) else []
                    out['controls'].append(dict(id='control-'+identity,label=label_axis,group=' / '.join(group) or '原作菜单',
                        parameter=name,kind='slider' if kind in (4,5,6) else 'button' if kind==1 else 'toggle',
                        value=float(c.get('value',1)),minimum=-1 if kind==4 else 0,maximum=1,
                        initial=params.get(name,{}).get('initial',0),sourceMenu=guid,sourceIndex=i,axis=axis,gates=list(gates)+gate))
    menu(desc.get('expressionsMenu',{}).get('guid'),[],set())
    used_masks=set()
    def behavior(d):
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
        guid=layer.get('animatorController',{}).get('guid')
        if not guid or layer.get('isDefault',0):continue
        docs=read(guid);controller=next((d for d in docs.values() if d['classID']==91),None)
        if not controller:
            notes.append(dict(kind='missing-controller',guid=guid));continue
        graph=dict(id=guid,playable=int(layer['type']),parameters=[],layers=[],machines=[],states=[],transitions=[],blends=[])
        for p in controller.get('m_AnimatorParameters',[]):
            name=p['m_Name'];kind={1:'float',3:'int',4:'bool',9:'trigger'}.get(p['m_Type'],'float')
            initial=p.get({'float':'m_DefaultFloat','int':'m_DefaultInt','bool':'m_DefaultBool','trigger':'m_DefaultBool'}[kind],0)
            if name not in params:
                params[name]=dict(name=name,kind=kind,initial=float(initial),saved=False);out['parameters'].append(params[name])
            graph['parameters'].append(name)
        for l in controller.get('m_AnimatorLayers',[]):
            mask=l.get('m_Mask',{}).get('guid') or layer.get('mask',{}).get('guid') or ''
            if mask:used_masks.add(mask)
            graph['layers'].append(dict(name=l['m_Name'],root=reference(l['m_StateMachine']),weight=float(l.get('m_DefaultWeight',1)),additive=l.get('m_BlendingMode',0)==1,mask=mask,synced=int(l.get('m_SyncedLayerIndex',-1))))
        def behaviors(d):return [x for r in d.get('m_StateMachineBehaviours',[]) if (x:=behavior(docs.get(reference(r),{})))]
        for identity,d in docs.items():
            common=dict(id=identity,name=d.get('m_Name') or '')
            if d['classID']==1107:
                exits=[dict(machine=reference(x['first']),transitions=[reference(t) for t in x['second']]) for x in (d.get('m_StateMachineTransitions') or [])]
                graph['machines'].append(dict(**common,states=[reference(x['m_State']) for x in d.get('m_ChildStates',[])],children=[reference(x['m_StateMachine']) for x in d.get('m_ChildStateMachines',[])],default=reference(d.get('m_DefaultState')),any=[reference(x) for x in d.get('m_AnyStateTransitions',[])],entry=[reference(x) for x in d.get('m_EntryTransitions',[])],behaviors=behaviors(d),machineTransitions=exits))
            elif d['classID']==1102:
                motion=d.get('m_Motion',{})
                graph['states'].append(dict(**common,motion=motion.get('guid') or reference(motion),speed=float(d.get('m_Speed',1)),cycle=float(d.get('m_CycleOffset',0)),writeDefaults=bool(d.get('m_WriteDefaultValues',1)),mirror=bool(d.get('m_Mirror',0)),timeParameter=d.get('m_TimeParameter','') if d.get('m_TimeParameterActive',0) else '',speedParameter=d.get('m_SpeedParameter','') if d.get('m_SpeedParameterActive',0) else '',transitions=[reference(x) for x in d.get('m_Transitions',[])],behaviors=behaviors(d)))
            elif d['classID'] in (1101,1109):
                graph['transitions'].append(dict(**common,target=reference(d.get('m_DstState')),machine=reference(d.get('m_DstStateMachine')),exit=bool(d.get('m_IsExit',0)),muted=bool(d.get('m_Mute',0)),solo=bool(d.get('m_Solo',0)),duration=float(d.get('m_TransitionDuration',0)),offset=float(d.get('m_TransitionOffset',0)),exitTime=float(d.get('m_ExitTime',0)),hasExitTime=bool(d.get('m_HasExitTime',0)),fixedDuration=bool(d.get('m_HasFixedDuration',1)),interrupt=int(d.get('m_InterruptionSource',0)),ordered=bool(d.get('m_OrderedInterruption',1)),self=bool(d.get('m_CanTransitionToSelf',1)),conditions=[dict(parameter=c['m_ConditionEvent'],mode=int(c['m_ConditionMode']),threshold=float(c.get('m_EventTreshold',0))) for c in d.get('m_Conditions',[])]))
            elif d['classID']==206:
                graph['blends'].append(dict(**common,kind=int(d.get('m_BlendType',0)),x=d.get('m_BlendParameter',''),y=d.get('m_BlendParameterY',''),automatic=bool(d.get('m_UseAutomaticThresholds',0)),minimum=float(d.get('m_MinThreshold',0)),maximum=float(d.get('m_MaxThreshold',1)),children=[dict(motion=c.get('m_Motion',{}).get('guid') or reference(c.get('m_Motion')),threshold=float(c.get('m_Threshold',0)),x=c.get('m_Position',{}).get('x',0),y=c.get('m_Position',{}).get('y',0),speed=float(c.get('m_TimeScale',1)),cycle=float(c.get('m_CycleOffset',0)),mirror=bool(c.get('m_Mirror',0)),parameter=c.get('m_DirectBlendParameter','')) for c in d.get('m_Childs',[])]))
        out['controllers'].append(prune_graph(graph))
    for guid in sorted(used_masks):
        mask=next((d for d in read(guid).values() if d['classID']==319),None)
        sdk_mask=Path('.local/dependencies/vrc-avatar-masks')/(guid+'.mask')
        if not mask and sdk_mask.exists():
            mask=next((d for d in documents(sdk_mask).values() if d['classID']==319),None)
        if mask:
            body=mask.get('m_Mask', '')
            out['masks'].append(dict(id=guid,body=str(body),transforms=[dict(path=t['m_Path'] or '',active=bool(t['m_Weight'])) for t in mask.get('m_Elements',[])]))
        else:notes.append(dict(kind='missing-avatar-mask',guid=guid))
    for side in ('Left','Right'):
        name='Gesture'+side
        if name in params:
            for value,label in enumerate(('默认','握拳','张开','指向','比心手势','摇滚','手枪','赞')):
                out['controls'].append(dict(id='gesture-'+side.lower()+'-'+str(value),label=('左手' if side=='Left' else '右手')+' · '+label,group='原作手势',parameter=name,kind='toggle',value=value,initial=0,minimum=0,maximum=7))
    return out,desc
