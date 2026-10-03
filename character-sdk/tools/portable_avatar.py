"""Capability-specific preflight for data-only avatar controller packages.

Old XCP packages never enter this validator. New mandatory behavior is negotiated
with core.avatar-controls@1; unknown optional JSON fields remain forward-safe.
"""
import math
import re
from pathlib import Path


def validate_secondary(secondary, capabilities, model, options=()):
    """Validate scoped collisions even for avatars without controller graphs."""
    def need(ok, message):
        if not ok:raise ValueError('secondary-motion: '+message)
    def numeric(value):return isinstance(value,(int,float)) and not isinstance(value,bool) and math.isfinite(value)
    def vector(value):return isinstance(value,dict) and all(numeric(value.get(a)) for a in 'xyz')
    version=secondary.get('schemaVersion')
    need(version in (2,3,4) and f'core.secondary-motion@{version}' in capabilities,'secondary profile/version mismatch')
    nodes={n['path']:n for n in model['nodes']}
    strands=secondary.get('strands');colliders=secondary.get('colliders');planes=secondary.get('planes',[])
    need(isinstance(strands,list) and len(strands)<=512,'strand count/type')
    need(isinstance(colliders,list) and len(colliders)<=256,'collider count/type')
    need(isinstance(planes,list) and len(planes)<=256 and (version==4 or not planes),'plane profile/count')
    ids=set()
    for collider in colliders:
        need(collider['bone'] in nodes and numeric(collider['radius']) and collider['radius']>=0,'collider binding/radius')
        local=collider.get('localRadius',False)
        need(isinstance(local,bool),'collider radius space')
        need(not local or version>=3,'local collider radius requires secondary-motion@3 or newer')
        effective=collider['radius']*(max(nodes[collider['bone']]['scaleFactors']) if local else 1)
        need(numeric(effective) and effective<=.5,'collider bounds')
        need(vector(collider.get('offset')),'collider offset')
        if version==4:
            need(isinstance(collider.get('id'),str) and 0<len(collider['id'])<=128,'collider identity')
            ids.add(collider['id'])
    for plane in planes:
        need(plane.get('bone') in nodes and vector(plane.get('offset')) and vector(plane.get('normal')),'plane binding/vector')
        need(abs(sum(plane['normal'][a]**2 for a in 'xyz')-1)<.001,'plane normal must be unit length')
        need(isinstance(plane.get('id'),str) and 0<len(plane['id'])<=128 and plane['id'] not in ids,'plane identity')
        ids.add(plane['id'])
    chain_ids=set()
    for strand in strands:
        need(strand['bone'] in nodes and strand['tip'] in nodes and strand['tip'].rsplit('/',1)[0]==strand['bone'],'invalid strand binding')
        need(numeric(strand['angle']) and numeric(strand['radius']) and 1<=strand['angle']<=20 and 0<=strand['radius']<=.05,'strand bounds')
        if version==4:
            scope=strand.get('colliderIDs')
            need(isinstance(scope,list) and len(scope)<=256 and all(isinstance(i,str) and i in ids for i in scope),'unresolved collider association')
            need(len(scope)==len(set(scope)),'duplicate collider association')
            chains=strand.get('chainIDs',[])
            need(isinstance(chains,list) and all(isinstance(i,str) and 0<len(i)<=128 for i in chains),'chain identities')
            chain_ids.update(chains)
            need(isinstance(strand.get('initialEnabled',True),bool),'initial strand state')
    controls=secondary.get('controls',[])
    need(isinstance(controls,list) and len(controls)<=256 and (version==4 or not controls),'physics control profile/count')
    option_ids={o['id'] for o in options}
    for control in controls:
        need(control.get('option') in option_ids and control.get('kind') in ('preset','motion','toggle'),'physics option binding')
        for side in ('on','off'):
            bindings=control.get(side)
            need(isinstance(bindings,list) and len(bindings)<=256,'physics binding count/type')
            for binding in bindings:
                need(binding.get('kind') in ('chain','collider') and binding.get('id') in (chain_ids if binding['kind']=='chain' else ids) and isinstance(binding.get('enabled'),bool),'unresolved physics control binding')


def validate_materials(root, manifest, read, path):
    materials=read(path(root,'materials.json'))
    if materials.get('schemaVersion')!=2 or materials.get('sourceProfile')!='liltoon-properties-v1':
        raise ValueError('full lilToon capability requires the typed portable material profile')
    files={f['path'] for f in manifest['files']}
    for mat in materials['materials']:
        if not re.fullmatch('mat_[a-f0-9]{32}',mat['name']) or not mat['shader'].startswith(('lilToon','Hidden/lilToon','_lil/')):
            raise ValueError('unapproved material identity/shader')
        for tex in mat['textures']:
            if not tex['path'].startswith('textures/') or tex['path'] not in files:
                raise ValueError('unsealed/missing material texture')
            path(root,tex['path'])


def validate(root, manifest, read, path, inspect):
    capabilities=set(manifest['compatibility']['required']+manifest['compatibility']['optional'])
    required=bool({'core.avatar-controls@1','core.avatar-controls@2'} & set(manifest['compatibility']['required']))
    if not required:
        if 'core.secondary-motion@4' in capabilities:
            validate_secondary(read(path(root,'secondary-motion.json')),capabilities,inspect(path(root,manifest['source']['model'])),manifest.get('performance',{}).get('options',[]))
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
    motion_file='avatar-motions.json.gz' if 'core.source-motions@1' in capabilities else 'avatar-motions.json'
    needed={'avatar-controls.json',motion_file,'avatar-geometry.json','materials.json','secondary-motion.json'}
    need(needed<=files,'required sidecars are absent from the sealed file list')
    data=read(path(root,'avatar-controls.json'))
    from jsonschema import Draft202012Validator
    schema=read(Path(__file__).resolve().parents[1]/'schemas/avatar-controls.schema.json')
    errors=list(Draft202012Validator(schema).iter_errors(data))
    need(not errors,'schema validation: '+('; '.join(e.message for e in errors[:3])))
    version=data.get('schemaVersion')
    need(version in (1,2) and data.get('profile')==f'mecanim-portable-v{version}' and f'core.avatar-controls@{version}' in manifest['compatibility']['required'],'unsupported profile/version')
    params=index(data['parameters'],'name',512,'parameters')
    for p in params.values():
        need(name(p['name']) and p['kind'] in ('float','int','bool','trigger') and numeric(p['initial']),'invalid parameter')
    controls=index(data['controls'],'id',2048 if version==2 else 256,'controls')
    for c in controls.values():
        need(name(c['id']) and name(c['label']) and name(c['group']) and c['parameter'] in params,'invalid control binding')
        need(c['kind'] in ('toggle','button','slider'),'unsupported control kind')
        need(all(numeric(c[k]) for k in ('minimum','maximum','initial','value')) and c['minimum']<c['maximum'],'invalid control range')
        for g in items(c.get('gates',[]),16,'menu gates'):
            need(g['parameter'] in params and numeric(g['value']),'invalid menu gate')
    options=manifest.get('performance',{}).get('options',[])
    need({o['control']['id'] for o in options if o.get('control')}==set(controls),'manifest and controller options differ')
    for o in options:
        if o.get('control'):need(o['control']==controls[o['control']['id']],'stale embedded control')
    model=inspect(path(root,manifest['source']['model']))
    nodes={n['path'] for n in model['nodes']}
    scale_factors={n['path']:n['scaleFactors'] for n in model['nodes']}
    def node(p):return isinstance(p,str) and ('Avatar'+('/'+p if p else '')) in nodes
    geometry=read(path(root,'avatar-geometry.json'))
    need(all(node(n['path']) for n in geometry['nodes']),'geometry node missing from GLB')
    def motion_json(filename):
        if not filename.endswith('.gz'):return read(path(root,filename))
        import gzip,json
        with gzip.open(path(root,filename),'rb') as stream:
            raw=stream.read(128*1024*1024+1)
        need(len(raw)<=128*1024*1024,'expanded motion data budget exceeded')
        return json.loads(raw)
    motions=motion_json(motion_file)
    if 'core.source-motions@1' in capabilities:
        need('source-motions.json.gz' in files,'source motion library missing from sealed files')
        library=motion_json('source-motions.json.gz')
        library_schema=read(Path(__file__).resolve().parents[1]/'schemas/source-motions.schema.json')
        errors=list(Draft202012Validator(library_schema).iter_errors(library))
        need(not errors,'source schema validation: '+('; '.join(e.message for e in errors[:3])))
        need(library.get('schemaVersion')==1 and library.get('parameter')=='Starry_SourceMotion','source motion profile')
        reserved=params.get(library['parameter'],{})
        need(reserved.get('kind')=='int' and reserved.get('initial')==0 and not reserved.get('saved',False),'source preview parameter must be transient integer')
        entries=index(library.get('motions'), 'guid',2048,'source motion library')
        previews=[c for c in controls.values() if c['parameter']==library['parameter']]
        need(len(previews)==len(entries),'source library/control count')
        for i,m in enumerate(library['motions'],1):
            need(name(m['name']) and numeric(m['duration']) and 0<=m['duration']<=120,'source motion duration/name')
            c=controls.get('source-motion-'+m['guid'])
            need(c is not None and c['value']==i and c['initial']==0 and c['kind']=='button','source motion control mapping')
            need(m['tracks'] or m['curves'],'empty source motion')
            need(all(node(t['path']) and t['path'] for t in m['tracks']),'source motion targets')
            need(all(node(c['path']) and c['path'] and (
                c['component']=='UnityEngine.GameObject' and c['property']=='m_IsActive' or
                c['component'] in ('UnityEngine.MeshRenderer','UnityEngine.SkinnedMeshRenderer') and c['property']=='m_Enabled' or
                c['component']=='UnityEngine.SkinnedMeshRenderer' and c['property'].startswith('blendShape.')
                and c['property'][11:] in next(n.get('morphs',[]) for n in model['nodes'] if n['path']=='Avatar/'+c['path']))
                     for c in m['curves']),'source curve allowlist')
            for curve in m['curves']:
                keys=curve['keys']
                need(all(numeric(k[n]) for k in keys for n in ('time','value','inTangent','outTangent','inWeight','outWeight')),'source key must be finite')
                need(all(0<=k['time']<=m['duration']+.0001 for k in keys) and all(a['time']<b['time'] for a,b in zip(keys,keys[1:])),'source key time sequence')
        # Validate source transform samples using the same bounded track profile.
        motions=dict(motions,motions=motions['motions']+library['motions'])
    # Original-library GUIDs may also be referenced by the original controller.
    # They remain distinct compiled clips; validate both data versions.
    clips=index(motion_json(motion_file)['motions'],'guid',4096,'motions')
    for clip in motions['motions']:
        need(numeric(clip['duration']) and 0<=clip['duration']<=600,'clip duration outside profile')
        times=items(clip['times'],36001,'sample times')
        need(times and all(numeric(t) and t>=0 for t in times) and all(a<b for a,b in zip(times,times[1:])),'invalid time sequence')
        for t in items(clip['tracks'],1024,'motion tracks'):
            need(node(t['path']),'track targets missing node')
            track_times=t.get('times',times)
            need('times' not in t or version==2,'per-track samples require avatar-controls@2')
            need(isinstance(track_times,list) and 0<len(track_times)<=len(times) and all(numeric(v) and times[0]<=v<=times[-1] for v in track_times) and all(a<b for a,b in zip(track_times,track_times[1:])),'invalid per-track time sequence')
            for k,axes in (('positions','xyz'),('rotations','xyzw'),('scales','xyz')):
                need(len(t[k])==len(track_times),'track/time mismatch')
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
    validate_secondary(read(path(root,'secondary-motion.json')),capabilities,model,options)
