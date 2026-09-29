#!/bin/zsh
set -eu
ROOT="${0:A:h:h}"
cd "$ROOT"
mkdir -p .local/logs
if curl -fsS --noproxy '*' --max-time 2 http://127.0.0.1:18765/health 2>/dev/null | .local/voice-venv/bin/python -c 'import json,sys;v=json.load(sys.stdin);sys.exit(0 if v.get("ready") and v.get("asr")=="SenseVoiceSmall int8" else 1)' 2>/dev/null; then
  print 'Xuyu speech service is available at 127.0.0.1:18765'; exit 0
fi
if [[ ! -x .local/voice-venv/bin/python || ! -f .local/voice-models/melo/model.onnx ]]; then
  print 'Run scripts/setup_voice.sh first.'; exit 1
fi
python3 scripts/install_voice_agent.py
SERVICE="gui/$(id -u)/com.xuyu.local-voice"
RUNTIME="$HOME/Library/Application Support/Xuyu/Voice"
if launchctl print "$SERVICE" >/dev/null 2>&1; then launchctl bootout "$SERVICE"; fi
# bootout returns before the old registration is always fully reaped.
for attempt in {1..5}; do
  if launchctl bootstrap "gui/$(id -u)" "$RUNTIME/launch-agent.plist"; then break; fi
  if (( attempt == 5 )); then exit 1; fi
  sleep 1
done
for attempt in {1..60}; do
  if curl -fsS --noproxy '*' --max-time 2 http://127.0.0.1:18765/health 2>/dev/null; then exit 0; fi
  sleep 1
done
print "Speech service did not become ready. See $RUNTIME/logs/server.log"; exit 1
