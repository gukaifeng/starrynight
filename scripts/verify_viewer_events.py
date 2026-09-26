#!/usr/bin/env python3
"""Validate engine evidence from the final complete-flow XCTest run."""
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
events = [json.loads(line) for line in path.read_text().splitlines() if line.strip()]
assert all(e['schemaVersion'] == 1 and e['kind'] == 'event' for e in events)
assert not [e for e in events if e['name'] == 'error'], 'Engine reported an error'
ready = [e for e in events if e['name'] == 'sceneReady']
assert len(ready) == 1, 'Repeated viewing must reuse a single initialized scene'
states = [e for e in events if e['name'] == 'state' and e['presentationId'] == 1]
assert len(states) >= 2, 'Both real gestures must report settled camera state'
normal = ready[0]['defaultDistance']
rotated = next((e for e in states if abs(e['yaw'] - 155) > 20 and abs(e['distance'] - normal) < .02), None)
assert rotated, 'Single-finger drag must rotate without changing distance'
zoomed = next((e for e in states if e['distance'] < normal * .9), None)
assert zoomed, 'Two-finger pinch must move the camera closer'
resets = [e for e in events if e['name'] == 'viewReset']
assert len([e for e in resets if e['presentationId'] == 1]) >= 2, 'Manual reset acknowledgement is missing'
assert set(range(1,23)).issubset({e['presentationId'] for e in resets}), '20 re-entries must all reset'
for event in resets:
    assert abs(event['yaw'] - 155) < .02 and abs(event['pitch'] - 12) < .02
    assert abs(event['distance'] - event['defaultDistance']) < .02
started = [e for e in events if e['name'] == 'actionStarted']
completed = [e for e in events if e['name'] == 'actionCompleted']
for action in ['Wave','Jump','Dance','No']:
    assert any(e['action'] == action for e in started), f'{action} never started'
    assert any(e['action'] == action for e in completed), f'{action} never completed'
head_hits = [e for e in events if e['name'] == 'headTapped']
assert len(head_hits) == 1, 'Only the deliberate head tap may trigger a shake; body, background and drag must not'
assert any(e['action'] == 'No' and e['source'] == 'head' for e in started)
assert any(e['action'] == 'Dance' and e['presentationId'] == 22 for e in completed), 'Animation must recover after backgrounding'
performance = [e for e in events if e['name'] == 'performance']
assert {60,120}.issubset({e['targetFPS'] for e in performance}), 'Both render targets must produce measured samples'
assert all(e['fps'] > 0 and e['frameCount'] > 0 and e['p99Ms'] >= e['p95Ms'] > 0 for e in performance)
assert all(e['width'] == 1206 and e['height'] == 2622 for e in performance), 'iPhone 17 must retain native rendering resolution'
summary = dict(status='PASS', sceneReadyCount=len(ready), verifiedPresentations=22,
    initialDistance=normal, rotatedYaw=rotated['yaw'], rotatedPitch=rotated['pitch'],
    zoomedDistance=zoomed['distance'], resetCount=len(resets), eventCount=len(events),
    actionsVerified=['Wave','Jump','Dance','No'], headHitCount=len(head_hits),
    performanceWindows=len(performance), renderTargetsVerified=[60,120])
output = path.with_suffix('.verification.json')
output.write_text(json.dumps(summary,indent=2)+'\n')
print(json.dumps(summary,indent=2))
