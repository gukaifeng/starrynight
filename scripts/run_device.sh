#!/bin/bash
# Explicit device selection avoids installing to the wrong phone or iPad.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"
if [ "$#" -ne 1 ] || [ -z "$1" ]; then
  echo 'Usage: bash scripts/run_device.sh DEVICE_UDID' >&2
  echo 'Connect and trust the device, enable Developer Mode, and list devices with xcrun devicectl list devices.' >&2
  exit 2
fi
DEVICE_ID="$1"
bash scripts/build_device.sh --device "$DEVICE_ID"
APP_PATH="$ROOT_DIR/.local/build/DeviceDerivedData/Build/Products/Release-iphoneos/CharacterHost.app"
codesign --verify --deep --strict "$APP_PATH"
if [ ! -f "$APP_PATH/embedded.mobileprovision" ]; then
  echo 'No provisioning profile in app; refusing installation of an unsigned build.' >&2
  exit 1
fi
BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP_PATH/Info.plist")"
mkdir -p .local/checks
INSTALL_STAMP="$(date +%Y%m%d-%H%M%S)"
xcrun devicectl device install app --device "$DEVICE_ID" "$APP_PATH" \
  --json-output ".local/checks/device-install-$INSTALL_STAMP.json"
xcrun devicectl device process launch --device "$DEVICE_ID" --terminate-existing "$BUNDLE_ID" \
  --json-output ".local/checks/device-launch-$INSTALL_STAMP.json"
