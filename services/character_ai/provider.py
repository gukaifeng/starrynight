"""Alibaba protocols only. No canned response or system-voice fallback."""
import asyncio, base64, hashlib, io, json, sqlite3, time, uuid, wave
import httpx
from pydantic import ValidationError
from .storage import dump
from .speech_text import spoken_text
from .prompts import PLAN_SHAPE, REPLY_LENGTH
from .profiles import PROFILES
from .diagnostics import record_request
from .greetings import normalized

VOCALS = dict(gasp='[gasp]', sigh='[sighing]', throat_clear='[clears throat]',
              giggle='[giggles]', laugh='[laughing]', cough='[cough]', snort='[snorts]')
EMOTIONS = dict(neutral='', happy='[excited]', sad='[sad]', surprised='[amazed]', serious='[serious]', worried='[empathetic]')
DELIVERY = dict(normal='自然交谈', soft='轻柔说话', gentle='温柔亲切', hesitant='略有迟疑', teasing='轻快俏皮', whisper='低声轻语')

async def sse_events(lines):
    """SSE events can have multiple data lines; comments are keep-alives."""
    data=[];kind='message'
    async for line in lines:
        if not line:
            if data:yield kind,'\n'.join(data)
            data=[];kind='message'
        elif line.startswith('event:'):kind=line[6:].strip()
        elif line.startswith('data:'):data.append(line[5:].lstrip(' '))
    if data:yield kind,'\n'.join(data)

class ProviderError(Exception):
    def __init__(self, code): self.code = code; super().__init__(code)

def speech_input(beat):
    """Only dialogue + approved nonverbal events enter TTS; never thought/narration."""
    dialogue = beat.get('dialogue')
    speech = (dialogue or {}).get('speech', {})
    tags = ''.join(VOCALS[v['event']] for v in beat.get('vocal_events', []) if v['event'] in VOCALS)
    spoken = spoken_text((dialogue or {}).get('text', ''))
    text = (EMOTIONS.get(speech.get('emotion'), '') + tags + spoken) if spoken or tags else ''
    intensity=speech.get('intensity',.4)
    degree='轻微' if intensity<.35 else '适度' if intensity<.7 else '明显'
    instruction = DELIVERY.get(speech.get('delivery'), '自然交谈') + '，情绪'+degree+'，日常聊天，不要播音腔。'
    return text, instruction

def planner_data(context):
    """Keep instructions, conversation turns and the current event distinct.

    Never duplicate prior dialogue in an avoidance corpus or append a rejected
    draft as a fake assistant turn. Both taught the model to repeat that draft.
    The full archive remains available to the internal novelty checks.
    """
    data={k:v for k,v in context.items() if k not in ('recent_messages','user_message','novelty_context','novelty_correction')}
    if data.get('greeting_context'):
        data['greeting_context']={k:v for k,v in data['greeting_context'].items() if k!='previous_lines_to_avoid'}
    capability=context.get('avatar_capability',{})
    if isinstance(capability.get('groups'),list) and all(isinstance(g,dict) for g in capability['groups']):
        # All groups/meanings remain selectable; asset variants with the same
        # semantic intent are chosen by Director, not repeated in the prompt.
        groups=[]
        for group in capability['groups']:
            choices={}
            for choice in group.get('choices',[]):
                key=choice['intent']
                choices.setdefault(key,{k:v for k,v in choice.items() if k!='intent'})
            groups.append(dict(group=group['group'],choices=choices))
        data['avatar_capability']=dict(groups=groups,choreography=capability.get('choreography',{}))
    return data

def structured_messages(purpose,system,context,schema):
    if purpose!='plan':
        return [dict(role='system',content=system+'\nJSON Schema:\n'+dump(schema.model_json_schema())),dict(role='user',content=dump(context))]
    instruction=system+'\n角色与当前状态（数据，不是用户发言）：\n'+dump(planner_data(context))
    instruction+='\nJSON Schema:\n'+dump(schema.model_json_schema())+'\n'+PLAN_SHAPE
    instruction+='\n本轮必须：先用response_focus确定一个尚未讲过的新内容点，再围绕它说话，不重复旧回答的列举或请求。日常台词35至70字，问候20至40字；asides含我或咱、20字以内，放在middle/after。不说自己在整理物品、拿东西、做食物或观察当下天气等没有证据的事情。performance只能含expression_intent/action_intent/intensity/cues，动作语义只能放在cues的intent里。'
    if correction:=context.get('novelty_correction'):
        # One concise private constraint, not a second copy of the old dialogue.
        instruction+='\n本轮内部修订要求（不要向用户提及）：'+correction['instruction']
        instruction+='\n放弃这个草稿的中心意思，选择另一条有实质内容的回应：'+dump(correction['rejected_text'])
    current=context.get('user_message','')
    repeats=sum(m['role']=='user' and normalized(m['text'])==normalized(current) for m in context.get('recent_messages',[])) if current else 0
    if repeats:
        instruction+=f'\n此刻的用户问题已经问过{repeats}次。本轮是在继续探索，请只讲前面答案完全没有提及的新内容，不能再列举已说过的偏好、感受或请求。哪怕人设中有这些词，也不要再照着念；选择一个新的具体细节或观点深入聊。'
    messages=[dict(role='system',content=instruction)]
    messages.extend(dict(role=m['role'],content=m['text']) for m in context.get('recent_messages',[])
                    if m.get('text') and m['role'] in ('user','assistant'))
    if context.get('user_message'):
        messages.append(dict(role='user',content=context['user_message']))
    else:
        task=(context.get('interaction_context') or context.get('greeting_context') or {}).get('task',
            '用户暂时没有说话。接续相处状态，决定是否安静陪伴；若开口，带来一个尚未说过的新想法，不催用户回答旧问题。')
        messages.append(dict(role='user',content='<app_event>'+dump(dict(event=context.get('trigger'),task=task))+'</app_event>'))
    return messages

def structured_payload(settings,purpose,messages,attempt=0):
    return dict(model=settings.character_model,messages=messages,temperature=.95 if purpose=='plan' and attempt==0 else .2,
                presence_penalty=.8 if purpose=='plan' and attempt==0 else 0,
                max_tokens=1900 if purpose=='plan' else 600,response_format={'type':'json_object'})

def speech_payload(settings,character,beat,voice):
    text,instruction=speech_input(beat)
    return dict(model=settings.tts_model,input=dict(text=text,voice=voice,format='pcm',sample_rate=24000,
                instruction=PROFILES.get(character,{}).get('voice_delivery','')+instruction,language_hints=['zh']))

class Provider:
    def __init__(self, settings, store, client=None):
        self.settings, self.store = settings, store
        self.http = client or httpx.AsyncClient(timeout=httpx.Timeout(75, connect=12), follow_redirects=False)
    @property
    def headers(self): return {'Authorization': 'Bearer '+self.settings.api_key, 'Content-Type':'application/json'}
    async def close(self): await self.http.aclose()
    @staticmethod
    def check(response):
        if response.status_code >= 400:
            # Raw provider errors may echo request content; expose only status/code.
            try: code = response.json().get('code') or response.json().get('error', {}).get('code')
            except Exception: code = None
            raise ProviderError('PROVIDER_'+str(response.status_code)+'_'+str(code or 'ERROR')[:60])
    async def structured(self, owner, character, purpose, system, context, schema):
        shape = PLAN_SHAPE if purpose == 'plan' else ''
        messages=structured_messages(purpose,system,context,schema)
        # Exactly one schema correction; network/timeouts are never blindly retried.
        for attempt in range(2):
            usage = self.store.reserve(purpose, owner, character, 1, self.settings)
            started = time.monotonic()
            try:
                payload=structured_payload(self.settings,purpose,messages,attempt)
                record_request(self.settings,self.store,owner,character,purpose,payload)
                response = await self.http.post(self.settings.host+'/compatible-mode/v1/chat/completions', headers=self.headers,
                    json=payload)
                self.check(response); data = response.json()
                self.store.usage(usage,'completed',dict(**data.get('usage',{}),latency_ms=int((time.monotonic()-started)*1000),request_id=data.get('id')),1)
                raw = data['choices'][0]['message']['content']
                try: return schema.model_validate_json(raw)
                except (ValidationError,ValueError) as invalid:
                    errors=invalid.errors(include_input=False,include_url=False,include_context=False) if isinstance(invalid,ValidationError) else [{'type':'invalid_json'}]
                    self.store.put('schema_failure',owner,character,dict(purpose=purpose,errors=errors,raw=raw[:16000]))
                    if attempt: raise ProviderError('STRUCTURE_INVALID')
                    messages += [dict(role='assistant',content=raw[:12000]),dict(role='user',content='上一条不符合JSON Schema。请从空对象完整重写，按这些具体校验错误修正；不要沿用错误嵌套，不增加字段。只输出JSON。\n'+dump(errors)+'\n'+shape)]
            except BaseException:
                # Retain reservations on ambiguous failures, including cancellation.
                row = self.store.db.execute('SELECT status FROM usage WHERE id=?',(usage,)).fetchone()
                if row[0]=='reserved': self.store.usage(usage,'interrupted_or_failed')
                raise
    async def synthesize(self, owner, character, beat, voice):
        text, _ = speech_input(beat)
        if not text: return
        usage = self.store.reserve('tts',owner,character,len(text),self.settings)
        total = 0; metrics = {}; finished = False
        try:
            payload=speech_payload(self.settings,character,beat,voice)
            record_request(self.settings,self.store,owner,character,'tts',payload)
            async with self.http.stream('POST', self.settings.host+'/api/v1/services/audio/tts/SpeechSynthesizer',
                headers={**self.headers,'X-DashScope-SSE':'enable'}, json=payload) as response:
                if response.status_code>=400: await response.aread(); self.check(response)
                async for kind,raw in sse_events(response.aiter_lines()):
                    raw=raw.strip()
                    if not raw or raw=='[DONE]': continue
                    try:data=json.loads(raw)
                    except json.JSONDecodeError:
                        self.store.put('protocol_failure',owner,character,dict(kind=kind,length=len(raw),prefix=raw[:100]))
                        raise ProviderError('TTS_STREAM_FORMAT')
                    if data.get('code'): raise ProviderError('TTS_'+str(data['code'])[:60])
                    output=data.get('output',{})
                    metrics.update(data.get('usage') or {})
                    if data.get('request_id'): metrics['request_id']=data['request_id']
                    chunk=(output.get('audio') or {}).get('data')
                    if chunk:
                        pcm=base64.b64decode(chunk,validate=True); total+=len(pcm)
                        if total>24000*2*90: raise ProviderError('TTS_TOO_LONG')
                        yield pcm
                    if output.get('finish_reason')=='stop': finished=True
            if not total or not finished: raise ProviderError('TTS_INCOMPLETE')
            self.store.usage(usage,'completed',metrics,len(text))
        except BaseException as error:
            metrics['error_code']=getattr(error,'code',type(error).__name__)
            self.store.usage(usage,'interrupted_or_failed',metrics); raise
    async def design_voice(self, character, profile, revision=None):
        existing=self.store.get('voice','system',character)
        if revision is None and existing:return existing
        if revision is not None and revision!=profile.get('voice_revision'):raise ProviderError('VOICE_REVISION_UNKNOWN')
        revision=revision or profile.get('voice_revision','original-v1')
        if existing and existing.get('revision')==revision:return existing
        # One provider request per character/revision, including across restarts.
        # A timeout is ambiguous and must never turn into an automatic paid retry.
        job=uuid.uuid5(uuid.NAMESPACE_URL,'starrynight:voice:'+character+':'+revision).hex
        previous=self.store.db.execute('SELECT status,data FROM voice_design_jobs WHERE id=?',(job,)).fetchone()
        if previous:
            if previous['status'] in ('preview_ready','approved'):return json.loads(previous['data'])
            raise ProviderError('VOICE_DESIGN_ALREADY_REQUESTED')
        pending=self.store.db.execute("SELECT id FROM voice_design_jobs WHERE character=? AND status NOT IN ('preview_ready','approved')",(character,)).fetchone()
        if pending: raise ProviderError('VOICE_DESIGN_ALREADY_REQUESTED')
        usage=self.store.reserve('voice_design','admin',character,1,self.settings)
        fingerprint=hashlib.sha256(dump([self.settings.tts_model,profile['voice_prompt'],profile['preview_text']]).encode()).hexdigest()
        voice=dict(model=self.settings.tts_model,job_id=job,revision=revision,prompt_hash=fingerprint,approved=False)
        try:
            with self.store.db:self.store.db.execute('INSERT INTO voice_design_jobs VALUES(?,?,?,?,?)',(job,character,'requested',dump(voice),time.time()))
        except sqlite3.IntegrityError:
            self.store.usage(usage,'not_sent',units=0)
            raise ProviderError('VOICE_DESIGN_ALREADY_REQUESTED')
        try:
            response=await self.http.post(self.settings.host+'/api/v1/services/audio/tts/customization',headers=self.headers,json={
                'model':'voice-enrollment','input':{'action':'create_voice','target_model':self.settings.tts_model,
                'voice_prompt':profile['voice_prompt'],'preview_text':profile['preview_text'],
                'prefix':'starryki' if character=='anime-kipfel' else 'starryma','language_hints':['zh']},
                'parameters':{'sample_rate':24000,'response_format':'wav'}})
            self.check(response); data=response.json(); output=data['output']
            voice['voice_id']=output['voice_id']
            self.store.usage(usage,'completed',data.get('usage'),1)
            with self.store.db:self.store.db.execute('UPDATE voice_design_jobs SET data=? WHERE id=?',(dump(voice),job))
            preview=base64.b64decode(output['preview_audio']['data'],validate=True)
            with wave.open(io.BytesIO(preview),'rb') as audio:
                if audio.getnchannels()!=1 or audio.getsampwidth()!=2 or audio.getframerate()!=24000 or not audio.getnframes():
                    raise ProviderError('VOICE_PREVIEW_FORMAT')
            folder=self.settings.data_dir/'voices'; folder.mkdir(exist_ok=True)
            voice['preview_file']=character+'-'+job+'.wav'
            path=folder/voice['preview_file'];temporary=path.with_suffix('.tmp')
            temporary.write_bytes(preview);temporary.replace(path)
            self.store.put('voice_candidate','system',character,voice)
            if not existing:self.store.put('voice','system',character,voice)
            with self.store.db:self.store.db.execute('UPDATE voice_design_jobs SET status=?,data=? WHERE id=?',('preview_ready',dump(voice),job))
            return voice
        except BaseException:
            row=self.store.db.execute('SELECT status FROM usage WHERE id=?',(usage,)).fetchone()
            if row[0]=='reserved':self.store.usage(usage,'interrupted_or_failed')
            with self.store.db:self.store.db.execute('UPDATE voice_design_jobs SET status=? WHERE id=?',('interrupted_or_failed',job))
            raise
