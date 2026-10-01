#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .local/checks/voice-capture
if [ "${1:-}" = '--interpret' ]; then
  # Same production state and assertions, run by the Swift interpreter when a
  # host cannot launch freshly linked command-line binaries. No alternate model.
  python3 - <<'PY'
from pathlib import Path
core=Path('ios/CharacterHost/Features/Companion/VoiceCaptureState.swift').read_text()
tests=Path('scripts/tests/VoiceCaptureStateTests.swift').read_text().replace('@main enum VoiceCaptureStateTests','enum VoiceCaptureStateTests')
Path('.local/checks/voice-capture/InterpretedVoiceCaptureTests.swift').write_text(core+'\n'+tests+'\nVoiceCaptureStateTests.main()\n')
PY
  swift -module-cache-path .local/build/VoiceModuleCache .local/checks/voice-capture/InterpretedVoiceCaptureTests.swift
  exit 0
fi
swiftc -swift-version 6 -parse-as-library -module-cache-path .local/build/VoiceModuleCache \
  ios/CharacterHost/Features/Companion/VoiceCaptureState.swift \
  scripts/tests/VoiceCaptureStateTests.swift -o .local/checks/voice-capture/voice-capture-tests
.local/checks/voice-capture/voice-capture-tests
