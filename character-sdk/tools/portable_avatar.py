"""Capability-specific preflight for data-only avatar controller packages.

Old XCP packages never enter this validator. New mandatory behavior is negotiated
with core.avatar-controls@1; unknown optional JSON fields remain forward-safe.
"""
import math
import re
from pathlib import Path


def validate(root, manifest, read, path, inspect):
    capabilities=set(manifest['compatibility']['required']+manifest['compatibility']['optional'])
    required='core.avatar-controls@1' in manifest['compatibility']['required']
    if not required:
        if any(o.get('control',{}).get('id') for o in manifest.get('performance',{}).get('options',[])):
            raise ValueError('avatar controls require core.avatar-controls@1')
        return
    def need(ok, message):
        if not ok:raise ValueError('avatar-controls: '+message)
    def items(value, limit, label):
        need(isinstance(value,list) and len(value)<=limit,label+' count/type');return value
    def index(values,key,limit,label):
        items(values,limit,label); result={v[key]:v for v in values}
        need(len(result)==len(values),label+' duplicate ID');return result
    def name(value):return isinstance(value,str) and 0<len(value)<=256 and '\0' not in value
    def numeric(value):return isinstance(value,(int,float)) and not isinstance(value,bool) and math.isfinite(value)
    def acyclic(values,children,label):
        visiting=set();done=set()
        def visit(identity):
            need(identity not in visiting,label+' cycle')
            if identity in done:return
            visiting.add(identity)
            for child in children(values[identity]):
                if child in values:visit(child)
            visiting.remove(identity);done.add(identity)
        for identity in values:visit(identity)
    files={f['path'] for f in manifest['files']}
    needed={'avatar-controls.json','avatar-motions.json','avatar-geometry.json','materials.json','secondary-motion.json'}
    need(needed<=files,'required sidecars are absent from the sealed file list')
    data=read(path(root,'avatar-controls.json'))
    from jsonschema import Draft202012Validator
    schema=read(Path(__file__).resolve().parents[1]/'schemas/avatar-controls.schema.json')
    errors=list(Draft202012Validator(schema).iter_errors(data))
    need(not errors,'schema validation: '+('; '.join(e.message for e in errors[:3])))
    need(data.get('schemaVersion')==1 and data.get('profile')=='mecanim-portable-v1','unsupported profile/version')
    params=index(data['parameters'],'name',512,'parameters')
    for p in params.values():
        need(name(p['name']) and p['kind'] in ('float','int','bool','trigger') and numeric(p['initial']),'invalid parameter')
    controls=index(data['controls'],'id',256,'controls')
    for c in controls.values():
        need(name(c['id']) and name(c['label']) and name(c['group']) and c['parameter'] in params,'invalid control binding')
        need(c['kind'] in ('toggle','button','slider'),'unsupported control kind')
        need(all(numeric(c[k]) for k in ('minimum','maximum','initial','value')) and c['minimum']<c['maximum'],'invalid control range')
        for g in items(c.get('gates',[]),16,'menu gates'):
            need(g['parameter'] in params and numeric(g['value']),'invalid menu gate')
    options=manifest.get('performance',{}).get('options',[])
    need({o['control']['id'] for o in options}==set(controls),'manifest and controller options differ')
    for o in options:need(o['control']==controls[o['control']['id']],'stale embedded control')
    model=inspect(path(root,manifest['source']['model']))
    nodes={n['path'] for n in model['nodes']}
    def node(p):return isinstance(p,str) and ('Avatar'+('/'+p if p else '')) in nodes
    geometry=read(path(root,'avatar-geometry.json'))
    need(all(node(n['path']) for n in geometry['nodes']),'geometry node missing from GLB')
    motions=read(path(root,'avatar-motions.json'))
    clips=index(motions['motions'],'guid',4096,'motions')
    for clip in clips.values():
        need(numeric(clip['duration']) and 0<=clip['duration']<=600,'clip duration outside profile')
        times=items(clip['times'],36001,'sample times')
        need(times and all(numeric(t) and t>=0 for t in times) and all(a<b for a,b in zip(times,times[1:])),'invalid time sequence')
        for t in items(clip['tracks'],1024,'motion tracks'):
            need(node(t['path']),'track targets missing node')
            for k,axes in (('positions','xyz'),('rotations','xyzw'),('scales','xyz')):
                need(len(t[k])==len(times),'track/time mismatch')
                need(all(isinstance(v,dict) and all(a in v and numeric(v[a]) for a in axes) for v in t[k]),'invalid transform sample')
    masks=index(data['masks'],'id',64,'masks')
    for mask in masks.values():
        need(bool(re.fullmatch('[a-fA-F0-9]{104}',mask['body'])),'invalid humanoid mask bitset')
    # SDK neutral hand/standing proxies use the declared host rest baseline.
    # Movement/emote clips are never replaced by an empty or standing clip.
    fallbacks=set(data.get('baselineFallbackMotions',[]))
    need(fallbacks<={'14980fc5fe40191418954549174fe63e','91e5518865a04934b82b8aba11398609','61a99b5de5e4b6d4c8ed51d9dfd9ddc7'},'unreviewed motion fallback')
    for graph in items(data['controllers'],8,'controllers'):
        states=index(graph['states'],'id',4096,'states');machines=index(graph['machines'],'id',512,'machines')
        blends=index(graph['blends'],'id',512,'blend trees');transitions=index(graph['transitions'],'id',8192,'transitions')
        available=set(clips)|set(blends)|fallbacks|{'0',''}
        for s in states.values():
            need(s['motion'] in available,'unresolved state motion')
            need(set(s['transitions'])<=set(transitions),'unresolved state transition')
        for b in blends.values():need(all(c['motion'] in available for c in b['children']),'unresolved blend child')
        acyclic(blends,lambda b:[c['motion'] for c in b['children']],'blend tree')
        acyclic(machines,lambda m:m['children'],'nested state machine')
        for layer in items(graph['layers'],128,'layers'):
            need(layer['root'] in machines and (not layer['mask'] or layer['mask'] in masks),'unresolved layer root/mask')
            need(layer['synced']==-1,'synced layer needs a newer adapter')
        for m in machines.values():
            need(not m['behaviors'],'machine behavior needs a newer adapter')
            need(set(m['states'])<=set(states) and set(m['children'])<=set(machines),'unresolved machine child')
        for t in transitions.values():
            need(t['target']=='0' or t['target'] in states,'unresolved destination state')
            need(t['machine']=='0' or t['machine'] in machines,'unresolved destination machine')
            need(all(c['parameter'] in params and c['mode'] in (1,2,3,4,6,7) and numeric(c['threshold']) for c in t['conditions']),'invalid transition condition')
    materials=read(path(root,'materials.json'))
    need(materials.get('schemaVersion')==2 and materials.get('sourceProfile')=='liltoon-properties-v1','unknown material profile')
    for mat in items(materials['materials'],256,'materials'):
        need(bool(re.fullmatch('mat_[a-f0-9]{32}',mat['name'])),'invalid material identity')
        need(mat['shader'].startswith(('lilToon','Hidden/lilToon','_lil/')),'unapproved shader')
        for tex in mat['textures']:
            need(tex['path'].startswith('textures/') and tex['path'] in files,'unsealed/missing texture')
            path(root,tex['path'])
    secondary=read(path(root,'secondary-motion.json'))
    need('core.secondary-motion@2' in capabilities and secondary['schemaVersion']==2,'secondary profile/version mismatch')
    for strand in items(secondary['strands'],512,'secondary strands'):
        need(strand['bone'] in nodes and strand['tip'] in nodes and strand['tip'].rsplit('/',1)[0]==strand['bone'],'invalid strand binding')
        need(1<=strand['angle']<=20 and 0<=strand['radius']<=.05,'strand bounds')
    for collider in items(secondary['colliders'],256,'secondary colliders'):
        need(collider['bone'] in nodes and 0<=collider['radius']<=.5,'collider bounds')
