#!/usr/bin/env python3
"""Summarize observed player-loop cadence without treating a requested FPS as achieved."""
import json
import sys
from pathlib import Path

source = Path(sys.argv[1])
events = [json.loads(line) for line in source.read_text().splitlines() if line.strip()]
samples = [e for e in events if e['name'] == 'performance']
assert samples, 'No performance measurements'
groups = []
for target in sorted({s['targetFPS'] for s in samples}):
    windows = [s for s in samples if s['targetFPS'] == target]
    frames = sum(s['frameCount'] for s in windows)
    seconds = sum(s['windowSeconds'] for s in windows)
    slow = sum(s['over16_7ms'] for s in windows)
    groups.append(dict(requestedFPS=target, appliedFPS=sorted({s['appliedFPS'] for s in windows}),
        reportedRefreshHz=sorted({s['refreshHz'] for s in windows}), windows=len(windows),
        frames=frames, measuredSeconds=round(seconds,3), averageFPS=round(frames/seconds,2),
        minimumWindowFPS=round(min(s['fps'] for s in windows),2),
        maximumWindowFPS=round(max(s['fps'] for s in windows),2),
        worstWindowP95Ms=round(max(s['p95Ms'] for s in windows),3),
        worstWindowP99Ms=round(max(s['p99Ms'] for s in windows),3),
        worstFrameMs=round(max(s['worstMs'] for s in windows),3),
        framesOver16_7ms=slow, percentOver16_7ms=round(slow/frames*100,2),
        everyMeasuredFrameStrictlyAbove60=(slow == 0)))
report = dict(environment='iPhone 17 / iOS 26.4 Simulator on Apple M3 Pro',
    measurement='Unity player-loop wall-clock intervals; not physical display presentation or GPU timing',
    sampling='Two-second windows; first second after configure/focus/pause excluded; no other slow-frame rejection',
    source=source.name, physicalDevice120FPS='NOT_TESTED', sustainedAbove60Acceptance='NOT_PROVEN',
    resolution=sorted({f"{s['width']}x{s['height']}" for s in samples}), groups=groups)
destination = Path(sys.argv[2]) if len(sys.argv) > 2 else source.with_suffix('.performance.json')
destination.parent.mkdir(parents=True, exist_ok=True)
destination.write_text(json.dumps(report, indent=2)+'\n')
print(json.dumps(report, indent=2))
