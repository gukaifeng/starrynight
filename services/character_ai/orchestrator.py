import asyncio, base64, hashlib, random, time, uuid, wave
from .schemas import Plan, NarrationResult, Speech, Vocal, visible_text, visible_thought
from .profiles import PROFILES
from .prompts import PLANNER, NARRATOR
from .director import Director, grounded
from .storage import clamp, dump

def event(kind, **data): return dict(type=kind,**data)

class Orchestrator:
    def __init__(self,settings,store,provider):
        self.settings,self.store,self.provider=settings,store,provider
        self.director=Director(store)
    def context(self,owner,request):
        char=request.character_id
        self.store.sync_memories(owner,char,request.memories)
        return dict(character_profile={k:v for k,v in PROFILES[char].items() if k not in ('voice_prompt','preview_text')},
            user_message=request.text,trigger=request.trigger,preferences=request.preferences,scene=request.scene,
            recent_messages=self.store.history(owner,char) or [m.model_dump() for m in request.recent_messages],memories=self.store.recall(owner,char,request.text),
            relationship=self.store.get('relationship',owner,char,dict(closeness=.05,trust=.1,conflict=0)),
            state=self.store.state(owner,char),avatar_capability=self.director.capability(char,request.available_assets),
            speech_capability=dict(emotions=Speech.model_json_schema()['properties']['emotion']['enum'],
                                   deliveries=Speech.model_json_schema()['properties']['delivery']['enum'],
                                   vocal_events=Vocal.model_json_schema()['properties']['event']['enum']))
    async def reply(self,owner,request):
        char=request.character_id; rid=str(request.request_id)
        cached=self.store.request(owner,char,rid,request.model_dump(mode='json'))
        if cached:
            yield event('reply.narration.ready',script=cached,cached=True)
            async for e in self.audio(owner,char,cached,create=False): yield e
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
        resolved=[self.director.beat(owner,char,b,context['relationship'],context['state'],request.available_assets) for b in plan.beats]
        yield event('segment.visual.resolved',count=len(resolved))
        narrations=[]; warning=None
        if plan.beats:
            try:
                narration=await self.provider.structured(owner,char,'narration',NARRATOR,
                    dict(plan=plan.model_dump(),resolved=resolved,scene=request.scene),NarrationResult)
                narrations=[n for n in narration.narrations if grounded(n,resolved)]
            except Exception:
                # Valid dialogue still reaches the user if the second model call fails.
                warning='旁白暂未生成，台词与语音仍可使用。'
        beats=[]
        for b,r in zip(plan.beats,resolved):
            thought=b.thought if b.thought and b.thought.visibility=='visible' else None
            beats.append(dict(beat_id=b.beat_id,thought=visible_thought(thought.text) if thought else None,
                dialogue=({'text':visible_text(b.dialogue.text),'speech':b.dialogue.speech.model_dump()} if b.dialogue else None),
                narrations=[dict(text=visible_text(n.text),mode=n.mode,grounding=r['grounding'] if n.mode=='performed' else 'none') for n in narrations if n.beat_id==b.beat_id][:1],
                vocal_events=[v.model_dump() for v in b.vocal_events],
                visuals=[dict(asset_id=a['asset_id'],group=a['group'],duration_ms=a['duration_ms'],grounding=r['grounding']) for k in ('expression_asset','action_asset') if (a:=r.get(k))]))
        text='\n'.join(b['dialogue']['text'] for b in beats if b['dialogue'])
        script=dict(message_id=str(uuid.uuid4()),character_id=char,beats=beats,text=text,idle_decision=plan.idle_decision,
            memory_suggestions=[m.content for m in plan.memory_updates] if request.trigger=='user_message' else [])
        if request.text:self.store.message(str(uuid.uuid4()),owner,char,rid,'user',dict(text=request.text))
        self.store.message(script['message_id'],owner,char,rid,'assistant',script)
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
        if request.wants_audio:
            async for e in self.audio(owner,char,script,create=True):yield e
        yield event('reply.completed',message_id=script['message_id'])

    async def audio(self,owner,char,script,create):
        voice=self.store.get('voice','system',char)
        if not voice or not voice.get('approved'):
            yield event('audio.error',message='角色音色尚未就绪，文字已保留。'); return
        folder=self.settings.data_dir/'audio';folder.mkdir(exist_ok=True)
        for beat in script['beats']:
            if not beat['dialogue'] and not beat['vocal_events']:continue
            key=hashlib.sha256((owner+'|'+char+'|'+voice['voice_id']+'|'+script['message_id']+'|'+beat['beat_id']).encode()).hexdigest()
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
                    async for chunk in self.provider.synthesize(owner,char,beat,voice['voice_id']):
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
