"""Data-only natural idle adaptation authorized on 2026-09-30.

Source clips stay unchanged. The host supplies a local blink scheduler and wind,
not a VRChat SDK state machine. Reusable by full conversion and sidecar updates.
"""
from collections import Counter


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
            closeSeconds=.08 if mame else .09,closedSeconds=0 if mame else .025,
            openSeconds=.06 if mame else .14,firstDelay=2.2 if mame else 1.8,
            suppressGroups=['expression'],suppressOptions=suppress),
        breathing=dict(clip=source_idle['sourceBreathClip'],bones=sorted({x['bone'] for x in source_idle['channels']}),poseOptions=static))


def configure_wind(data):
    data['ambientHairAngle']=2.2
    data['ambientClothAngle']=.65
    for s in data['strands']:
        # Reviewed explicit source-chain classes. Never blow the body, ears,
        # tails, solid bags, name tags or short attachment/bell chains.
        name=s['bone'].rsplit('/',1)[-1].lower()
        cloth=any(t in name for t in ('ribbon','shorts','yakke_sode','pocket_string'))
        hair=not cloth and any(t in name for t in ('hair','ahoge'))
        s['wind']='cloth' if cloth else 'hair' if hair else 'none'
        s['windResponse']=.6 if cloth else .68 if hair else 0
    return dict(hairAngle=data['ambientHairAngle'],clothAngle=data['ambientClothAngle'],
                chains=dict(Counter(s['wind'] for s in data['strands'])),source='App environment adaptation, not source avatar motion')


def provenance(role):
    return dict(revision=1,authorization='2026-09-30: automatic blinking, breathing/idle and ambient wind requested',
        breathing='Unchanged source stand + breath; source additive breath also layers onto authored static poses. Never double breath in neutral Idle or sleep clips.',
        blink=('Restored source Auto_Blink shape and Auto_Blink FX durations: close 0.08 s, open 0.06 s; interval lottery 0.3 / 10 / 6 / 6 / 6 s. Initial 2.2 s and smooth interpolation are App adaptations; not a full SDK graph emulation.' if role=='mamehinata' else
               'Original eye_close morph with App-authored irregular blink timing; no verified source automatic schedule claimed.'),
        priority='Manual expressions and sleep transitions suppress automatic blinking. Mouth visemes remain separate.',
        wind='App-authored low-amplitude horizontal breeze, independent hair/cloth budgets, source chains and collision spheres; no upward gusts or direct bone sine animation.')


def notice(role):
    p=provenance(role)
    return '# Avatar conversion and natural idle\n\nAuthor: もち山金魚 / MOCHIYAMA.\n\n'+ '\n\n'.join(p[k] for k in ('breathing','blink','priority','wind'))+ '\n\nOriginal facial, hand, ear, tail and appearance options are retained. No SDK code or default VRChat motions are included. Source archives and samples remain unchanged. The standalone spring approximation is not the VRChat PhysBone solver.\n'
