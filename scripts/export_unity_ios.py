#!/usr/bin/env python3
"""Export via Unity CLI using project-owned build logic. Prefer the live Editor."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import time

ROOT=Path(__file__).resolve().parents[1]
PROJECT=ROOT/'unity/CharacterRuntime'
parser=argparse.ArgumentParser()
parser.add_argument('--platform',choices=['simulator','device'],default='simulator')
parser.add_argument('--prepare-timeout',type=int,default=3600,help='Seconds allowed for scene preparation, including a cold iOS asset import')
args=parser.parse_args()
subprocess.run(['python3',str(ROOT/'scripts/prepare_palette_shaders.py')],check=True)
if args.prepare_timeout < 1:
    parser.error('--prepare-timeout must be positive')
method='BuildIos.ExportSimulator' if args.platform=='simulator' else 'BuildIos.ExportDevice'
log=ROOT/'.local/logs'/f'export-{args.platform}.log'
log.parent.mkdir(parents=True,exist_ok=True)
editor_pid = None
def editor_ready():
    global editor_pid
    result=subprocess.run(['unity','status','--json'],capture_output=True,text=True)
    try: instances=json.loads(result.stdout).get('data',{}).get('instances',[])
    except (ValueError,AttributeError): instances=[]
    matching = next((i for i in instances if i.get('project')==str(PROJECT) and i.get('state')=='ready'),None)
    if matching: editor_pid = matching.get('pid')
    return matching is not None

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
    # Import source edits before invoking BuildPipeline: refreshing inside Export is
    # too late for a domain reload, and Editor/Player serialized layouts can differ.
    subprocess.run(['unity','command','eval','UnityEditor.AssetDatabase.Refresh(); UnityEditor.Compilation.CompilationPipeline.RequestScriptCompilation(); UnityEditor.EditorUtility.RequestScriptReload(); return "refresh-requested";',
        '--project-path',str(PROJECT),'--json'],capture_output=True,text=True)
    time.sleep(2)
    # Confirm through the live endpoint, not just the discovery record, which can
    # briefly outlive a C# domain reload. Read-only probes may safely be retried.
    deadline=time.monotonic()+120
    while time.monotonic()<deadline:
        probe=subprocess.run(['unity','command','eval','return !UnityEditor.EditorUtility.scriptCompilationFailed && !UnityEditor.EditorApplication.isCompiling && !UnityEditor.EditorApplication.isUpdating && !UnityEditor.EditorApplication.isPlaying && typeof(ModelSpace.CompanionAvatarDriver).GetField("AtmosphereRevision") is object && typeof(ModelSpace.BridgePayload).GetField("framingShot") is object && typeof(ModelSpace.ViewerCharacter).GetField("framingEnvelopes") is object;',
            '--project-path',str(PROJECT),'--detach','--json'],capture_output=True,text=True)
        responsive = False
        try:
            probe_response = json.loads(probe.stdout)
            probe_job = probe_response.get('data',{}).get('jobId') if probe_response.get('success') else None
        except (ValueError,AttributeError): probe_job = None
        # Synchronous main-thread eval has a 5 s server budget. A busy but healthy
        # Editor may miss it; a tracked read-only job avoids misreporting compilation.
        if probe_job:
            probe_deadline = min(deadline,time.monotonic()+45)
            while time.monotonic() < probe_deadline:
                result = subprocess.run(['unity','job','status',probe_job,'--project-path',str(PROJECT),'--json'],capture_output=True,text=True)
                try: state = json.loads(result.stdout).get('data') or {}
                except (ValueError,AttributeError): state = {}
                if state.get('state') in ('completed','succeeded'):
                    responsive = (state.get('result') or {}).get('result') is True
                    break
                if state.get('state') in ('failed','cancelled','canceled'): break
                time.sleep(2)
        if responsive: break
        time.sleep(2)
    else: raise SystemExit('Editor has compilation errors, is compiling/updating, or is in Play Mode; resolve before exporting')
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
            poll=subprocess.run(['unity','job','status',job,'--project-path',str(PROJECT),'--json'],capture_output=True,text=True)
            try: status=json.loads(poll.stdout)
            except ValueError: status={'success':False,'pollExitCode':poll.returncode,'diagnostic':poll.stderr[-1000:]}
            stream.write(json.dumps(status)+'\n');stream.flush()
            if not status.get('success'):
                # A native Editor crash loses its accepted job. Do not poll that lost
                # job for twenty minutes or silently resubmit a mutating export.
                if editor_pid:
                    try: os.kill(editor_pid,0)
                    except ProcessLookupError:
                        raise SystemExit('Unity Editor exited during the accepted export. Inspect its crash log, then rerun in a fresh Editor.')
                # This is a read-only status query. Keep the accepted job ID and retry
                # across transient CLI/network errors; never submit the export again.
                time.sleep(3)
                continue
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
    # Unity 6000.3 can crash in URP's build callback after thumbnail rendering
    # in the same process. A clean second Editor avoids that native state while
    # preserving all Setup/Validate/thumbnail checks and the saved source scene.
    prepare_log=log.with_name('prepare-'+args.platform+'.log')
    subprocess.run(['unity','run',str(PROJECT),'--timeout',str(args.prepare_timeout),'--','-buildTarget','iOS','-executeMethod','BuildIos.PrepareExport','-logFile',str(prepare_log)],check=True)
    prepared='BuildIos.ExportPreparedSimulator' if args.platform=='simulator' else 'BuildIos.ExportPreparedDevice'
    subprocess.run(['unity','run',str(PROJECT),'--timeout','1200','--','-buildTarget','iOS','-executeMethod',prepared,'-logFile',str(log)],check=True)
stamp=ROOT/'build'/f'unity-{args.platform}'/'modelspace-export.json'
if not stamp.exists(): raise SystemExit('Export completed without required postprocessing')
subprocess.run(['python3',str(ROOT/'scripts/check_export_content.py'),'--platform',args.platform],check=True)
print(f'Export ready: {stamp.parent.relative_to(ROOT)}')
