import random, math, time, re
from .profiles import assets

FALLBACK={'shy_smile':['soft_smile','neutral'],'teasing_smile':['soft_smile','neutral'],
 'bright_smile':['soft_smile','neutral'],'worried':['thinking','neutral'],
 'nod':['idle'],'shake_head':['idle'],'wave':['open_hands','idle'],'cover_mouth':['idle'],
 'look_away':['idle'],'lean_forward':['idle'],'hug':['idle']}

class Director:
    def __init__(self,store,rng=None):self.store=store;self.rng=rng or random.Random()
    def capability(self,character,available):
        enabled=[a for a in assets(character) if a['asset_id'] in available]
        return dict(supported_expression_intents=sorted({'neutral'}|{a['intent'] for a in enabled if a['kind']=='expression'}),
                    supported_action_intents=sorted({'idle'}|{a['intent'] for a in enabled if a['kind']=='action'}))
    def resolve(self,owner,character,kind,intent,intensity,relationship,state,available):
        now=time.time()
        library=[a for a in assets(character) if a['enabled'] and a['asset_id'] in available and a['kind']==kind]
        candidates=[];match='exact'
        for semantic in [intent]+FALLBACK.get(intent,['neutral' if kind=='expression' else 'idle']):
            if semantic in ('neutral','idle'): return None, 'none'
            for a in library:
                if a['intent']!=semantic or relationship.get('closeness',0)<a['min_closeness'] or state.get('anger',0)>a['max_anger']:continue
                if not a['intensity_min']<=intensity<=a['intensity_max']:continue
                row=self.store.db.execute('SELECT count(*),max(created) FROM asset_usage WHERE owner=? AND character=? AND asset=?',(owner,character,a['asset_id'])).fetchone()
                used,last=row[0],row[1] or 0
                if now-last<a['cooldown_sec']:continue
                style=(1-.4*intensity) if character=='anime-kipfel' else (.6+.4*intensity)
                context=(1-state.get('anxiety',.1)) if kind=='action' else (.7+.3*state.get('attention_to_user',.7))
                score=.35*(1 if semantic==intent else .75)+.20*(1-abs(intensity-(a['intensity_min']+a['intensity_max'])/2))+.15*style+.10*context+.10*min(1,(now-last)/120)+.05*(1 if a['rarity']=='common' else .7)+.05/(used+1)
                candidates.append((a,score*a['base_weight']))
            if candidates:
                candidates=sorted(candidates,key=lambda x:x[1],reverse=True)[:4]
                chosen=self.rng.choices([a for a,_ in candidates],weights=[w for _,w in candidates],k=1)[0]
                with self.store.db:self.store.db.execute('INSERT INTO asset_usage(owner,character,asset,kind,created) VALUES(?,?,?,?,?)',(owner,character,chosen['asset_id'],kind,now))
                return chosen,match
            match='approximate'
        return None,'none'
    def beat(self,owner,character,beat,relationship,state,available):
        performance=beat.performance.model_copy()
        for vocal in beat.vocal_events:
            if vocal.visual_sync:
                if performance.expression_intent=='neutral':performance.expression_intent=vocal.visual_sync.expression_intent
                if performance.action_intent=='idle':performance.action_intent=vocal.visual_sync.action_intent
        face,fg=self.resolve(owner,character,'expression',performance.expression_intent,performance.intensity,relationship,state,available)
        action,ag=self.resolve(owner,character,'action',performance.action_intent,performance.intensity,relationship,state,available)
        return dict(beat_id=beat.beat_id,expression_asset=face,action_asset=action,
                    grounding='approximate' if 'approximate' in (fg,ag) else 'exact' if face or action else 'none')

def grounded(narration,resolved,appearance_facts=()):
    entry=next((r for r in resolved if r['beat_id']==narration.beat_id),None)
    if not entry:return False
    effects=[s for k in ('expression_asset','action_asset') if entry.get(k) for s in entry[k]['observable_effects']]
    if narration.mode=='performed' and (not effects or not narration.evidence or any(e not in effects for e in narration.evidence)):return False
    if narration.mode=='performed':
        # Hard grounding: a valid citation alone is insufficient. Models can cite
        # a hand pose and then hallucinate handing over a cup. Permit only the
        # cited observable clauses (plus punctuation/pronoun), never an expansion.
        clean=lambda s: re.sub(r'[\s，。；、！,.!;：:她他]+','',s)
        if clean(narration.text)!=clean(''.join(narration.evidence)):return False
    if narration.mode=='literary':
        if narration.visual_grounding!='none':return False
        # Facts are reviewed server-side character metadata. Client scene text
        # and fictional backstory never authorize claims about the actual image.
        remainder=narration.text
        for fact in narration.evidence:
            if fact not in appearance_facts or fact not in remainder:return False
            remainder=remainder.replace(fact,'',1)
        # The rest may describe conversational pace only. A real cited eye/hair
        # trait cannot be used to smuggle in an unperformed physical interaction.
        words=r'(?:短暂|片刻|轻轻|微微|渐渐|稍稍|慢慢|柔和|温柔|安静|轻柔|平静|停顿|沉默|对话|话语|话音|语气|交流|声音|字句|余音|这一刻|此刻|之间|之中|落下|放缓|停留|延续|流淌|散开|下来|一点|一阵|让|中|在|的|地|得|了|也|更|很|里|间|变|得以|带着|显得|随着|和|与|而|着|是|一|丝|份|分|，|。|、|；|：|…|\s)'
        if not re.fullmatch(words+r'*',remainder):return False
    # Do not display common hallucinated physical interactions even if the model
    # incorrectly cites an otherwise valid facial expression as evidence.
    forbidden=['走到','走向','拿起','抱住','拥抱','拍你','拍了拍','捂嘴','捂住嘴','抬手','伸手','伸出手','打开门','靠在你','坐到','递给','摸了摸','转过身','偏过头','别过脸','转过头']
    return not any(x in narration.text and not any(x in e for e in effects) for x in forbidden)

def grounded_excerpt(narration,resolved,appearance_facts=()):
    """Render only independently grounded clauses or the model's verified citations.

    A correct hair description followed by invented sunlight should lose the
    sunlight, not the valid clause. If the prose entirely rewrites those facts,
    use the actual citations the AI selected. No random/local conversation reply
    or invented action is introduced, and a performance is never relabelled.
    """
    if grounded(narration,resolved,appearance_facts):return narration
    parts=[];evidence=[]
    for clause in re.split(r'[，。！？；,!?;\n]+',narration.text):
        clause=clause.strip()
        if not clause:continue
        citations=[e for e in narration.evidence if e in clause]
        candidate=narration.model_copy(update={'text':clause,'evidence':citations})
        if grounded(candidate,resolved,appearance_facts):
            parts.append(clause)
            for citation in citations:
                if citation not in evidence:evidence.append(citation)
    if parts:
        excerpt=narration.model_copy(update={'text':'。'.join(parts)+'。','evidence':evidence})
        if grounded(excerpt,resolved,appearance_facts):return excerpt
    if narration.evidence:
        cited=narration.model_copy(update={'text':'。'.join(dict.fromkeys(narration.evidence))+'。',
                                         'evidence':list(dict.fromkeys(narration.evidence))})
        if grounded(cited,resolved,appearance_facts):return cited
    return None
