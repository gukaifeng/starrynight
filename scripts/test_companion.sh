#!/bin/zsh
set -eu
ROOT="${0:A:h:h}"
cd "$ROOT"
DEVICE_ID="${1:-99F5FAC6-A73A-4C59-A723-D57D648B342E}"
TEST_CASE="${2:-CompanionFlowTests}"
RESULT_NAME="${3:-Companion-Phone}"
python3 scripts/check_export_content.py --platform simulator
python3 scripts/generate_host.py --platform simulator
xcrun simctl boot "$DEVICE_ID" 2>/dev/null || true
python3 scripts/wait_for_simulator.py "$DEVICE_ID"
xcrun simctl terminate "$DEVICE_ID" com.modelspace.viewer 2>/dev/null || true
# A reused unsigned runner has executed an older loaded test bundle despite a
# newly linked binary. Replace only the test harness; preserve the app's data.
xcrun simctl uninstall "$DEVICE_ID" com.modelspace.viewer.uitests.xctrunner 2>/dev/null || true
TEST_FILTERS=()
for CASE in ${(s:,:)TEST_CASE}; do TEST_FILTERS+=("-only-testing:CharacterHostUITests/$CASE"); done
xcodebuild -workspace ios/StarryNight-Simulator.xcworkspace -scheme CharacterHost -configuration Debug \
 -destination "platform=iOS Simulator,id=$DEVICE_ID" -derivedDataPath .local/build/DerivedData \
 -resultBundlePath ".local/checks/$RESULT_NAME.xcresult" -parallel-testing-enabled NO \
 -maximum-concurrent-test-simulator-destinations 1 "${TEST_FILTERS[@]}" \
 CODE_SIGNING_ALLOWED=NO test >".local/logs/$RESULT_NAME.log" 2>&1
if ! rg -q '^Test Case .+ passed' ".local/logs/$RESULT_NAME.log"; then
  echo "No XCTest case completed. Check the filter; method filters may require trailing (). See .local/logs/$RESULT_NAME.log" >&2
  exit 1
fi
