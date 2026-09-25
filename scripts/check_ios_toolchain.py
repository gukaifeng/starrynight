#!/usr/bin/env python3
"""Export a disposable Unity scene and compile its unsigned iOS framework."""
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
if sys.argv[1:] not in ([], ["--skip-export"]):
    raise SystemExit("Usage: check_ios_toolchain.py [--skip-export]")
if not sys.argv[1:]:
    subprocess.run([sys.executable, str(ROOT / "scripts/run_unity_check.py"), "--export-ios"], check=True)
export_report = json.loads((ROOT / ".local/checks/unity-ios-export.json").read_text())
if export_report["status"] != "PASS":
    raise SystemExit("A successful probe export is required before compilation.")
for filename, key in [("manifest.json", "manifestSha256"), ("packages-lock.json", "lockSha256")]:
    digest = hashlib.sha256((ROOT / "unity/CharacterRuntime/Packages" / filename).read_bytes()).hexdigest()
    if digest != export_report.get(key):
        raise SystemExit("Dependencies changed since the probe export; rerun without --skip-export.")
project = ROOT / ".local/build/ios-dependency-probe/Unity-iPhone.xcodeproj"
log = ROOT / ".local/logs/unityframework-build.log"
derived = ROOT / ".local/build/ios-probe-derived-data"
report_path = ROOT / ".local/checks/ios-toolchain.json"
report = {"status": "RUNNING", "startedAt": datetime.now(timezone.utc).isoformat(),
          "target": "UnityFramework", "configuration": "Debug", "sdk": "iphoneos",
          "architecture": "arm64", "codeSigning": "DISABLED", "deviceRun": "NOT_TESTED",
          "exportFinishedAt": export_report["finishedAt"], "log": str(log.relative_to(ROOT))}
report_path.write_text(json.dumps(report, indent=2) + "\n")
command = ["xcodebuild", "-project", str(project), "-scheme", "UnityFramework",
           "-configuration", "Debug", "-sdk", "iphoneos", "-destination", "generic/platform=iOS",
           "-derivedDataPath", str(derived), "CODE_SIGNING_ALLOWED=NO", "CODE_SIGNING_REQUIRED=NO",
           "ARCHS=arm64", "ONLY_ACTIVE_ARCH=YES", "build"]
print("Compiling unsigned UnityFramework for physical iOS ARM64; log: .local/logs/unityframework-build.log", flush=True)
try:
    with log.open("w") as stream:
        result = subprocess.run(command, stdout=stream, stderr=subprocess.STDOUT)
    report["exitCode"] = result.returncode
    framework = derived / "Build/Products/Debug-iphoneos/UnityFramework.framework/UnityFramework"
    passed = result.returncode == 0 and framework.is_file()
    report["status"] = "PASS" if passed else "FAIL"
    if passed:
        report["frameworkBinary"] = str(framework.relative_to(ROOT))
        report["fileDescription"] = subprocess.check_output(["file", str(framework)], text=True).strip().split(": ", 1)[-1]
except Exception as error:
    report["status"] = "FAIL"
    report["errorType"] = type(error).__name__
finally:
    report["finishedAt"] = datetime.now(timezone.utc).isoformat()
    report_path.write_text(json.dumps(report, indent=2) + "\n")
print(f"iOS toolchain: {report['status']}; report: .local/checks/ios-toolchain.json")
raise SystemExit(0 if report["status"] == "PASS" else 1)
