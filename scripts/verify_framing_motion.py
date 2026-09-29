#!/usr/bin/env python3
"""Verify action camera continuity from real Unity events, not slow UI polling."""
import argparse
import json
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('events', type=Path)
parser.add_argument('--output', type=Path, required=True)
args = parser.parse_args()
events = [json.loads(line) for line in args.events.read_text().splitlines() if line.strip()]
results = []
for model in ['real-woman', 'studio-robot', 'hatsune-miku']:
    rows = [e for e in events if e.get('modelId') == model]
    starts = [e for e in rows if e.get('name') == 'actionStarted' and e.get('source') == 'button']
    assert len(starts) == 3, (model, 'expected three consecutive button actions', len(starts))
    first_index = rows.index(starts[0])
    before = next(e for e in reversed(rows[:first_index]) if e.get('name') == 'state' and not e.get('framingMotionActive'))
    initial_distance = before['distance']
    assert starts[0]['framingMotionRevision'] == 1
    assert starts[0]['framingMotionActive']
    assert abs(starts[0]['distance']-initial_distance) < initial_distance*.001, (model, 'teleported on action start')
    assert starts[0]['framingDistanceTarget'] > initial_distance
    assert abs(starts[1]['framingZoomVelocity']) > .001, (model, 'second action did not interrupt moving camera')
    completions = [e for e in rows if e.get('name') == 'actionCompleted' and e.get('source') == 'button']
    assert len(completions) == 1 and completions[0]['action'] == starts[-1]['action'], (model, 'cancelled action completed late')
    completed = completions[0]
    target = starts[-1]['framingDistanceTarget']
    assert abs(completed['distance']-target) < target*.003, (model, 'action view did not converge')
    assert completed['framingMotionActive'], (model, 'recovery should ease from current pose')
    after = next(e for e in rows[rows.index(completed)+1:] if e.get('name') == 'state' and not e.get('actionFraming') and not e.get('framingMotionActive'))
    assert abs(after['distance']-initial_distance) < initial_distance*.001, (model, 'did not restore original view')
    assert (after['framingShot'],after['framingSize'],after['framingAngle']) == (before['framingShot'],before['framingSize'],before['framingAngle'])
    results.append({'model':model, 'actions':[e['action'] for e in starts], 'initialDistance':initial_distance,
                    'startDistance':starts[0]['distance'], 'interruptedZoomVelocity':starts[1]['framingZoomVelocity'],
                    'actionTargetDistance':target, 'completedDistance':completed['distance'], 'restoredDistance':after['distance']})
args.output.parent.mkdir(parents=True, exist_ok=True)
args.output.write_text(json.dumps({'result':'passed','models':results}, ensure_ascii=False, indent=2)+'\n')
print('Three-character motion continuity, interrupted actions and restoration passed.')
