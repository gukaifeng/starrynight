"""Specialize source controllers for StarryNight's stationary conversation host.

VR tracking, locomotion and stations are not inputs of this app. Remove only
states proven unreachable under those fixed inputs; never remove a dependency
because its file is missing. Menus, parameter drivers and animated parameters
keep their inputs dynamic. Original graphs remain in the source audit.
"""
import copy

CONTEXT = {'IsLocal':1, 'Grounded':1, 'TrackingType':3, 'Upright':1,
           'VRMode':0, 'Seated':0, 'InStation':0, 'AFK':0,
           'VelocityX':0, 'VelocityY':0, 'VelocityZ':0, 'AngularY':0,
           'VRCEmote':0, 'VRCFaceBlendH':0, 'VRCFaceBlendV':0}


def condition_known_false(condition, constants):
    name=condition['parameter']
    if name not in constants:return False
    value=constants[name]; threshold=condition.get('threshold',0)
    checks={1:lambda:value!=0,2:lambda:value==0,3:lambda:value>threshold,
            4:lambda:value<threshold,6:lambda:value==threshold,7:lambda:value!=threshold}
    predicate=checks.get(condition['mode'])
    return predicate is not None and not predicate()


def specialize_graph(source,constants):
    graph=copy.deepcopy(source)
    transitions={t['id']:t for t in graph['transitions'] if not t.get('muted') and
                 not any(condition_known_false(c,constants) for c in t['conditions'])}
    states={s['id']:s for s in graph['states']}; machines={m['id']:m for m in graph['machines']}
    state_parent={s:m['id'] for m in machines.values() for s in m['states']}
    machine_parent={s:m['id'] for m in machines.values() for s in m['children']}
    used_s=set();used_m=set();used_t=set()
    def transition(identity):
        if identity in used_t or identity not in transitions:return
        used_t.add(identity);t=transitions[identity]
        state(t['target']);machine(t['machine'])
    def machine(identity):
        if identity not in machines or identity in used_m:return
        used_m.add(identity);m=machines[identity]
        machine(machine_parent.get(identity))
        state(m['default'])
        for t in m['any']+m['entry']:transition(t)
        # Machine exits remain conservative: any reachable child may finish.
        for link in m['machineTransitions']:
            if link['machine'] in used_m:
                for t in link['transitions']:transition(t)
    def state(identity):
        if identity not in states or identity in used_s:return
        used_s.add(identity);machine(state_parent.get(identity))
        for t in states[identity]['transitions']:transition(t)
    for layer in graph['layers']:machine(layer['root'])
    # New nested-machine reachability can enable a parent's exit links.
    previous=None
    while previous!=(len(used_s),len(used_m),len(used_t)):
        previous=(len(used_s),len(used_m),len(used_t))
        for identity in list(used_m):
            for link in machines[identity]['machineTransitions']:
                if link['machine'] in used_m:
                    for t in link['transitions']:transition(t)
    graph['states']=[s for s in graph['states'] if s['id'] in used_s]
    for s in graph['states']:s['transitions']=[t for t in s['transitions'] if t in used_t]
    graph['machines']=[m for m in graph['machines'] if m['id'] in used_m]
    for m in graph['machines']:
        m['states']=[s for s in m['states'] if s in used_s]
        m['children']=[s for s in m['children'] if s in used_m]
        m['any']=[t for t in m['any'] if t in used_t]
        m['entry']=[t for t in m['entry'] if t in used_t]
        m['machineTransitions']=[dict(machine=l['machine'],transitions=[t for t in l['transitions'] if t in used_t])
                                 for l in m['machineTransitions'] if l['machine'] in used_m]
    graph['transitions']=[t for t in graph['transitions'] if t['id'] in used_t]
    blends={b['id']:b for b in graph['blends']}
    for b in blends.values():
        children=b['children'];x=constants.get(b['x']);y=constants.get(b['y'])
        if b['kind']==0 and x is not None and children:
            ordered=sorted(children,key=lambda c:c['threshold'])
            exact=[c for c in children if abs(c['threshold']-x)<1e-7]
            if len(exact)==1:b['children']=exact
            elif x<=ordered[0]['threshold']:b['children']=ordered[:1]
            elif x>=ordered[-1]['threshold']:b['children']=ordered[-1:]
            else:b['children']=[c for a,z in zip(ordered,ordered[1:]) if a['threshold']<x<z['threshold'] for c in (a,z)]
        elif b['kind'] in (1,2,3) and x is not None and y is not None:
            exact=[c for c in children if abs(c['x']-x)<1e-7 and abs(c['y']-y)<1e-7]
            if len(exact)==1:b['children']=exact
        elif b['kind']==4:
            b['children']=[c for c in children if c['parameter'] not in constants or constants[c['parameter']]!=0]
    used_b=set()
    def motion(identity):
        if identity not in blends or identity in used_b:return
        used_b.add(identity)
        for c in blends[identity]['children']:motion(c['motion'])
    for s in graph['states']:motion(s['motion'])
    graph['blends']=[b for b in graph['blends'] if b['id'] in used_b]
    return graph


def specialize(controls,animated_parameters=()):
    dynamic=set(animated_parameters)
    for c in controls['controls']:
        dynamic.add(c['parameter']);dynamic.update(g['parameter'] for g in c.get('gates',[]))
    for graph in controls['controllers']:
        for node in graph['states']+graph['machines']:
            for behavior in node['behaviors']:
                if behavior['kind']=='parameter-driver':dynamic.update(p['name'] for p in behavior['parameters'])
    constants={k:v for k,v in CONTEXT.items() if k not in dynamic}
    for p in controls['parameters']:
        if p['name'] in constants:p['initial']=constants[p['name']]
    before=sum(len(g['states']) for g in controls['controllers'])
    controls['controllers']=[specialize_graph(g,constants) for g in controls['controllers']]
    after=sum(len(g['states']) for g in controls['controllers'])
    controls['limitations'].append(dict(kind='host-conversation-context',version=1,constants=constants,
        removedUnreachableStates=before-after,detail='Stationary local desktop conversation. Source menus and writable parameters remain dynamic; missing motions are never a pruning criterion.'))
    return controls
