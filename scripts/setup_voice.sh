#!/bin/zsh
set -eu
ROOT="${0:A:h:h}"
cd "$ROOT"
if [[ ! -x .local/voice-venv/bin/python ]]; then uv venv --python 3.11 .local/voice-venv; fi
uv pip sync --python .local/voice-venv/bin/python local-services/voice/requirements.lock
.local/voice-venv/bin/python scripts/prepare_voice.py
scripts/start_voice.sh
