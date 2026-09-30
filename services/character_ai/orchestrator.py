import asyncio, base64, random, re, time, uuid
from contextlib import aclosing
from .schemas import Plan, TimelinePlan, ShakeTimelinePlan, NarrationResult, Speech, Vocal, PerformanceCue, visible_text, visible_thought, CONTROL_TEXT
from .profiles import PROFILES
from .prompts import PLANNER, NARRATOR
from .director import Director, grounded_excerpt, visible_narration
from .storage import clamp, dump
from .speech_text import audio_key
from .greetings import ENTRY_TRIGGERS, greeting_context, plan_text
from . import novelty
from .reply_flow import compile_parts, duration_hint
from .semantic_novelty import SemanticNovelty

def event(kind, **data): return dict(type=kind,**data)

INTERACTION_TRIGGERS={'model_shaken','model_pinched'}
PINCH_ROTATION_LANGUAGE=re.compile(r'转圈|转来转去|摇晃|晃动|晃[得晕]|摇头|头晕')

def interaction_mismatch(request,text):
    if request.trigger!='model_pinched' or not request.interaction:return None
    if PINCH_ROTATION_LANGUAGE.search(text):
        return '本次是双指缩放，不是旋转或摇晃；台词把互动说错了。按interaction_context.kind重新回应，不要复述错误动作或头晕。'
    return None
def brief_shake_plan(plan,mood):
    """Keep one AI-authored reaction; never manufacture a local complaint.

    Character models sometimes append unrelated invitation beats. Keep the
    reaction beat, but retain its second clause: cutting at the first generic
    complaint discarded both its fresh content and later thought anchors.
    """
    first=next((b for b in plan.beats if b.dialogue),None)
    if first is None:return
    plan.beats=[first];plan.memory_updates=[]
    lines=re.split(r'(?<=[。！？!?～])\s*',first.dialogue.text)
    kept=''
    for line in lines:
        if not line:continue
        if kept and len(kept+line)>70:break
        kept+=line
    first.dialogue.text=kept or first.dialogue.text
    plan.state_interpretation.dominant_emotion=mood
    first.dialogue.speech.emotion='happy' if mood=='playful' else 'serious'
    first.dialogue.speech.delivery='teasing' if mood=='playful' else 'soft'
    face='pout' if mood=='playful' else 'serious'
    first.performance.expression_intent=face
    first.performance.cues=[c for c in first.performance.cues if c.group!='expression' or c.offset_ms>=2200][:22]
    first.performance.cues.insert(0,PerformanceCue(group='expression',intent=face))
    if not any(c.group=='expression' and c.offset_ms>=2200 for c in first.performance.cues):
        first.performance.cues.append(PerformanceCue(group='expression',intent='soft_smile',offset_ms=2800))

class Orchestrator:
    def __init__(self,settings,store,provider):
        self.settings,self.store,self.provider=settings,store,provider
        self.director=Director(store)
        self.semantic=SemanticNovelty(settings,store)
    def context(self,owner,request,*,persist=True):
        char=request.character_id
        if persist:self.store.sync_memories(owner,char,request.memories)
        context = dict(character_profile={k:v for k,v in PROFILES[char].items() if k not in ('voice_prompt','preview_text','voice_revision','voice_delivery','appearance_facts')},
            user_message=request.text,trigger=request.trigger,preferences=request.preferences,scene=request.scene,
            recent_messages=self.store.history(owner,char) or [m.model_dump() for m in request.recent_messages],memories=self.store.recall(owner,char,request.text,incoming=None if persist else request.memories,touch=persist),
            relationship=self.store.get('relationship',owner,char,dict(closeness=.05,trust=.1,conflict=0)),
            state=self.store.state(owner,char),avatar_capability=self.director.capability(char,request.available_assets),
            speech_capability=dict(emotions=Speech.model_json_schema()['properties']['emotion']['enum'],
                                   deliveries=Speech.model_json_schema()['properties']['delivery']['enum'],
                                   vocal_events=Vocal.model_json_schema()['properties']['event']['enum']))
        # Retain original archives, but don't feed historical broken control JSON
        # back to the model as a demonstration of how to speak.
        context['recent_messages']=[m for m in context['recent_messages'] if m['role']!='assistant' or not CONTROL_TEXT.search(m['text'])]
        context['novelty_context']=novelty.context(self.store,owner,char)
        context['recent_response_focus']=self.store.get('response_focus',owner,char,[])
        context['reply_format']='timeline-v2' if request.timeline_reply else 'legacy'
        if request.trigger in ENTRY_TRIGGERS:
            last = self.store.db.execute('SELECT max(created) FROM messages WHERE owner=? AND character=?',(owner,char)).fetchone()[0]
            context['greeting_context'] = greeting_context(context['recent_messages'],
                self.store.get('greetings',owner,char,[]),max(0,int(time.time()-last)) if last else None)
        if request.trigger in INTERACTION_TRIGGERS:
            kind=request.interaction.kind if request.interaction else 'shake'
            gesture={
                'shake':'用户刚刚连续晃动虚拟角色，这是单指转动，不是捏或拉扯。',
                'pinch_out':'用户刚刚双指向外拉开，临时放大了角色，如同轻扯着拉近一点。围绕这次拉近、轻扯的玩闹回应；绝不能误说转、摇晃或头晕。',
                'pinch_in':'用户刚刚双指向内收拢，临时缩小了角色，如同轻轻捏了一下。围绕这次轻捏、缩小的玩闹回应；绝不能误说转、摇晃或头晕。',
            }[kind]
            context['interaction_context']=dict(kind=kind,intensity=request.interaction.intensity if request.interaction else 0,
                mood=random.choice(['playful','serious']) if persist else 'playful',
                task=gesture+'用角色的个性做一次新的撒娇回应或轻微生气的小抱怨，1个beat、短短1至2句，附多组真实表演。注意与之前的反应不同：推进这次玩闹，而非再次复述同一种不适或同一句请求。只是显示变换，不编造身体变形、衣服变化或现实伤害，不重答过去的问题。')
        return context
    async def narration(self,owner,char,plan,resolved,scene):
        facts=[]
        try:
            async with asyncio.timeout(self.settings.narration_timeout_seconds):
                result=await self.provider.structured(owner,char,'narration',NARRATOR,
                    dict(plan=plan.model_dump(),resolved=resolved,scene=scene),NarrationResult)
                reviewed=[(n,grounded_excerpt(n,resolved,facts)) for n in result.narrations]
                accepted=[];seen=set()
                for _,excerpt in reviewed:
                    if excerpt is not None and excerpt.text not in seen:
                        accepted.append(excerpt);seen.add(excerpt.text)
                # Bounded, owner-scoped private evidence explains omissions;
                # provider text and user context never go to public/server logs.
                self.store.put('narration_review',owner,char,dict(
                    accepted=len(accepted),trimmed=sum(excerpt is not None and excerpt!=n for n,excerpt in reviewed),
                    rejected=[n.model_dump() for n,excerpt in reviewed if excerpt is None]))
                return accepted,None
        except TimeoutError:
            return [],None  # Optional decoration must not hold up conversation.
        except Exception:
            return [],'旁白暂未生成，台词与语音仍可使用。'
    async def reply(self,owner,request):
        budget=[3]  # Original + at most two internal quality revisions, shared with publication races.
        try:
            for attempt in range(3):
                try:
                    async with aclosing(self._reply(owner,request,resume=attempt>0,budget=budget)) as source:
                        async for item in source:yield item
                    return
                except ValueError as error:
                    # Another role/worker may publish the same line while this
                    # request awaits the provider. The atomic final guard stays
                    # internal; retry from fresh history before exposing text.
                    if str(error)!='REPLY_REPEATED':raise
                    if not budget[0]:raise ValueError('REPLY_UNAVAILABLE') from None
        finally:
            # Completed text is retained; interrupted generations aren't left
            # labelled as running. Never retry an ambiguously billed request.
            self.store.interrupt(owner,request.character_id,str(request.request_id))
    async def fresh_plan(self,owner,request,context,schema,budget):
        char=request.character_id;reviews=[];correction=None
        extra=[m for m in context['recent_messages'] if m['role']=='assistant']
        while budget[0]:
            budget[0]-=1
            plan=await self.provider.structured(owner,char,'plan',PLANNER,
                {**context,**({'novelty_correction':correction} if correction else {})},schema)
            if request.trigger in INTERACTION_TRIGGERS:brief_shake_plan(plan,context['interaction_context']['mood'])
            text=plan_text(plan)
            wrong_gesture=interaction_mismatch(request,text)
            duplicate=novelty.match(self.store,owner,text,extra)
            related=await self.semantic.match(owner,text,request.trigger) if not duplicate and not wrong_gesture else None
            # BGE is a retrieval model, not an equivalence judge. One semantic
            # suggestion may steer a new draft; it cannot reject a succession
            # of otherwise distinct answers merely sharing a topic or event.
            revise=bool(wrong_gesture or duplicate or (related and (related['score']>=.86 or (correction is None and budget[0]>0))))
            reviews.append(dict(text=text,duplicate=duplicate,semantic_hint=related,interaction_mismatch=wrong_gesture,revised=revise))
            if self.settings.enable_test_inspector:
                self.store.put('novelty_review',owner,char,dict(attempts=reviews,accepted=not revise,remaining=budget[0]))
            if not revise:return plan
            correction=dict(rejected_text=text,reason=wrong_gesture or (duplicate or related)['reason'],
                instruction=(wrong_gesture+' ' if wrong_gesture else '')+'本轮需要一个实质不同的新回应。舍弃草稿的核心观点、请求和比喻，结合当前这条输入换一个具体切入点；不要仅更换同义词，不复述旧问题，不向用户解释修订。保留角色身份、正确事实、真实可执行表演和简短心声。')
        # No canned answer, repeated speech or unbounded paid retry. Optional
        # proactive turns stay quiet; a failed direct question uses the normal
        # availability error, never a moderation/repetition message.
        if request.trigger not in ('user_message','story'):return None
        raise ValueError('REPLY_UNAVAILABLE')

    async def _reply(self,owner,request,*,resume=False,budget=None):
        char=request.character_id; rid=str(request.request_id)
        # Delivery negotiation isn't conversation content. Preserve hashes for
        # pre-upgrade requests and never re-bill a retry with a different mode.
        cached=None if resume else self.store.request(owner,char,rid,request.model_dump(mode='json',exclude={'progressive_reply','timeline_reply'}|({'interaction'} if request.interaction is None else set())))
        if cached:
            # Revalidate pre-upgrade cached thoughts without rewriting archives
            # or generating/charging for the same message again.
            cached={**cached,'beats':[{**b,'thought':visible_thought(b['thought']) if b.get('thought') else None,
                                      'narrations':[n for n in b.get('narrations',[]) if visible_narration(n)]}
                                      for b in cached.get('beats',[])]}
            yield event('reply.narration.ready',script=cached,cached=True)
            if request.wants_audio:
                async with aclosing(self.audio(owner,char,cached,create=False)) as audio:
                    async for e in audio:yield e
            yield event('reply.completed',message_id=cached['message_id']); return
        context=self.context(owner,request)
        if request.trigger in INTERACTION_TRIGGERS and not resume:
            # Keep the historical key so an older app's rotation cooldown also
            # covers pinches after upgrading. All physical play shares one lane.
            previous=self.store.get('shake_reaction',owner,char,{})
            kinds={'shake'} if request.trigger=='model_shaken' else {'pinch_out','pinch_in'}
            if request.interaction is None or request.interaction.kind not in kinds or request.interaction.intensity<.4 or time.time()-previous.get('last',0)<20:
                empty=dict(message_id=str(uuid.uuid4()),character_id=char,beats=[],text='')
                self.store.complete(owner,char,rid,empty)
                yield event('reply.completed',message_id=empty['message_id']);return
            self.store.put('shake_reaction',owner,char,dict(last=time.time()))
        if request.trigger=='idle' and not resume:
            timing=self.store.get('proactive',owner,char,{})
            unanswered=timing.get('unanswered',0)
            allowed=(any(m['role']=='user' for m in context['recent_messages']) and time.time()-timing.get('last',0)>150 and unanswered<3)
            chance=[1,.5,.2][min(2,unanswered)]
            if not allowed or random.random()>chance:
                empty=dict(message_id=str(uuid.uuid4()),character_id=char,beats=[],text='',idle_decision='do_nothing')
                self.store.complete(owner,char,rid,empty)
                yield event('reply.completed',message_id=empty['message_id']); return
        schema=(ShakeTimelinePlan if request.trigger in INTERACTION_TRIGGERS else TimelinePlan) if request.timeline_reply else Plan
        plan=await self.fresh_plan(owner,request,context,schema,budget if budget is not None else [3])
        if plan is None:
            empty=dict(message_id=str(uuid.uuid4()),character_id=char,beats=[],text='',idle_decision='do_nothing')
            self.store.complete(owner,char,rid,empty)
            yield event('reply.completed',message_id=empty['message_id']);return
        # Silence is a first-class outcome; no TTS or narration expense.
        if request.trigger=='idle' and plan.idle_decision=='do_nothing': plan.beats=[]
        if request.trigger!='idle' and not any(b.dialogue for b in plan.beats): raise ValueError('EMPTY_REPLY')
        # Event density and consecutive-event suppression are enforced, not just prompted.
        previous=self.store.get('vocals',owner,char,[])
        allowance=1 if sum(len(b.dialogue.text) if b.dialogue else 0 for b in plan.beats)<80 else 2
        used=[]
        for b in plan.beats:
            if b.thought:
                thought=visible_thought(b.thought.text)
                b.thought=b.thought.model_copy(update={'text':thought}) if thought else None
            filtered=[]
            for v in b.vocal_events:
                if v.event in previous or len(used)>=allowance:continue
                filtered.append(v); used.append(v.event)
            b.vocal_events=filtered
            if request.trigger=='idle' and plan.idle_decision in ('visual_only','thought_only'):
                b.dialogue=None; b.vocal_events=[]
        self.store.put('vocals',owner,char,used)
        yield event('reply.plan.ready',beat_count=len(plan.beats))
        resolved=[self.director.beat(owner,char,b,context['relationship'],context['state'],request.available_assets,
                  plan.state_interpretation.dominant_emotion,request.trigger) for b in plan.beats]
        yield event('segment.visual.resolved',count=len(resolved))
        narrations=[]; warning=None
        if plan.beats and not request.progressive_reply and not request.timeline_reply:
            narrations,warning=await self.narration(owner,char,plan,resolved,request.scene)
        beats=[]
        for b,r in zip(plan.beats,resolved):
            thought=b.thought if b.thought and b.thought.visibility=='visible' else None
            beats.append(dict(beat_id=b.beat_id,thought=visible_thought(thought.text) if thought else None,
                dialogue=({'text':visible_text(b.dialogue.text),'speech':b.dialogue.speech.model_dump()} if b.dialogue else None),
                narrations=[dict(text=visible_text(n.text),mode=n.mode,grounding=r['grounding'] if n.mode=='performed' else 'none') for n in narrations if n.beat_id==b.beat_id][:1],
                vocal_events=[v.model_dump() for v in b.vocal_events],
                visuals=[dict(asset_id=c['asset']['asset_id'],group=c['asset']['group'],duration_ms=c['duration_ms'],
                    offset_ms=c['offset_ms'],active=c['active'],grounding=r['grounding']) for c in r['performances']]))
            if request.timeline_reply:
                beats[-1]['parts']=compile_parts(b,r)
                beats[-1]['reading_duration']=duration_hint(beats[-1]['dialogue']['text'] if beats[-1]['dialogue'] else '')
        text='\n'.join(b['dialogue']['text'] for b in beats if b['dialogue'])
        if request.timeline_reply and self.settings.enable_test_inspector:
            self.store.put('reply_flow_review',owner,char,dict(beats=[dict(beat_id=b.beat_id,
                thought=b.thought.model_dump() if b.thought else None,asides=[a.model_dump() for a in b.asides],parts=wire.get('parts',[]))
                for b,wire in zip(plan.beats,beats)]))
        script=dict(message_id=str(uuid.uuid4()),character_id=char,beats=beats,text=text,trigger=request.trigger,idle_decision=plan.idle_decision,
            memory_suggestions=[m.content for m in plan.memory_updates] if request.trigger=='user_message' else [])
        self.store.publish_reply(owner,char,rid,request.text,script)
        if plan.response_focus and text:
            self.store.put('response_focus',owner,char,(context['recent_response_focus']+[plan.response_focus])[-12:])
        if request.trigger in ENTRY_TRIGGERS:
            self.store.put('greetings',owner,char,(self.store.get('greetings',owner,char,[])+[text])[-5:])
        # Only allowed, bounded state fields. Relationship never leaks between roles/accounts.
        for key,value in plan.suggested_state_delta.items():
            if not isinstance(value,(int,float)) or not (-.08<=value<=.08):continue
            target=context['relationship'] if key in ('closeness','trust','conflict') else context['state']
            if key in ('closeness','trust','conflict','happiness','sadness','anger','anxiety','energy'):
                target[key]=clamp(target.get(key,0)+value)
        self.store.put('state',owner,char,context['state']); self.store.put('relationship',owner,char,context['relationship'])
        # AI memories are proposals. Only user-approved client memories enter recall.
        timing=self.store.get('proactive',owner,char,{})
        self.store.put('proactive',owner,char,dict(last=time.time(),unanswered=timing.get('unanswered',0)+1 if request.trigger=='idle' else 0))
        # Commit the text BEFORE audio so interruption never repeats the two brain calls.
        self.store.complete(owner,char,rid,script)
        yield event('reply.narration.ready',script=script,cached=False)
        if warning:yield event('reply.warning',message=warning)
        if request.timeline_reply:
            # Complete ordered content was published once. Never append a late
            # Narrator result above words the user has already heard/read.
            if request.wants_audio:
                async with aclosing(self.audio(owner,char,script,create=True)) as audio:
                    async for e in audio:yield e
            yield event('reply.completed',message_id=script['message_id']);return
        narration_task=None;audio_task=None
        audio=self.audio(owner,char,script,create=True) if request.wants_audio else None
        try:
            if request.progressive_reply and plan.beats:
                narration_task=asyncio.create_task(self.narration(owner,char,plan,resolved,request.scene))
            if audio is not None:audio_task=asyncio.create_task(anext(audio))
            # Deliver narration as soon as it is ready, even while TTS is still
            # producing chunks. Only one audio event is prefetched; the outer
            # stream keeps its bounded buffer and cancellation semantics.
            while narration_task is not None or audio_task is not None:
                done,_=await asyncio.wait([t for t in (narration_task,audio_task) if t is not None],return_when=asyncio.FIRST_COMPLETED)
                if narration_task is not None and narration_task in done:
                    narrations,warning=narration_task.result();narration_task=None
                    if narrations:
                        enriched=[{**b,'narrations':[dict(text=visible_text(n.text),mode=n.mode,
                            grounding=r['grounding'] if n.mode=='performed' else 'none')
                            for n in narrations if n.beat_id==b['beat_id']][:1]} for b,r in zip(beats,resolved)]
                        script={**script,'beats':enriched}
                        self.store.enrich_reply(owner,char,rid,script)
                        yield event('reply.script.updated',script=script)
                    if warning:yield event('reply.warning',message=warning)
                if audio_task is not None and audio_task in done:
                    try:audio_event=audio_task.result()
                    except StopAsyncIteration:audio_task=None
                    else:
                        audio_task=None
                        yield audio_event
                        audio_task=asyncio.create_task(anext(audio))
        finally:
            pending=[t for t in (narration_task,audio_task) if t is not None]
            for task in pending:task.cancel()
            if pending:await asyncio.gather(*pending,return_exceptions=True)
            if audio is not None:await audio.aclose()
        yield event('reply.completed',message_id=script['message_id'])

    async def audio(self,owner,char,script,create):
        voice=self.store.get('voice','system',char)
        if not voice or not voice.get('approved'):
            yield event('audio.error',message='角色音色尚未就绪，文字已保留。'); return
        folder=self.settings.data_dir/'audio';folder.mkdir(exist_ok=True)
        for beat in script['beats']:
            if not beat['dialogue'] and not beat['vocal_events']:continue
            key=audio_key(owner,char,voice['voice_id'],script['message_id'],beat['beat_id'])
            path=folder/(key+'.pcm')
            if not create and not path.exists():
                yield event('audio.error',message='这句语音未完成，可点播放重新生成。');continue
            yield event('segment.audio.started',beat_id=beat['beat_id'],sample_rate=24000,message_id=script['message_id'])
            data=bytearray()
            try:
                if path.exists():
                    path.touch()
                    content=path.read_bytes()
                    for offset in range(0,len(content),12288):
                        chunk=content[offset:offset+12288];data.extend(chunk)
                        yield event('segment.audio.chunk',beat_id=beat['beat_id'],data=base64.b64encode(chunk).decode())
                        await asyncio.sleep(0)
                else:
                    async with aclosing(self.provider.synthesize(owner,char,beat,voice['voice_id'])) as synthesis:
                        async for chunk in synthesis:
                            data.extend(chunk)
                            yield event('segment.audio.chunk',beat_id=beat['beat_id'],data=base64.b64encode(chunk).decode())
                    if data:
                        temp=path.with_suffix('.tmp');temp.write_bytes(data);temp.replace(path)
                        files=sorted(folder.glob('*.pcm'),key=lambda f:f.stat().st_mtime)
                        total=sum(f.stat().st_size for f in files)
                        for old in files:
                            if total<=128*1024*1024:break
                            if old==path:continue
                            total-=old.stat().st_size;old.unlink(missing_ok=True)
                yield event('segment.audio.ready',beat_id=beat['beat_id'],duration=len(data)/48000)
            except Exception:
                yield event('audio.error',message='语音连接中断，文字已保留。点播放可重试。')
                return
