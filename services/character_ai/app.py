"""Authenticated LAN development gateway; cloud keys never enter the iOS bundle."""
import asyncio, hashlib, hmac, json, re, time
from contextlib import asynccontextmanager
from uuid import UUID
from fastapi import FastAPI, Request as HTTPRequest, HTTPException, WebSocket, WebSocketDisconnect
from fastapi.responses import StreamingResponse
from .config import Settings
from .storage import Store, dump
from .provider import Provider
from .orchestrator import Orchestrator, event
from .schemas import Request
from .profiles import PROFILES
from .asr import recognize

def create_app(settings=None,provider=None):
    settings=settings or Settings.load();store=Store(settings.data_dir/'state.sqlite3')
    provider=provider or Provider(settings,store);engine=Orchestrator(settings,store,provider)
    busy=set(); last={}
    @asynccontextmanager
    async def lifespan(app):
        yield
        await provider.close();store.db.close()
    app=FastAPI(title='StarryNight Character Gateway',version='1.0',lifespan=lifespan,docs_url=None,redoc_url=None)
    app.state.store=store;app.state.engine=engine
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
        if key in busy or len(busy)>=4:raise HTTPException(409,'BUSY')
        if time.monotonic()-last.get(key,0)<1:raise HTTPException(429,'SLOW_DOWN')
        busy.add(key);last[key]=time.monotonic()
    async def stream(iterator,key):
        try:
            async for e in iterator:yield 'data: '+dump(e)+'\n\n'
        except asyncio.CancelledError:raise
        except Exception as error:
            code=str(error) if isinstance(error,ValueError) else getattr(error,'code','CONNECTION_FAILED')
            safe=code if re.fullmatch(r'[A-Za-z0-9_-]{1,100}',code) else 'CONNECTION_FAILED'
            yield 'data: '+dump(event('reply.error',code=safe,message='暂时没有收到回复，请检查连接或稍后重试。'))+'\n\n'
        finally:busy.discard(key)
    @app.get('/health')
    async def health():return dict(status='ok',protocol=1,paid_calls=False)
    @app.get('/v1/status')
    async def status(request:HTTPRequest):
        owner(request.headers)
        return dict(ready=bool(settings.api_key),voices={c:bool((store.get('voice','system',c) or {}).get('approved')) for c in PROFILES})
    @app.post('/v1/conversations/{character}/messages')
    async def messages(character:str,body:Request,request:HTTPRequest):
        who=owner(request.headers)
        if character!=body.character_id:raise HTTPException(400,'CHARACTER_MISMATCH')
        if body.trigger in ('user_message','story') and not body.text.strip():raise HTTPException(400,'EMPTY_MESSAGE')
        key=who+':'+character;acquire(key)
        return StreamingResponse(stream(engine.reply(who,body),key),media_type='text/event-stream',headers={'Cache-Control':'no-store','X-Accel-Buffering':'no'})
    @app.post('/v1/conversations/{character}/messages/{message_id}/audio')
    async def replay(character:str,message_id:UUID,request:HTTPRequest):
        who=owner(request.headers)
        row=store.db.execute("SELECT data FROM messages WHERE id=? AND owner=? AND character=? AND role='assistant'",(str(message_id),who,character)).fetchone()
        if not row:raise HTTPException(404,'MESSAGE_NOT_FOUND')
        key=who+':'+character;acquire(key)
        return StreamingResponse(stream(engine.audio(who,character,json.loads(row[0]),True),key),media_type='text/event-stream',headers={'Cache-Control':'no-store'})
    @app.delete('/v1/conversations/{character}/messages')
    async def clear_messages(character:str,request:HTTPRequest):
        who=owner(request.headers)
        if character not in PROFILES:raise HTTPException(404)
        if who+':'+character in busy:raise HTTPException(409,'BUSY')
        voice=store.get('voice','system',character,{})
        rows=store.db.execute("SELECT data FROM messages WHERE owner=? AND character=? AND role='assistant'",(who,character)).fetchall()
        for row in rows:
            script=json.loads(row[0])
            for beat in script.get('beats',[]):
                key=hashlib.sha256((who+'|'+character+'|'+voice.get('voice_id','')+'|'+script['message_id']+'|'+beat['beat_id']).encode()).hexdigest()
                (settings.data_dir/'audio'/(key+'.pcm')).unlink(missing_ok=True)
        with store.db:
            store.db.execute('DELETE FROM messages WHERE owner=? AND character=?',(who,character))
            store.db.execute('DELETE FROM requests WHERE owner=? AND character=?',(who,character))
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
    async def design(character:str,request:HTTPRequest):
        admin(request.headers)
        if character not in PROFILES:raise HTTPException(404)
        acquire('voice:'+character)
        try:return await provider.design_voice(character,PROFILES[character])
        finally:busy.discard('voice:'+character)
    @app.post('/v1/characters/{character}/voice-designs/approve')
    async def approve(character:str,request:HTTPRequest):
        admin(request.headers);voice=store.get('voice','system',character)
        if not voice:raise HTTPException(404)
        voice['approved']=True;store.put('voice','system',character,voice)
        return dict(approved=True,character_id=character)
    return app
