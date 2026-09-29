#!/usr/bin/env python3
"""Measure the first real panel opening, not just whether the camera avoided Snap."""
import argparse
import json
import math
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('samples', type=Path)
parser.add_argument('--output', type=Path, required=True)
args = parser.parse_args()
rows = [json.loads(line) for line in args.samples.read_text().splitlines() if line.strip()]
start = next(i for i, row in enumerate(rows) if row['compositionArea']['height'] < .9)
assert start > 0
origin = rows[start-1]
target = rows[start]['framingDistanceTarget']
delta = math.log(target/origin['distance'])
assert delta > .1, 'Opening must exercise a visible zoom-out'
window = []
for row in rows[start:]:
    if abs(math.log(row['framingDistanceTarget']/target)) > .002:
        break
    window.append((row['sampleTime']-origin['sampleTime'],math.log(row['distance']/origin['distance'])/delta))
assert window[-1][0] > 1.2, 'Capture must include the main travel and rebound'
quarter = min(window,key=lambda pair:abs(pair[0]-.25))
reached95 = next(time for time, progress in window if progress >= .95)
peak = max(progress for _, progress in window)
assert .15 < quarter[1] < .50, ('Opening rushes / stalls during the first quarter-second',quarter)
assert .65 < reached95 < 1.05, ('Main travel must be visibly gradual',reached95)
assert 1.01 < peak < 1.04, ('Expected one modest rebound',peak)
report = {'result':'passed','quarterSecondSampleTime':quarter[0],
          'quarterSecondProgress':quarter[1],'timeTo95Percent':reached95,
          'maximumProgress':peak,'layoutMotionRevision':rows[start]['layoutMotionRevision'],
          'note':'Measured Unity log-distance trajectory in simulator; not physical-device FPS.'}
args.output.write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
print(json.dumps(report,ensure_ascii=False))
