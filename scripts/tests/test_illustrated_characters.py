"""Geometric acceptance checks for the delivered portrait companion packages.

These inspect final glTF samples and independently reconstruct matrix FK; they
do not reproduce the animation generator's retargeting or sleeve-copy rules.
Run with .local/character-venv/bin/python -m unittest discover -s scripts/tests
         -p test_illustrated_characters.py -v
"""
from pathlib import Path
import json
import sys
import unittest

import numpy as np

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'scripts'))
from prepare_anime_characters import GLB
from vmd_motion import read_vmd

PACKAGES = ('anime-uka', 'anime-velara', 'anime-onyx')


def angular_speed(values, times):
    # Normalize serialized float32 keys in double precision before acos, so
    # rounding in a static quaternion cannot masquerade as angular velocity.
    q = values.astype(np.float64)
    q /= np.linalg.norm(q, axis=1, keepdims=True)
    dots = np.abs(np.sum(q[:-1] * q[1:], axis=1))
    return 2 * np.degrees(np.arccos(np.clip(dots, 0, 1))) / np.diff(times.astype(np.float64))


def rotation_matrix(quaternions):
    q = np.atleast_2d(quaternions)
    x, y, z, w = q.T
    matrix = np.empty((len(q), 3, 3))
    matrix[:, 0, 0] = 1 - 2 * (y*y + z*z)
    matrix[:, 0, 1] = 2 * (x*y - z*w)
    matrix[:, 0, 2] = 2 * (x*z + y*w)
    matrix[:, 1, 0] = 2 * (x*y + z*w)
    matrix[:, 1, 1] = 1 - 2 * (x*x + z*z)
    matrix[:, 1, 2] = 2 * (y*z - x*w)
    matrix[:, 2, 0] = 2 * (x*z - y*w)
    matrix[:, 2, 1] = 2 * (y*z + x*w)
    matrix[:, 2, 2] = 1 - 2 * (x*x + y*y)
    return matrix


def sampled_world(glb, clip):
    """Reconstruct column-vector TRS matrices from the serialized GLB only."""
    g = glb.doc
    channels = {}
    timeline = None
    for channel in clip['channels']:
        sampler = clip['samplers'][channel['sampler']]
        times = glb.array(sampler['input'])[:, 0]
        if timeline is None:
            timeline = times
        if not np.array_equal(times, timeline):
            raise AssertionError('Baked acceptance fixture requires synchronized sample times')
        if channel['target']['path'] != 'weights':
            channels[channel['target']['node'], channel['target']['path']] = glb.array(sampler['output'])
    parents = {child: index for index, node in enumerate(g['nodes']) for child in node.get('children', [])}
    cache = {}
    def world(index):
        if index in cache:
            return cache[index]
        node = g['nodes'][index]
        if 'matrix' in node:
            local = np.tile(np.asarray(node['matrix']).reshape(4, 4).T, (len(timeline), 1, 1))
        else:
            local = np.tile(np.eye(4), (len(timeline), 1, 1))
            q = channels.get((index, 'rotation'), np.tile(node.get('rotation', [0, 0, 0, 1]), (len(timeline), 1)))
            position = channels.get((index, 'translation'), np.tile(node.get('translation', [0, 0, 0]), (len(timeline), 1)))
            scale = channels.get((index, 'scale'), np.tile(node.get('scale', [1, 1, 1]), (len(timeline), 1)))
            local[:, :3, :3] = rotation_matrix(q) * scale[:, None, :]
            local[:, :3, 3] = position
        cache[index] = world(parents[index]) @ local if index in parents else local
        return cache[index]
    return world


class IllustratedCharacterTests(unittest.TestCase):
    def test_delivered_motion_and_mobile_skin_budgets(self):
        """Foot support is measured in world space, not merely fixed leg keys."""
        for package in PACKAGES:
            with self.subTest(package=package):
                glb = GLB(ROOT / 'character-packages/imported' / package / 'model.glb')
                g = glb.doc
                self.assertEqual({x['name'] for x in g['animations']},
                                 {'Idle', 'Hello', 'Yes', 'No', 'Listen', 'Think', 'Talk', 'Relax', 'Thanks'})
                for node in g['nodes']:
                    if 'skin' not in node:
                        continue
                    skin = g['skins'][node['skin']]
                    self.assertLessEqual(len(skin['joints']), 256, package + ' skin bone budget')
                    self.assertEqual(len(glb.array(skin['inverseBindMatrices'])), len(skin['joints']))
                    for primitive in g['meshes'][node['mesh']]['primitives']:
                        weights = glb.array(primitive['attributes']['WEIGHTS_0'])
                        joints = glb.array(primitive['attributes']['JOINTS_0'])
                        self.assertTrue(np.isfinite(weights).all())
                        self.assertTrue(np.allclose(weights.sum(axis=1), 1, atol=2e-5))
                        self.assertLess(int(joints[weights > 1e-6].max()), len(skin['joints']))
                feet = [i for i, node in enumerate(g['nodes'])
                        if node.get('name') in ('左足首', '右足首', '左つま先', '右つま先',
                                                'J_Bip_L_Foot', 'J_Bip_R_Foot', 'J_Bip_L_ToeBase', 'J_Bip_R_ToeBase')]
                self.assertGreaterEqual(len(feet), 2, package + ' identifiable support feet')
                idle = next(clip for clip in g['animations'] if clip['name'] == 'Idle')
                idle_world = sampled_world(glb, idle)
                support = {node: idle_world(node)[0, :3, 3].copy() for node in feet}
                neutral = {}
                for channel in idle['channels']:
                    if channel['target']['path'] == 'rotation':
                        neutral[channel['target']['node']] = glb.array(idle['samplers'][channel['sampler']]['output'])[0]
                for clip in g['animations']:
                    for channel in clip['channels']:
                        sampler = clip['samplers'][channel['sampler']]
                        times = glb.array(sampler['input'])[:, 0]
                        values = glb.array(sampler['output'])
                        self.assertTrue(np.isfinite(times).all() and np.all(np.diff(times) > 0))
                        self.assertTrue(np.isfinite(values).all())
                        self.assertNotEqual(channel['target']['path'], 'scale', package + '/' + clip['name'])
                        if channel['target']['path'] == 'rotation':
                            self.assertTrue(np.allclose(np.linalg.norm(values, axis=1), 1, atol=1e-5))
                            node = channel['target']['node']
                            target = neutral.get(node, g['nodes'][node].get('rotation', [0, 0, 0, 1]))
                            self.assertGreater(abs(float(np.dot(values[0], target))), .99999)
                            self.assertGreater(abs(float(np.dot(values[-1], target))), .99999)
                            name = g['nodes'][node]['name']
                            if any(part in name for part in ('Shoulder', 'UpperArm', 'LowerArm', 'Hand', '肩', '腕', 'ひじ', '手首')):
                                # Conversational gestures should not contain the
                                # source's 818°/s wrist snaps. This is a content
                                # comfort budget, not a universal anatomical law.
                                self.assertLessEqual(float(angular_speed(values, times).max()), 220,
                                                     package + '/' + clip['name'] + '/' + name)
                        elif channel['target']['path'] == 'weights':
                            values = values.reshape(len(times), -1)
                            self.assertTrue(np.allclose(values[0], values[-1], atol=1e-6))
                    world = sampled_world(glb, clip)
                    for node in feet:
                        drift = np.linalg.norm(world(node)[:, :3, 3] - support[node], axis=1).max()
                        self.assertLess(float(drift), .0001, package + '/' + clip['name'] + '/' + g['nodes'][node]['name'])

    def test_uka_sleeves_follow_arm_world_pose(self):
        glb = GLB(ROOT / 'character-packages/imported/anime-uka/model.glb')
        named = {node.get('name'): i for i, node in enumerate(glb.doc['nodes'])}
        for clip in glb.doc['animations']:
            world = sampled_world(glb, clip)
            for side in ('左', '右'):
                for segment in ('腕', 'ひじ', '手首'):
                    with self.subTest(action=clip['name'], joint=side+segment):
                        arm = world(named[side + segment])
                        sleeve = world(named[side + segment + '袖'])
                        error = np.linalg.norm(arm[:, :3, 3] - sleeve[:, :3, 3], axis=1).max()
                        self.assertLess(float(error), .002, 'Sleeve drifts more than 2mm from the corresponding arm joint')
                        self.assertTrue(np.allclose(arm[:, :3, :3], sleeve[:, :3, :3], atol=2e-5),
                                        'Sleeve and arm orientations diverge')

    def test_uka_authored_pose_reflection_and_grant_scope(self):
        """Use reflection matrices as an oracle, not copied quaternion signs."""
        folder = ROOT / 'character-packages/imported/anime-uka'
        glb = GLB(folder / 'model.glb')
        bones, _ = read_vmd(ROOT / '.local/sources/adult-anime-research/uka/motion/stand.vmd')
        idle = next(x for x in glb.doc['animations'] if x['name'] == 'Idle')
        first = {glb.doc['nodes'][channel['target']['node']]['name']:
                 glb.array(idle['samplers'][channel['sampler']]['output'])[0]
                 for channel in idle['channels'] if channel['target']['path'] == 'rotation'}
        reflect = np.diag([1, 1, -1])
        for name in ('上半身', '首', '頭', '左腕', '右腕', '左ひじ', '右ひじ', '右手首'):
            with self.subTest(bone=name):
                source = bones[name][0][1][1]
                source = source / np.linalg.norm(source)
                actual = first.get(name, [0, 0, 0, 1])
                expected = reflect @ rotation_matrix(source)[0] @ reflect
                self.assertTrue(np.allclose(rotation_matrix(actual)[0], expected, atol=2e-5))
        metadata = json.loads((folder / 'model.pmx.json').read_text())
        grants = {bone['name']: bone['grant'] for bone in metadata['bones'] if 'grant' in bone}
        self.assertEqual(set(grants), {'左目', '右目'})
        self.assertTrue(all(abs(x['weight']-.07) < 1e-6 and x['rotation'] and not x['translation'] for x in grants.values()))


if __name__ == '__main__':
    unittest.main(verbosity=2)
