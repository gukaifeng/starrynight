"""Conservative source-controller projection for a stationary conversation host.

Never synthesize a missing clip. Omit a layer whose reachable motions cannot be
resolved, retain its source evidence, and expose only controls used by retained
layers. Original face clips can independently become explicit source presets.
"""
from copy import deepcopy

NEUTRAL = {'14980fc5fe40191418954549174fe63e',
           '91e5518865a04934b82b8aba11398609', '61a99b5de5e4b6d4c8ed51d9dfd9ddc7'}


def project(source, motions):
    data = deepcopy(source)
    parameters = {}
    for parameter in data['parameters']:
        previous = parameters.get(parameter['name'])
        if previous:
            if (previous['kind'], previous['initial']) != (parameter['kind'], parameter['initial']):
                raise ValueError('Conflicting author parameter defaults: '+parameter['name'])
            previous['saved'] = previous.get('saved', False) or parameter.get('saved', False)
        else:
            parameters[parameter['name']] = parameter
    data['parameters'] = list(parameters.values())
    clips = {m['guid'] for m in motions['motions']}
    retained, omitted = [], []
    for graph in data['controllers']:
        machines = {m['id']: m for m in graph['machines']}
        states = {s['id']: s for s in graph['states']}
        blends = {b['id']: b for b in graph['blends']}
        def dependencies(identity, seen=None):
            if identity in clips | NEUTRAL | {'', '0'}:
                return set()
            seen = set() if seen is None else seen
            if identity not in blends or identity in seen:
                return {identity}
            return set().union(*(dependencies(c['motion'], seen | {identity})
                                 for c in blends[identity]['children']))
        def descendants(identity):
            return {identity}.union(*(descendants(i) for i in machines[identity]['children']))
        kept_layers, kept_machines, kept_states = [], set(), set()
        for layer in graph['layers']:
            mids = descendants(layer['root'])
            sids = set().union(*(set(machines[i]['states']) for i in mids))
            missing = set().union(*(dependencies(states[i]['motion']) for i in sids))
            reason = ('host-stationary-body-baseline' if graph['playable'] == 0 else
                      'unresolved-source-motion' if missing else
                      'unsupported-synced-layer' if layer['synced'] != -1 else
                      'unsupported-machine-behavior' if any(machines[i]['behaviors'] for i in mids) else '')
            if reason:
                omitted.append(dict(playable=graph['playable'], layer=layer['name'],
                                    reason=reason, missing=sorted(missing), states=len(sids)))
                continue
            kept_layers.append(layer); kept_machines |= mids; kept_states |= sids
        if not kept_layers:
            continue
        graph['layers'] = kept_layers
        graph['machines'] = [m for m in graph['machines'] if m['id'] in kept_machines]
        graph['states'] = [s for s in graph['states'] if s['id'] in kept_states]
        used_blends = set()
        def visit(identity):
            if identity in blends and identity not in used_blends:
                used_blends.add(identity)
                for child in blends[identity]['children']: visit(child['motion'])
        for state in graph['states']: visit(state['motion'])
        graph['blends'] = [b for b in graph['blends'] if b['id'] in used_blends]
        graph['transitions'] = [t for t in graph['transitions']
            if (t['target'] in kept_states or t['target'] == '0') and
               (t['machine'] in kept_machines or t['machine'] == '0')]
        tids = {t['id'] for t in graph['transitions']}
        for state in graph['states']: state['transitions'] = [i for i in state['transitions'] if i in tids]
        for machine in graph['machines']:
            for key in ('any', 'entry'): machine[key] = [i for i in machine[key] if i in tids]
            machine['machineTransitions'] = [dict(link, transitions=[i for i in link['transitions'] if i in tids])
                for link in machine.get('machineTransitions', []) if link['machine'] in kept_machines]
        retained.append(graph)
    data['controllers'] = retained
    used = set()
    for graph in retained:
        used.update(c['parameter'] for t in graph['transitions'] for c in t['conditions'])
        used.update(b.get(k) for b in graph['blends'] for k in ('x', 'y'))
        used.update(c.get('parameter') for b in graph['blends'] for c in b['children'])
        for state in graph['states']:
            used.update(state.get(k) for k in ('timeParameter', 'speedParameter'))
            for behavior in state.get('behaviors', []):
                used.update(p.get('name') for p in behavior.get('parameters', []))
    unsupported = [dict(id=c['id'], label=c['label'], parameter=c['parameter'],
                        reason='No retained author layer consumes this control')
                   for c in source['controls'] if c['parameter'] not in used]
    data['controls'] = [c for c in data['controls'] if c['parameter'] in used]
    data['schemaVersion'] = 2; data['profile'] = 'mecanim-portable-v2'
    data['baselineFallbackMotions'] = sorted(NEUTRAL & {
        s['motion'] for g in retained for s in g['states']})
    return data, dict(omittedLayers=omitted, unavailableControls=unsupported,
                      sourceControls=len(source['controls']), retainedControls=len(data['controls']))
