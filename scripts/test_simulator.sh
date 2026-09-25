#!/bin/bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"
SIMULATOR_ID="$(python3 - <<'PY'
import json,subprocess
data=json.loads(subprocess.check_output(['xcrun','simctl','list','devices','available','-j']))
print(next(d['udid'] for g in data['devices'].values() for d in g if d['name']=='iPhone 17'))
PY
)"
RUN_NAME="ViewerFlow-$(date +%Y%m%d-%H%M%S)"
RESULT_PATH="$ROOT_DIR/.local/checks/$RUN_NAME.xcresult"
mkdir -p .local/logs .local/checks
python3 scripts/generate_host.py --platform simulator
xcrun simctl boot "$SIMULATOR_ID" 2>/dev/null || true
xcrun simctl bootstatus "$SIMULATOR_ID" -b
xcodebuild -workspace ios/CharacterPrototype.xcworkspace -scheme CharacterHost \
  -configuration Debug -destination "platform=iOS Simulator,id=$SIMULATOR_ID" \
  -derivedDataPath .local/build/DerivedData -resultBundlePath "$RESULT_PATH" \
  -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO test > ".local/logs/$RUN_NAME.log" 2>&1
DATA_PATH="$(xcrun simctl get_app_container "$SIMULATOR_ID" com.modelspace.viewer data)"
cp "$DATA_PATH/Documents/viewer-events.jsonl" ".local/checks/$RUN_NAME-events.jsonl"
python3 scripts/verify_viewer_events.py ".local/checks/$RUN_NAME-events.jsonl"
xcrun xcresulttool export attachments --path "$RESULT_PATH" --output-path ".local/checks/$RUN_NAME-attachments"
echo "Tests and engine assertions passed: $RESULT_PATH"
