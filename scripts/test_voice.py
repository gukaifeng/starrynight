#!/usr/bin/env python3
"""Exercise actual local inference, not mocked transcripts."""
import io,json,pathlib,time,urllib.request,urllib.error,wave
ROOT=pathlib.Path(__file__).resolve().parents[1]
BASE='http://127.0.0.1:18765'
OUT=ROOT/'docs/verification/companion'; OUT.mkdir(parents=True,exist_ok=True)
def call(path,data=None,kind='application/json'):
 request=urllib.request.Request(BASE+path,data=data,headers={'Content-Type':kind})
 with urllib.request.urlopen(request,timeout=120) as response:
  return response.read(),{key.lower():value for key,value in response.headers.items()}
health=json.loads(call('/health')[0]); assert health['ready']
start=time.monotonic()
fixture=ROOT/'.local/voice-models/sensevoice/test_wavs/zh.wav'
recognized=json.loads(call('/v1/asr',fixture.read_bytes(),'audio/wav')[0]); assert len(recognized['text'])>=5,recognized
asr_elapsed=time.monotonic()-start
text='你好，我是小屿。今天想和你聊聊音乐。'
start=time.monotonic(); speech,headers=call('/v1/tts',json.dumps({'text':text,'speed':1.0}).encode())
tts_elapsed=time.monotonic()-start
with wave.open(io.BytesIO(speech),'rb') as audio: duration=audio.getnframes()/audio.getframerate();rate=audio.getframerate()
assert duration>1 and rate>=16000
(OUT/'melo-sample.wav').write_bytes(speech)
roundtrip=json.loads(call('/v1/asr',speech,'audio/wav')[0])
# This is an integration check, not an ASR accuracy certification. Preserve exact
# recognition and compute errors; homophones must remain visible in the report.
import re
expected=re.sub(r'[^\w]','',text); actual=re.sub(r'[^\w]','',roundtrip['text'])
row=list(range(len(actual)+1))
for i,left in enumerate(expected,1):
 nextrow=[i]
 for j,right in enumerate(actual,1): nextrow.append(min(nextrow[-1]+1,row[j]+1,row[j-1]+(left!=right)))
 row=nextrow
cer=row[-1]/len(expected)
assert actual and cer<=0.3,roundtrip
silence=io.BytesIO()
with wave.open(silence,'wb') as audio: audio.setnchannels(1);audio.setsampwidth(2);audio.setframerate(16000);audio.writeframes(bytes(32000))
silent=json.loads(call('/v1/asr',silence.getvalue(),'audio/wav')[0]);assert silent.get('reason')=='silence'
try: call('/v1/asr',b'invalid','audio/wav'); raise AssertionError('invalid accepted')
except urllib.error.HTTPError as error: assert error.code==422
result={'status':'PIPELINE_PASS' if cer==0 else 'PIPELINE_PASS_TRANSCRIPTION_NOT_EXACT','roundtripCharacterErrorRate':cer,'transcriptionExact':cer==0,'health':health,'fixture':str(fixture.relative_to(ROOT)),'fixtureRecognition':recognized,'asrWallSeconds':asr_elapsed,'ttsInput':text,'ttsWallSeconds':tts_elapsed,'ttsInferenceSeconds':headers.get('x-inference-seconds'),'audioSeconds':duration,'sampleRate':rate,'ttsToASR':roundtrip,'silenceRejected':True,'malformedAudioRejected':True,'liveMicrophoneTested':False}
(OUT/'voice-inference.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n')
print(json.dumps(result,ensure_ascii=False,indent=2))
