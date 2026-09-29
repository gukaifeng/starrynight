"""Data-only natural idle adaptation authorized on 2026-09-30.

Source clips stay unchanged. The host supplies a local blink scheduler and wind,
not a VRChat SDK state machine. Reusable by full conversion and sidecar updates.
"""
from collections import Counter
import copy
import numpy as np


def amplify_rotations(values, gain):
    """Scale a short-arc rotation about its first key, never Euler components."""
    from prepare_anime_characters import multiply, normalize
    q=normalize(np.asarray(values,dtype=np.float64))
    delta=normalize(multiply(q[0]*np.array([-1.,-1.,-1.,1.]),q))
    delta=np.where(delta[:,3:]<0,-delta,delta)
    sine=np.linalg.norm(delta[:,:3],axis=1,keepdims=True)
    half=np.arctan2(sine,delta[:,3:])*gain
    scaled=np.concatenate([delta[:,:3]/np.maximum(sine,1e-12)*np.sin(half),np.cos(half)],axis=1)
    return normalize(multiply(q[0],scaled))


def append_visible_idle(b,role,source_idle):
    """Keep original clips and compose an explicitly labelled, stronger idle.

    Only the audited Chest/Head rotations gain amplitude. Hips translations,
    hips rotations, feet, timing and static source pose offsets remain intact.
    Static poses use the same adapted additive breath, so it never doubles.
    """
    from prepare_anime_characters import paths
    gain={'kipfel':4.,'mamehinata':3.}[role]
    clips=b.doc['animations'];lookup={a['name']:a for a in clips};node_paths=paths(b.doc)
    if 'Source_Idle' in lookup or 'App_VisibleBreath' in lookup:
        raise ValueError('Visible idle already adapted; rebuild from source, do not multiply twice')
    source=lookup['Idle'];source['name']='Source_Idle'
    changes=[]
    for original,name in [(source,'Idle'),(lookup[source_idle['sourceBreathClip']],'App_VisibleBreath')]:
        adapted=copy.deepcopy(original);adapted['name']=name;changed=set()
        for channel in adapted['channels']:
            node=channel['target']['node'];path=node_paths[node]
            if channel['target']['path']!='rotation' or path.rsplit('/',1)[-1] not in ('Chest','Head'):continue
            sampler=adapted['samplers'][channel['sampler']]
            values=b.array(sampler['output']);scaled=amplify_rotations(values,gain)
            from prepare_anime_characters import multiply,normalize
            delta=normalize(multiply(scaled[0]*np.array([-1.,-1.,-1.,1.]),scaled))
            peak=float(np.max(2*np.arctan2(np.linalg.norm(delta[:,:3],axis=1),np.abs(delta[:,3]))*180/np.pi))
            if peak>8:raise ValueError('Adapted idle exceeds reviewed upper-body motion budget: '+path)
            sampler['output']=b.add(scaled,'VEC4');changed.add(path.rsplit('/',1)[-1])
            changes.append(dict(clip=name,bone=path,gain=gain,peakDegrees=peak))
        if changed!={'Chest','Head'}:raise ValueError('Audited upper-body breath channels missing')
        clips.append(adapted)
    return dict(revision=2,sourceIdleClip='Source_Idle',idleClip='Idle',breathClip='App_VisibleBreath',
        upperBodyGain=gain,channels=changes,
        policy='App amplitude adaptation on original Chest/Head motion; source clips, timeline, hips and foot motion unchanged.')


def profile(role, manifest, source_idle):
    options=manifest['performance']['options']
    # Sleep's authored face owns its eyelids, including the entering/leaving fade.
    suppress=[o['id'] for o in options if o['group']=='pose' and (o['morphs'] or o['morphTracks'])]
    static=[o['id'] for o in options if o['group']=='pose' and o.get('loop') and
            o.get('duration')==1 and not o['morphTracks'] and not o['morphs']]
    mame=role=='mamehinata'
    return dict(schemaVersion=1,
        blink=dict(bindings=[dict(renderer=manifest['rig']['headRenderer'],shape='Auto_Blink' if mame else 'eye_close',weight=1)],
            intervals=[.3,10,6,6,6] if mame else [3.2,4.7,5.8,3.9,4.4],
            closeSeconds=.16,closedSeconds=.035,
            openSeconds=.26,firstDelay=2.2 if mame else 1.8,
            suppressGroups=['expression'],suppressOptions=suppress),
        breathing=dict(clip=source_idle.get('adaptation',{}).get('breathClip',source_idle['sourceBreathClip']),
            bones=sorted({x['bone'] for x in source_idle['channels']}),poseOptions=static))


def configure_wind(data):
    data['ambientHairAngle']=7.5
    data['ambientClothAngle']=3.2
    for s in data['strands']:
        # Reviewed explicit source-chain classes. Never blow the body, ears,
        # tails, solid bags, name tags or short attachment/bell chains.
        name=s['bone'].rsplit('/',1)[-1].lower()
        cloth=any(t in name for t in ('ribbon','shorts','yakke_sode','pocket_string'))
        hair=not cloth and any(t in name for t in ('hair','ahoge'))
        s['wind']='cloth' if cloth else 'hair' if hair else 'none'
        s['windResponse']=.85 if cloth else .9 if hair else 0
    return dict(hairAngle=data['ambientHairAngle'],clothAngle=data['ambientClothAngle'],
                chains=dict(Counter(s['wind'] for s in data['strands'])),source='App environment adaptation, not source avatar motion')


def provenance(role):
    gain=4 if role=='kipfel' else 3
    return dict(revision=2,authorization='2026-09-30: clearly visible idle and hair/cloth motion, slower individual blinks requested',
        breathing=f'App-adapted Chest/Head rotation amplitude {gain}x around original first keys. Hips and feet, original 2.5 s timing, Source_Idle and VRC clips unchanged. Static poses use App_VisibleBreath; neutral and sleep never double breath.',
        blink=('Original Auto_Blink morph and unchanged source interval lottery; ' if role=='mamehinata' else 'Original eye_close morph and unchanged App interval schedule; ')+
              'App timing: close 0.16 s, hold 0.035 s, open 0.26 s (0.455 s total). Timing adaptation, not original SDK behavior.',
        priority='Manual expressions and sleep transitions suppress automatic blinking. Mouth visemes remain separate.',
        wind='App-authored visible horizontal breeze: 7.5 degree hair and 3.2 degree cloth force budgets, 0.9/0.85 response; original chain-angle and collision constraints remain. No upward gusts or direct bone sine animation.')


def notice(role):
    p=provenance(role)
    return '# Avatar conversion and natural idle\n\nAuthor: もち山金魚 / MOCHIYAMA.\n\n'+ '\n\n'.join(p[k] for k in ('breathing','blink','priority','wind'))+ '\n\nOriginal facial, hand, ear, tail and appearance options are retained. No SDK code or default VRChat motions are included. Source archives and samples remain unchanged. The standalone spring approximation is not the VRChat PhysBone solver.\n'
