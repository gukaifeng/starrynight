#!/usr/bin/env python3
"""Run actual Editor validation and save a status report without account data."""
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT / "unity/CharacterRuntime"
export = sys.argv[1:] == ["--export-ios"]
if sys.argv[1:] and not export:
    raise SystemExit("Usage: run_unity_check.py [--export-ios]")
version = re.search(r"^m_EditorVersion: (.+)$", (PROJECT / "ProjectSettings/ProjectVersion.txt").read_text(), re.M)[1]
editor = os.environ.get("UNITY_EDITOR", f"/Applications/Unity/Hub/Editor/{version}/Unity.app/Contents/MacOS/Unity")
name = "unity-ios-export" if export else "unity-dependencies"
log = ROOT / ".local/logs" / ("unity-ios-export.log" if export else "unity-dependency-check.log")
result_path = ROOT / ".local/checks" / f"{name}.json"
log.parent.mkdir(parents=True, exist_ok=True)
result_path.parent.mkdir(parents=True, exist_ok=True)
report = {"status": "RUNNING", "startedAt": datetime.now(timezone.utc).isoformat(),
          "editor": version, "log": str(log.relative_to(ROOT)), "deviceRun": "NOT_TESTED"}

def save():
    result_path.write_text(json.dumps(report, indent=2) + "\n")

save()
try:
    subprocess.run([sys.executable, str(ROOT / "scripts/prepare_packages.py"), "--check"], check=True)
    method = "DependencyBuildProbe.ExportIOS" if export else "DependencyReadiness.Check"
    marker = "DEPENDENCY_IOS_EXPORT_PASS" if export else "DEPENDENCY_CHECK_PASS"
    result = subprocess.run([editor, "-batchmode", "-quit", "-projectPath", str(PROJECT),
                             "-buildTarget", "iOS", "-executeMethod", method, "-logFile", str(log)])
    report["exitCode"] = result.returncode
    lines = log.read_text(errors="replace").splitlines() if log.exists() else []
    # Only preserve our own fixed-format result line, never licensing logs.
    matches = [line for line in lines if line.startswith(marker)]
    passed = result.returncode == 0 and bool(matches)
    report["status"] = "PASS" if passed else "FAIL"
    if passed:
        report["result"] = matches[-1]
        report["editorLicense"] = "VALID_FOR_THIS_RUN"
        report["manifestSha256"] = hashlib.sha256((PROJECT / "Packages/manifest.json").read_bytes()).hexdigest()
        report["lockSha256"] = hashlib.sha256((PROJECT / "Packages/packages-lock.json").read_bytes()).hexdigest()
    else:
        print(f"Editor validation failed (exit {result.returncode}). See {log.relative_to(ROOT)}.")
except Exception as error:
    report["status"] = "FAIL"
    report["errorType"] = type(error).__name__
    print(f"Validation could not complete: {type(error).__name__}.")
finally:
    report["finishedAt"] = datetime.now(timezone.utc).isoformat()
    save()
print(f"{name}: {report['status']}; report: {result_path.relative_to(ROOT)}")
raise SystemExit(0 if report["status"] == "PASS" else 1)
