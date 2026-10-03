"""Make small build thumbnails of existing avatars; never generate new artwork."""
import hashlib
import json
from pathlib import Path
import shutil
import subprocess

def stage_island_avatars(root:Path)->Path:
    destination=root/'.local/island-resources/IslandAvatars.xcassets'
    destination.mkdir(parents=True,exist_ok=True)
    (destination/'Contents.json').write_text(json.dumps({'info':{'author':'xcode','version':1}}))
    catalog=json.loads((root/'ios/CharacterHost/Resources/CharacterCatalog.json').read_text())['characters']
    for role in catalog:
        name='Avatar_'+role['id'].replace('-','_')
        source=root/'ios/CharacterHost/Assets.xcassets'/f'{name}.imageset'
        if not source.exists():continue
        images=json.loads((source/'Contents.json').read_text())['images']
        filename=next((i['filename'] for i in images if i.get('filename')),None)
        if not filename:continue
        original=source/filename
        target=destination/f'{name}.imageset';target.mkdir(exist_ok=True)
        digest=hashlib.sha256(original.read_bytes()).hexdigest()
        receipt=target/'source.sha256'
        if not receipt.exists() or receipt.read_text()!=digest or not (target/'avatar.png').exists():
            shutil.copy2(original,target/'avatar.png')
            subprocess.run(['sips','--resampleHeightWidthMax','96',str(target/'avatar.png')],check=True,stdout=subprocess.DEVNULL)
            receipt.write_text(digest)
        (target/'Contents.json').write_text(json.dumps({'images':[{'filename':'avatar.png','idiom':'universal','scale':'3x'}],
            'info':{'author':'xcode','version':1}}))
    return destination
