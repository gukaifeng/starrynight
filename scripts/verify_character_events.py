#!/usr/bin/env python3
"""Validate real bridge evidence from the multi-character XCTest (never synthetic FPS)."""
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
events = [json.loads(line) for line in path.read_text().splitlines() if line.strip()]
assert events and all(e.get('schemaVersion') == 1 and e.get('kind') == 'event' for e in events)
assert not any(e['name'] == 'error' for e in events), 'Runtime reported an error'
assert sum(e['name'] == 'sceneReady' for e in events) == 1, 'Switches must reuse the same engine'
selected = [e for e in events if e['name'] == 'modelSelected']
assert [(e['presentationId'], e['modelId']) for e in selected] == [(1,'studio-robot'),(2,'hatsune-miku'),(3,'studio-robot')]
for event in events:
    if event['name'] in {'actionStarted','actionCompleted','headTapped','performance','modelSelected'}:
        expected = 'hatsune-miku' if event['presentationId'] == 2 else 'studio-robot'
        assert event['modelId'] == expected, 'Old rig or FPS data leaked into a different presentation'
for action in ['Wave','Jump','Dance','Bow','Spin','Greet','Cheer']:
    for name in ['actionStarted','actionCompleted']:
        assert any(e['name'] == name and e['modelId'] == 'hatsune-miku' and e['action'] == action for e in events), (action, name)
assert any(e['name'] == 'actionCompleted' and e['presentationId'] == 3 and e['action'] == 'Wave' for e in events)
samples = [e for e in events if e['name'] == 'performance' and e['modelId'] == 'hatsune-miku']
assert samples and all(e['fps'] > 0 and e['frameCount'] > 0 for e in samples), 'Miku must produce actual timing windows'
summary = {'status':'PASS','models':['studio-robot','hatsune-miku'],'presentations':3,'mikuButtonActions':7,
           'mikuPerformanceWindows':len(samples),'physical120FPS':'NOT_TESTED','mikuHeadInteraction':'NOT_COVERED_BY_THIS_TEST'}
path.with_suffix('.verification.json').write_text(json.dumps(summary,indent=2)+'\n')
print(json.dumps(summary,indent=2))
