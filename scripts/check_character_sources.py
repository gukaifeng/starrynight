#!/usr/bin/env python3
"""Type-check against installed Unity assemblies without modifying the Editor's build cache.

This verifies C# compilation only. It does not generate assets, run Unity, validate
shaders, build IL2CPP, or measure rendering performance.
"""
import json
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT / 'unity/CharacterRuntime'
OUT = ROOT / '.local/checks/character-source-check'
OUT.mkdir(parents=True, exist_ok=True)
version = re.search(r'^m_EditorVersion: (.+)$', (PROJECT / 'ProjectSettings/ProjectVersion.txt').read_text(), re.M)[1]
resources = Path(f'/Applications/Unity/Hub/Editor/{version}/Unity.app/Contents/Resources')
csc = resources / 'Scripting/DotNetSdkRoslyn/csc.dll'
dotnet = resources / 'Scripting/NetCoreRuntime/dotnet'
response_files = list((PROJECT / 'Library/Bee/artifacts').glob('*.dag/Assembly-CSharp-Editor.rsp'))
if not response_files:
    raise SystemExit('Open this Unity project once to create its actual assembly reference response files.')
cache = max(response_files, key=lambda p: p.stat().st_mtime).parent
summary = {'scope': 'C# compiler and actual Unity reference assemblies; no Editor execution', 'results': []}
for assembly, source_dir in [('Assembly-CSharp', 'Assets/Scripts'), ('Assembly-CSharp-Editor', 'Assets/Editor')]:
    response = []
    for line in (cache / f'{assembly}.rsp').read_text(encoding='utf-8-sig').splitlines():
        if line.startswith(('-out:', '-refout:', '-analyzer:', '/additionalfile:')):
            continue
        if not line.startswith(('-', '/')):
            continue
        if 'Assembly-CSharp.ref.dll' in line:
            line = f'-r:"{OUT / "Assembly-CSharp.ref.dll"}"'
        response.append(line)
    response += [f'-out:"{OUT / (assembly + ".dll")}"', f'-refout:"{OUT / (assembly + ".ref.dll")}"']
    response += [f'"{p.relative_to(PROJECT)}"' for p in sorted((PROJECT / source_dir).rglob('*.cs'))]
    rsp = OUT / f'{assembly}.rsp'
    rsp.write_text('\n'.join(response) + '\n')
    result = subprocess.run([str(dotnet), str(csc), '@' + str(rsp)], cwd=PROJECT, capture_output=True, text=True)
    (OUT / f'{assembly}.log').write_text(result.stdout + result.stderr)
    summary['results'].append({'assembly': assembly, 'exitCode': result.returncode})
    print(f'{assembly}: {"PASS" if result.returncode == 0 else "FAIL"}')
    if result.stdout or result.stderr:
        print(result.stdout + result.stderr)
    if result.returncode:
        break
summary['status'] = 'PASS' if len(summary['results']) == 2 and all(x['exitCode'] == 0 for x in summary['results']) else 'FAIL'
(OUT / 'result.json').write_text(json.dumps(summary, indent=2) + '\n')
raise SystemExit(0 if summary['status'] == 'PASS' else 1)
