#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .local/checks
# Interpret the production envelope and its invariant tests together. This also
# works on development Macs that disallow launching fresh unsigned CLI binaries.
python3 - <<'PY'
from pathlib import Path
core=Path('ios/CharacterHost/Features/Companion/AtmosphereBlend.swift').read_text()
tests=Path('scripts/tests/AtmosphereBlendTests.swift').read_text().replace('@main enum','enum')
Path('.local/checks/AtmosphereBlendChecks.swift').write_text(core+'\n'+tests+'\nAtmosphereBlendTests.main()\n')
PY
swift -module-cache-path .local/build/VoiceModuleCache .local/checks/AtmosphereBlendChecks.swift
