#!/usr/bin/env python3
"""Resolve serialized physics references using isolated Unity inspection IDs.

Reads source YAML and the parent's data-only Unity transform export. Does not load
SDKs, run source scripts or change runtime. No bone-name guess is used for fileIDs.
"""
import argparse
from copy import deepcopy
import json
from pathlib import Path
import re

from audit_vrchat_archives import ROOT, field, inline_reference, scalar, text_file, unity_blocks
from vrchat_source_paths import resolve_source_path


def parsed_value(value):
    if value is None: return None
    if value.startswith('{') and re.search(r'\b[xyzw]:', value):
        return {key: float(number) for key, number in re.findall(r'([xyzw]):\s*([-+\deE.]+)', value)}
    return scalar(value)


def curve_data(text):
    keys = []
    for block in re.split(r'^\s+- serializedVersion: \d+\s*$', text, flags=re.M)[1:]:
        key = {name: parsed_value(match[1]) for name in ('time','value','inSlope','outSlope','weightedMode','inWeight','outWeight')
               if (match := re.search(r'^\s+' + name + r': ([^\n]+)$', block, re.M))}
        if 'time' in key and 'value' in key: keys.append(key)
    return {'keys': keys, 'preInfinity': scalar(field(text, 'm_PreInfinity', 4) or '2'),
            'postInfinity': scalar(field(text, 'm_PostInfinity', 4) or '2')}


class PhysicsResolver:
    def __init__(self, assets, inspection, fbx_inspection):
        self.assets = {a['guid']: a for a in assets}
        self.main = next(a for a in assets if a['path'] == inspection['prefab'])
        self.nodes = {n['path']: n for n in inspection['nodes']}
        self.ids = {(n['sourceGUID'], n['sourceID']): n['path'] for n in inspection['nodes']}
        self.fbx_ids = {(n['sourceGUID'], n['sourceID']): n['path'] for n in fbx_inspection['nodes']}
        self.source_transforms = {}; self.source_objects = {}
        for node in inspection['nodes']:
            for source in node.get('sources', []):
                self.source_transforms.setdefault((source['guid'],source['transformID']),set()).add(node['path'])
                if source.get('gameObjectID'):
                    self.source_objects.setdefault((source['guid'],source['gameObjectID']),set()).add(node['path'])
        self.occurrences = []
        self.unresolved = []
        self.collect(self.main, '', [])

    def source_path(self, guid, file_id, prefix, objects=False):
        table=self.source_objects if objects else self.source_transforms
        paths=table.get((guid,file_id),set())
        matches={p for p in paths if not prefix or p==prefix or p.startswith(prefix+'/')}
        return next(iter(matches)) if len(matches)==1 else None

    def own_transform_path(self, occurrence, file_id, seen=None):
        guid, prefix, asset = occurrence['guid'], occurrence['prefix'], occurrence['asset']
        resolved=self.source_path(guid,file_id,prefix)
        if resolved is not None:return resolved
        if (guid, file_id) in self.ids: return self.ids[(guid, file_id)]
        if (guid, file_id) in self.fbx_ids: return self.fbx_ids[(guid, file_id)]
        seen = set() if seen is None else seen
        if file_id in seen: return None
        seen.add(file_id)
        prefab = asset['prefab']
        transforms = {t['fileID']: t for t in prefab['transforms']}
        transform = transforms.get(file_id)
        if transform:
            parent_id = transform['parent'].get('fileID', 0)
            if not parent_id: return prefix
            parent_path = self.own_transform_path(occurrence, parent_id, seen)
            if parent_path is not None:
                name = transform['gameObject'].get('localName')
                if name: return '/'.join(part for part in (parent_path, name) if part)
        stripped = next((s for s in prefab['strippedSourceObjects'] if s['fileID'] == file_id), None)
        if stripped:
            source = stripped['source']
            identity = (source.get('guid'), source.get('fileID'))
            if identity in self.fbx_ids: return self.fbx_ids[identity]
            if identity in self.ids: return self.ids[identity]
        return None

    def component_owner_path(self, occurrence, component):
        go_id = component['gameObject'].get('fileID')
        resolved=self.source_path(occurrence['guid'],go_id,occurrence['prefix'],objects=True)
        if resolved is not None:return resolved
        transforms = [t for t in occurrence['asset']['prefab']['transforms'] if t['gameObject'].get('fileID') == go_id]
        if len(transforms) == 1: return self.own_transform_path(occurrence, transforms[0]['fileID'])
        # A stripped GameObject can be any bone, not just the avatar root.
        # Match the exact source identity from Unity's full prefab ancestry.
        stripped = [s for s in occurrence['asset']['prefab']['strippedSourceObjects'] if s['fileID'] == go_id and s['classID'] == 1]
        if len(stripped) == 1:
            ref=stripped[0]['source']
            return self.source_path(ref.get('guid'),ref.get('fileID'),occurrence['prefix'],objects=True)
        return None

    def nested_prefix(self, occurrence, instance, child):
        if not instance.get('transformParent',{}).get('fileID'):
            prefix=occurrence['prefix']
            if any(guid==child['guid'] and prefix in paths for (guid,_),paths in self.source_transforms.items()):
                return prefix
        # A prefab variant inherits its source root at the same location.
        # Resolve the child's serialized root identity before name/path fallback.
        roots=[t for t in child['prefab']['transforms'] if not t['parent'].get('fileID')]
        for root in roots:
            resolved=self.source_path(child['guid'],root['fileID'],occurrence['prefix'])
            if resolved is not None:return resolved
        for inner in child['prefab']['strippedSourceObjects']:
            if inner['classID']!=4:continue
            resolved=self.source_path(child['guid'],inner['fileID'],occurrence['prefix'])
            if resolved==occurrence['prefix']:return resolved
        candidates = []
        for stripped in occurrence['asset']['prefab']['strippedSourceObjects']:
            if stripped['classID'] != 4 or stripped['prefabInstance'].get('fileID') != instance['fileID']: continue
            path = self.own_transform_path(occurrence, stripped['fileID'])
            if path is not None: candidates.append(path)
        if candidates:
            parts = [p.split('/') for p in candidates]
            shared = []
            for position in zip(*parts):
                if len(set(position)) != 1: break
                shared.append(position[0])
            prefix = '/'.join(shared)
            if prefix in self.nodes: return prefix
        # When a nested instance exists only in another source prefab, match
        # its serialized root GameObject name under its resolved parent. This
        # is exact parent+name lookup and must be unique in the exported tree.
        parent = self.own_transform_path(occurrence, instance['transformParent'].get('fileID', 0))
        if parent is None and not instance['transformParent'].get('fileID'): parent = occurrence['prefix']
        names = [g['name'] for g in child['prefab']['gameObjectDefaults']
                 if any(t['gameObject'].get('fileID') == g['fileID'] and not t['parent'].get('fileID') for t in child['prefab']['transforms'])]
        for inner in child['prefab']['prefabInstances']:
            names += [o['value'] for o in inner['overrides'] if o['propertyPath'] == 'm_Name' and isinstance(o['value'], str)]
        matches = {('/'.join(p for p in (parent, name) if p)) for name in names} & set(self.nodes) if parent is not None else set()
        if len(matches) == 1: return matches.pop()
        return None

    def collect(self, asset, prefix, outer_overrides):
        if len(self.occurrences) > 128: raise ValueError('Excessive nested prefab graph')
        occurrence = {'guid': asset['guid'], 'prefix': prefix, 'asset': asset, 'overrides': outer_overrides}
        self.occurrences.append(occurrence)
        for instance in asset['prefab']['prefabInstances']:
            child = self.assets.get(instance['source'].get('guid'))
            if not child or 'prefab' not in child: continue
            nested = self.nested_prefix(occurrence, instance, child)
            if nested is None:
                self.unresolved.append({'kind': 'prefab-instance', 'source': child['path'], 'parentPrefix': prefix, 'instanceID': instance['fileID']})
                continue
            own_overrides = [(o, occurrence) for o in instance['overrides']]
            self.collect(child, nested, own_overrides + outer_overrides)

    def resolve_transform(self, ref, occurrence):
        file_id = ref.get('fileID', 0)
        if not file_id: return None
        guid = ref.get('guid', occurrence['guid'])
        resolved=self.source_path(guid,file_id,occurrence['prefix'])
        if resolved is not None:return resolved
        if (guid, file_id) in self.ids: return self.ids[(guid, file_id)]
        if (guid, file_id) in self.fbx_ids: return self.fbx_ids[(guid, file_id)]
        context = occurrence if guid == occurrence['guid'] else next((o for o in self.occurrences if o['guid'] == guid), None)
        return self.own_transform_path(context, file_id) if context else None

    def component_key(self, ref, occurrence):
        file_id = ref.get('fileID', 0)
        if not file_id: return None
        guid = ref.get('guid', occurrence['guid'])
        if guid == occurrence['guid']:
            stripped = next((s for s in occurrence['asset']['prefab']['strippedSourceObjects'] if s['fileID'] == file_id), None)
            if stripped:
                guid, file_id = stripped['source'].get('guid'), stripped['source'].get('fileID')
        contexts = [o for o in self.occurrences if o['guid'] == guid]
        if len(contexts) != 1: return None
        return f"{contexts[0]['prefix']}|{guid}:{file_id}"

    def is_active(self, path):
        if path not in self.nodes: return False
        prefix = path
        while True:
            if not self.nodes.get(prefix, {}).get('active', True): return False
            if not prefix: break
            prefix = prefix.rpartition('/')[0]
        return True

    def output(self):
        chains, colliders, contacts = [], [], []
        for occurrence in self.occurrences:
            asset = occurrence['asset']
            source_path = resolve_source_path(asset['extractedPath'], expected_sha256=asset.get('sha256'))
            raw_blocks = {b['fileID']: b['text'] for b in unity_blocks(text_file(source_path))}
            for component in asset['prefab']['physicsComponentsByFields']:
                source = raw_blocks[component['fileID']]
                parameters = {key: parsed_value(field(source, key)) for key in re.findall(r'^  ([A-Za-z_]\w*):', source, re.M)
                              if not key.startswith('m_') and key not in ('rootTransform','ignoreTransforms','colliders') and not key.endswith('Curve')}
                curves = {key: curve_data(value) for key, value in component.get('parameterCurvesRaw', {}).items()}
                root_ref = (deepcopy(component['rootTransform']), occurrence)
                arrays = {key: [(deepcopy(ref), occurrence) for ref in values] for key, values in component['referenceArrays'].items()}
                enabled, applied = component['enabled'], []
                for override, owner in occurrence['overrides']:
                    target = override['target']
                    if (target.get('guid'), target.get('fileID')) != (asset['guid'], component['fileID']): continue
                    path, value = override['propertyPath'], override['value']
                    applied.append({'propertyPath': path, 'value': value, 'objectReference': override['objectReference'], 'referenceContextGUID': owner['guid']})
                    if path == 'rootTransform': root_ref = (override['objectReference'], owner)
                    elif path == 'm_Enabled': enabled = value
                    elif (match := re.fullmatch(r'(ignoreTransforms|colliders)\.Array\.(size|data\[(\d+)\])', path)):
                        values = arrays[match[1]]
                        size = int(value) if match[2] == 'size' else int(match[3]) + 1
                        if match[2] == 'size': del values[size:]
                        while len(values) < size: values.append(({'fileID': 0}, owner))
                        if match[2] != 'size': values[int(match[3])] = (override['objectReference'], owner)
                    elif path in parameters: parameters[path] = value
                    elif '.' in path and path.partition('.')[0] in parameters:
                        key, _, axis = path.partition('.')
                        if isinstance(parameters[key], dict): parameters[key][axis] = value
                owner_path = self.component_owner_path(occurrence, component)
                root_path = self.resolve_transform(*root_ref) if root_ref[0].get('fileID') else owner_path
                if root_path not in self.nodes:
                    self.unresolved.append({'kind': 'physics-root', 'source': asset['path'], 'componentID': component['fileID'], 'reference': root_ref[0], 'ownerPath': owner_path})
                ignored = []
                for ref, context in arrays['ignoreTransforms']:
                    if not ref.get('fileID'): continue
                    path = self.resolve_transform(ref, context)
                    if path is None: self.unresolved.append({'kind': 'ignored-transform', 'componentID': component['fileID'], 'reference': ref})
                    else: ignored.append(path)
                collider_ids = []
                for ref, context in arrays['colliders']:
                    if not ref.get('fileID'): continue
                    key = self.component_key(ref, context)
                    if key is None: self.unresolved.append({'kind': 'collider-reference', 'componentID': component['fileID'], 'reference': ref})
                    else: collider_ids.append(key)
                record = {'id': f"{occurrence['prefix']}|{asset['guid']}:{component['fileID']}",
                    'sourcePrefab': asset['path'], 'sourceGUID': asset['guid'], 'sourceComponentFileID': component['fileID'],
                    'script': component['script'], 'ownerPath': owner_path, 'rootPath': root_path,
                    'enabled': bool(enabled), 'activeInHierarchy': self.is_active(owner_path),
                    'parameters': parameters, 'parameterCurves': curves, 'overridesApplied': applied,
                    'ignorePaths': ignored, 'colliderIDs': collider_ids}
                kind = component['componentKindByFields']
                if kind == 'spring-chain':
                    driven = [p for p in self.nodes if root_path is not None and (p == root_path or p.startswith(root_path + '/'))
                              and not any(p == ignore or p.startswith(ignore + '/') for ignore in ignored)]
                    record['transformPaths'] = driven
                    record['leafPaths'] = [p for p in driven if not any(other != p and other.startswith(p + '/') for other in driven)]
                    record['endpointPositionLocal'] = parameters.get('endpointPosition')
                    chains.append(record)
                elif kind == 'collider':
                    record['shape'] = {key: parameters.get(key) for key in ('shapeType','radius','height','position','rotation','insideBounds','bonesAsSpheres')}
                    colliders.append(record)
                else: contacts.append(record)
        collider_index = {c['id']: c for c in colliders}
        for chain in chains:
            for key in chain['colliderIDs']:
                if key not in collider_index: self.unresolved.append({'kind': 'missing-collider-component', 'chain': chain['id'], 'colliderID': key})
        return {'sourcePrefab': self.main['path'], 'rootScale': self.nodes['']['scale'],
                'coordinateSpace': 'Original Unity prefab local coordinates. Root scale and any later avatar normalization must also scale collider radius/offsets; parameters are source values, not a solver-equivalence promise.',
                'chains': chains, 'colliders': colliders, 'contacts': contacts, 'unresolved': self.unresolved}


def build_physics(audit, inspection_root):
    roles = []
    for path in sorted(inspection_root.glob('*-prefab.json')):
        inspection = json.loads(path.read_text())
        package = next(p for a in audit['archives'] for p in a['unityPackages'] if any(x['path'] == inspection['prefab'] for x in p['assets']))
        fbx = json.loads(path.with_name(inspection['role'] + '-fbx.json').read_text())
        resolver = PhysicsResolver(package['assets'], inspection, fbx)
        roles.append(dict(role=inspection['role'], inspectionSource=str(path), **resolver.output()))
    return {'schemaVersion': 1, 'auditTool': 'scripts/vrchat_physics.py',
            'scope': 'Source PhysBone values plus resolved prefab paths; no VRChat SDK or runtime solver executed.', 'roles': roles}


def runtime_secondary(role, gltf, metadata, model_scale=2):
    """Bounded standalone approximation; source parameters remain in audit JSON.

    These FBX bind axes have been compared to glTFast: local Unity x equals
    negative glTF x, y/z match after the armature conversion. Offset vectors are
    serialized for Unity; synthetic glTF endpoints flip x once.
    """
    import math
    from prepare_anime_characters import paths
    source=next(r for r in metadata['roles'] if r['role']==role)
    for issue in source['unresolved']:
        if not (role=='mamehinata' and issue['kind']=='prefab-instance' and
                issue.get('source')=='Assets/MOCHIYAMA/Mamehinata/Prefab/NameTag.prefab'):
            raise ValueError('Unreviewed physics reference: '+json.dumps(issue))
    nodes=gltf['nodes']; p=paths(gltf)
    names={n['name']:i for i,n in enumerate(nodes)}
    source_to_target={path:names.get(path.split('/')[-1]) for chain in source['chains'] for path in chain['transformPaths']}
    segments={}; skipped=[]
    for chain in source['chains']:
        if not chain['enabled'] or not chain['activeInHierarchy']:continue
        original=chain['rootPath'] or ''
        if any(x in original.lower() for x in ('bust','breast')):
            skipped.append(dict(root=original,reason='body dynamics not part of companion rig'));continue
        driven={source_to_target[x] for x in chain['transformPaths'] if source_to_target[x] is not None}
        radius=min(.025,float(chain['parameters'].get('radius') or .005))*model_scale
        angle=10 if 'hair' in original.lower() else 7 if 'tail' in original.lower() else 5
        for index in sorted(driven):
            children=[n for n in nodes[index].get('children',[]) if n in driven]
            if not children and chain.get('endpointPositionLocal'):
                e=chain['endpointPositionLocal'];v=[-float(e.get('x',0))*model_scale,float(e.get('y',0))*model_scale,float(e.get('z',0))*model_scale]
                if sum(x*x for x in v)>1e-8:
                    tip=len(nodes);nodes.append(dict(name='XCP_tip_'+str(index),translation=v));nodes[index].setdefault('children',[]).append(tip);children=[tip]
            for tip in children:
                if sum(x*x for x in nodes[tip].get('translation',[0,0,0]))<1e-8:continue
                # One transform can only receive one rotation; choose its longest
                # child on forks, then solve each independent child segment.
                length=sum(x*x for x in nodes[tip].get('translation',[0,0,0]))
                if index not in segments or length>segments[index][0]:segments[index]=(length,tip,radius,angle)
        if not driven:skipped.append(dict(root=original,reason='non-FBX accessory / unresolved static prefab content'))
    p=paths(gltf)
    strands=[dict(bone=p[i],tip=p[tip],radius=radius,angle=angle) for i,(length,tip,radius,angle) in sorted(segments.items(),key=lambda item:p[item[0]].count('/'))]
    colliders=[]
    for c in source['colliders']:
        if not c['enabled'] or not c['activeInHierarchy']:continue
        name=(c['rootPath'] or '').split('/')[-1];node=names.get(name);shape=c['shape']
        if node is None:skipped.append(dict(root=c['rootPath'],reason='collider bone absent'));continue
        if shape['shapeType'] not in (0,1) or shape['insideBounds']:
            skipped.append(dict(root=c['rootPath'],reason='plane/inside collider is not a sphere or capsule'));continue
        from mathutils import Quaternion,Vector
        rotation=shape['rotation'] or dict(x=0,y=0,z=0,w=1)
        q=Quaternion(tuple(rotation[k] for k in ('w','x','y','z')))
        pos=shape['position'] or dict(x=0,y=0,z=0);center=Vector(tuple(pos[k] for k in 'xyz'))
        radius=float(shape['radius']);half=max(0,float(shape['height'] or 0)*.5-radius) if shape['shapeType']==1 else 0
        # Three overlapping spheres approximate a capsule conservatively; the
        # runtime silhouette angle bound remains the final authority.
        for offset in ([-half,0,half] if half else [0]):
            v=center+q@Vector((0,offset,0))
            colliders.append(dict(bone=p[node],offset=dict(zip('xyz',v*model_scale)),radius=radius*model_scale))
    if len(strands)>128 or len(colliders)>64:raise ValueError('Secondary-motion budget exceeded')
    data=dict(schemaVersion=1,strands=strands,colliders=colliders)
    return data,dict(strands=len(strands),colliders=len(colliders),skipped=skipped,
        limitations=['Independent bounded solver, not VRC PhysBone equivalence.',
        'Author pull/spring/gravity/curves and per-chain collider masks are archived; runtime uses shared damped springs and conservative angle limits.',
        'Capsules approximated with three overlapping spheres; plane colliders omitted.',
        'Nested name tag attachment is a static accessory not exported from FBX.'],sourceUnresolved=source['unresolved'])

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--audit', type=Path, default=ROOT / 'docs/verification/vrchat-import/source-audit.json')
    parser.add_argument('--inspection-root', type=Path, default=ROOT / '.local/vrchat-stage/Inspection')
    parser.add_argument('--output', type=Path, default=ROOT / 'docs/verification/vrchat-import/source-physics.json')
    parser.add_argument('--allow-unresolved-prefab', action='append', default=[],
                        help='Exact source prefab path already reviewed as outside this conversion; does not waive physics root/collider failures.')
    args = parser.parse_args()
    result = build_physics(json.loads(args.audit.read_text()), args.inspection_root)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n')
    for role in result['roles']:
        print(role['role'], 'chains',len(role['chains']),'colliders',len(role['colliders']),'contacts',len(role['contacts']),'unresolved',len(role['unresolved']))
        for item in role['unresolved']: print('UNRESOLVED',json.dumps(item,ensure_ascii=False))
    fatal=[issue for role in result['roles'] for issue in role['unresolved']
           if not (issue['kind']=='prefab-instance' and issue.get('source') in args.allow_unresolved_prefab)]
    return 1 if fatal else 0


if __name__ == '__main__':
    raise SystemExit(main())
