#!/usr/bin/env python3
"""Deploy an explicit local speech runtime into macOS Application Support."""
import json,pathlib,plistlib,shutil,subprocess
ROOT=pathlib.Path(__file__).resolve().parents[1]
runtime=pathlib.Path.home()/'Library/Application Support/Xuyu/Voice'
runtime.mkdir(parents=True,exist_ok=True,mode=0o700)
for sub in ['src','models','logs']: (runtime/sub).mkdir(exist_ok=True)
shutil.copy2(ROOT/'local-services/voice/server.py',runtime/'src/server.py')
shutil.copy2(ROOT/'local-services/voice/requirements.lock',runtime/'requirements.lock')
manifest=json.loads((ROOT/'local-services/voice/models.lock.json').read_text())
for item in manifest['files']:
 src=ROOT/'.local/voice-models'/item['model']/item['path'];dst=runtime/'models'/item['model']/item['path']
 dst.parent.mkdir(parents=True,exist_ok=True)
 if not dst.exists() or dst.stat().st_size!=src.stat().st_size: shutil.copy2(src,dst)
python=runtime/'venv/bin/python';uv=shutil.which('uv') or str(pathlib.Path.home()/'.local/bin/uv')
if not python.exists(): subprocess.run([uv,'venv','--python','3.11',str(runtime/'venv')],check=True)
subprocess.run([uv,'pip','sync','--offline','--python',str(python),str(runtime/'requirements.lock')],check=True)
config={'Label':'com.xuyu.local-voice','ProgramArguments':[str(python),'-m','uvicorn','server:app','--app-dir',str(runtime/'src'),'--host','127.0.0.1','--port','18765','--no-access-log'],'WorkingDirectory':str(runtime),'RunAtLoad':True,'KeepAlive':False,'EnvironmentVariables':{'PYTHONUNBUFFERED':'1','XUYU_VOICE_MODELS':str(runtime/'models')},'StandardOutPath':str(runtime/'logs/stdout.log'),'StandardErrorPath':str(runtime/'logs/server.log')}
# This engine serves foreground speech requests. Standard launchd jobs are
# CPU/I/O throttled; XPC-based Adaptive classification does not fit HTTP.
config['ProcessType']='Interactive'
(runtime/'launch-agent.plist').write_bytes(plistlib.dumps(config))
print(runtime)
