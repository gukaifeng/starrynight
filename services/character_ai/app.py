"""Authenticated LAN development gateway; cloud keys never enter the iOS bundle."""
import asyncio, hashlib, hmac, json, re
from contextlib import asynccontextmanager
from uuid import UUID
from fastapi import FastAPI, Request as HTTPRequest, HTTPException, WebSocket, WebSocketDisconnect
from .config import Settings
from .storage import Store
from .provider import Provider, ProviderError
from .orchestrator import Orchestrator
from .schemas import Request
from .profiles import PROFILES
from .asr import recognize
from .streams import TurnStreams
from .speech_text import audio_key
from .public_profiles import public_profile
from .inspection import report as inspection_report

def create_app(settings=None,provider=None):
    settings=settings or Settings.load();store=Store(settings.data_dir/'state.sqlite3')
    provider=provider or Provider(settings,store);engine=Orchestrator(settings,store,provider)
    busy=set(); turns=TurnStreams()
    @asynccontextmanager
    async def lifespan(app):
        yield
        await turns.close();await provider.close();store.db.close()
    app=FastAPI(title='StarryNight Character Gateway',version='1.2',lifespan=lifespan,docs_url=None,redoc_url=None)
    app.state.store=store;app.state.engine=engine;app.state.turns=turns
    def owner(headers):
        token=headers.get('authorization','').removeprefix('Bearer ')
        if not settings.client_token or not hmac.compare_digest(token,settings.client_token):raise HTTPException(401,'UNAUTHORIZED')
        install=headers.get('x-starry-installation',''); account=headers.get('x-starry-account','')
        try:UUID(install)
        except ValueError:raise HTTPException(400,'INSTALLATION_REQUIRED')
        if not re.fullmatch(r'[a-zA-Z0-9_-]{1,100}',account):raise HTTPException(400,'ACCOUNT_REQUIRED')
        return hmac.new(settings.client_token.encode(),(install+'|'+account).encode(),hashlib.sha256).hexdigest()
    def admin(headers):
        if not settings.admin_token or not hmac.compare_digest(headers.get('authorization','').removeprefix('Bearer '),settings.admin_token):raise HTTPException(401,'UNAUTHORIZED')
    def acquire(key):
        if key in busy:raise HTTPException(409,'AUDIO_INPUT_BUSY')
        if len(busy)>=4:raise HTTPException(503,'SERVER_BUSY')
        busy.add(key)
    @app.get('/health')
    async def health():return dict(status='ok',protocol=1,revision=5,paid_calls=False)
    @app.get('/v1/status')
    async def status(request:HTTPRequest):
        owner(request.headers)
        return dict(ready=bool(settings.api_key),voices={c:bool((store.get('voice','system',c) or {}).get('approved')) for c in PROFILES})
    @app.get('/v1/characters/{character}/profile')
    async def character_profile(character:str,request:HTTPRequest):
        owner(request.headers)
        if character not in PROFILES:raise HTTPException(404)
        return public_profile(character)
    @app.post('/v1/testing/characters/{character}/inspector')
    async def inspector(character:str,body:Request,request:HTTPRequest):
        if not settings.enable_test_inspector:raise HTTPException(404)
        who=owner(request.headers)
        if character!=body.character_id:raise HTTPException(400,'CHARACTER_MISMATCH')
        return inspection_report(settings,engine,who,body)
    @app.post('/v1/conversations/{character}/messages')
    async def messages(character:str,body:Request,request:HTTPRequest):
        who=owner(request.headers)
        if character!=body.character_id:raise HTTPException(400,'CHARACTER_MISMATCH')
        if body.trigger in ('user_message','story') and not body.text.strip():raise HTTPException(400,'EMPTY_MESSAGE')
        if request.headers.get('x-starry-reply-mode')=='progressive-v1':body.progressive_reply=True
        return await turns.start(who+':'+character,str(body.request_id),lambda: engine.reply(who,body),replace=body.trigger!='idle')
    @app.post('/v1/conversations/{character}/messages/{message_id}/audio')
    async def replay(character:str,message_id:UUID,request:HTTPRequest):
        who=owner(request.headers)
        row=store.db.execute("SELECT data FROM messages WHERE id=? AND owner=? AND character=? AND role='assistant'",(str(message_id),who,character)).fetchone()
        if not row:raise HTTPException(404,'MESSAGE_NOT_FOUND')
        return await turns.start(who+':'+character,'audio:'+str(message_id),lambda: engine.audio(who,character,json.loads(row[0]),True))
    @app.delete('/v1/conversations/{character}/messages')
    async def clear_messages(character:str,request:HTTPRequest):
        who=owner(request.headers)
        if character not in PROFILES:raise HTTPException(404)
        await turns.cancel(who+':'+character)
        voice=store.get('voice','system',character,{})
        rows=store.db.execute("SELECT data FROM messages WHERE owner=? AND character=? AND role='assistant'",(who,character)).fetchall()
        for row in rows:
            script=json.loads(row[0])
            for beat in script.get('beats',[]):
                for revision in ('', 'spoken-v2'):
                    key=audio_key(who,character,voice.get('voice_id',''),script['message_id'],beat['beat_id'],revision=revision)
                    (settings.data_dir/'audio'/(key+'.pcm')).unlink(missing_ok=True)
        with store.db:
            store.db.execute('DELETE FROM messages WHERE owner=? AND character=?',(who,character))
            store.db.execute('DELETE FROM requests WHERE owner=? AND character=?',(who,character))
            store.db.execute("DELETE FROM records WHERE kind='greetings' AND owner=? AND character=?",(who,character))
            store.db.execute("DELETE FROM records WHERE kind='inspection_requests' AND owner=? AND character=?",(who,character))
        return dict(cleared=True)
    @app.websocket('/v1/asr/{character}')
    async def asr(socket:WebSocket,character:str):
        key=None
        try:
            who=owner(socket.headers)
            if character not in PROFILES:raise HTTPException(404)
            candidate=who+':'+character;acquire(candidate);key=candidate;await socket.accept()
            await recognize(socket,settings,store,who,character,socket.query_params.get('nickname',''))
        except (WebSocketDisconnect,asyncio.CancelledError):pass
        except Exception:
            try:await socket.send_json(dict(type='asr.error',message='语音识别连接中断，请重试。'))
            except Exception:pass
        finally:
            if key:busy.discard(key)
            try:await socket.close()
            except Exception:pass
    @app.get('/v1/admin/usage')
    async def usage(request:HTTPRequest):
        admin(request.headers)
        return [dict(row) for row in store.db.execute('SELECT kind,count(*) calls,sum(units) units,sum(reserved) reserved FROM usage GROUP BY kind')]
    @app.post('/v1/characters/{character}/voice-designs')
    async def design(character:str,request:HTTPRequest,revision:str|None=None):
        admin(request.headers)
        if character not in PROFILES:raise HTTPException(404)
        acquire('voice:'+character)
        try:return await provider.design_voice(character,PROFILES[character],revision=revision)
        except (ProviderError,ValueError) as error:raise HTTPException(409,str(error)) from None
        finally:busy.discard('voice:'+character)
    @app.post('/v1/characters/{character}/voice-designs/approve')
    async def approve(character:str,request:HTTPRequest,job_id:str|None=None):
        admin(request.headers)
        try:voice=store.approve_voice(character,job_id)
        except ValueError as error:raise HTTPException(409,str(error)) from None
        return dict(approved=True,character_id=character,revision=voice.get('revision','original-v1'))
    return app
