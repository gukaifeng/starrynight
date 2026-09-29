import io,json,time,pathlib,urllib.request
import sherpa_onnx,soundfile as sf
ROOT=pathlib.Path(__file__).resolve().parents[1];d=ROOT/'.local/voice-models/kokoro'
config=sherpa_onnx.OfflineTtsConfig(model=sherpa_onnx.OfflineTtsModelConfig(kokoro=sherpa_onnx.OfflineTtsKokoroModelConfig(model=str(d/'model.int8.onnx'),voices=str(d/'voices.bin'),tokens=str(d/'tokens.txt'),data_dir=str(d/'espeak-ng-data'),lexicon=','.join(str(d/name) for name in ['lexicon-us-en.txt','lexicon-zh.txt'])),num_threads=4,provider='cpu'),rule_fsts=','.join(str(d/name) for name in ['date-zh.fst','number-zh.fst','phone-zh.fst']),max_num_sentences=1)
assert config.validate()
start=time.monotonic();tts=sherpa_onnx.OfflineTts(config);load=time.monotonic()-start
results=[]
for sid in [3,58]:
 text='你好，我是小屿。今天想和你聊聊音乐。'
 start=time.monotonic();a=tts.generate(text=text,sid=sid,speed=1.0);elapsed=time.monotonic()-start
 out=ROOT/f'docs/verification/companion/kokoro-voice-{sid}.wav';sf.write(str(out),a.samples,a.sample_rate,subtype='PCM_16')
 results.append({'speaker':sid,'inferenceSeconds':elapsed,'audioSeconds':len(a.samples)/a.sample_rate})
 print(json.dumps(results[-1]),flush=True)
result={'loadSeconds':load,'results':results}
(ROOT/'docs/verification/companion/kokoro-benchmark.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n')
print(json.dumps(result,ensure_ascii=False,indent=2))
