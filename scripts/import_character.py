#!/usr/bin/env python3
"""Import a validated XCP source folder/.xcp archive; build engine assets and native catalog."""
import argparse,json,shutil,subprocess,sys,tempfile,time
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'character-sdk/tools'))
from character_tool import validate,unpack

def editor_build():
    command=['unity','command','eval','BuildIos.Setup(); BuildIos.Validate(); BuildIos.Thumbnail(); return "character-imported";',
             '--project-path',str(ROOT/'unity/CharacterRuntime'),'--detach','--format','json']
    reply=json.loads(subprocess.run(command,cwd=ROOT,text=True,capture_output=True,check=True).stdout)
    if not reply.get('success'): raise RuntimeError(reply)
    job=reply['data']['jobId']; print('Unity validation job: '+job,flush=True)
    end=time.monotonic()+600
    while time.monotonic()<end:
        response=subprocess.run(['unity','job','status',job,'--format','json'],cwd=ROOT,text=True,capture_output=True)
        if response.returncode: time.sleep(2); continue
        data=json.loads(response.stdout).get('data') or {}
        if data.get('state') in ('completed','succeeded'):
            if not (data.get('result') or {}).get('success'): raise RuntimeError(data.get('result'))
            return
        if data.get('state') in ('failed','cancelled'): raise RuntimeError(data)
        time.sleep(2)
    raise RuntimeError('Unity job timed out; inspect the accepted job before retrying: '+job)

def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('source',type=Path)
    parser.add_argument('--replace',action='store_true',help='Replace the same package identity after compatibility comparison')
    parser.add_argument('--source-only',action='store_true',help='Stage validated source only; export later runs Unity validation')
    args=parser.parse_args()
    with tempfile.TemporaryDirectory(prefix='xiaoban-import-') as temp:
        temp=Path(temp);source=args.source.resolve()
        if source.is_file(): source=unpack(source,temp/'extracted')
        manifest,warnings=validate(source)
        destination=ROOT/'character-packages/imported'/manifest['id'];builtin=ROOT/'character-packages/builtins'/manifest['id']
        if builtin.exists(): raise ValueError('The package identity collides with a shipped built-in character')
        if destination.exists():
            if not args.replace: raise ValueError('This character already exists; use --replace for a compatible upgrade')
            subprocess.run([sys.executable,str(ROOT/'character-sdk/tools/character_tool.py'),'compare',str(destination/'character.json'),str(source/'character.json')],check=True)
            shutil.copytree(destination,temp/'previous');shutil.rmtree(destination)
        destination.parent.mkdir(parents=True,exist_ok=True)
        shutil.copytree(source,destination)
        try:
            if not args.source_only: editor_build()
        except Exception:
            shutil.rmtree(destination)
            if (temp/'previous').exists(): shutil.copytree(temp/'previous',destination)
            print('Source registration rolled back. Re-run BuildIos.Setup after fixing the reported package error.',file=sys.stderr)
            raise
        print(json.dumps(dict(status='PASS',id=manifest['id'],version=manifest['packageVersion'],warnings=warnings,
                             next='Export Unity for each target platform, then build the host. Import does not modify an installed app.'),ensure_ascii=False,indent=2))
if __name__=='__main__':
    try: main()
    except (ValueError,RuntimeError,OSError,subprocess.CalledProcessError) as error: print(str(error),file=sys.stderr);sys.exit(1)
