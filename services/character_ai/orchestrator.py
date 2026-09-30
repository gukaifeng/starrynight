import asyncio, base64, random, time, uuid
from contextlib import aclosing
from .schemas import Plan, NarrationResult, Speech, Vocal, visible_text, visible_thought, CONTROL_TEXT
from .profiles import PROFILES
from .prompts import PLANNER, NARRATOR
from .director import Director, grounded_excerpt
from .storage import clamp, dump
from .speech_text import audio_key
from .greetings import ENTRY_TRIGGERS, greeting_context, repeated_greeting, plan_text

def event(kind, **data): return dict(type=kind,**data)

class Orchestrator:
    def __init__(self,settings,store,provider):
        self.settings,self.store,self.provider=settings,store,provider
        self.director=Director(store)
    def context(self,owner,request):
        char=request.character_id
        self.store.sync_memories(owner,char,request.memories)
        context = dict(character_profile={k:v for k,v in PROFILES[char].items() if k not in ('voice_prompt','preview_text','voice_revision','voice_delivery')},
            user_message=request.text,trigger=request.trigger,preferences=request.preferences,scene=request.scene,
            recent_messages=self.store.history(owner,char) or [m.model_dump() for m in request.recent_messages],memories=self.store.recall(owner,char,request.text),
            relationship=self.store.get('relationship',owner,char,dict(closeness=.05,trust=.1,conflict=0)),
            state=self.store.state(owner,char),avatar_capability=self.director.capability(char,request.available_assets),
            speech_capability=dict(emotions=Speech.model_json_schema()['properties']['emotion']['enum'],
                                   deliveries=Speech.model_json_schema()['properties']['delivery']['enum'],
                                   vocal_events=Vocal.model_json_schema()['properties']['event']['enum']))
        # Retain original archives, but don't feed historical broken control JSON
        # back to the model as a demonstration of how to speak.
        context['recent_messages']=[m for m in context['recent_messages'] if m['role']!='assistant' or not CONTROL_TEXT.search(m['text'])]
        if request.trigger in ENTRY_TRIGGERS:
            last = self.store.db.execute('SELECT max(created) FROM messages WHERE owner=? AND character=?',(owner,char)).fetchone()[0]
            context['greeting_context'] = greeting_context(context['recent_messages'],
                self.store.get('greetings',owner,char,[]),max(0,int(time.time()-last)) if last else None)
        return context
    async def narration(self,owner,char,plan,resolved,scene):
        facts=PROFILES[char].get('appearance_facts',[])
        try:
            async with asyncio.timeout(self.settings.narration_timeout_seconds):
                result=await self.provider.structured(owner,char,'narration',NARRATOR,
                    dict(plan=plan.model_dump(),resolved=resolved,scene=scene,appearance_facts=facts),NarrationResult)
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
        try:
            async with aclosing(self._reply(owner,request)) as source:
                async for item in source:yield item
        finally:
            # Completed text is retained; interrupted generations aren't left
            # labelled as running. Never retry an ambiguously billed request.
            self.store.interrupt(owner,request.character_id,str(request.request_id))
    async def _reply(self,owner,request):
        char=request.character_id; rid=str(request.request_id)
        # Delivery negotiation isn't conversation content. Preserve hashes for
        # pre-upgrade requests and never re-bill a retry with a different mode.
        cached=self.store.request(owner,char,rid,request.model_dump(mode='json',exclude={'progressive_reply'}))
        if cached:
            yield event('reply.narration.ready',script=cached,cached=True)
            if request.wants_audio:
                async with aclosing(self.audio(owner,char,cached,create=False)) as audio:
                    async for e in audio:yield e
            yield event('reply.completed',message_id=cached['message_id']); return
        context=self.context(owner,request)
        if request.trigger=='idle':
            timing=self.store.get('proactive',owner,char,{})
            unanswered=timing.get('unanswered',0)
            allowed=(any(m['role']=='user' for m in context['recent_messages']) and time.time()-timing.get('last',0)>150 and unanswered<3)
            chance=[1,.5,.2][min(2,unanswered)]
            if not allowed or random.random()>chance:
                empty=dict(message_id=str(uuid.uuid4()),character_id=char,beats=[],text='',idle_decision='do_nothing')
                self.store.complete(owner,char,rid,empty)
                yield event('reply.completed',message_id=empty['message_id']); return
        plan=await self.provider.structured(owner,char,'plan',PLANNER,context,Plan)
        if request.trigger in ENTRY_TRIGGERS:
            previous=context['greeting_context']['previous_lines_to_avoid']
            if repeated_greeting(plan_text(plan),previous):
                # One bounded semantic correction, only for a confirmed duplicate.
                # This is a new completed model request, not a network retry.
                correction={**context,'greeting_correction':dict(rejected_text=plan_text(plan),
                    instruction='刚生成的内容重复了历史回复。重新写一句新的见面问候，换一个切入点，不要再次解答历史问题，也不要只改几个词。')}
                plan=await self.provider.structured(owner,char,'plan',PLANNER,correction,Plan)
                if repeated_greeting(plan_text(plan),previous):
                    raise ValueError('GREETING_REPEATED')
        # Silence is a first-class outcome; no TTS or narration expense.
        if request.trigger=='idle' and plan.idle_decision=='do_nothing': plan.beats=[]
        if request.trigger!='idle' and not any(b.dialogue for b in plan.beats): raise ValueError('EMPTY_REPLY')
        # Event density and consecutive-event suppression are enforced, not just prompted.
        previous=self.store.get('vocals',owner,char,[])
        allowance=1 if sum(len(b.dialogue.text) if b.dialogue else 0 for b in plan.beats)<80 else 2
        used=[]
        for b in plan.beats:
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
        if plan.beats and not request.progressive_reply:
            narrations,warning=await self.narration(owner,char,plan,resolved,request.scene)
        beats=[]
        for b,r in zip(plan.beats,resolved):
            thought=b.thought if b.thought and b.thought.visibility=='visible' else None
            beats.append(dict(beat_id=b.beat_id,thought=visible_thought(thought.text) if thought else None,
                dialogue=({'text':visible_text(b.dialogue.text),'speech':b.dialogue.speech.model_dump()} if b.dialogue else None),
                narrations=[dict(text=visible_text(n.text),mode=n.mode,grounding=r['grounding'] if n.mode=='performed' else 'none') for n in narrations if n.beat_id==b.beat_id][:1],
                vocal_events=[v.model_dump() for v in b.vocal_events],
                visuals=[dict(asset_id=a['asset_id'],group=a['group'],duration_ms=a['duration_ms'],grounding=r['grounding']) for k in ('expression_asset','action_asset') if (a:=r.get(k))]))
        text='\n'.join(b['dialogue']['text'] for b in beats if b['dialogue'])
        script=dict(message_id=str(uuid.uuid4()),character_id=char,beats=beats,text=text,trigger=request.trigger,idle_decision=plan.idle_decision,
            memory_suggestions=[m.content for m in plan.memory_updates] if request.trigger=='user_message' else [])
        if request.text:self.store.message(str(uuid.uuid4()),owner,char,rid,'user',dict(text=request.text))
        self.store.message(script['message_id'],owner,char,rid,'assistant',script)
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
