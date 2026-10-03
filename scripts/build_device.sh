#!/bin/bash
# Compile ahead of device arrival with --unsigned; otherwise use local Apple signing.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"
UNSIGNED=false
DEVICE_ID=""
GENERATE_ARGS=(--platform device)
while [ "$#" -gt 0 ]; do
  case "$1" in
    --unsigned) UNSIGNED=true; shift ;;
    --distribution) GENERATE_ARGS+=(--distribution); shift ;;
    --device)
      if [ "$#" -lt 2 ] || [ -z "$2" ]; then echo 'Missing device identifier' >&2; exit 2; fi
      DEVICE_ID="$2"; shift 2 ;;
    *) echo 'Usage: bash scripts/build_device.sh [--unsigned | --device DEVICE_ID] [--distribution]' >&2; exit 2 ;;
  esac
done
if $UNSIGNED && [ -n "$DEVICE_ID" ]; then
  echo 'Unsigned preparation does not target or install on a device.' >&2
  exit 2
fi
SIGNING_ARGS=()
DESTINATION='generic/platform=iOS'
if $UNSIGNED; then
  SIGNING_ARGS=(CODE_SIGNING_ALLOWED=NO)
else
  TEAM_ID="$(python3 - <<'PY'
from pathlib import Path
import re
p=Path('ios/Config/Local.xcconfig')
text=p.read_text() if p.exists() else ''
matches=re.findall(r'^\s*DEVELOPMENT_TEAM\s*=\s*([A-Z0-9]{10})\s*(?://[^\n]*)?$',text,re.M)
if len(matches)!=1:
    raise SystemExit('Sign in to Xcode with your Apple Account, then set DEVELOPMENT_TEAM in ios/Config/Local.xcconfig. No paid membership is needed for personal testing.')
print(matches[0])
PY
)"
  SIGNING_ARGS=(-allowProvisioningUpdates -allowProvisioningDeviceRegistration "DEVELOPMENT_TEAM=$TEAM_ID")
  if [ -n "$DEVICE_ID" ]; then DESTINATION="platform=iOS,id=$DEVICE_ID"; fi
fi
python3 scripts/check_export_content.py --platform device
python3 scripts/generate_host.py "${GENERATE_ARGS[@]}"
mkdir -p .local/logs
BUILD_LOG=".local/logs/host-device-$(date +%Y%m%d-%H%M%S).log"
echo "Building device Release; log: $BUILD_LOG"
if ! xcodebuild -workspace ios/StarryNight.xcworkspace -scheme StarryNight \
  -configuration Release -sdk iphoneos -destination "$DESTINATION" \
  -derivedDataPath .local/build/DeviceDerivedData "${SIGNING_ARGS[@]}" \
  build > "$BUILD_LOG" 2>&1; then
  tail -60 "$BUILD_LOG" >&2
  exit 1
fi
echo 'Device build succeeded: .local/build/DeviceDerivedData/Build/Products/Release-iphoneos/StarryNight.app'
if $UNSIGNED; then echo 'Unsigned preparation only. Apple signing is still required before installation.'; fi
