#!/usr/bin/env python3
"""Import-time PMX 2.0/2.1 -> glTF 2 skinned mesh, with an auditable sidecar.

No MMD runtime ships in the app. SDEF/QDEF are explicitly approximated by LBS;
IK, grant transforms, material/UV/bone morphs and physics are preserved as source
metadata for the character adapter, not silently represented as glTF features.

API: load_pmx(path) -> PMXModel (source coordinates/units)
     convert_pmx(source, output, scale=.08, morph_names=None) -> sidecar dict
CLI: .local/character-venv/bin/python scripts/pmx_to_glb.py input.pmx model.glb

Layout follows this project's PmxModelData reader; the original mmd_tools parser
was consulted for signed indices and optional bone flags (no code imported):
https://github.com/powroupi/blender_mmd_tools/blob/dev_test/mmd_tools/core/pmx/__init__.py
"""
from __future__ import annotations

import argparse
from dataclasses import dataclass
import hashlib
import json
import math
from pathlib import Path
import struct

import numpy as np
from PIL import Image


class PMXError(ValueError):
    pass


DEFAULT_MORPH_NAMES = ('まばたき', '笑い', 'ウィンク', 'ウィンク右', 'あ', 'い', 'う', 'え', 'お',
                       'にこり', '真面目', '困る', '怒り', '驚き', 'にやり', 'にっこり', '頬照り1',
                       'mouthSmile', 'mouthFrown', 'eyeBlinkLeft', 'eyeBlinkRight', 'browInnerUp',
                       'jawOpen', 'eyeSquint', 'eyeWide')


class Reader:
    def __init__(self, path):
        self.data = Path(path).read_bytes()
        self.at = 0
        self.header = []

    def take(self, size):
        if size < 0 or self.at + size > len(self.data):
            raise PMXError(f'Truncated PMX at byte {self.at}, requested {size}')
        value = self.data[self.at:self.at + size]
        self.at += size
        return value

    def unpack(self, form):
        values = struct.unpack('<' + form, self.take(struct.calcsize('<' + form)))
        return values[0] if len(values) == 1 else list(values)

    def count(self, label, limit=1_000_000):
        count = self.unpack('i')
        if not 0 <= count <= limit:
            raise PMXError(f'Invalid {label} count {count} at {self.at}')
        return count

    def text(self):
        size = self.count('text bytes', 16_000_000)
        return self.take(size).decode('utf-16-le' if self.header[0] == 0 else 'utf-8')

    def index(self, slot, unsigned=False):
        size = self.header[slot]
        return self.unpack(({1: 'B', 2: 'H', 4: 'I'} if unsigned else {1: 'b', 2: 'h', 4: 'i'})[size])

    def vec(self, size=3):
        return self.unpack('f' * size)


@dataclass
class PMXModel:
    source: Path
    version: float
    name: str
    name_en: str
    comment: str
    comment_en: str
    positions: np.ndarray
    normals: np.ndarray
    uv: np.ndarray
    additional_uv: np.ndarray
    joints: np.ndarray
    weights: np.ndarray
    weight_types: np.ndarray
    sdef: dict
    edge_scale: np.ndarray
    indices: np.ndarray
    textures: list
    materials: list
    bones: list
    morphs: list
    display_frames: list
    rigid_bodies: list
    physics_joints: list
    soft_bodies: list


def load_pmx(path) -> PMXModel:
    path = Path(path)
    r = Reader(path)
    if r.take(4) != b'PMX ':
        raise PMXError('Not a PMX file')
    version = r.unpack('f')
    if not (abs(version - 2) < 1e-5 or abs(version - 2.1) < 1e-5):
        raise PMXError(f'Unsupported PMX version {version}')
    r.header = list(r.take(r.unpack('B')))
    if len(r.header) < 8 or r.header[0] not in (0, 1) or r.header[1] > 4 or any(x not in (1, 2, 4) for x in r.header[2:8]):
        raise PMXError('Invalid PMX global header')
    name, name_en, comment, comment_en = [r.text() for _ in range(4)]
    count = r.count('vertices')
    if not count:
        raise PMXError('Empty vertex array')
    positions = np.empty((count, 3), np.float32)
    normals = np.empty((count, 3), np.float32)
    uv = np.empty((count, 2), np.float32)
    additional_uv = np.empty((count, r.header[1], 4), np.float32)
    joints = np.zeros((count, 4), np.int32)
    weights = np.zeros((count, 4), np.float32)
    weight_types = np.empty(count, np.uint8)
    edge_scale = np.empty(count, np.float32)
    sdef = {}
    for i in range(count):
        positions[i], normals[i], uv[i] = r.vec(), r.vec(), r.vec(2)
        for j in range(r.header[1]):
            additional_uv[i, j] = r.vec(4)
        kind = weight_types[i] = r.unpack('B')
        if kind == 0:
            joints[i, 0], weights[i, 0] = r.index(5), 1
        elif kind in (1, 3):
            joints[i, :2] = [r.index(5), r.index(5)]
            weights[i, 0] = r.unpack('f')
            weights[i, 1] = 1 - weights[i, 0]
            if kind == 3:
                sdef[i] = {'center': r.vec(), 'radius0': r.vec(), 'radius1': r.vec()}
        elif kind in (2, 4):
            joints[i] = [r.index(5) for _ in range(4)]
            weights[i] = r.vec(4)
        else:
            raise PMXError(f'Unknown skinning kind {kind}')
        edge_scale[i] = r.unpack('f')
    index_count = r.count('face indices', 12_000_000)
    if index_count % 3:
        raise PMXError('Triangle index count is not divisible by 3')
    indices = np.frombuffer(r.take(index_count * r.header[2]), dtype={1: 'u1', 2: '<u2', 4: '<u4'}[r.header[2]]).astype(np.uint32)
    if len(indices) and indices.max() >= count:
        raise PMXError('Triangle index is outside vertex array')
    textures = [r.text().replace('\\', '/') for _ in range(r.count('textures', 65535))]
    materials = []
    start = 0
    for i in range(r.count('materials', 65535)):
        material = dict(index=i, name=r.text(), name_en=r.text(), diffuse=r.vec(4), specular=r.vec(),
                        shininess=r.unpack('f'), ambient=r.vec(), flags=r.unpack('B'), edgeColor=r.vec(4),
                        edgeSize=r.unpack('f'), texture=r.index(3), sphereTexture=r.index(3), sphereMode=r.unpack('B'))
        material['sharedToon'] = r.unpack('B')
        if material['sharedToon'] not in (0, 1):
            raise PMXError('Invalid shared toon flag')
        material['toonTexture'] = r.unpack('B') if material['sharedToon'] else r.index(3)
        material['memo'] = r.text()
        material['indexStart'], material['indexCount'] = start, r.count('material indices', index_count)
        if material['indexCount'] % 3:
            raise PMXError('Material triangle count is not divisible by 3')
        start += material['indexCount']
        materials.append(material)
    if start != index_count:
        raise PMXError('Material index ranges do not cover the face array')
    bones = []
    for i in range(r.count('bones', 65535)):
        bone = dict(index=i, name=r.text(), name_en=r.text(), position=r.vec(), parent=r.index(5),
                    layer=r.unpack('i'), flags=r.unpack('H'))
        flags = bone['flags']
        bone['tailBone' if flags & 1 else 'tailOffset'] = r.index(5) if flags & 1 else r.vec()
        if flags & 0x300:
            bone['grant'] = dict(bone=r.index(5), weight=r.unpack('f'), rotation=bool(flags & 0x100), translation=bool(flags & 0x200))
        if flags & 0x400:
            bone['fixedAxis'] = r.vec()
        if flags & 0x800:
            bone['localAxes'] = dict(x=r.vec(), z=r.vec())
        if flags & 0x2000:
            bone['externalParent'] = r.unpack('i')
        if flags & 0x20:
            ik = dict(target=r.index(5), iterations=r.unpack('i'), angleLimit=r.unpack('f'), links=[])
            for _ in range(r.count('IK links', 65535)):
                link = dict(bone=r.index(5), limited=r.unpack('B'))
                if link['limited']:
                    link.update(minimum=r.vec(), maximum=r.vec())
                ik['links'].append(link)
            bone['ik'] = ik
        bones.append(bone)
    if not bones:
        raise PMXError('A character mesh requires a skeleton')
    for i, bone in enumerate(bones):
        seen = {i}
        parent = bone['parent']
        while parent != -1:
            if not 0 <= parent < len(bones) or parent in seen:
                raise PMXError(f'Invalid or cyclic bone parent at {i}')
            seen.add(parent)
            parent = bones[parent]['parent']
    morphs = []
    for i in range(r.count('morphs', 10000)):
        morph = dict(index=i, name=r.text(), name_en=r.text(), panel=r.unpack('B'), type=r.unpack('B'), entries=[])
        kind = morph['type']
        for _ in range(r.count('morph entries', 2_000_000)):
            if kind in (0, 9):
                entry = dict(morph=r.index(6), weight=r.unpack('f'))
            elif kind == 1:
                entry = dict(vertex=r.index(2, True), offset=r.vec())
            elif kind == 2:
                entry = dict(bone=r.index(5), translation=r.vec(), rotation=r.vec(4))
            elif 3 <= kind <= 7:
                entry = dict(vertex=r.index(2, True), offset=r.vec(4))
            elif kind == 8:
                entry = dict(material=r.index(4), operation=r.unpack('B'), diffuse=r.vec(4), specular=r.vec(),
                             shininess=r.unpack('f'), ambient=r.vec(), edgeColor=r.vec(4), edgeSize=r.unpack('f'),
                             textureTint=r.vec(4), sphereTint=r.vec(4), toonTint=r.vec(4))
            elif kind == 10:
                entry = dict(rigidBody=r.index(7), local=r.unpack('B'), velocity=r.vec(), torque=r.vec())
            else:
                raise PMXError(f'Unsupported morph type {kind}')
            morph['entries'].append(entry)
        morphs.append(morph)
    displays = []
    for _ in range(r.count('display frames', 10000)):
        display = dict(name=r.text(), name_en=r.text(), special=r.unpack('B'), entries=[])
        for _ in range(r.count('display elements', 100000)):
            kind = r.unpack('B')
            if kind not in (0, 1):
                raise PMXError('Invalid display element kind')
            display['entries'].append(dict(type=kind, index=r.index(5 if kind == 0 else 6)))
        displays.append(display)
    bodies = []
    for i in range(r.count('rigid bodies', 100000)):
        body = dict(index=i, name=r.text(), name_en=r.text(), bone=r.index(5), group=r.unpack('B'),
                    collisionMask=r.unpack('H'), shape=r.unpack('B'), size=r.vec(), position=r.vec(), rotation=r.vec(),
                    mass=r.unpack('f'), linearDamping=r.unpack('f'), angularDamping=r.unpack('f'),
                    restitution=r.unpack('f'), friction=r.unpack('f'), mode=r.unpack('B'))
        bodies.append(body)
    physics_joints = []
    for _ in range(r.count('physics joints', 100000)):
        joint = dict(name=r.text(), name_en=r.text(), type=r.unpack('B'), bodyA=r.index(7), bodyB=r.index(7),
                     position=r.vec(), rotation=r.vec(), translationMin=r.vec(), translationMax=r.vec(),
                     rotationMin=r.vec(), rotationMax=r.vec(), translationSpring=r.vec(), rotationSpring=r.vec())
        physics_joints.append(joint)
    soft_bodies = []
    if version > 2.05 and r.at < len(r.data):
        for _ in range(r.count('soft bodies', 100000)):
            soft = dict(name=r.text(), name_en=r.text(), shape=r.unpack('B'), material=r.index(4),
                        group=r.unpack('B'), collisionMask=r.unpack('H'), flags=r.unpack('B'),
                        bLinkDistance=r.unpack('i'), clusters=r.unpack('i'), mass=r.unpack('f'),
                        collisionMargin=r.unpack('f'), aeroModel=r.unpack('i'), config=r.vec(12), cluster=r.vec(6),
                        iterations=r.unpack('iiii'), materialConfig=r.vec(3), anchors=[], pins=[])
            for _ in range(r.count('soft body anchors', 1_000_000)):
                soft['anchors'].append(dict(rigidBody=r.index(7), vertex=r.index(2, True), nearMode=r.unpack('B')))
            soft['pins'] = [r.index(2, True) for _ in range(r.count('soft body pins', 1_000_000))]
            soft_bodies.append(soft)
    if r.at != len(r.data):
        raise PMXError(f'Unparsed trailing bytes: {len(r.data)-r.at}')
    for label, array in [('positions', positions), ('normals', normals), ('uv', uv), ('weights', weights)]:
        if not np.isfinite(array).all():
            raise PMXError(f'Non-finite {label}')
    return PMXModel(path, version, name, name_en, comment, comment_en, positions, normals, uv, additional_uv,
                    joints, weights, weight_types, sdef, edge_scale, indices, textures, materials, bones, morphs,
                    displays, bodies, physics_joints, soft_bodies)


def expand_vertex_morphs(model):
    """Return source-space sparse offsets; recursively expand group morphs only.

    PMX 2.1 flip morphs are selectors, not additive groups: preserve their source
    entries but do not misrepresent them as a glTF blendshape.
    """
    cache = {}
    def expand(index, stack):
        if not 0 <= index < len(model.morphs):
            raise PMXError(f'Morph reference outside array: {index}')
        if index in stack:
            raise PMXError(f'Cyclic group morph at {index}')
        if index in cache:
            return cache[index]
        morph = model.morphs[index]
        offsets = {}
        if morph['type'] == 1:
            for entry in morph['entries']:
                vertex = entry['vertex']
                if not 0 <= vertex < len(model.positions):
                    raise PMXError(f'Morph vertex outside array: {vertex}')
                offsets[vertex] = offsets.get(vertex, np.zeros(3)) + np.asarray(entry['offset'])
        elif morph['type'] == 0:
            for entry in morph['entries']:
                for vertex, value in expand(entry['morph'], stack | {index}).items():
                    offsets[vertex] = offsets.get(vertex, np.zeros(3)) + value * entry['weight']
        cache[index] = offsets
        return offsets
    for i in range(len(model.morphs)):
        expand(i, set())
    return cache


class GLBWriter:
    def __init__(self):
        self.data = bytearray()
        self.doc = dict(asset=dict(version='2.0', generator='Starry PMX import adapter 1.0'),
                        bufferViews=[], accessors=[], nodes=[], meshes=[], materials=[], textures=[], images=[],
                        samplers=[dict(magFilter=9729, minFilter=9987, wrapS=10497, wrapT=10497)])

    def view(self, raw, target=None):
        self.data.extend(b'\0' * (-len(self.data) % 4))
        view = dict(buffer=0, byteOffset=len(self.data), byteLength=len(raw))
        if target:
            view['target'] = target
        index = len(self.doc['bufferViews'])
        self.doc['bufferViews'].append(view)
        self.data.extend(raw)
        return index

    def array(self, values, kind, component=5126, target=None):
        width = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4, 'MAT4': 16}[kind]
        values = np.asarray(values, dtype={5126: '<f4', 5123: '<u2', 5125: '<u4'}[component]).reshape(-1, width)
        if not len(values) or not np.isfinite(values).all():
            raise PMXError('Empty or non-finite glTF accessor')
        accessor = dict(bufferView=self.view(values.tobytes(), target), componentType=component,
                        count=len(values), type=kind)
        if kind != 'MAT4':
            accessor.update(min=values.min(axis=0).tolist(), max=values.max(axis=0).tolist())
        index = len(self.doc['accessors'])
        self.doc['accessors'].append(accessor)
        return index

    def write(self, output):
        self.data.extend(b'\0' * (-len(self.data) % 4))
        self.doc['buffers'] = [dict(byteLength=len(self.data))]
        raw = json.dumps(self.doc, ensure_ascii=False, separators=(',', ':'), allow_nan=False).encode()
        raw += b' ' * (-len(raw) % 4)
        output.write_bytes(struct.pack('<4sII', b'glTF', 2, 28 + len(raw) + len(self.data)) +
                           struct.pack('<II', len(raw), 0x4e4f534a) + raw +
                           struct.pack('<II', len(self.data), 0x004e4942) + self.data)


def convert_pmx(source, output, scale=.08, morph_names=None, mesh_groups=None, max_texture_size=None):
    source, output = Path(source), Path(output)
    if not math.isfinite(scale) or not 0 < scale <= 10:
        raise PMXError('scale must be positive finite meters per PMX unit')
    if max_texture_size is not None and (not isinstance(max_texture_size, int) or max_texture_size < 64):
        raise PMXError('max_texture_size must be an integer of at least 64 pixels')
    model = load_pmx(source)
    output.parent.mkdir(parents=True, exist_ok=True)
    textures_dir = output.parent / (output.stem + '-textures')
    textures_dir.mkdir(exist_ok=True)
    writer = GLBWriter()
    g = writer.doc
    # PMX is left-handed Y-up; glTF is right-handed Y-up. Reflect Z exactly once
    # and reverse triangle winding. PMX/glTF both address UV origin at top-left.
    basis = np.array([1., 1., -1.])
    positions = model.positions * basis * scale
    normals = model.normals * basis
    lengths = np.linalg.norm(normals, axis=1, keepdims=True)
    if (lengths < 1e-9).any():
        raise PMXError('Zero source normals must be repaired before conversion')
    normals /= lengths
    weights, joints = model.weights.copy(), model.joints.copy()
    invalid = (joints < 0) | (joints >= len(model.bones))
    invalid_count = int(np.count_nonzero(invalid & (weights > 1e-6)))
    weights[invalid] = 0
    joints[invalid] = 0
    weights = np.maximum(weights, 0)
    sums = weights.sum(axis=1, keepdims=True)
    unbound = (sums[:, 0] < 1e-8)
    weights[unbound, 0] = 1
    joints[unbound, 0] = 0
    weights /= weights.sum(axis=1, keepdims=True)
    texture_info = []
    for index, relative in enumerate(model.textures):
        path = (source.parent / relative).resolve()
        if not path.is_relative_to(source.parent.resolve()) or Path(relative).is_absolute() or ':' in relative:
            raise PMXError(f'Texture escapes source package: {relative}')
        if not path.is_file():
            raise PMXError(f'Missing PMX texture: {relative}')
        with Image.open(path) as image:
            image = image.convert('RGBA')
            source_size = [image.width, image.height]
            if max_texture_size:
                image.thumbnail((max_texture_size, max_texture_size), Image.Resampling.LANCZOS)
            alpha = np.asarray(image.getchannel('A'))
            intermediate = int(np.count_nonzero((alpha > 0) & (alpha < 255)))
            coverage = max(1, int(np.count_nonzero(alpha)))
            mode = 'OPAQUE' if alpha.min() == 255 else ('BLEND' if intermediate / coverage > .08 else 'MASK')
            filename = textures_dir / f'{index:03d}.png'
            image.save(filename, compress_level=6)
            png = filename.read_bytes()
            texture_info.append(dict(source=relative, path=filename.relative_to(output.parent).as_posix(),
                                     width=image.width, height=image.height, sourceSize=source_size,
                                     alphaMode=mode, intermediateAlphaFraction=intermediate/coverage,
                                     sha256=hashlib.sha256(png).hexdigest()))
        g['images'].append(dict(name=Path(relative).stem, mimeType='image/png', bufferView=writer.view(png)))
        g['textures'].append(dict(source=index, sampler=0))
    for material in model.materials:
        diffuse = np.clip(material['diffuse'], 0, 1).tolist()
        entry = dict(name=material['name'] or f'Material{material["index"]}',
                     pbrMetallicRoughness=dict(baseColorFactor=diffuse, metallicFactor=0,
                                              roughnessFactor=max(.25, min(.95, math.sqrt(2 / (max(0, material['shininess']) + 2))))),
                     doubleSided=bool(material['flags'] & 1), extras=dict(pmxMaterialIndex=material['index']))
        if material['texture'] >= 0:
            if material['texture'] >= len(texture_info):
                raise PMXError('Material texture index outside array')
            entry['pbrMetallicRoughness']['baseColorTexture'] = dict(index=material['texture'])
            entry['alphaMode'] = texture_info[material['texture']]['alphaMode']
            if entry['alphaMode'] == 'MASK':
                entry['alphaCutoff'] = .35
        if diffuse[3] < .999:
            entry['alphaMode'] = 'BLEND'
            entry.pop('alphaCutoff', None)
        g['materials'].append(entry)
    bone_positions = np.asarray([bone['position'] for bone in model.bones]) * basis * scale
    nodes = [dict(name='Root', children=[])]
    for i, bone in enumerate(model.bones):
        parent = bone['parent']
        nodes.append(dict(name=bone['name'] or f'Bone{i}', translation=(bone_positions[i] -
                     (bone_positions[parent] if parent >= 0 else 0)).tolist(), extras=dict(pmxBoneIndex=i, pmxNameEnglish=bone['name_en'])))
    for i, bone in enumerate(model.bones):
        parent_node = bone['parent'] + 1
        nodes[parent_node].setdefault('children', []).append(i + 1)
    inverse_bind = np.repeat(np.eye(4)[None, :, :], len(model.bones), axis=0)
    inverse_bind[:, :3, 3] = -bone_positions
    g['skins'] = [dict(name=model.name or 'PMXSkeleton', skeleton=0, joints=list(range(1, len(model.bones) + 1)),
                       inverseBindMatrices=writer.array(inverse_bind.transpose(0, 2, 1), 'MAT4'))]
    offsets_by_morph = expand_vertex_morphs(model)
    selected_names = DEFAULT_MORPH_NAMES if morph_names is None else morph_names
    selected_morphs, morph_metadata = [], []
    for index, morph in enumerate(model.morphs):
        metadata = {key: value for key, value in morph.items() if key != 'entries'}
        offsets = offsets_by_morph[index]
        selected = '*' in selected_names or morph['name'] in selected_names or morph['name_en'] in selected_names
        if selected and offsets:
            selected_morphs.append(index)
            metadata['targets'] = {}
        metadata['sourceEntryCount'] = len(morph['entries'])
        # Dense vertex offsets are already in GLB; retain all other source types
        # and group weights so a future adapter can account for their semantics.
        if morph['type'] != 1:
            metadata['entries'] = morph['entries']
        morph_metadata.append(metadata)
    if mesh_groups is None:
        mesh_groups = {'Face': [], 'Hair': [], 'Body': []}
        for material in model.materials:
            name = material['name'].lower()
            if any(word in name for word in ('髪', 'hair')):
                group = 'Hair'
            elif any(word in name for word in ('目', '頭', '顔', '耳', '頬', '青ざめ', 'イライラ', 'face', 'eye', 'brow', 'lash', 'mouth', 'tooth', 'teeth')):
                group = 'Face'
            else:
                group = 'Body'
            mesh_groups[group].append(material['index'])
    assigned = [index for indices in mesh_groups.values() for index in indices]
    if sorted(assigned) != list(range(len(model.materials))):
        raise PMXError('mesh_groups must assign every material exactly once')
    mesh_metadata = []
    for name, material_indices in mesh_groups.items():
        used = [model.materials[index] for index in material_indices if model.materials[index]['indexCount']]
        if not used:
            continue
        source_indices = np.unique(np.concatenate([model.indices[m['indexStart']:m['indexStart']+m['indexCount']] for m in used]))
        remap = np.full(len(positions), -1, np.int32)
        remap[source_indices] = np.arange(len(source_indices))
        attrs = dict(POSITION=writer.array(positions[source_indices], 'VEC3', target=34962),
                     NORMAL=writer.array(normals[source_indices], 'VEC3', target=34962),
                     TEXCOORD_0=writer.array(model.uv[source_indices], 'VEC2', target=34962),
                     JOINTS_0=writer.array(joints[source_indices], 'VEC4', 5123, 34962),
                     WEIGHTS_0=writer.array(weights[source_indices], 'VEC4', target=34962))
        targets, target_names = [], []
        for index in selected_morphs:
            delta = np.zeros((len(source_indices), 3))
            for vertex, offset in offsets_by_morph[index].items():
                if remap[vertex] >= 0:
                    delta[remap[vertex]] = offset * basis * scale
            if not np.isfinite(delta).all():
                raise PMXError(f'Non-finite morph {model.morphs[index]["name"]}')
            if not np.any(np.abs(delta) > 1e-10):
                continue
            morph_metadata[index]['targets'][name] = len(targets)
            targets.append(dict(POSITION=writer.array(delta, 'VEC3', target=34962)))
            target_names.append(model.morphs[index]['name'] or f'Morph{index}')
        primitives = []
        for material in used:
            begin, count = material['indexStart'], material['indexCount']
            triangles = remap[model.indices[begin:begin + count]].reshape(-1, 3)[:, [0, 2, 1]]
            primitive = dict(attributes=attrs.copy(), material=material['index'], mode=4,
                             indices=writer.array(triangles.reshape(-1), 'SCALAR', 5125, 34963))
            if targets:
                primitive['targets'] = targets
            primitives.append(primitive)
        mesh = dict(name=name, primitives=primitives)
        if targets:
            mesh.update(weights=[0] * len(targets), extras=dict(targetNames=target_names))
        mesh_index = len(g['meshes'])
        g['meshes'].append(mesh)
        node_index = len(nodes)
        nodes[0]['children'].append(node_index)
        nodes.append(dict(name=name, mesh=mesh_index, skin=0))
        mesh_metadata.append(dict(name=name, path='Root/'+name, nodeIndex=node_index, meshIndex=mesh_index,
                                  materials=material_indices, vertices=len(source_indices), targetNames=target_names))
    g.update(nodes=nodes, scenes=[dict(name=model.name or 'Character', nodes=[0])], scene=0)
    writer.write(output)
    paths = {}
    def bone_path(i):
        if i not in paths:
            parent = model.bones[i]['parent']
            paths[i] = (bone_path(parent) if parent >= 0 else 'Root') + '/' + nodes[i + 1]['name']
        return paths[i]
    sidecar = dict(schemaVersion=1, source=dict(file=source.name, sha256=hashlib.sha256(source.read_bytes()).hexdigest(),
                   version=round(model.version, 1), name=model.name, nameEnglish=model.name_en, comment=model.comment,
                   commentEnglish=model.comment_en), coordinates=dict(source='PMX left-handed Y-up', target='glTF right-handed Y-up',
                   metersPerSourceUnit=scale, positionMapping=['x', 'y', '-z'], reverseTriangleWinding=True, flipV=False),
                   counts=dict(vertices=len(positions), triangles=len(model.indices)//3, bones=len(model.bones),
                   materials=len(model.materials), morphs=len(selected_morphs)), bounds=dict(min=positions.min(axis=0).tolist(), max=positions.max(axis=0).tolist()),
                   bones=[dict(**bone, nodeIndex=i+1, path=bone_path(i), positionMeters=bone_positions[i].tolist()) for i, bone in enumerate(model.bones)],
                   materials=model.materials, textures=texture_info, morphs=morph_metadata, meshes=mesh_metadata,
                   physics=dict(coordinateSpace='source PMX units (apply coordinates mapping)', rigidBodies=model.rigid_bodies,
                   joints=model.physics_joints, softBodies=model.soft_bodies),
                   approximations=dict(sdefVertices=int(np.count_nonzero(model.weight_types == 3)),
                   qdefVertices=int(np.count_nonzero(model.weight_types == 4)), skinning='SDEF and QDEF approximated as normalized linear blend skinning',
                   invalidWeightedInfluencesRemoved=invalid_count, unboundVerticesAttachedToRoot=int(unbound.sum()),
                   bakedGroupMorphs='vertex offsets only; non-vertex contributions remain in sidecar',
                   sourceBoneAxes='local axes stored as metadata; skeleton bind orientations are identity',
                   maxTextureSize=max_texture_size,
                   notBaked=['IK solver', 'bone grant transforms', 'bone/UV/material/flip/impulse morphs', 'rigid/soft-body simulation', 'sphere/toon shading']),
                   output=dict(file=output.name, sha256=hashlib.sha256(output.read_bytes()).hexdigest(), bytes=output.stat().st_size))
    output.with_suffix('.pmx.json').write_text(json.dumps(sidecar, ensure_ascii=False, indent=2, allow_nan=False) + '\n')
    return sidecar


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path)
    parser.add_argument('output', type=Path)
    parser.add_argument('--scale', type=float, default=.08, help='Meters per PMX unit (default: .08)')
    parser.add_argument('--morph', action='append', help='Only include this Japanese/English morph name; repeat as needed')
    parser.add_argument('--morph-names', help='Comma-separated morph names; * includes all vertex/group morphs')
    parser.add_argument('--max-texture-size', type=int, help='Optional largest texture edge; omitted keeps all original pixels')
    args = parser.parse_args()
    selected = args.morph or (args.morph_names.split(',') if args.morph_names else None)
    result = convert_pmx(args.source, args.output, args.scale, selected, max_texture_size=args.max_texture_size)
    print(json.dumps(dict(output=str(args.output), **result['counts'], bounds=result['bounds'], approximations=result['approximations']), ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()
