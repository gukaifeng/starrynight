#!/bin/bash
set -euo pipefail
BUILD_CONFIGURATION=Debug
BUILD_OPTION=--debug
case "${1:-}" in
  --release) BUILD_CONFIGURATION=Release; BUILD_OPTION=--release ;;
  --debug|'') ;;
  *) echo 'Usage: run_simulator.sh [--debug|--release]' >&2; exit 2 ;;
esac
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
APP_PATH="$ROOT_DIR/.local/build/DerivedData/Build/Products/$BUILD_CONFIGURATION-iphonesimulator/StarryNight.app"
SOURCE_VERSION="$(python3 - <<'PYVERSION'
import re
from pathlib import Path
print(re.search(r"'CURRENT_PROJECT_VERSION':'([^']+)'", Path('scripts/generate_host.py').read_text())[1])
PYVERSION
)"
BUILT_VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "$APP_PATH/Info.plist" 2>/dev/null || true)"
if [ ! -d "$APP_PATH" ] || [ "$BUILT_VERSION" != "$SOURCE_VERSION" ]; then
  bash scripts/build_host.sh "$BUILD_OPTION"
fi
xcrun simctl boot "$SIMULATOR_ID" 2>/dev/null || true
python3 scripts/wait_for_simulator.py "$SIMULATOR_ID"
open -a Simulator --args -CurrentDeviceUDID "$SIMULATOR_ID"
xcrun simctl install "$SIMULATOR_ID" "$APP_PATH"
xcrun simctl launch --terminate-running-process "$SIMULATOR_ID" com.modelspace.viewer
