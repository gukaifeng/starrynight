"""Local-only speech adapter. No dialogue/recording content is logged or stored."""
import asyncio, io, os, threading, time
from contextlib import asynccontextmanager
from pathlib import Path
import numpy as np
import soundfile as sf
import sherpa_onnx
from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import Response
from pydantic import BaseModel, Field
ROOT = Path(__file__).resolve().parents[2]
MODELS = Path(os.environ.get('XUYU_VOICE_MODELS', str(ROOT / '.local/voice-models')))
lock = threading.Lock()
recognizer = synthesizer = None
startup_seconds = 0
metrics={"ttsReceived":0,"ttsCompleted":0,"asrReceived":0}
@asynccontextmanager
async def lifespan(app):
 global recognizer, synthesizer, startup_seconds
 started=time.monotonic()
 asr=MODELS/'sensevoice'; tts=MODELS/'melo'
 recognizer=sherpa_onnx.OfflineRecognizer.from_sense_voice(
  model=str(asr/'model.int8.onnx'),tokens=str(asr/'tokens.txt'),num_threads=2,use_itn=True,debug=False)
 config=sherpa_onnx.OfflineTtsConfig(
  model=sherpa_onnx.OfflineTtsModelConfig(vits=sherpa_onnx.OfflineTtsVitsModelConfig(
   model=str(tts/'model.onnx'),lexicon=str(tts/'lexicon.txt'),tokens=str(tts/'tokens.txt'),dict_dir=str(tts/'dict')),
   num_threads=4,debug=False,provider='cpu'),
  rule_fsts=','.join(str(tts/file) for file in ['date.fst','number.fst','phone.fst']),max_num_sentences=1)
 if not config.validate(): raise RuntimeError('Invalid TTS model configuration')
 synthesizer=sherpa_onnx.OfflineTts(config)
 startup_seconds=round(time.monotonic()-started,3)
 yield
app=FastAPI(title='Xuyu local speech',lifespan=lifespan,docs_url=None,redoc_url=None)
@app.get('/health')
def health():
 return {'ready':recognizer is not None and synthesizer is not None,'asr':'SenseVoiceSmall int8','tts':'MeloTTS zh_en','runtime':'sherpa-onnx 1.13.8','localOnly':True,'busy':lock.locked(),'metrics':metrics,'ttsThreads':4,'startupSeconds':startup_seconds}
class SpeechRequest(BaseModel):
 text: str=Field(min_length=1,max_length=500)
 speed: float=Field(default=1.0,ge=0.7,le=1.4)
async def locked(operation,request):
 deadline=time.monotonic()+45
 while not lock.acquire(blocking=False):
  if await request.is_disconnected(): raise HTTPException(499,'Client disconnected')
  if time.monotonic()>deadline: raise HTTPException(503,'Speech engine busy; retry shortly')
  await asyncio.sleep(0.1)
 if await request.is_disconnected():
  lock.release(); raise HTTPException(499,'Client disconnected')
 def infer_and_release():
  try: return operation()
  finally: lock.release()
 return await asyncio.to_thread(infer_and_release)
@app.post('/v1/tts')
async def tts(body:SpeechRequest,request:Request):
 metrics["ttsReceived"]+=1
 def infer():
  started=time.monotonic(); cpu_started=time.process_time()
  audio=synthesizer.generate(body.text,sid=0,speed=body.speed)
  if len(audio.samples)==0: raise HTTPException(422,'No speech produced')
  output=io.BytesIO(); sf.write(output,audio.samples,audio.sample_rate,format='WAV',subtype='PCM_16')
  metrics['ttsCompleted']+=1
  metrics['lastTTSSeconds']=round(time.monotonic()-started,3)
  metrics['lastTTSCPUSeconds']=round(time.process_time()-cpu_started,3)
  metrics['lastAudioSeconds']=round(len(audio.samples)/audio.sample_rate,3)
  metrics['lastTextLength']=len(body.text)
  return Response(output.getvalue(),media_type='audio/wav',headers={'X-Inference-Seconds':str(round(time.monotonic()-started,3)),'Cache-Control':'no-store'})
 return await locked(infer,request)
@app.post('/v1/asr')
async def asr(request:Request):
 metrics["asrReceived"]+=1
 chunks=[]; size=0
 async for chunk in request.stream():
  size+=len(chunk)
  if size>4_000_000: raise HTTPException(413,'Audio exceeds 4 MB')
  chunks.append(chunk)
 try: samples,rate=sf.read(io.BytesIO(b''.join(chunks)),dtype='float32',always_2d=True)
 except Exception: raise HTTPException(422,'Expected a WAV audio file')
 if rate<8000 or rate>48000 or samples.shape[1]>2 or not 0.15<=len(samples)/rate<=31:
  raise HTTPException(422,'Expected 0.15–31 seconds, mono/stereo, 8–48 kHz')
 if not np.isfinite(samples).all(): raise HTTPException(422,'Invalid audio samples')
 samples=samples.mean(axis=1)
 if float(np.sqrt(np.mean(samples*samples)))<0.001: return {'text':'','reason':'silence'}
 def infer():
  started=time.monotonic(); stream=recognizer.create_stream(); stream.accept_waveform(rate,samples)
  recognizer.decode_stream(stream)
  return {'text':stream.result.text.strip(),'inferenceSeconds':round(time.monotonic()-started,3)}
 return await locked(infer,request)
