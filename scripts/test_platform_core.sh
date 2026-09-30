#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .local/checks/platform-core .local/build/PlatformCoreCache
swiftc -swift-version 6 -parse-as-library -module-cache-path .local/build/PlatformCoreCache \
  ios/CharacterHost/Features/Account/PlatformAPI.swift \
  ios/CharacterHost/Features/Account/AccountSyncMerge.swift \
  scripts/tests/PlatformSyncTests.swift -o .local/checks/platform-core/platform-tests
.local/checks/platform-core/platform-tests
