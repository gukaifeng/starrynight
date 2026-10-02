#!/bin/bash
# Explicit device selection avoids installing to the wrong phone or iPad.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"
if [ "$#" -lt 1 ] || [ "$#" -gt 2 ] || [ -z "$1" ]; then
  echo 'Usage: bash scripts/run_device.sh DEVICE_UDID [--shell-discover]' >&2
  echo 'Connect and trust the device, enable Developer Mode, and list devices with xcrun devicectl list devices.' >&2
  exit 2
fi
DEVICE_ID="$1"
LAUNCH_ARGS=()
if [ "$#" -eq 2 ]; then
  case "$2" in
    --shell-discover) LAUNCH_ARGS=("$2");;
    *) echo "Unknown launch mode: $2" >&2; exit 2;;
  esac
fi
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
xcrun devicectl device process launch --device "$DEVICE_ID" --terminate-existing \
  --json-output ".local/checks/device-launch-$INSTALL_STAMP.json" -- "$BUNDLE_ID" ${LAUNCH_ARGS[@]+"${LAUNCH_ARGS[@]}"}
