"""Map *actual* source FX curves to optional conversational expression hints.

Hand enum values and menu names are not emotion labels. We trace the selected
parameter to an FX state, inspect its nonzero face curves, and allow only known
expression semantics. Unknown or mixed costume/shape effects stay manual.
"""
import re

RULES=[
 (r'guruguru|ぐるぐる|confus|dizzy','confused','露出晕乎乎的神情',['confused','worried']),
 (r'angry|anger|怒|pout|sulk|mumu|puku','pout','露出一点小小的不满',['playful','serious','worried']),
 (r'sad|cry|tear|泣|悲','sad','神情变得委屈柔软',['sad','worried']),
 (r'wink|ウィンク','playful','俏皮地眨起一只眼睛',['happy','playful']),
 (r'kirakira|eye_star|キラキラ','bright_smile','眼睛闪亮起来',['happy','excited','curious']),
 (r'surpris|びっくり','surprised','露出惊讶的神情',['surprised','curious']),
 (r'doya|どや','proud','露出小小得意的神情',['happy','playful']),
 (r'smile|happy|joy|笑|nagomi|relax','soft_smile','神情变得轻松愉快',['neutral','happy','curious']),
 (r'shy|blush|cheek|照れ','shy','脸上浮起一点羞意',['playful','happy']),
]
UNSAFE=re.compile(r'breast|bust|nipple|underwear|nude|naked|ero[_ -]?|orgasm|ahe|costume|clothes|skirt|shirt|pants|hair_toggle',re.I)

def holds(condition,values):
    if condition['parameter'] not in values:return False
    value=values[condition['parameter']];threshold=condition.get('threshold',0)
    return {1:lambda:value!=0,2:lambda:value==0,3:lambda:value>threshold,4:lambda:value<threshold,
            6:lambda:abs(value-threshold)<1e-5,7:lambda:abs(value-threshold)>=1e-5}.get(condition['mode'],lambda:False)()

def classify(motion):
    # Animated object/material switches need a separate, reviewed adapter.
    if motion.get('objects'):return None
    shapes=[c for c in motion.get('curves',[]) if c['component']=='UnityEngine.SkinnedMeshRenderer'
        and c['property'].startswith('blendShape.') and any(k['value']>5 for k in c['keys'])]
    if not shapes:return None
    evidence=' '.join([motion['name']]+[c['property'][11:] for c in shapes])
    if UNSAFE.search(evidence):return None
    for text in (motion['name'],evidence):
        for pattern,intent,effect,moods in RULES:
            if re.search(pattern,text,re.I):return dict(kind='expression',intent=intent,effects=[effect],moods=moods,
                automatic=True,speechCompatible=True,cooldownSeconds=5,conflicts=[])
    return None

def hints(controls,motions):
    clips={m['guid']:m for m in motions['motions']};result={};evidence={}
    defaults={p['name']:p['initial'] for p in controls['parameters']}
    for control in controls['controls']:
        if control['kind']=='slider' or abs(control['value'])<1e-5:continue
        values=dict(defaults);values.update({g['parameter']:g['value'] for g in control.get('gates',[])})
        values[control['parameter']]=control['value']
        candidates=[]
        for graph in controls['controllers']:
            if graph['playable']!=5:continue
            states={s['id']:s for s in graph['states']}
            for transition in graph['transitions']:
                conditions=transition['conditions']
                if not any(c['parameter']==control['parameter'] for c in conditions) or not all(holds(c,values) for c in conditions):continue
                state=states.get(transition['target']);motion=clips.get(state['motion']) if state else None
                if motion and (hint:=classify(motion)):candidates.append((hint,motion))
        intents={c[0]['intent'] for c in candidates}
        if len(intents)!=1:continue
        result[control['id']]=candidates[0][0]
        evidence[control['id']]=dict(parameter=control['parameter'],value=control['value'],
            motions=[dict(guid=m['guid'],name=m['name']) for _,m in candidates],intent=candidates[0][0]['intent'])
    return result,evidence
