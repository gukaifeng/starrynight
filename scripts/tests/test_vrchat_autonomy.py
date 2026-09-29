"""Visible idle conversion preserves source data and grounded lower-body motion."""
import copy
from pathlib import Path
import sys
import unittest
import numpy as np

sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from prepare_anime_characters import GLB, axis_q
from vrchat_autonomy import amplify_rotations, append_visible_idle


class VisibleIdleTests(unittest.TestCase):
    def test_scales_about_first_key_and_keeps_source(self):
        source=axis_q(1,[13,14,13]);saved=source.copy()
        np.testing.assert_allclose(amplify_rotations(source,4),axis_q(1,[13,17,13]),atol=1e-8)
        np.testing.assert_array_equal(source,saved)

    def test_crossing_180_uses_short_arc(self):
        source=axis_q(1,[177,183]);source[1]*=-1
        np.testing.assert_allclose(amplify_rotations(source,3),axis_q(1,[177,195]),atol=1e-8)

    def test_antipodal_quaternions_are_not_motion(self):
        source=axis_q(0,[35,35,35]);source[1]*=-1
        np.testing.assert_allclose(amplify_rotations(source,4),axis_q(0,[35,35,35]),atol=1e-8)

    def test_adaptation_preserves_hips_feet_clips_and_time(self):
        b=GLB.__new__(GLB);b.data=bytearray()
        b.doc=dict(nodes=[dict(name='armature',children=[1]),dict(name='Hips',children=[2,4]),
                         dict(name='Chest',children=[3]),dict(name='Head'),dict(name='Foot')],
                   accessors=[],bufferViews=[],animations=[])
        times=b.add([[0],[1],[2]],'SCALAR')
        original=dict(name='Idle',channels=[],samplers=[])
        for node in [1,2,3,4]:
            out=b.add(axis_q(0,[10,11,10]),'VEC4')
            original['channels'].append(dict(sampler=len(original['samplers']),target=dict(node=node,path='rotation')))
            original['samplers'].append(dict(input=times,output=out,interpolation='LINEAR'))
        pos=b.add([[0,1,0],[0,1.001,0],[0,1,0]],'VEC3')
        original['channels'].append(dict(sampler=len(original['samplers']),target=dict(node=1,path='translation')))
        original['samplers'].append(dict(input=times,output=pos,interpolation='LINEAR'))
        breath=copy.deepcopy(original);breath['name']='VRC_breath'
        b.doc['animations']=[original,breath]
        originals={a['name']:[b.array(s['output']) for s in a['samplers']] for a in b.doc['animations']}
        report=append_visible_idle(b,'kipfel',{'sourceBreathClip':'VRC_breath'})
        self.assertEqual(report['upperBodyGain'],4)
        clips={a['name']:a for a in b.doc['animations']}
        for name in ['Source_Idle','VRC_breath']:
            for s,expected in zip(clips[name]['samplers'],originals['Idle' if name=='Source_Idle' else name]):
                np.testing.assert_array_equal(b.array(s['output']),expected)
        for name in ['Idle','App_VisibleBreath']:
            for ch in clips[name]['channels']:
                s=clips[name]['samplers'][ch['sampler']]
                np.testing.assert_array_equal(b.array(s['input']),[[0],[1],[2]])
                if ch['target']['node'] in [2,3]:
                    np.testing.assert_allclose(b.array(s['output']),axis_q(0,[10,14,10]),atol=1e-7)
                else:
                    np.testing.assert_array_equal(b.array(s['output']),originals['Idle'][ch['sampler']])
        with self.assertRaisesRegex(ValueError,'multiply twice'):
            append_visible_idle(b,'kipfel',{'sourceBreathClip':'VRC_breath'})


if __name__=='__main__':unittest.main()
