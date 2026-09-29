#!/usr/bin/env python3
"""Verify real Unity samples while opening panels without changing camera controls."""
import argparse
import json
import math
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('samples', type=Path)
parser.add_argument('--output', type=Path, required=True)
args = parser.parse_args()
rows = [json.loads(line) for line in args.samples.read_text().splitlines() if line.strip()]
assert len(rows) > 200, 'Insufficient actual rendered camera samples'
assert len({row['presentationId'] for row in rows}) == 1, 'Expected one retained conversation'
fields = ['distance', 'framingSize', 'framingAngle', 'pitch', 'yaw', 'cameraFov', 'cameraAspect', 'cameraSnapCount']
fields += ['cameraPosition.' + axis for axis in ('x', 'y', 'z')]
fields += [name + '.' + axis for name in ('compositionArea', 'renderViewport') for axis in ('x', 'y', 'width', 'height')]

def value(row, field):
    for key in field.split('.'):
        row = row[key]
    return float(row)

spreads = {}
for field in fields:
    values = [value(row, field) for row in rows]
    assert all(math.isfinite(v) for v in values), field
    spreads[field] = max(values) - min(values)
    assert spreads[field] < 0.0001, (field, spreads[field])
assert len({row['framingShot'] for row in rows}) == 1, 'Automatic shot change'
assert not any(row['framingMotionActive'] for row in rows), 'Unexpected camera animation'
assert all(b['sampleTime'] > a['sampleTime'] for a, b in zip(rows, rows[1:])), 'Non-monotonic samples'
result = {'result': 'passed', 'samples': len(rows), 'sampledSeconds': rows[-1]['sampleTime'] - rows[0]['sampleTime'],
          'movingCameraSamples': 0, 'maximumSpreads': spreads,
          'note': 'Covers actual transition frames, not only before/after screenshots; simulator evidence, not device FPS.'}
args.output.parent.mkdir(parents=True, exist_ok=True)
args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n')
print(json.dumps(result, ensure_ascii=False))
