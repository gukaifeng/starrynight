#!/usr/bin/env python3
"""Export via Unity CLI using project-owned build logic. Prefer the live Editor."""
import argparse
import json
from pathlib import Path
import subprocess
import time

ROOT=Path(__file__).resolve().parents[1]
PROJECT=ROOT/'unity/CharacterRuntime'
parser=argparse.ArgumentParser()
parser.add_argument('--platform',choices=['simulator','device'],default='simulator')
args=parser.parse_args()
method='BuildIos.ExportSimulator' if args.platform=='simulator' else 'BuildIos.ExportDevice'
log=ROOT/'.local/logs'/f'export-{args.platform}.log'
log.parent.mkdir(parents=True,exist_ok=True)
def editor_ready():
    result=subprocess.run(['unity','status','--json'],capture_output=True,text=True)
    try: instances=json.loads(result.stdout).get('data',{}).get('instances',[])
    except (ValueError,AttributeError): instances=[]
    return any(i.get('project')==str(PROJECT) and i.get('state')=='ready' for i in instances)

live=editor_ready()
# A domain reload briefly hides Pipeline. Never open a second Editor on its lock.
lock=PROJECT/'Temp/UnityLockfile'
occupied=lock.exists() and subprocess.run(['lsof','-t',str(lock)],capture_output=True).returncode==0
if occupied and not live:
    print('Waiting for the existing Editor to finish its reload...',flush=True)
    deadline=time.monotonic()+120
    while time.monotonic()<deadline and not live:
        time.sleep(2); live=editor_ready()
    if not live: raise SystemExit('Editor owns project but Pipeline is unavailable; inspect compilation errors in Editor.log')
if live:
    # Confirm through the live endpoint, not just the discovery record, which can
    # briefly outlive a C# domain reload. Read-only probes may safely be retried.
    deadline=time.monotonic()+120
    while time.monotonic()<deadline:
        probe=subprocess.run(['unity','command','eval','return !UnityEditor.EditorApplication.isCompiling && !UnityEditor.EditorApplication.isUpdating && !UnityEditor.EditorApplication.isPlaying;',
            '--project-path',str(PROJECT),'--json'],capture_output=True,text=True)
        try: responsive=json.loads(probe.stdout).get('data',{}).get('result',{}).get('result') is True
        except (ValueError,AttributeError): responsive=False
        if responsive: break
        time.sleep(2)
    else: raise SystemExit('Editor is compiling, updating, or in Play Mode; finish that operation before exporting')
    command=['unity','command','eval',f'{method}(); return "export-complete";', '--project-path',str(PROJECT),'--detach','--json']
    response=subprocess.run(command,capture_output=True,text=True)
    if response.returncode:
        raise SystemExit('Export request was not accepted. Inspect the Editor before retrying:\n'+response.stdout+response.stderr)
    result=json.loads(response.stdout)
    if not result.get('success'): raise SystemExit(result)
    job=result['data']['jobId']
    deadline=time.monotonic()+1200
    with log.open('w') as stream:
        while time.monotonic()<deadline:
            status=json.loads(subprocess.check_output(['unity','job','status',job,'--project-path',str(PROJECT),'--json'],text=True))
            stream.write(json.dumps(status)+'\n');stream.flush()
            data=status.get('data',{})
            state=data.get('state')
            if state in ['completed','succeeded']:
                inner=data.get('result') or {}
                if inner.get('success') is not True: raise SystemExit(inner)
                break
            if state in ['failed','cancelled','canceled']: raise SystemExit(data)
            time.sleep(3)
        else: raise SystemExit('Unity export timed out; inspect the running job before retrying')
else:
    subprocess.run(['unity','run',str(PROJECT),'--','-buildTarget','iOS','-executeMethod',method,'-logFile',str(log)],check=True)
stamp=ROOT/'build'/f'unity-{args.platform}'/'modelspace-export.json'
if not stamp.exists(): raise SystemExit('Export completed without required postprocessing')
print(f'Export ready: {stamp.parent.relative_to(ROOT)}')
