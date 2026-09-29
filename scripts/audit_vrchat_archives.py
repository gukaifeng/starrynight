#!/usr/bin/env python3
"""Read-only source audit and bounded data extraction for ZIP + UnityPackage assets.

Never imports Unity or executes an extracted script. Original archives are untouched.
The extracted tree is data for an explicit later conversion, not an import command.
"""
import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path, PurePosixPath
import re
import shutil
import stat
import struct
import tarfile
import zipfile
import zlib

ROOT = Path(__file__).resolve().parents[1]
MAX_FILE = 512 * 1024 * 1024
MAX_TOTAL = 3 * 1024 * 1024 * 1024
MAX_ARRAY = 64 * 1024 * 1024
GUID = re.compile(r'\b[0-9a-f]{32}\b')
TEXT_EXTENSIONS = {'.prefab', '.anim', '.controller', '.overridecontroller', '.mat', '.asset', '.meta', '.txt', '.md', '.url', '.json', '.shader', '.cs'}


def sha256(path):
    digest = hashlib.sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(chunk)
    return digest.hexdigest()


def safe_target(root, name):
    if '\x00' in name or '\\' in name:
        raise ValueError('Ambiguous archive path: ' + repr(name))
    relative = PurePosixPath(name)
    if relative.is_absolute() or '..' in relative.parts or re.match(r'^[a-zA-Z]:', name):
        raise ValueError('Unsafe archive path: ' + repr(name))
    target = root.joinpath(*relative.parts)
    if not target.resolve().is_relative_to(root.resolve()):
        raise ValueError('Archive path escapes extraction root')
    for parent in [target, *target.parents]:
        if parent == root.parent:
            break
        if parent.is_symlink():
            raise ValueError('Refusing extraction through a symlink: ' + str(parent))
    return target


def write_stream(root, name, stream, size):
    if size < 0 or size > MAX_FILE:
        raise ValueError('Oversize archive member: ' + name)
    target = safe_target(root, name)
    target.parent.mkdir(parents=True, exist_ok=True)
    total = 0
    with target.open('wb') as output:
        while chunk := stream.read(min(1024 * 1024, size - total + 1)):
            total += len(chunk)
            if total > size:
                raise ValueError('Archive member larger than its declared size')
            output.write(chunk)
    if total != size:
        raise ValueError('Truncated archive member: ' + name)
    target.chmod(0o600)  # Extracted scripts have no execute bit.
    return target


def text_file(path):
    data = path.read_bytes()
    for encoding in ('utf-8-sig', 'utf-16', 'cp932'):
        try:
            return data.decode(encoding)
        except UnicodeError:
            continue
    return data.decode('utf-8', errors='replace')


def extract_zip(path, root):
    inventory, seen, expanded = [], set(), 0
    with zipfile.ZipFile(path) as archive:
        for item in archive.infolist():
            safe_target(root, item.filename)
            identity = str(PurePosixPath(item.filename)).casefold()
            if identity in seen:
                raise ValueError('Duplicate ZIP member: ' + item.filename)
            seen.add(identity)
            mode = item.external_attr >> 16
            if stat.S_ISLNK(mode) or (stat.S_IFMT(mode) not in (0, stat.S_IFREG, stat.S_IFDIR)):
                raise ValueError('ZIP links/special files are not allowed')
            if item.is_dir():
                safe_target(root, item.filename).mkdir(parents=True, exist_ok=True)
                continue
            if item.flag_bits & 1:
                raise ValueError('Encrypted ZIP member is not auditable')
            expanded += item.file_size
            if expanded > MAX_TOTAL:
                raise ValueError('ZIP expands beyond audit budget')
            with archive.open(item) as stream:
                target = write_stream(root, item.filename, stream, item.file_size)
            inventory.append({'path': item.filename, 'bytes': item.file_size, 'sha256': sha256(target), 'extractedPath': str(target)})
    return inventory


class FbxArray:
    def __init__(self, kind, count, encoding, data):
        self.kind, self.count, self.encoding, self.data = kind, count, encoding, data

    def values(self):
        codes = {'f': 'f', 'd': 'd', 'i': 'i', 'l': 'q', 'b': 'B', 'c': 'b'}
        code = codes[self.kind]
        expected = self.count * struct.calcsize('<' + code)
        if expected > MAX_ARRAY:
            raise ValueError('FBX array exceeds audit limit')
        if self.encoding == 0:
            data = self.data
        elif self.encoding == 1:
            decoder = zlib.decompressobj()
            data = decoder.decompress(self.data, expected + 1)
            if not decoder.eof or decoder.unconsumed_tail:
                raise ValueError('Invalid or oversize compressed FBX array')
        else:
            raise ValueError('Unknown FBX array encoding')
        if len(data) != expected:
            raise ValueError('FBX array byte count mismatch')
        return (value[0] for value in struct.iter_unpack('<' + code, data))


def fbx_inventory(path):
    data = path.read_bytes()
    if not data.startswith(b'Kaydara FBX Binary  \x00\x1a\x00'):
        return {'format': 'not-binary-fbx', 'inspection': 'not parsed'}
    version = struct.unpack_from('<I', data, 23)[0]
    wide = version >= 7500
    header = '<QQQB' if wide else '<IIIB'
    header_bytes = struct.calcsize(header)

    def property_at(position):
        kind = chr(data[position]); position += 1
        primitive = {'Y': 'h', 'C': '?', 'I': 'i', 'F': 'f', 'D': 'd', 'L': 'q'}
        if kind in primitive:
            code = '<' + primitive[kind]
            return struct.unpack_from(code, data, position)[0], position + struct.calcsize(code)
        if kind in ('S', 'R'):
            size = struct.unpack_from('<I', data, position)[0]; position += 4
            if size > MAX_ARRAY or position + size > len(data):
                raise ValueError('Invalid FBX string/blob length')
            value = data[position:position + size]
            return (value.decode('utf-8', errors='replace') if kind == 'S' else value), position + size
        if kind in 'fdilbc':
            count, encoding, size = struct.unpack_from('<III', data, position); position += 12
            if size > MAX_ARRAY or position + size > len(data):
                raise ValueError('Invalid FBX array length')
            return FbxArray(kind, count, encoding, data[position:position + size]), position + size
        raise ValueError('Unknown FBX property type: ' + kind)

    def node_at(position, depth=0):
        if depth > 128:
            raise ValueError('FBX node nesting too deep')
        end, count, length, name_bytes = struct.unpack_from(header, data, position)
        if end == 0:
            return None, position + header_bytes
        if end > len(data) or end <= position or count > 1_000_000:
            raise ValueError('Invalid FBX node bounds')
        position += header_bytes
        name = data[position:position + name_bytes].decode('utf-8', errors='replace'); position += name_bytes
        properties, start = [], position
        for _ in range(count):
            value, position = property_at(position); properties.append(value)
        if position - start != length:
            raise ValueError('FBX property length mismatch')
        children = []
        while position < end:
            child, following = node_at(position, depth + 1)
            position = following
            if child is None:
                break
            children.append(child)
        if position != end:
            raise ValueError('FBX node endpoint mismatch')
        return (name, properties, children), end

    nodes, position = [], 27
    while position + header_bytes < len(data):
        node, position = node_at(position)
        if node is None:
            break
        nodes.append(node)
    sections = {node[0]: node for node in nodes}
    objects = sections.get('Objects', ('', [], []))[2]
    clean = lambda name: str(name).split('\x00')[0]
    models = {node[1][0]: {'name': clean(node[1][1]), 'kind': node[1][2]} for node in objects if node[0] == 'Model'}
    parent_ids = {}
    for _, props, _ in sections.get('Connections', ('', [], []))[2]:
        if len(props) >= 3 and props[0] == 'OO' and props[1] in models and props[2] in models:
            parent_ids[props[1]] = props[2]
    bones = [dict(id=key, parentID=parent_ids.get(key), **value) for key, value in models.items() if value['kind'] in ('LimbNode', 'Root')]
    shapes = [clean(node[1][1]) for node in objects if node[0] == 'Deformer' and node[1][2] == 'BlendShapeChannel']
    geometry = []
    for _, props, children in [node for node in objects if node[0] == 'Geometry' and node[1][2] == 'Mesh']:
        fields = {node[0]: node[1] for node in children}
        vertices = fields.get('Vertices', [None])[0]
        polygons = fields.get('PolygonVertexIndex', [None])[0]
        faces = triangles = run = 0
        if polygons:
            for index in polygons.values():
                run += 1
                if index < 0:
                    faces += 1; triangles += max(0, run - 2); run = 0
            if run:
                raise ValueError('Unterminated FBX polygon')
        geometry.append({'name': clean(props[1]), 'controlPoints': vertices.count // 3 if vertices else 0,
                         'polygonCount': faces, 'triangulatedFaces': triangles})
    settings = {}
    for name, _, children in sections.get('GlobalSettings', ('', [], []))[2]:
        if name == 'Properties70':
            settings = {props[0]: props[4:] for _, props, _ in children if props and props[0] in ('UnitScaleFactor', 'OriginalUnitScaleFactor', 'UpAxis', 'UpAxisSign', 'FrontAxis', 'FrontAxisSign', 'CoordAxis', 'CoordAxisSign')}
    return {'format': 'binary-fbx', 'version': version, 'globalSettings': settings, 'boneCount': len(bones), 'bones': bones,
            'blendShapeChannelCount': len(shapes), 'blendShapeNames': shapes, 'meshes': geometry,
            'totalControlPoints': sum(item['controlPoints'] for item in geometry),
            'totalTriangulatedFaces': sum(item['triangulatedFaces'] for item in geometry),
            'animationStacks': [clean(node[1][1]) for node in objects if node[0] == 'AnimationStack'],
            'skinClusterCount': sum(node[0] == 'Deformer' and node[1][2] == 'Cluster' for node in objects)}


def animation_inventory(text):
    attributes = sorted(set(re.findall(r'^\s+attribute: (.+)$', text, re.M)))
    paths = sorted(set(re.findall(r'^\s+path: (.+)$', text, re.M)))
    transform = any(re.search(r'^  ' + field + r':\s*\n\s*-', text, re.M) for field in
                    ['m_RotationCurves', 'm_EulerCurves', 'm_PositionCurves', 'm_ScaleCurves'])
    muscles = [a for a in attributes if re.search(r'(Front-Back|Left-Right|Twist|Stretched|Spread|Root[QT]\.|Motion[QT]\.)', a)]
    body_muscles = [a for a in muscles if not any(finger in a for finger in ('Thumb', 'Index', 'Middle', 'Ring', 'Little'))]
    kinds = []
    if any(a.startswith('blendShape.') for a in attributes): kinds.append('blendshape-expression')
    if any('material.' in a or a.startswith('_') for a in attributes): kinds.append('material-FX')
    if any(a in ('m_IsActive', 'm_Enabled') for a in attributes): kinds.append('object-toggle')
    if transform: kinds.append('transform-curves')
    if body_muscles: kinds.append('humanoid-body-muscles')
    elif muscles: kinds.append('humanoid-hand-muscles')
    if not kinds: kinds.append('other-or-empty')
    stop = re.search(r'^\s+m_StopTime: (.+)$', text, re.M)
    name = re.search(r'^  m_Name: (.+)$', text, re.M)
    return {'clipName': name[1] if name else '', 'stopTime': float(stop[1]) if stop else None,
            'loop': bool(re.search(r'^\s+m_LoopTime: 1$', text, re.M)), 'classification': kinds,
            'attributes': attributes, 'paths': paths, 'readablePaths': [p for p in paths if not p.isdigit()],
            'bodyMuscleBindings': body_muscles,
            'note': 'Classification describes serialized bindings, not a Unity playback/retargeting validation.'}


def inline_reference(value, by_guid=None):
    """Unity fileIDs are signed 64-bit identities; keep integers intact in Python."""
    fields = dict(re.findall(r'(fileID|guid|type):\s*([^,}\s]+)', value or ''))
    result = {key: int(val) if key != 'guid' else val for key, val in fields.items()}
    asset = (by_guid or {}).get(result.get('guid'))
    if asset:
        result.update(path=asset['path'], extractedPath=asset['extractedPath'])
    return result


def scalar(value):
    value = value.strip()
    if re.fullmatch(r'[-+]?\d+', value): return int(value)
    if re.fullmatch(r'[-+]?(?:\d+\.\d*|\d*\.\d+|\d+)(?:[eE][-+]?\d+)?', value): return float(value)
    return value


def field(text, name, indent=2):
    match = re.search(r'^' + ' ' * indent + re.escape(name) + r':([^\n]*)(?:\n|$)', text, re.M)
    if not match: return None
    values = [match[1]]
    for line in text[match.end():].splitlines():
        stripped = line.lstrip(' ')
        leading = len(line) - len(stripped)
        if stripped and (leading < indent or (leading == indent and not stripped.startswith('- '))): break
        values.append(line)
    return '\n'.join(values).strip()


def unity_blocks(text):
    matches = list(re.finditer(r'^--- !u!(\d+) &(-?\d+)( stripped)?\s*$', text, re.M))
    return [{'classID': int(m[1]), 'fileID': int(m[2]), 'stripped': bool(m[3]),
             'text': text[m.end():matches[i + 1].start() if i + 1 < len(matches) else len(text)]}
            for i, m in enumerate(matches)]


def material_inventory(text, by_guid):
    textures = []
    for match in re.finditer(r'^    - (\S+):\n        m_Texture: (\{[^}]*\})\n        m_Scale: (\{[^}]*\})\n        m_Offset: (\{[^}]*\})', text, re.M):
        reference = inline_reference(match[2], by_guid)
        if reference.get('fileID'):
            textures.append({'property': match[1], 'texture': reference, 'scale': match[3], 'offset': match[4]})
    floats = re.search(r'^    m_Floats:\n([\s\S]*?)(?=^    \w|\Z)', text, re.M)
    colors = re.search(r'^    m_Colors:\n([\s\S]*?)(?=^    \w|\Z)', text, re.M)
    return {'shader': inline_reference(field(text, 'm_Shader'), by_guid),
            'customRenderQueue': scalar(field(text, 'm_CustomRenderQueue') or '-1'),
            'textureBindings': textures,
            'floats': {m[1]: scalar(m[2]) for m in re.finditer(r'^    - (\S+): (.+)$', floats[1] if floats else '', re.M)},
            'colors': {m[1]: {k: float(v) for k, v in re.findall(r'([rgba]): ([-+\deE.]+)', m[2])}
                       for m in re.finditer(r'^    - (\S+): (\{[^}]*\})$', colors[1] if colors else '', re.M)},
            'lilToonMarkers': sorted(set(re.findall(r'\b(?:_lilToonVersion|_Use[A-Za-z0-9_]+|_MatCap[A-Za-z0-9_]+)\b', text)))}


def model_importer_inventory(text, by_guid):
    material_remaps = []
    for match in re.finditer(r'^  - first:\n      type: ([^\n]*)\n      assembly: ([^\n]*)\n      name: ([^\n]*)\n    second: (\{[^}]*\})', text, re.M):
        material_remaps.append({'type': match[1], 'assembly': match[2], 'sourceName': match[3], 'target': inline_reference(match[4], by_guid)})
    name_table = field(text, 'internalIDToNameTable')
    return {'externalObjects': material_remaps, 'internalIDToNameTableRaw': name_table,
            'animationType': scalar(field(text, 'animationType') or '-1'),
            'meshGlobalScale': scalar(field(text, 'globalScale', 4) or '1'),
            'fileScale': scalar(field(text, 'fileScale', 4) or '1'),
            'humanoidBoneMap': [{'boneName': m[1], 'humanName': m[2]} for m in re.finditer(r'^    - boneName: (.+)\n      humanName: (.+)$', text, re.M)]}


def prefab_inventory(text, by_guid=None):
    classes = Counter(re.findall(r'^--- !u!(\d+)', text, re.M))
    scripts = sorted(set(re.findall(r'm_Script: \{[^}]*guid: ([a-f0-9]{32})', text)))
    names = re.findall(r'^  m_Name: (.+)$', text, re.M)
    result = {'unityClassCounts': dict(classes), 'gameObjects': classes.get('1', 0),
            'skinnedMeshRenderers': classes.get('137', 0), 'scriptGUIDs': scripts,
            'animatorCount': classes.get('95', 0), 'namedObjects': names,
            'SDKPropertyMarkers': sorted({token for token in ['ViewPosition', 'lipSync', 'customExpressions', 'baseAnimationLayers', 'isLocal', 'allowCollision', 'pull', 'spring', 'immobile', 'parameter'] if re.search(r'^\s+' + token + r':', text, re.M)}),
            'gameObjectDefaults': [], 'transforms': [], 'rendererDefaults': [], 'physicsComponentsByFields': [],
            'prefabInstances': [], 'strippedSourceObjects': [],
            'resolutionNote': 'Serialized defaults plus explicit nested overrides. FBX-derived hashed fileIDs without an importer name table remain unresolved; this is not an instantiated Unity hierarchy.'}
    blocks = unity_blocks(text)
    go_names = {b['fileID']: field(b['text'], 'm_Name') for b in blocks if b['classID'] == 1 and not b['stripped']}
    transform_gos = {b['fileID']: inline_reference(field(b['text'], 'm_GameObject')).get('fileID')
                     for b in blocks if b['classID'] == 4 and not b['stripped']}

    def local_reference(value):
        ref = inline_reference(value, by_guid)
        local_id = ref.get('fileID')
        if 'guid' not in ref:
            name = go_names.get(local_id) or go_names.get(transform_gos.get(local_id))
            if name: ref['localName'] = name
        return ref

    for block in blocks:
        content, class_id = block['text'], block['classID']
        base = {'fileID': block['fileID'], 'classID': class_id}
        if block['stripped']:
            result['strippedSourceObjects'].append(dict(base, source=inline_reference(field(content, 'm_CorrespondingSourceObject'), by_guid),
                prefabInstance=local_reference(field(content, 'm_PrefabInstance'))))
            continue
        go = local_reference(field(content, 'm_GameObject'))
        if class_id == 1:
            result['gameObjectDefaults'].append(dict(base, name=field(content, 'm_Name'), active=scalar(field(content, 'm_IsActive') or '1')))
        elif class_id == 4:
            result['transforms'].append(dict(base, gameObject=go, parent=local_reference(field(content, 'm_Father')),
                localPosition=field(content, 'm_LocalPosition'), localRotation=field(content, 'm_LocalRotation'), localScale=field(content, 'm_LocalScale')))
        elif class_id in (137, 23):
            result['rendererDefaults'].append(dict(base, gameObject=go, enabled=scalar(field(content, 'm_Enabled') or '1'),
                mesh=inline_reference(field(content, 'm_Mesh'), by_guid),
                materials=[inline_reference(m, by_guid) for m in re.findall(r'\{[^}]*\}', field(content, 'm_Materials') or '')],
                bones=[local_reference(m) for m in re.findall(r'\{[^}]*\}', field(content, 'm_Bones') or '')],
                blendShapeWeights=[float(v) for v in re.findall(r'^\s*- ([-+\d.eE]+)$', field(content, 'm_BlendShapeWeights') or '', re.M)]))
        elif class_id == 114 and field(content, 'rootTransform') is not None:
            physics = dict(base, gameObject=go, enabled=scalar(field(content, 'm_Enabled') or '1'),
                script=inline_reference(field(content, 'm_Script'), by_guid), rootTransform=local_reference(field(content, 'rootTransform')),
                componentKindByFields='spring-chain' if field(content, 'pull') is not None else ('contact' if field(content, 'collisionTags') is not None else ('collider' if field(content, 'shapeType') is not None else 'other')),
                referenceArrays={key: [local_reference(m) for m in re.findall(r'\{[^}]*\}', field(content, key) or '')] for key in ('ignoreTransforms','colliders')},
                parameters={})
            for key in ('pull','spring','stiffness','gravity','gravityFalloff','immobile','immobileType','radius','limitType','maxAngleX','maxAngleZ','limitRotation',
                        'allowCollision','allowGrabbing','allowPosing','grabMovement','stretchMotion','maxStretch','maxSquish','isAnimated','endpointPosition','parameter','shapeType','height','position','rotation'):
                value = field(content, key)
                if value is not None: physics['parameters'][key] = scalar(value)
            result['physicsComponentsByFields'].append(physics)
            physics['parameterCurvesRaw'] = {key: field(content, key) for key in re.findall(r'^  ([A-Za-z_][A-Za-z0-9_]*Curve):', content, re.M)}
        elif class_id == 1001:
            overrides = []
            for match in re.finditer(r'^    - target: (\{[^}]*\})\n      propertyPath: ([^\n]*)\n      value: ([^\n]*)\n      objectReference: (\{[^}]*\})', content, re.M):
                overrides.append({'target': inline_reference(match[1], by_guid), 'propertyPath': match[2],
                                  'value': scalar(match[3]), 'objectReference': local_reference(match[4])})
            result['prefabInstances'].append(dict(base, source=inline_reference(field(content, 'm_SourcePrefab'), by_guid),
                transformParent=local_reference(field(content, 'm_TransformParent', 4)), overrides=overrides,
                visibilityAndShapeOverrides=[item for item in overrides if item['propertyPath'] in ('m_Name','m_IsActive','m_Enabled')
                    or item['propertyPath'].startswith(('m_BlendShapeWeights.','m_Materials.'))],
                physicsRootOverrides=[item for item in overrides if item['propertyPath'].startswith(('rootTransform','ignoreTransforms.','colliders.'))]))
    return result


def enrich_package(package):
    """Read only already-extracted stable files; never re-extract during refresh."""
    by_guid = {asset['guid']: asset for asset in package['assets']}
    for asset in package['assets']:
        if asset['folder']: continue
        source = Path(asset['extractedPath'])
        suffix = asset['extension']
        if suffix == '.prefab': asset['prefab'] = prefab_inventory(text_file(source), by_guid)
        if suffix == '.mat': asset['material'] = material_inventory(text_file(source), by_guid)
        if suffix == '.anim': asset['animation'] = animation_inventory(text_file(source))
        if suffix == '.fbx' and asset.get('metaPath'):
            asset['modelImporter'] = model_importer_inventory(text_file(Path(asset['metaPath'])), by_guid)
    package['guidIndex'] = {a['guid']: {'path': a['path'], 'extractedPath': a['extractedPath'], 'extension': a['extension']}
                            for a in package['assets']}


def package_inventory(path, output):
    raw = output / 'guid-data'; rebuilt = output / 'reconstructed'
    total, seen = 0, set()
    with tarfile.open(path, 'r:gz') as archive:
        for item in archive:
            safe_target(raw, item.name)
            identity = str(PurePosixPath(item.name)).casefold()
            if identity in seen: raise ValueError('Duplicate TAR member')
            seen.add(identity)
            if item.isdir(): continue
            if not item.isfile(): raise ValueError('UnityPackage links/special files rejected')
            if not re.fullmatch(r'[a-fA-F0-9]{32}/(?:asset|asset\.meta|pathname|preview\.png)', item.name):
                raise ValueError('Unexpected UnityPackage member: ' + item.name)
            total += item.size
            if total > MAX_TOTAL: raise ValueError('UnityPackage expands beyond audit budget')
            with archive.extractfile(item) as stream:
                write_stream(raw, item.name, stream, item.size)
    assets, rebuilt_paths = [], set()
    for pathname in sorted(raw.glob('*/pathname')):
        original = text_file(pathname).strip('\x00\r\n')
        target = safe_target(rebuilt, original)
        # The default macOS volume is case-insensitive. Reject aliases before a
        # later GUID could overwrite either an asset or its adjacent .meta file.
        identities = {str(PurePosixPath(original)).casefold(), str(PurePosixPath(original + '.meta')).casefold()}
        if identities & rebuilt_paths: raise ValueError('Duplicate or aliased Unity asset pathname: ' + original)
        rebuilt_paths.update(identities)
        if not (original.startswith('Assets/') or original.startswith('Packages/')):
            raise ValueError('Unexpected Unity asset root: ' + original)
        guid = pathname.parent.name
        source = pathname.parent / 'asset'
        meta = pathname.parent / 'asset.meta'
        entry = {'guid': guid, 'path': original, 'extractedPath': str(target), 'extension': Path(original).suffix.lower(), 'folder': not source.exists()}
        if source.exists():
            target.parent.mkdir(parents=True, exist_ok=True); shutil.copyfile(source, target); target.chmod(0o600)
            entry.update(bytes=source.stat().st_size, sha256=sha256(source))
            if entry['extension'] in TEXT_EXTENSIONS:
                text = text_file(source)
                entry['referencedGUIDs'] = sorted(set(re.findall(r'guid: ([a-f0-9]{32})', text)))
                if entry['extension'] == '.anim': entry['animation'] = animation_inventory(text)
                if entry['extension'] == '.prefab': entry['prefab'] = prefab_inventory(text)
                if entry['extension'] == '.controller':
                    entry['controller'] = {'namedObjects': re.findall(r'^\s+m_Name: (.+)$', text, re.M),
                                           'parameters': re.findall(r'^\s+- m_Name: (.+)$', text, re.M)}
                if entry['extension'] == '.mat':
                    match = re.search(r'm_Shader: \{[^}]*guid: ([a-f0-9]{32})', text)
                    entry['material'] = {'shaderGUID': match[1] if match else None,
                                         'lilToonMarkers': sorted(set(re.findall(r'\b(?:_lilToonVersion|_Use[A-Za-z0-9_]+|_MatCap[A-Za-z0-9_]+)\b', text)))}
            if entry['extension'] == '.fbx': entry['fbx'] = fbx_inventory(source)
        else:
            target.mkdir(parents=True, exist_ok=True)
        if meta.exists():
            meta_target = safe_target(rebuilt, original + '.meta'); meta_target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(meta, meta_target); meta_target.chmod(0o600)
            entry['metaPath'] = str(meta_target)
        assets.append(entry)
    by_guid = {asset['guid']: asset['path'] for asset in assets}
    unresolved = {}
    for asset in assets:
        for guid in asset.get('referencedGUIDs', []):
            if guid not in by_guid and not guid.startswith('0000000000000000'):
                unresolved.setdefault(guid, []).append(asset['path'])
    return {'file': str(path), 'sha256': sha256(path), 'guidEntryCount': len(assets),
            'fileCountsByExtension': dict(sorted(Counter(a['extension'] for a in assets if not a['folder']).items())),
            'reconstructedRoot': str(rebuilt), 'assets': assets, 'unresolvedExternalGUIDReferences': unresolved,
            'scriptAssetCount': sum(a['extension'] in ('.cs', '.dll') for a in assets),
            'shaderAssetCount': sum(a['extension'] in ('.shader', '.shadergraph') for a in assets)}


def audit_archive(path, destination):
    path = path.resolve()
    slug = re.sub(r'[^a-z0-9.-]+', '-', path.stem.lower())
    output = destination / slug
    inventory = extract_zip(path, output / 'source')
    packages, documents, models = [], [], []
    for item in inventory:
        local = Path(item['extractedPath']); suffix = local.suffix.lower()
        if suffix == '.unitypackage': packages.append(package_inventory(local, output / ('package-' + local.stem)))
        if suffix == '.fbx': models.append(dict(path=item['path'], extractedPath=str(local), sha256=item['sha256'], **fbx_inventory(local)))
        if suffix in ('.txt', '.md', '.url', '.pdf'):
            text = text_file(local) if suffix != '.pdf' else None
            documents.append({'path': item['path'], 'extractedPath': str(local), 'text': text,
                              'urls': re.findall(r'https?://[^\s\r\n]+', text or ''),
                              'licenseCandidateByName': bool(re.search(r'license|terms|利用規約|使用条款|許諾', item['path'], re.I))})
    local_license = [d['extractedPath'] for d in documents if d['licenseCandidateByName']]
    package_license = [a['extractedPath'] for p in packages for a in p['assets']
                       if re.search(r'license|terms|利用規約|使用条款|許諾|readme', a['path'], re.I) and a['extension'] in ('.txt','.md','.pdf')]
    return {'sourceArchive': str(path), 'archiveBytes': path.stat().st_size, 'archiveSHA256': sha256(path),
            'slug': slug, 'extractionRoot': str(output), 'outerFiles': inventory,
            'outerFileCountsByExtension': dict(sorted(Counter(Path(a['path']).suffix.lower() for a in inventory).items())),
            'documents': documents, 'localLicenseBodyCandidates': local_license + package_license,
            'licenseStatus': 'Local candidate documents require review' if local_license or package_license else 'No license body found in supplied archive; URL shortcuts are references, not an embedded license.',
            'outerFBX': models, 'unityPackages': packages}


def markdown(report):
    lines = ['# VRChat 源压缩包只读审计', '', '只读取本地压缩包、FBX 二进制结构与 Unity YAML；未导入 Unity、未执行来源脚本，也未验证动画实际播放。路径、GUID 和详细计数以同目录 JSON 为准。', '']
    for archive in report['archives']:
        lines += ['## ' + Path(archive['sourceArchive']).name, '', '- 源 SHA-256：`' + archive['archiveSHA256'] + '`',
                  '- 安全提取目录：`' + archive['extractionRoot'] + '`', '- 许可正文：' + archive['licenseStatus'], '']
        for package in archive['unityPackages']:
            lines += ['包内文件计数：`' + json.dumps(package['fileCountsByExtension'], ensure_ascii=False) + '`。',
                      '未解析的外部 GUID：' + str(len(package['unresolvedExternalGUIDReferences'])) + '；源码脚本/编译程序集：' + str(package['scriptAssetCount']) + '；Shader资源：' + str(package['shaderAssetCount']) + '。', '']
            lines += ['| FBX | 骨骼 | 表情通道 | 三角面 | 内含 AnimationStack |', '|---|---:|---:|---:|---|']
            for asset in package['assets']:
                if 'fbx' not in asset: continue
                fbx = asset['fbx']
                lines.append('| ' + asset['path'] + ' | ' + ' | '.join(str(fbx.get(key, '未解析')) for key in ['boneCount','blendShapeChannelCount','totalTriangulatedFaces','animationStacks']) + ' |')
            kinds = Counter(kind for a in package['assets'] for kind in a.get('animation', {}).get('classification', []))
            lines += ['', '动画绑定类别（可重叠）：`' + json.dumps(dict(kinds), ensure_ascii=False) + '`。', '', '主/附属 Prefab：', '']
            lines += ['- `' + a['path'] + '`' for a in package['assets'] if a['extension'] == '.prefab']
            moving = [a for a in package['assets'] if 'humanoid-body-muscles' in a.get('animation', {}).get('classification', [])
                      and (a['animation']['stopTime'] or 0) > 0]
            poses = [a for a in package['assets'] if 'humanoid-body-muscles' in a.get('animation', {}).get('classification', [])
                     and not (a['animation']['stopTime'] or 0) > 0]
            lines += ['', '具有非零时长的身体肌肉曲线（仍需重定向/播放验证）：', '']
            lines += ['- `' + a['path'] + '`：' + str(a['animation']['stopTime']) + ' 秒；' + str(len(a['animation']['bodyMuscleBindings'])) + ' 条身体绑定。' for a in moving]
            lines += ['', '身体肌肉曲线但时长为 0 的静态姿势：' + str(len(poses)) + ' 项；不能算作可直接循环的身体动作。', '']
            main_prefabs = [a for a in package['assets'] if Path(a['path']).name in ('Kipfel.prefab', 'Mamehinata_PC.prefab')]
            for main in main_prefabs:
                prefab = main['prefab']
                lines += ['转换主参考：`' + main['path'] + '`。其 PrefabInstance 共 ' + str(sum(len(i['overrides']) for i in prefab['prefabInstances'])) +
                          ' 条显式 override；其中可见性/材质/shape 相关 ' + str(sum(len(i['visibilityAndShapeOverrides']) for i in prefab['prefabInstances'])) + ' 条。', '']
        lines += ['', '本地说明文件：', '']
        lines += ['- `' + d['path'] + '`' + (' → ' + ', '.join(d['urls']) if d['urls'] else '') for d in archive['documents']]
        lines.append('')
    lines += ['## 转换交接与边界', '',
              '优先以原装主 Prefab 的可见性、衣服、材质和默认 BlendShape 为准：Kipfel 使用 FBX/Kipfel.fbx + Prefab/Kipfel.prefab；Mamehinata 以 PC 的 FBX/Mamehinata.fbx + Mamehinata_PC.prefab 保留较完整细节，Quest 是另一个较低面数版本。不要因为 FBX 内同时存在多个衣服或替换部件而全部显示。', '',
              'JSON 的 prefabInstances 保留每项源 GUID/fileID、属性路径、值和 objectReference；strippedSourceObjects 保留本地 fileID 到源的映射。physicsComponentsByFields 保留原始根引用、碰撞/忽略引用、标量与参数曲线。两个 FBX 的 internalIDToNameTable 为空时，离线解析不能可靠还原 Unity hashed fileID 到网格名，需由隔离的 Unity 数据导出步骤解析；本报告不虚构该映射。', '',
              'Kipfel 的物理组件主要位于 AvatarDynamics.prefab，主 Prefab 的 rootTransform overrides 把它们绑定到 FBX 骨架。对应 SDK 只有组件引用，没有随包 DLL/源码，因此本地解析记录原值而不运行 SDK。', '',
              '完整材质数据与贴图 GUID 解析见 [source-materials.json](source-materials.json)。Kipfel 眼睛发光带独立 mask，Mamehinata 的 Outfit 启用两层 MatCap；基础色贴图不能替代这些效果。原 toon 材质的 Smoothness=1 经常伴随 Reflection 禁用，不能直接转换为 PBR 零粗糙度。', '',
              '骨骼计数为 FBX Model/LimbNode 与 Root 节点数；BlendShapeChannel 是形变通道数量，不等于已绑定的对话表情数。三角面由原始 polygon 拆分计数，不能代替 Unity 导入后的 GPU 顶点/材质预算。controller 名称不能证明有独立身体动作；需看 .anim 的变换/肌肉绑定及外部 motion GUID。外部 GUID 没有源码依赖包时仅报告未解析，不猜测版本或补装 SDK。', '',
              '此审计未导入主 Unity、未安装 SDK、未执行下载包内的代码。压缩包内是说明网页 URL 快捷方式，未发现许可正文；文件持有本身不能作为许可范围的确认。来源/授权由上层集成流程另行确认。']
    return '\n'.join(lines) + '\n'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('archives', nargs='*', type=Path)
    parser.add_argument('--refresh-metadata', action='store_true', help='Read existing report/stable extracted files and update metadata without writing the asset tree.')
    parser.add_argument('--output-root', type=Path, default=ROOT / '.local/vrchat-audit')
    parser.add_argument('--report', type=Path, default=ROOT / 'docs/verification/vrchat-import/source-audit.json')
    args = parser.parse_args()
    if not args.archives and not args.refresh_metadata: parser.error('Supply an archive or --refresh-metadata')
    if args.archives and args.refresh_metadata: parser.error('--refresh-metadata must not be combined with new archives')
    report = json.loads(args.report.read_text()) if args.refresh_metadata else {'schemaVersion': 1, 'auditTool': 'scripts/audit_vrchat_archives.py',
              'scope': 'Local static inspection only; original archives untouched; no Unity import, dependency installation or source execution.',
              'limits': {'maxMemberBytes': MAX_FILE, 'maxExpandedBytesPerArchive': MAX_TOTAL, 'maxFBXArrayBytes': MAX_ARRAY},
              'archives': []}
    for source in args.archives:
        report['archives'].append(audit_archive(source, args.output_root.resolve()))
        print('Audited ' + source.name, flush=True)
    for archive in report['archives']:
        for package in archive['unityPackages']: enrich_package(package)
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
    args.report.with_suffix('.md').write_text(markdown(report))
    print('Report: ' + str(args.report))


if __name__ == '__main__':
    main()
