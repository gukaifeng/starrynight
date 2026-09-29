#!/bin/bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"
python3 scripts/check_export_content.py --platform simulator
python3 scripts/generate_host.py --platform simulator
read -r PHONE_ID TABLET_ID < <(python3 - <<'PYIDS'
import json, subprocess
devices=json.loads(subprocess.check_output(['xcrun','simctl','list','devices','available','-j']))['devices']
for runtime, group in devices.items():
    phone=next((d for d in group if d['name']=='iPhone 17'),None)
    if phone:
        tablet=next((d for d in group if 'iPad-Pro-11-inch-M4-' in d.get('deviceTypeIdentifier','')),None)
        tablet_id=tablet['udid'] if tablet else subprocess.check_output(['xcrun','simctl','create','iPad Pro 11-inch (M4) - Model Space QA','com.apple.CoreSimulator.SimDeviceType.iPad-Pro-11-inch-M4-8GB',runtime],text=True).strip()
        print(phone['udid'],tablet_id)
        break
else: raise SystemExit('An available iPhone 17 simulator runtime is required')
PYIDS
)
TEST_TAG="MikuLayouts-$(date +%Y%m%d-%H%M%S)"
mkdir -p .local/checks .local/logs
for TYPE in phone ipad; do
  if [ "$TYPE" = phone ]; then
    SIM_ID="$PHONE_ID"
    CASES=(-only-testing:CharacterHostUITests/ViewerFlowTests/testD_CharacterSwitchAndAdditionalActions -only-testing:CharacterHostUITests/ViewerFlowTests/testE_MikuHeadInteractionFramingAndFrameTargets)
  else
    SIM_ID="$TABLET_ID"
    CASES=(-only-testing:CharacterHostUITests/ViewerFlowTests/testF_IPadPortraitAndLandscape)
  fi
  xcrun simctl boot "$SIM_ID" 2>/dev/null || true
  python3 scripts/wait_for_simulator.py "$SIM_ID"
  RESULT="$ROOT_DIR/.local/checks/$TEST_TAG-$TYPE.xcresult"
  xcodebuild -workspace ios/StarryNight-Simulator.xcworkspace -scheme CharacterHost \
    -configuration Debug -destination "platform=iOS Simulator,id=$SIM_ID" \
    -derivedDataPath .local/build/DerivedData -resultBundlePath "$RESULT" \
    -parallel-testing-enabled NO "${CASES[@]}" CODE_SIGNING_ALLOWED=NO test > ".local/logs/$TEST_TAG-$TYPE.log" 2>&1
  DATA_PATH="$(xcrun simctl get_app_container "$SIM_ID" com.modelspace.viewer data)"
  if [ "$TYPE" = phone ]; then
    cp "$DATA_PATH/Documents/character-switch-events.jsonl" ".local/checks/$TEST_TAG-character-switch-events.jsonl"
    cp "$DATA_PATH/Documents/miku-head-events.jsonl" ".local/checks/$TEST_TAG-head-events.jsonl"
    python3 scripts/verify_character_events.py ".local/checks/$TEST_TAG-character-switch-events.jsonl"
    python3 scripts/verify_miku_head_events.py ".local/checks/$TEST_TAG-head-events.jsonl"
  else
    cp "$DATA_PATH/Documents/ipad-events.jsonl" ".local/checks/$TEST_TAG-ipad-events.jsonl"
  fi
  xcrun xcresulttool export attachments --path "$RESULT" --output-path ".local/checks/$TEST_TAG-$TYPE-attachments" > ".local/logs/$TEST_TAG-$TYPE-attachments.log"
  xcrun simctl terminate "$SIM_ID" com.modelspace.viewer 2>/dev/null || true
  echo "$TYPE interaction/layout checks passed: $RESULT"
done
