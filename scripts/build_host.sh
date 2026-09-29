#!/bin/bash
set -euo pipefail
BUILD_CONFIGURATION=Debug
case "${1:-}" in
  --release) BUILD_CONFIGURATION=Release ;;
  --debug|'') ;;
  *) echo 'Usage: build_host.sh [--debug|--release]' >&2; exit 2 ;;
esac
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"
mkdir -p .local/logs
python3 scripts/check_export_content.py --platform simulator
python3 scripts/generate_host.py --platform simulator
xcodebuild -workspace ios/StarryNight-Simulator.xcworkspace -scheme CharacterHost \
  -configuration "$BUILD_CONFIGURATION" -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath .local/build/DerivedData CODE_SIGNING_ALLOWED=NO \
  build > .local/logs/host-simulator-build.log 2>&1
echo "Host build succeeded: .local/build/DerivedData/Build/Products/$BUILD_CONFIGURATION-iphonesimulator/CharacterHost.app"
