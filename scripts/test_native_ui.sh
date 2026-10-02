#!/bin/bash
# Production native UI in an isolated simulator app. No Unity rendering claims.
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_ROOT"
TEST_CASES="${1:-ConversationInfoCardTests,MessageListScrollTests}"
RUN_NAME="${2:-NativeUI-$(date +%Y%m%d-%H%M%S)}"
if [[ ! "$RUN_NAME" =~ ^[A-Za-z0-9._-]+$ ]]; then echo 'Invalid result name' >&2; exit 2; fi
SIMULATOR_ID="$(python3 - <<'PY'
import json, subprocess
data=json.loads(subprocess.check_output(['xcrun','simctl','list','devices','available','-j']))
print(next(d['udid'] for group in data['devices'].values() for d in group if d['name']=='iPhone 17'))
PY
)"
STARRY_LIVE_AI_TESTS=0 python3 scripts/generate_host.py --platform simulator --native-ui-fixture
xcrun simctl boot "$SIMULATOR_ID" 2>/dev/null || true
python3 scripts/wait_for_simulator.py "$SIMULATOR_ID"
mkdir -p .local/logs .local/checks
IFS=',' read -ra CASES <<< "$TEST_CASES"
TEST_FILTERS=()
for CASE in "${CASES[@]}"; do TEST_FILTERS+=("-only-testing:CharacterHostUITests/$CASE"); done
LOG_PATH=".local/logs/$RUN_NAME.log"
RESULT_PATH=".local/checks/$RUN_NAME.xcresult"
if ! xcodebuild -workspace ios/StarryNight-NativeUI.xcworkspace -scheme CharacterHost \
  -configuration Debug -destination "platform=iOS Simulator,id=$SIMULATOR_ID" \
  -derivedDataPath .local/build/NativeUIDerivedData -resultBundlePath "$RESULT_PATH" \
  -parallel-testing-enabled NO "${TEST_FILTERS[@]}" CODE_SIGNING_ALLOWED=NO test > "$LOG_PATH" 2>&1; then
  tail -60 "$LOG_PATH" >&2;exit 1
fi
if ! rg -q '^Test Case .+ passed' "$LOG_PATH"; then echo 'No selected XCTest completed' >&2;exit 1;fi
echo "Native UI tests passed: $RESULT_PATH"
