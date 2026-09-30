#!/usr/bin/env python3
"""Build a reviewable import plan from every audited package, including variants.

Selection is explicit in the generated recipe; candidates and unresolved GUIDs
are retained separately. This does not register unconverted avatars in the app.
"""
import argparse
from collections import Counter
import json
from pathlib import Path
import re
from vrchat_batch_audit import dump

PREFERRED = {
    'airi': 'Assets/Kyubi closet/Airi/lilToon_Airi.prefab',
    'kikyo': 'Assets/Kikyo/Prefab/Kikyo_PB.prefab',
    'mizuki': 'Assets/IKUSIA/mizuki/Prefab/liltoon/mizuki.prefab',
    'nemesis': 'Assets/Nemesis/Nemesis_Full.prefab',
    'ramune': 'Assets/EMOLab Avatars/Ramune/Ramune.prefab',
    'shiratsume': 'Assets/HARUNOPUPU/Shiratsume/Prefab/Shiratsume_All.prefab',
    'shizuku': 'Assets/kuromaru9/shizuku/Prefabs/shizuku.prefab',
    'nozomi': 'Assets/Nozomi/Nozomi_1.00.prefab',
    'lasyusha': 'Assets/KeenooSHOP/Lasyusha/Prefabs/Co1/Lasyusha_C1_Ver1.1.prefab',
}
NAMES = {'kipfel':'琪宝','airi':'爱莉','chiffon':'戚风','cornet':'可露','eku':'意可蕾','ichigo':'草莓',
         'karin':'卡琳','kikyo':'桔梗','lime':'青柠','mafuyu':'真冬','maki':'真纪','mao':'真央',
         'mashu':'麻薯','meiyun':'美云','milfy':'米露菲','milltina':'米露缇娜','mizuki':'瑞希',
         'rindo':'龙胆','rurune':'露露奈','shinano':'信浓','koharu':'小春'}


def role_key(folder):
    if folder.startswith('小春'):
        return 'koharu'
    match = re.search(r'[A-Za-z]+', folder)
    if not match:
        raise ValueError('Add an explicit stable ASCII role ID: ' + folder)
    return match[0].lower()


def prefab_score(asset, key):
    name = Path(asset['path']).stem.casefold()
    score = 100 if name == key else 60 if key in name else 0
    for token in ('sotai', '素体', '素體', 'dress-up', 'kisekae', 'kaihen', 'useredit', '改変', 'body', 'base', 'mmd', 'mobile', 'quest', 'none', 'limit', 'facetracking', '2p', 'another', 'poiyomi'):
        if token in asset['path'].casefold():
            score -= 30
    return score


def avatar_prefabs(package):
    """Find avatar roots whose descriptor lives in a nested source prefab.

    Only actual prefab-instance edges count. A menu or controller referring to
    an avatar must not become a candidate. Walk each root with its own visited
    set so malformed cycles cannot recurse forever or hide another live branch.
    Build-time assembly requirements are reviewed separately before activation.
    """
    prefabs = {a['guid']: a for a in package['assets'] if a['extension'] == '.prefab'}
    edges = {}
    for guid, asset in prefabs.items():
        path = asset.get('metadataPath')
        data = Path(path).read_text(errors='replace') if path else ''
        edges[guid] = re.findall(r'm_SourcePrefab:\s*\{[^}]*\bguid:\s*([0-9a-f]{32})', data)
    def has_descriptor(root):
        pending, seen = [root], set()
        while pending:
            guid = pending.pop()
            if guid in seen or guid not in prefabs:
                continue
            seen.add(guid)
            if prefabs[guid].get('inspection', {}).get('descriptors'):
                return True
            pending.extend(edges[guid])
        return False
    return [asset for guid, asset in prefabs.items() if has_descriptor(guid)]


def select_fbx(package, prefab):
    by_guid = {a['guid']: a for a in package['assets']}
    counts, seen = Counter(), set()
    def walk(asset):
        if asset['guid'] in seen:
            return
        seen.add(asset['guid'])
        text = Path(asset['metadataPath']).read_text(errors='replace') if asset.get('metadataPath') else ''
        for guid, count in Counter(re.findall(r'guid: ([0-9a-f]{32})', text)).items():
            target = by_guid.get(guid)
            if not target:
                continue
            if target['extension'] == '.fbx':
                counts[guid] += count
            elif target['extension'] == '.prefab':
                walk(target)
    walk(prefab)
    models = [a for a in package['assets'] if a['extension'] == '.fbx']
    if not models:
        return None
    def score(asset):
        meta = Path(asset['metaPath']).read_text(errors='replace') if asset.get('metaPath') else ''
        return (bool(re.search(r'animationType:\s*3\b', meta)), counts[asset['guid']], asset['bytes'])
    return max(models, key=score)['path']


def build(index_path, output):
    index = json.loads(index_path.read_text())
    models = []
    for source in index['archives']:
        report = json.loads(Path(source['report']).read_text())
        folder = Path(source['source']).parent.name
        key = role_key(folder)
        packages = report.get('inventory', {}).get('packages', [])
        candidates = [(i,a) for i,p in enumerate(packages) for a in avatar_prefabs(p)]
        selected = next(((i,a) for i,a in candidates if a['path'] == PREFERRED.get(key)), None)
        if selected is None and candidates:
            selected = max(candidates, key=lambda pair:prefab_score(pair[1], key))
        images = sorted(p for p in Path(source['source']).parent.iterdir() if p.suffix.lower() in {'.png','.jpg','.jpeg'})
        row = dict(role=key, id='anime-'+key, name=NAMES.get(key,key.capitalize()),
                   sourceFolder=folder, archive=Path(source['source']).name, sourceSHA256=report.get('sha256'),
                   version=(re.search(r'_v([\d.]+)$',folder)[1] if re.search(r'_v([\d.]+)$',folder) else None),
                   coverCandidates=[p.name for p in images], cover=images[0].name if images else None,
                   sourceReport=source['report'],
                   variants=[dict(package=i,prefab=a['path']) for i,a in candidates],
                   status='audit-failed' if source['status'] != 'audited' else 'source-selected' if selected else 'missing-avatar-prefab')
        if selected:
            i, prefab = selected
            row.update(package=i, packageLocation=packages[i]['location'][1:], prefab=prefab['path'],
                       fbx=select_fbx(packages[i],prefab))
        # Scenes remain evidence for which variant the author presents. The
        # full Ramune prefab nests its descriptor inside the base body; the
        # separately supplied Gomenne prefab must not stand in for that root.
        scenes=[dict(package=i,path=a['path']) for i,p in enumerate(packages) for a in p['assets'] if a['extension']=='.unity']
        if scenes:row['scenes']=scenes
        if key == 'kipfel':
            row['upgrade'] = dict(previousVersion='1.0.3', preserveCharacterID=True)
        models.append(row)
    dump(output, dict(schemaVersion=1, sourceRoot=index['sourceRoot'], localOnly=True, models=models))
    return models


if __name__ == '__main__':
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--index',type=Path,default=Path('.local/vrchat-batch/index.json'))
    p.add_argument('--output',type=Path,default=Path('.local/vrchat-batch/plan.json'))
    a=p.parse_args()
    for row in build(a.index,a.output):print(row['role'],row['status'],row.get('prefab',''),row.get('fbx',''))
