#!/bin/bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"
mkdir -p .local/logs
python3 scripts/generate_host.py --platform simulator
xcodebuild -workspace ios/CharacterPrototype.xcworkspace -scheme CharacterHost \
  -configuration Debug -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath .local/build/DerivedData CODE_SIGNING_ALLOWED=NO \
  build > .local/logs/host-simulator-build.log 2>&1
echo 'Host build succeeded: .local/build/DerivedData/Build/Products/Debug-iphonesimulator/CharacterHost.app'
