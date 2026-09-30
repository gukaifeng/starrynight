"""Alibaba protocols only. No canned response or system-voice fallback."""
import asyncio, base64, hashlib, io, json, sqlite3, time, uuid, wave
import httpx
from pydantic import ValidationError
from .storage import dump
from .speech_text import spoken_text
from .prompts import PLAN_SHAPE, REPLY_LENGTH
from .profiles import PROFILES

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
        content=dump(context)
        if purpose=='plan':
            # The previous layout placed the current user message BEFORE a long
            # history/capability object. Explicitly anchor the current turn last;
            # older dialogue is background, not another request to answer.
            current=dict(trigger=context.get('trigger'),user_message=context.get('user_message',''))
            current['reply_length']=REPLY_LENGTH
            if context.get('greeting_context'):
                current['task']=context['greeting_context']['task']
            else:
                current['task']='只回应user_message这条新消息。历史回复不是本轮台词，不要照搬。明确的表演请求放进performance，台词不自述动作。'
            if context.get('greeting_correction'): current['correction']=context['greeting_correction']
            content+='\n\n当前这一轮（历史仅供参考）：\n'+dump(current)
        messages = [dict(role='system',content=system+'\nJSON Schema:\n'+dump(schema.model_json_schema())+'\n'+shape),
                    dict(role='user',content=content)]
        # Exactly one schema correction; network/timeouts are never blindly retried.
        for attempt in range(2):
            usage = self.store.reserve(purpose, owner, character, 1, self.settings)
            started = time.monotonic()
            try:
                response = await self.http.post(self.settings.host+'/compatible-mode/v1/chat/completions', headers=self.headers,
                    json=dict(model=self.settings.character_model,messages=messages,temperature=.45 if attempt == 0 else .1,
                              max_tokens=1500 if purpose=='plan' else 600,response_format={'type':'json_object'}))
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
        text, instruction = speech_input(beat)
        if not text: return
        instruction=PROFILES.get(character,{}).get('voice_delivery','')+instruction
        usage = self.store.reserve('tts',owner,character,len(text),self.settings)
        total = 0; metrics = {}; finished = False
        try:
            async with self.http.stream('POST', self.settings.host+'/api/v1/services/audio/tts/SpeechSynthesizer',
                headers={**self.headers,'X-DashScope-SSE':'enable'}, json={
                    'model':self.settings.tts_model,'input':dict(text=text,voice=voice,format='pcm',sample_rate=24000,instruction=instruction,language_hints=['zh'])}) as response:
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
