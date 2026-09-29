#!/usr/bin/env python3
"""Check actual Unity camera samples from the explicit interface-motion UI review."""
import argparse
import json
import math
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('samples', type=Path)
parser.add_argument('--output', required=True, type=Path)
args = parser.parse_args()
rows = [json.loads(line) for line in args.samples.read_text().splitlines() if line.strip()]
assert len(rows) > 200, 'Insufficient actual camera samples'
assert len({r['presentationId'] for r in rows}) == 1, 'Review one presentation at a time'
assert len({r['cameraSnapCount'] for r in rows}) == 1, 'Live camera was snapped during the review'
assert sum(r['framingMotionActive'] for r in rows) > 60, 'Review did not exercise moving transitions'
for row in rows:
    rect = row['renderViewport']
    assert tuple(rect[k] for k in ('x','y','width','height')) == (0,0,1,1), 'Rendered viewport changed'
    assert row['cameraFov'] == rows[0]['cameraFov'], 'Projection FOV changed instantly'
    assert row['layoutMotionRevision'] in (1, 2)
    assert math.isfinite(row['distance']) and row['distance'] > 0
speeds = []
steps = []
for previous, current in zip(rows, rows[1:]):
    dt = current['sampleTime']-previous['sampleTime']
    assert dt > 0, 'Sample times must advance'
    change = abs(math.log(current['distance']/previous['distance']))
    speeds.append(change/dt)
    if dt <= .05: steps.append(change)
# A discontinuous multi-fold jump in one frame exceeds this generous camera speed bound.
# It complements (does not replace) the exact spring/retarget checks and visual review.
assert max(speeds) < 8, ('Camera zoom discontinuity', max(speeds))
report = {'result':'passed','samples':len(rows),
          'movingSamples':sum(r['framingMotionActive'] for r in rows),
          'renderViewport':'full screen throughout','fov':rows[0]['cameraFov'],
          'cameraSnapCount':rows[0]['cameraSnapCount'],'additionalCameraSnaps':0,
          'maximumSampledLogZoomSpeed':max(speeds),
          'maximumLogDistanceChangeForIntervalsUpTo50ms':max(steps),
          'aspectRatios':sorted(set(round(r['cameraAspect'],4) for r in rows)),
          'note':'Simulator trajectory evidence; no physical-device FPS assertion.'}
args.output.parent.mkdir(parents=True,exist_ok=True)
args.output.write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
print(json.dumps(report,ensure_ascii=False))
