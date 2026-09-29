#!/usr/bin/env python3
"""Check actual runtime gaze samples, including the turn's unreachable rear arc."""
import argparse
import json
import math
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument('capture', type=Path)
parser.add_argument('--output', type=Path)
args = parser.parse_args()
rows = [json.loads(line) for line in args.capture.read_text().splitlines() if line.strip()]
assert len(rows) > 300, 'Missing continuous runtime capture'
steady_since = None
last_model = None
contacts = []
rear = []
bow = []
for row in rows:
    g = row['gaze']
    assert g['revision'] == 1 and g['available'], 'Gaze rig missing'
    assert all(math.isfinite(g[k]) for k in ('headYaw', 'headPitch', 'eyeYaw', 'eyePitch', 'eyeError'))
    assert abs(g['headYaw']) <= 50.02 and -28.02 <= g['headPitch'] <= 22.02
    assert abs(g['eyeYaw']) <= 12.02 and -10.02 <= g['eyePitch'] <= 8.02
    assert 0 <= g['weight'] <= 1
    action = g.get('action', '')
    model = row['modelId']
    time = row['sampleTime']
    stable = not row['framingMotionActive'] and not action and model == last_model
    if not stable:
        steady_since = None
    elif steady_since is None:
        steady_since = time
    if (steady_since is not None and time-steady_since > .8 and g['independentEyes']
            and abs(g['targetYaw']) < 35 and abs(g['targetPitch']) < 20):
        contacts.append(g['eyeError'])
        assert g['eyeError'] < 1.5, f'Lost eye contact in settled framing: {g}'
    if action == 'Spin' and abs(g['targetYaw']) >= 120:
        rear.append(g)
        assert g['weight'] == 0, 'Rear target must release gaze'
    if action == 'Bow':
        bow.append(g)
        assert g['weight'] == 0, 'Bow must retain its authored downcast look'
    last_model = model
assert len(contacts) > 20, 'No settled eye-contact evidence'
assert len(rear) > 5 and len(bow) > 20, 'Missing full spin/bow evidence'
report = dict(status='PASS', samples=len(rows), settledContactSamples=len(contacts),
              maxSettledEyeErrorDegrees=max(contacts), rearSpinSamples=len(rear), bowSamples=len(bow),
              maxHeadYawDegrees=max(abs(r['gaze']['headYaw']) for r in rows),
              minHeadPitchDegrees=min(r['gaze']['headPitch'] for r in rows),
              maxHeadPitchDegrees=max(r['gaze']['headPitch'] for r in rows))
if args.output:
    args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2)+'\n')
print(json.dumps(report, ensure_ascii=False, indent=2))
