"""Regression: a cancelled synthesis must not make the next utterance fail with 503."""
import concurrent.futures,io,json,pathlib,time,urllib.request,urllib.error,wave
BASE='http://127.0.0.1:18765'
def post(text,timeout):
 req=urllib.request.Request(BASE+'/v1/tts',data=json.dumps({'text':text}).encode(),headers={'Content-Type':'application/json'})
 with urllib.request.urlopen(req,timeout=timeout) as response:return response.read()
# Confirm the worker has actually started before the first client times out.
# Otherwise this would only test discarding a request before native inference.
observed_busy=False;cancelled=False
with concurrent.futures.ThreadPoolExecutor(max_workers=1) as pool:
 first=pool.submit(post,'你好，我们一起慢慢聊聊今天的心情。',1.5)
 deadline=time.monotonic()+5
 while time.monotonic()<deadline and not observed_busy:
  with urllib.request.urlopen(BASE+'/health',timeout=3) as response:
   observed_busy=json.load(response)['busy']
  if not observed_busy: time.sleep(0.05)
 try: first.result()
 except TimeoutError: cancelled=True
 except urllib.error.URLError as error:
  if not isinstance(error.reason,TimeoutError): raise
  cancelled=True
assert observed_busy and cancelled,'Did not exercise cancellation during actual inference'
started=time.monotonic();result=post('你好。',90);elapsed=time.monotonic()-started
with wave.open(io.BytesIO(result),'rb') as audio: seconds=audio.getnframes()/audio.getframerate()
assert seconds>0.1 and elapsed<90
pathlib.Path('docs/verification/companion/voice-cancellation.json').write_text(json.dumps({'status':'PASS','firstInferenceObservedBusy':observed_busy,'firstClientTimedOut':cancelled,'nextUtteranceSucceeded':True,'elapsedSeconds':elapsed,'audioSeconds':seconds,'serverComputeCancellationSupported':False},indent=2)+'\n')
print('PASS: next utterance succeeded after prior client cancellation')
