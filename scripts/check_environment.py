#!/usr/bin/env python3
"""Read local tool versions and license state without exposing account details."""
from __future__ import annotations
import json
from pathlib import Path
import plistlib
import shutil
import subprocess
from datetime import datetime, timezone

ROOT = Path(__file__).resolve().parents[1]
VERSION = "6000.3.25f1"
INSTALL = Path("/Applications/Unity/Hub/Editor") / VERSION
APP = INSTALL / "Unity.app"


def command(args: list[str]) -> dict:
    try:
        result = subprocess.run(args, capture_output=True, text=True, timeout=30)
        return {"exitCode": result.returncode, "output": (result.stdout + result.stderr).strip()}
    except (OSError, subprocess.TimeoutExpired) as error:
        return {"exitCode": -1, "output": str(error)}


def main() -> None:
    report = {"checkedAt": datetime.now(timezone.utc).isoformat(), "tools": {}}
    for name, args in {
        "macOS": ["sw_vers"], "architecture": ["uname", "-m"],
        "chip": ["sysctl", "-n", "machdep.cpu.brand_string"],
        "memoryBytes": ["sysctl", "-n", "hw.memsize"],
        "xcode": ["xcodebuild", "-version"],
        "xcodeFirstLaunch": ["xcodebuild", "-checkFirstLaunchStatus"],
        "iphoneosSDK": ["xcrun", "--sdk", "iphoneos", "--show-sdk-version"],
        "swift": ["xcrun", "swift", "--version"],
        "clang": ["xcrun", "clang", "--version"],
        "metal": ["xcrun", "metal", "--version"],
        "rosetta": ["arch", "-x86_64", "/usr/bin/true"],
        "git": ["git", "--version"], "python": ["python3", "--version"],
        "unityCLI": ["unity", "--version"],
    }.items():
        report["tools"][name] = command(args)

    hub_plist = Path("/Applications/Unity Hub.app/Contents/Info.plist")
    report["unityHubVersion"] = plistlib.loads(hub_plist.read_bytes()).get("CFBundleShortVersionString") if hub_plist.exists() else None
    editor_plist = APP / "Contents/Info.plist"
    report["unityEditorVersion"] = plistlib.loads(editor_plist.read_bytes()).get("CFBundleVersion") if editor_plist.exists() else None
    module_paths = [INSTALL / "PlaybackEngines/iOSSupport", APP / "Contents/PlaybackEngines/iOSSupport"]
    report["iosModuleFilesPresent"] = any((p / "UnityEditor.iOS.Extensions.dll").is_file() and (p / "Trampoline").is_dir() for p in module_paths)
    report["diskFreeBytes"] = shutil.disk_usage(ROOT).free

    # Deliberately keep only status booleans, never account or license identifiers.
    license_result = command(["unity", "license", "status", "--format", "json", "--non-interactive"])
    try:
        data = json.loads(license_result["output"])["data"]
        report["unityCLIAuth"] = {"active": data.get("active"), "signedIn": data.get("signedIn")}
    except (ValueError, KeyError, TypeError):
        report["unityCLIAuth"] = {"status": "UNKNOWN", "exitCode": license_result["exitCode"]}

    # The CLI and Hub can have separate sessions. A CLI boolean is not proof
    # that the Editor is licensed (or unlicensed).
    readiness_path = ROOT / ".local/checks/unity-dependencies.json"
    report["unityEditorValidation"] = json.loads(readiness_path.read_text()) if readiness_path.exists() else {"status": "NOT_TESTED"}
    ios_check_path = ROOT / ".local/checks/ios-toolchain.json"
    report["iosToolchainValidation"] = json.loads(ios_check_path.read_text()) if ios_check_path.exists() else {"status": "NOT_TESTED"}

    result_path = ROOT / ".local/checks/environment.json"
    result_path.parent.mkdir(parents=True, exist_ok=True)
    result_path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    for name, result in report["tools"].items():
        print(f"{name}: {'OK' if result['exitCode'] == 0 else 'CHECK REQUIRED'}")
    print("Unity Hub:", report["unityHubVersion"])
    print("Unity Editor:", report["unityEditorVersion"])
    print("iOS module files present:", report["iosModuleFilesPresent"])
    print("Unity CLI session (separate from Hub/Editor):", report["unityCLIAuth"])
    print("Unity Editor validation:", report["unityEditorValidation"]["status"])
    print("Last full iOS framework build:", report["iosToolchainValidation"]["status"])
    print("Saved .local/checks/environment.json (account identifiers excluded).")


if __name__ == "__main__":
    main()
