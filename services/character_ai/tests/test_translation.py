import asyncio
import hashlib
import hmac
import json
import uuid
import httpx
import pytest
from services.character_ai.app import create_app
from services.character_ai.config import Settings
from services.character_ai.provider import structured_payload
from services.character_ai.translation import TranslationResult

class Translator:
    calls = 0
    malformed = False
    async def structured(self, owner, character, purpose, system, context, schema):
        self.calls += 1
        assert purpose == 'translation' and 'untrusted' in system
        await asyncio.sleep(.01)
        segments=[dict(s, text='translated: '+s['text']) for s in context['segments']]
        if self.malformed: segments.reverse()
        return TranslationResult(segments=segments)

def fixture(tmp_path):
    provider=Translator();settings=Settings(data_dir=tmp_path,client_token='translation-test',paid_enabled=False)
    app=create_app(settings,provider);store=app.state.store
    install=str(uuid.uuid4());account='reader'
    headers={'Authorization':'Bearer translation-test','X-Starry-Installation':install,'X-Starry-Account':account}
    owner=hmac.new(b'translation-test',(install+'|'+account).encode(),hashlib.sha256).hexdigest()
    role='anime-kipfel';message=str(uuid.uuid4())
    parts=[dict(kind='dialogue',text='Good morning!\nDid you sleep well?',at=0),
           dict(kind='thought',text='I hope you did.',at=.5),dict(kind='narration',text='A gentle wave.',at=.7)]
    script=dict(message_id=message,text=parts[0]['text'],beats=[dict(beat_id='b',parts=parts)])
    store.message(message,owner,role,'fixture','assistant',script)
    body=dict(target_language='zh-Hans',segments=[dict(id=f'b.part.{i}',kind=s['kind'],text=s['text']) for i,s in enumerate(parts)])
    return app,provider,headers,owner,role,message,body

@pytest.mark.asyncio
async def test_translation_preserves_format_is_cached_and_owner_scoped(tmp_path):
    app,provider,headers,owner,role,message,body=fixture(tmp_path)
    path=f'/v1/conversations/{role}/messages/{message}/translation'
    before=app.state.store.history(owner,role)
    async with httpx.AsyncClient(transport=httpx.ASGITransport(app=app),base_url='http://test') as client:
        a,b=await asyncio.gather(*(client.post(path,headers=headers,json=body) for _ in range(2)))
        assert a.status_code==b.status_code==200 and a.json()==b.json() and provider.calls==1
        assert [s['kind'] for s in a.json()['segments']]==['dialogue','thought','narration']
        assert '\n' in a.json()['segments'][0]['text']
        assert app.state.store.history(owner,role)==before
        assert (await client.post(path,headers={**headers,'X-Starry-Account':'other'},json=body)).status_code==404
        altered=json.loads(json.dumps(body));altered['segments'][0]['text']='unowned content'
        assert (await client.post(path,headers=headers,json=altered)).status_code==409
        assert (await client.post(path,headers=headers,json={**body,'target_language':'de'})).status_code==422
        assert provider.calls==1
        assert (await client.post(path,headers=headers,json={**body,'target_language':'zh-Hant'})).status_code==200
        assert provider.calls==2
        assert (await client.delete(f'/v1/conversations/{role}?reset_id={uuid.uuid4()}',headers=headers)).status_code==200
        assert not app.state.store.db.execute("SELECT 1 FROM records WHERE owner=? AND character=? AND kind LIKE 'translation:%'",(owner,role)).fetchone()
        assert (await client.post(path,headers=headers,json=body)).status_code==404

@pytest.mark.asyncio
async def test_shape_errors_never_cache_or_replace_original(tmp_path):
    app,provider,headers,owner,role,message,body=fixture(tmp_path);provider.malformed=True
    async with httpx.AsyncClient(transport=httpx.ASGITransport(app=app),base_url='http://test') as client:
        response=await client.post(f'/v1/conversations/{role}/messages/{message}/translation',headers=headers,json=body)
        assert response.status_code==502
        assert not app.state.store.get('translation:'+message+':zh-Hans',owner,role)
        assert app.state.store.history(owner,role)[0]['text'].startswith('Good morning')

def test_translation_uses_fast_general_model_without_roleplay_or_thinking():
    settings=Settings(suggestions_model='test-fast',character_model='test-roleplay')
    payload=structured_payload(settings,'translation',[])
    assert payload['model']=='test-fast' and payload['enable_thinking'] is False
    assert payload['response_format']=={'type':'json_object'} and payload['max_tokens']>=4000
