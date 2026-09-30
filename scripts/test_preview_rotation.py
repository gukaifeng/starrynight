#!/usr/bin/env python3
"""Test actual preview motion with Unity managed math; no Editor/AI/network calls."""
import os
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]
version = re.search(r"^m_EditorVersion: (.+)$", (ROOT / "unity/CharacterRuntime/ProjectSettings/ProjectVersion.txt").read_text(), re.M)[1]
scripting = Path(f"/Applications/Unity/Hub/Editor/{version}/Unity.app/Contents/Resources/Scripting")
mono = scripting / "MonoBleedingEdge"
engine = scripting / "Managed/UnityEngine"
output = ROOT / ".local/checks/preview-rotation"
output.mkdir(parents=True, exist_ok=True)
binary = output / "core-tests.exe"
# Unity's csc shell wrapper can contain its build machine's absolute path.
# Invoke the shipped compiler assembly through the installed Mono explicitly.
subprocess.run([
    str(mono / "bin/mono"), str(mono / "lib/mono/4.5/csc.exe"), "-nologo",
    f"-out:{binary}", f"-r:{engine / 'UnityEngine.CoreModule.dll'}",
    f"-r:{mono / 'lib/mono/unityjit-macos/Facades/netstandard.dll'}",
    str(ROOT / "unity/CharacterRuntime/Assets/Scripts/Runtime/CharacterPreviewRotation.cs"),
    str(ROOT / "scripts/tests/CharacterPreviewRotationTests.cs"),
], check=True, cwd=ROOT)
result = subprocess.run([str(mono / "bin/mono"), str(binary)],
                        env={**os.environ, "MONO_PATH": str(engine)},
                        capture_output=True, text=True, cwd=ROOT)
(output / "core-tests.log").write_text(result.stdout + result.stderr)
print(result.stdout + result.stderr, end="")
result.check_returncode()
