#!/usr/bin/env python3
"""Check positive and negative touch cases against actual Unity bridge events."""
import json
import sys
from pathlib import Path
source=Path(sys.argv[1])
events=[json.loads(line) for line in source.read_text().splitlines() if line.strip()]
assert not any(e['name']=='error' for e in events)
assert [e['modelId'] for e in events if e['name']=='modelSelected']==['hatsune-miku']
hits=[e for e in events if e['name']=='headTapped']
assert len(hits)==1 and hits[0]['modelId']=='hatsune-miku', 'Only the deliberate head tap may trigger'
assert any(e['name']=='actionCompleted' and e.get('action')=='No' for e in events)
assert {e['targetFPS'] for e in events if e['name']=='performance'}=={60,120}
assert any(e['name']=='framingConfigured' for e in events)
assert all(160 <= e['yaw'] <= 200 for e in events if e['name']=='state')
result={'status':'PASS','headPositiveHits':1,'backgroundBodyAndDragNegativeCases':'PASS','requestedFrameTargets':[60,120]}
source.with_suffix('.verification.json').write_text(json.dumps(result,indent=2)+'\n')
print(json.dumps(result,indent=2))
