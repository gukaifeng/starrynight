#!/usr/bin/env python3
"""Convert pinned VRM 1 portrait avatars for private local XCP preview.

The model metadata prohibits redistribution and artistic modifications. This
adapter preserves the author's geometry, colours and textures; it only supplies
the host's rig, animation and render bindings. Do not publish the output packs.
No downloaded application code is executed.
"""
from __future__ import annotations
import argparse
import copy
import hashlib
import json
import math
import subprocess
from pathlib import Path

import numpy as np
from prepare_anime_characters import (GLB, ROOT, SOURCES as MOTION_SOURCES, MOTIONS,
                                     axis_q, motion_tracks, multiply, normalize,
                                     paths, resample, slerp, smooth)

SOURCES = ROOT / '.local/sources/adult-anime-research/nitral-personal'
LOCK = ROOT / 'assets/characters/portrait-vrm-sources.lock.json'
ROLES = [
    dict(id='anime-velara', source='Velara', name='维拉', symbol='moon.stars',
         description='黑发盘起、身着金色礼服的幻想伙伴。带着从容的微笑，愿意陪你把今天慢慢说完。',
         invitation='今晚的时间，留一点给我们吧。', tagline='把夜色，聊成温柔的日常'),
    dict(id='anime-onyx', source='Onyx', name='安宁', symbol='moon',
         description='戴着细框眼镜的安静伙伴。喜欢音乐和夜晚，认真倾听，也有自己的小小幽默。',
         invitation='你来了。今天想从哪件事聊起？', tagline='你的心事，我会认真听'),
]
IDENTITY = np.array([0., 0., 0., 1.])


def write_json(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n')


def world_rest_rotations(g):
    parents = {c: i for i, n in enumerate(g['nodes']) for c in n.get('children', [])}
    rotations = {}

    def world(node):
        if node not in rotations:
            n = g['nodes'][node]
            if 'matrix' in n:
                raise ValueError('Matrix-form rest transform needs explicit decomposition')
            rotations[node] = normalize(multiply(world(parents[node]) if node in parents else IDENTITY,
                                                  np.array(n.get('rotation', IDENTITY))))
        return rotations[node]

    for node in range(len(g['nodes'])):
        world(node)
    return parents, rotations


def retarget_rotation(normalized_keys, node, parents, world):
    # VRMA is normalized in humanoid rest axes. A VRM 1 source can have arbitrary
    # local joint rotations. Undo its parent's rest basis, then restore the
    # bone's world-rest basis (the inverse of VRMA normalization).
    parent = world[parents[node]] if node in parents else IDENTITY
    return normalize(multiply(multiply(parent * [-1, -1, -1, 1], normalized_keys), world[node]))


def smooth_rotations(values, times, sigma=.16):
    """Zero-phase Gaussian on continuous quaternion hemispheres, then normalize.

    All upper-body channels use the same physical-time kernel, preserving their
    coordination. A 160 ms sigma removes the source wrist's abrupt 22-degree
    sample jump without lagging one joint behind another. Static support and eye
    bones bypass this filter. Endpoint posture is reapplied after filtering.
    """
    values = normalize(np.array(values, dtype=np.float64, copy=True))
    for i in range(1, len(values)):
        if np.dot(values[i - 1], values[i]) < 0:
            values[i] *= -1
    step = float(np.mean(np.diff(times)))
    radius = int(math.ceil(3 * sigma / step))
    offsets = np.arange(-radius, radius + 1) * step
    kernel = np.exp(-.5 * (offsets / sigma) ** 2)
    kernel /= kernel.sum()
    padded = np.pad(values, ((radius, radius), (0, 0)), mode='edge')
    result = np.stack([np.convolve(padded[:, axis], kernel, mode='valid') for axis in range(4)], axis=1)
    if np.any(np.linalg.norm(result, axis=1) < .1):
        raise ValueError('Quaternion smoothing spans an ambiguous hemisphere')
    return normalize(result)


def material_kind(name):
    if 'Lens' in name:
        return 'glass'
    if 'HAIR' in name:
        return 'hair'
    if 'SKIN' in name:
        return 'skin'
    if 'EYE' in name:
        return 'eye'
    if 'FACE' in name:
        return 'face'
    if 'CLOTH' in name:
        return 'cloth'
    return 'accessory'


def color(values):
    return dict(zip(('r', 'g', 'b', 'a'), list(values[:3]) + [values[3] if len(values) > 3 else 1]))


def prepare_materials(b, folder):
    g = b.doc
    (folder / 'textures').mkdir(exist_ok=True)

    def extract(texture, kind):
        if texture is None:
            return ''
        index = texture['index'] if isinstance(texture, dict) else texture
        image = g['images'][g['textures'][index]['source']]
        assert image['mimeType'] == 'image/png'
        view = g['bufferViews'][image['bufferView']]
        name = f'textures/{kind}_{index}.png'
        start = view.get('byteOffset', 0)
        (folder / name).write_bytes(b.data[start:start + view['byteLength']])
        return name

    result = []
    for m in g['materials']:
        pbr = m['pbrMetallicRoughness']
        toon = m.get('extensions', {}).get('VRMC_materials_mtoon', {})
        result.append(dict(name=m['name'], kind=material_kind(m['name']),
                           texture=extract(pbr.get('baseColorTexture'), 'base'),
                           normal=extract(m.get('normalTexture'), 'normal'),
                           emission=extract(m.get('emissiveTexture'), 'emission'),
                           emissionColor=color(m.get('emissiveFactor', [0, 0, 0])),
                           matcap=extract(toon.get('matcapTexture'), 'matcap'),
                           shadeTexture=extract(toon.get('shadeMultiplyTexture'), 'shade'),
                           shadeColor=color(toon.get('shadeColorFactor', [1, 1, 1])),
                           matcapColor=color(toon.get('matcapFactor', [1, 1, 1])),
                           rimColor=color(toon.get('parametricRimColorFactor', [0, 0, 0])),
                           matcapStrength=1 if toon.get('matcapTexture') else 0,
                           bumpScale=m.get('normalTexture', {}).get('scale', 1),
                           color=color(pbr.get('baseColorFactor', [1, 1, 1, 1])),
                           alphaMode=m.get('alphaMode', 'OPAQUE'), cutoff=m.get('alphaCutoff', .5),
                           normalScale=m.get('normalTexture', {}).get('scale', 1),
                           shadingShift=toon.get('shadingShiftFactor', 0),
                           shadingToony=toon.get('shadingToonyFactor', .9),
                           authoredMToon=copy.deepcopy(toon)))
        m.pop('extensions', None)
    write_json(folder / 'materials.json', dict(schemaVersion=1, preserveAuthoredAppearance=True, materials=result))


def prepare_secondary_motion(g, vrm_springs, path_map, folder):
    parents = {c: i for i, n in enumerate(g['nodes']) for c in n.get('children', [])}
    strands = {}
    groups = sorted(vrm_springs.get('springs', []), key=lambda s: s.get('name') != 'Hair')
    for group in groups:
        # No exaggerated breast dynamics; use authored hair and garment chains.
        if group.get('name') == 'Bust':
            continue
        joints = group.get('joints', [])
        for a, z in zip(joints, joints[1:]):
            node, tip = a['node'], z['node']
            if parents.get(tip) != node:
                raise ValueError('Spring tip is not an immediate child')
            if np.linalg.norm(g['nodes'][tip].get('translation', [0, 0, 0])) < .0001:
                continue
            strands[path_map[node]] = dict(bone=path_map[node], tip=path_map[tip],
                                          radius=min(.018, a.get('hitRadius', .01)),
                                          angle=16 if group.get('name') == 'Hair' else 8)
    if len(strands) > 128:
        raise ValueError(f'Spring budget exceeded: {len(strands)}')
    colliders = []
    for collider in vrm_springs.get('colliders', []):
        shape = collider['shape']
        if 'sphere' not in shape:
            raise ValueError('Capsule collider needs a bounded sphere conversion')
        sphere = shape['sphere']; o = sphere.get('offset', [0, 0, 0])
        colliders.append(dict(bone=path_map[collider['node']],
                              offset=dict(x=-o[0], y=o[1], z=o[2]), radius=sphere['radius']))
    if len(colliders) > 64:
        raise ValueError('Collider budget exceeded')
    write_json(folder / 'secondary-motion.json', dict(schemaVersion=1, strands=list(strands.values()), colliders=colliders))
    return len(strands), len(colliders)


def prepare_animations(b, vrm, role_index, arm_clearance_degrees=5):
    g = b.doc
    human = {k: v['node'] for k, v in vrm['humanoid']['humanBones'].items()}
    parents, world = world_rest_rotations(g)
    idle = motion_tracks('idle')
    baseline = {bone: resample(track, np.array([0]))[0] for (bone, kind), track in idle.items()
                if kind == 'rotation' and bone in human and 'Eye' not in bone}
    g['animations'] = []
    durations = {}
    # Standard VRM 1 faces +Z, the same forward as the normalized VRMA. glTFast
    # owns the one handedness flip. There is deliberately no VRM 0 Y-half-turn.
    hip = np.array(g['nodes'][human['hips']]['translation'])
    for action, name, *_ in MOTIONS:
        tracks = motion_tracks(name)
        source_duration = max(t[-1] for t, v in tracks.values())
        duration = 30. if action == 'Idle' else source_duration
        speed = 1.22 if action == 'Hello' else 1.
        times = np.linspace(0, duration, int(math.ceil(duration * 30)) + 1)
        durations[action] = float(duration / speed)
        elapsed = times / speed
        # The raise-hand source begins far from conversational idle. Give that
        # full coordinated shoulder/elbow transition one second to settle.
        attack = 1.05 if action == 'Hello' else .55
        fade = smooth(elapsed / attack) * smooth((duration / speed - elapsed) / .7)
        clip = dict(name=action, samplers=[], channels=[])
        time_index = b.add(times / speed, 'SCALAR')

        def channel(node, target, values, kind):
            output = b.add(values, kind)
            clip['channels'].append(dict(sampler=len(clip['samplers']), target=dict(node=node, path=target)))
            clip['samplers'].append(dict(input=time_index, output=output, interpolation='LINEAR'))

        for bone, node in human.items():
            if bone not in baseline:
                continue
            sample_times = np.mod(times * (1. if role_index == 0 else .93), source_duration) if action == 'Idle' else times
            q = resample(tracks.get((bone, 'rotation'), idle[(bone, 'rotation')]), sample_times)
            if action == 'Idle':
                loop = smooth(sample_times / .55) * smooth((source_duration - sample_times) / .65)
                q = slerp(baseline[bone], q, loop)
                if bone in ('spine', 'chest', 'upperChest', 'neck', 'head', 'leftShoulder', 'rightShoulder',
                            'leftUpperArm', 'rightUpperArm', 'leftLowerArm', 'rightLowerArm', 'leftHand', 'rightHand'):
                    relaxed = motion_tracks('relaxed').get((bone, 'rotation'))
                    if relaxed is not None:
                        rq = resample(relaxed, np.mod(times * .4, relaxed[0][-1]))
                        mix = (smooth((times - 3) / 3) * smooth((13 - times) / 3)
                               + smooth((times - 17) / 3) * smooth((28 - times) / 4)) * .22
                        q = slerp(q, rq, mix)
                if bone in ('spine', 'chest'):
                    breath = np.sin(times / (5. + role_index * .6) * np.pi * 2) * (.6 if bone == 'chest' else -.16)
                    q = multiply(axis_q(0, breath), q)
            # Preserve support and foot contact throughout conversational gestures.
            if bone == 'hips' or any(k in bone for k in ('UpperLeg', 'LowerLeg', 'Foot', 'Toes')):
                q = np.tile(baseline[bone], (len(times), 1))
            else:
                q = smooth_rotations(q, elapsed)
            q = slerp(baseline[bone], q, fade)
            if bone in ('leftUpperArm', 'rightUpperArm'):
                q = multiply(axis_q(2, np.full(len(times), arm_clearance_degrees if bone.startswith('left') else -arm_clearance_degrees)), q)
            q = retarget_rotation(q, node, parents, world)
            for j in range(1, len(q)):
                if np.dot(q[j - 1], q[j]) < 0:
                    q[j] *= -1
            if not np.isfinite(q).all():
                raise ValueError('Non-finite retargeted rotation')
            channel(node, 'rotation', q, 'VEC4')
        channel(human['hips'], 'translation', np.tile(hip, (len(times), 1)), 'VEC3')
        # Independent blink morphs never animate eye bones or overwrite gaze.
        for bind in vrm['expressions']['preset']['blink']['morphTargetBinds']:
            node = bind['node']; mesh = g['meshes'][g['nodes'][node]['mesh']]
            weights = np.zeros((len(times), len(mesh['extras']['targetNames'])))
            for at in ([2.6, 6.9, 11.1, 11.46, 16.3, 21.8, 27.0] if action == 'Idle' else [2.6, 6.9]):
                phase = times / speed - at - role_index * .31
                value = np.where(phase < 0, smooth((phase + .09) / .09), 1 - smooth(phase / .18))
                weights[:, bind['index']] = np.maximum(weights[:, bind['index']], value * bind['weight'])
            # A blink scheduled near a short clip's end must release completely
            # before the next action. Apply the envelope to morphs, not just rig.
            weights *= (smooth(elapsed / .14) * smooth((duration / speed - elapsed) / .22))[:, None]
            channel(node, 'weights', weights.flatten(), 'SCALAR')
        g['animations'].append(clip)
    return durations


def package(role, index, source_lock):
    source = SOURCES / (role['source'] + '.vrm')
    if hashlib.sha256(source.read_bytes()).hexdigest() != source_lock['sha256']:
        raise ValueError('Pinned model SHA-256 mismatch: ' + source.name)
    b = GLB(source); g = b.doc
    vrm = copy.deepcopy(g['extensions']['VRMC_vrm'])
    assert vrm['specVersion'] == '1.0'
    assert vrm['meta']['authors'] == ['Nitral'] and vrm['meta']['allowRedistribution'] is False
    human = {k: v['node'] for k, v in vrm['humanoid']['humanBones'].items()}
    p = paths(g)
    folder = ROOT / 'character-packages/imported' / role['id']
    folder.mkdir(parents=True, exist_ok=True)
    prepare_materials(b, folder)
    strand_count, collider_count = prepare_secondary_motion(g, g['extensions']['VRMC_springBone'], p, folder)
    durations = prepare_animations(b, vrm, index)
    g.pop('extensions', None); g.pop('extensionsRequired', None); g.pop('extensionsUsed', None)
    # The texture references retain their standard glTF UV transforms; declare
    # that extension even after removing the VRM-only runtime extensions.
    g['extensionsUsed'] = ['KHR_texture_transform']
    g['asset']['generator'] = 'Starry private-preview VRM 1 adapter 1.0; source appearance by Nitral'
    b.write(folder / 'model.glb')
    write_json(folder / 'source-meta.json', vrm['meta'])
    manifest = json.loads((ROOT / 'character-packages/imported/anime-vita/character.json').read_text())
    manifest.update(id=role['id'], packageId='app.starry.characters.' + role['id'], packageVersion='1.0.0')
    manifest['display'] = dict(name=role['name'], originalName=role['source'] + ' · Nitral',
        description=role['description'], invitation=role['invitation'], tagline=role['tagline'], symbol=role['symbol'],
        thumbnail='Anime_' + role['source'].lower(), cardIdentifier='card-' + role['id'], openIdentifier='open-' + role['id'],
        style='anime', thumbnailScale=1, order=70 + index * 10)
    manifest['source'] = dict(format='glb', model='model.glb', scale=1, yaw=0)
    manifest['rig'] = dict(head=p[human['head']], neck=p[human['neck']], leftEye=p[human['leftEye']],
                           rightEye=p[human['rightEye']], headRenderer='Face', conversationStart=.63)
    manifest['gaze'] = dict(yaw=34, up=14, down=18, eyeYaw=8, eyeUp=5, eyeDown=7)
    manifest['interactions'] = [dict(id='head', bone=p[human['head']], renderer='Face', radius=.12,
                                      eventName='interaction.head.tap')]

    def binding(preset, intensity=1):
        return [dict(renderer=p[v['node']], shape=g['meshes'][g['nodes'][v['node']]['mesh']]['extras']['targetNames'][v['index']],
                     weight=v['weight'] * intensity)
                for v in vrm['expressions']['preset'][preset]['morphTargetBinds']]

    manifest['expressions'] = [dict(id=e, bindings=binding(preset, weight)) for e, preset, weight in
                               [('joy', 'happy', .55), ('care', 'relaxed', .4), ('sad', 'sad', .5),
                                ('anger', 'angry', .45), ('blink', 'blink', 1)]]
    manifest['speech'] = dict(mode='amplitude', amplitude=binding('aa', .6),
                              visemes=[dict(id=v, bindings=binding(v, .72)) for v in ('aa', 'ih', 'ou', 'ee', 'oh')])
    # Preserve author's artistic appearance. No hair, skin, face or outfit edits.
    manifest['parameters'] = []
    manifest['compatibility']['optional'] = [x for x in manifest['compatibility']['optional'] if x != 'core.parameters@1']
    manifest['license'] = dict(name='VRM Public License 1.0 (metadata restrictions) AND Apache-2.0',
        authors=['Nitral / Nitral Studios', 'High Fidelity, Inc.', 'Vircadia contributors', 'Overte e.V.',
                 'Undi95 / Hanami (animation conversion)'], notice='LICENSE.txt', source=source_lock['url'])
    manifest['files'] = []
    manifest['extensions']['app.starry.private-preview'] = dict(version=1, redistributionAllowed=False,
                                                               appearanceEditingAllowed=False, metadata='source-meta.json')
    notice = ('PRIVATE LOCAL PREVIEW ONLY — DO NOT REDISTRIBUTE\n\n'
              + role['name'] + ' / ' + role['source'] + '\nOriginal avatar: Nitral. Copyright 2024 Nitral Studios.\n'
              + source_lock['url'] + '\n\nLicense: VRM Public License 1.0, subject to the embedded metadata.\n'
              'https://vrm.dev/licenses/1.0/\n'
              'Credit is required. Redistribution is prohibited. Artistic modifications are prohibited.\n'
              'This is a technical format/runtime adapter for local private testing. Author geometry,\n'
              'base colours, textures and facial shapes are retained; appearance editing is disabled.\n'
              'Do not publish these packages, include them in a public repository, or distribute an app\n'
              'containing these assets without separate written authorization from the author.\n'
              'The complete embedded permission settings are preserved in source-meta.json.\n\n'
              'Animation data: Overte-derived VRMA, Apache-2.0, distributed by Undi95 / Hanami.\n'
              'Host bindings: VRM 1 inverse-rest retargeting, planted support, eased transitions and blinks.\n\n'
              + (MOTION_SOURCES / 'Overte-LICENSE').read_text() + '\n\n'
              + (MOTION_SOURCES / 'APACHE-2.0.txt').read_text())
    (folder / 'LICENSE.txt').write_text(notice)
    (folder / 'NOTICE.md').write_text((MOTION_SOURCES / 'Hanami-NOTICE.md').read_text())
    (folder / 'UPSTREAM-README.md').write_text((SOURCES / 'README.upstream.md').read_text())
    report = dict(id=role['id'], source=source.name, materials=len(g['materials']),
                  triangles=sum(len(b.array(pr['indices'])) // 3 for mesh in g['meshes'] for pr in mesh['primitives']),
                  springSegments=strand_count, colliders=collider_count, bytes=(folder / 'model.glb').stat().st_size,
                  actions=durations, sourceYaw=0, privatePreview=True)
    (folder / 'README.md').write_text('# ' + role['name'] + ' / ' + role['source'] + '\n\n'
        '原作：Nitral。仅供本机私人预览，禁止公开再分发；不提供外观改作功能。\n\n'
        '重建：`.local/character-venv/bin/python scripts/prepare_portrait_vrm.py`。\n'
        'VRM 1 非标准 rest 骨轴经过逆基变换，眼球独立，源纹理和脸部 morph 保留。\n'
        '目前仅站姿会话；九个连续曲线动作的源采样率不等于屏幕帧率。\n\n'
        + json.dumps(report, ensure_ascii=False, indent=2) + '\n')
    write_json(folder / 'character.json', manifest)
    subprocess.run([str(ROOT / '.local/character-sdk-venv/bin/python'),
                    str(ROOT / 'character-sdk/tools/character_tool.py'), 'seal', str(folder)], check=True)
    return report


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--only', choices=[r['source'] for r in ROLES])
    args = parser.parse_args()
    upstream = json.loads((SOURCES / 'sources.json').read_text())
    selected = [m for m in upstream['models'] if m['name'] in {r['source'] for r in ROLES}]
    write_json(LOCK, dict(schemaVersion=1, revision=upstream['revision'], usage='private-local-preview-only',
                          modelLicense='https://vrm.dev/licenses/1.0/', redistributionAllowed=False,
                          appearanceEditingAllowed=False, sources=selected,
                          animationsLock='assets/characters/anime-sources.lock.json'))
    # Revalidate all pinned motion inputs used by the shared normalization helper.
    motion_lock = json.loads((ROOT / 'assets/characters/anime-sources.lock.json').read_text())
    for item in motion_lock['sources']:
        if item['file'].endswith('.vrma'):
            if hashlib.sha256((MOTION_SOURCES / item['file']).read_bytes()).hexdigest() != item['sha256']:
                raise ValueError('Pinned animation SHA-256 mismatch: ' + item['file'])
    reports = [package(r, i, next(s for s in selected if s['name'] == r['source']))
               for i, r in enumerate(ROLES) if args.only is None or args.only == r['source']]
    print(json.dumps(reports, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()
