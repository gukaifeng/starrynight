#!/usr/bin/env python3
"""Summarize observed player-loop cadence without treating a requested FPS as achieved."""
import json
import argparse
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument('source',type=Path)
parser.add_argument('destination',nargs='?',type=Path)
parser.add_argument('--environment',default='NOT_RECORDED')
parser.add_argument('--device-kind',choices=['simulator','physical','editor','unknown'],default='unknown')
args = parser.parse_args()
source = args.source
events = [json.loads(line) for line in source.read_text().splitlines() if line.strip()]
samples = [e for e in events if e['name'] == 'performance']
assert samples, 'No performance measurements'
groups = []
for model,target in sorted({(s.get('modelId','legacy-unlabeled'),s['targetFPS']) for s in samples}):
    windows = [s for s in samples if s['targetFPS'] == target and s.get('modelId','legacy-unlabeled') == model]
    frames = sum(s['frameCount'] for s in windows)
    seconds = sum(s['windowSeconds'] for s in windows)
    slow = sum(s['over16_7ms'] for s in windows)
    groups.append(dict(modelId=model, requestedFPS=target, appliedFPS=sorted({s['appliedFPS'] for s in windows}),
        reportedRefreshHz=sorted({s['refreshHz'] for s in windows}), windows=len(windows),
        frames=frames, measuredSeconds=round(seconds,3), averageFPS=round(frames/seconds,2),
        minimumWindowFPS=round(min(s['fps'] for s in windows),2),
        maximumWindowFPS=round(max(s['fps'] for s in windows),2),
        worstWindowP95Ms=round(max(s['p95Ms'] for s in windows),3),
        worstWindowP99Ms=round(max(s['p99Ms'] for s in windows),3),
        worstFrameMs=round(max(s['worstMs'] for s in windows),3),
        framesOver16_7ms=slow, percentOver16_7ms=round(slow/frames*100,2),
        everyMeasuredFrameStrictlyAbove60=(max(s['worstMs'] for s in windows) < 1000.0/60)))
physical_status = ('PLAYER_LOOP_MEASURED_DISPLAY_PRESENTATION_NOT_MEASURED'
    if args.device_kind == 'physical' and any(g['requestedFPS'] == 120 for g in groups) else 'NOT_TESTED')
report = dict(environment=args.environment, deviceKind=args.device_kind,
    measurement='Unity player-loop wall-clock intervals; not physical display presentation or GPU timing',
    sampling='Two-second windows; first second after configure/focus/pause excluded; no other slow-frame rejection',
    source=source.name, physicalDevice120FPS=physical_status, sustainedAbove60Acceptance='NO_UNCONDITIONAL_GUARANTEE',
    resolution=sorted({f"{s['width']}x{s['height']}" for s in samples}), groups=groups)
destination = args.destination or source.with_suffix('.performance.json')
destination.parent.mkdir(parents=True, exist_ok=True)
destination.write_text(json.dumps(report, indent=2)+'\n')
print(json.dumps(report, indent=2))
