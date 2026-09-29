#!/usr/bin/env python3
"""Inspect real simulator data after XCTest, excluding user production data."""
import argparse,json,pathlib,subprocess
p=argparse.ArgumentParser();p.add_argument('--device',default='99F5FAC6-A73A-4C59-A723-D57D648B342E');args=p.parse_args()
container=pathlib.Path(subprocess.check_output(['xcrun','simctl','get_app_container',args.device,'com.modelspace.viewer','data'],text=True).strip())
data=json.loads((container/'Library/Application Support/companion-test.json').read_text())
luma=data['characters']['studio-robot']
assert luma['profile']['name']=='小屿'
assert any('海边' in item['text'] for item in luma['memories'])
assert any('海边' in item['text'] and item['role']=='assistant' for item in luma['messages'])
assert len(luma['messages'])>=4
result={'status':'PASS','source':'actual simulator companion-test.json','profilePersisted':True,'explicitMemoryPersisted':True,'assistantUsedMemory':True,'messageCount':len(luma['messages']),'productionDataInspected':False}
pathlib.Path('docs/verification/companion/persistence.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n')
print(json.dumps(result))
