#!/bin/bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"
SIMULATOR_ID="$(python3 - <<'PY'
import json,subprocess
data=json.loads(subprocess.check_output(['xcrun','simctl','list','devices','available','-j']))
devices=[d for group in data['devices'].values() for d in group if d['name']=='iPhone 17']
if not devices: raise SystemExit('Create an iPhone 17 simulator in Xcode first')
print(devices[0]['udid'])
PY
)"
APP_PATH="$ROOT_DIR/.local/build/DerivedData/Build/Products/Debug-iphonesimulator/CharacterHost.app"
if [ ! -d "$APP_PATH" ]; then bash scripts/build_host.sh; fi
xcrun simctl boot "$SIMULATOR_ID" 2>/dev/null || true
xcrun simctl bootstatus "$SIMULATOR_ID" -b
open -a Simulator --args -CurrentDeviceUDID "$SIMULATOR_ID"
xcrun simctl install "$SIMULATOR_ID" "$APP_PATH"
xcrun simctl launch --terminate-running-process "$SIMULATOR_ID" com.modelspace.viewer
