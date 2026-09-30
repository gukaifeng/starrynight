"""Regression cases from distinct author serialization/dependency failures."""
import copy
import pathlib
import sys
import tempfile
import unittest

sys.path.insert(0,str(pathlib.Path(__file__).resolve().parents[1]))
from vrchat_controls import documents,prune_graph
from package_vrchat_library import control_dependencies


class UnityDataTests(unittest.TestCase):
    def test_names_and_packed_hex_are_not_yaml_booleans_or_octal(self):
        text='%YAML 1.1\n%TAG !u! tag:unity3d.com,2011:\n--- !u!319 &31900000\nAvatarMask:\n  m_Name: ON\n  m_Mask: 0000000001000000\n  eyelidsBlendshapes: 00000000ffffffffffffffff\n'
        with tempfile.TemporaryDirectory() as root:
            path=pathlib.Path(root)/'test.mask';path.write_text(text)
            data=documents(path)['31900000']
        self.assertEqual(data['m_Name'],'ON')
        self.assertEqual(data['m_Mask'],'0000000001000000')
        self.assertEqual(data['eyelidsBlendshapes'],'00000000ffffffffffffffff')

    def test_orphaned_sdk_clips_do_not_become_live_dependencies(self):
        def machine(id,states):return dict(id=id,states=states,children=[],any=[],entry=[],machineTransitions=[])
        graph=dict(layers=[dict(root='root')],machines=[machine('root',['live']),machine('orphan',['obsolete'])],
            states=[dict(id='live',motion='good',transitions=[]),dict(id='obsolete',motion='absent',transitions=[])],blends=[],transitions=[])
        result=prune_graph(graph)
        self.assertEqual([s['id'] for s in result['states']],['live'])
        self.assertEqual([m['id'] for m in result['machines']],['root'])

    def test_actual_missing_motion_is_not_silently_dropped(self):
        graph=dict(layers=[dict(synced=-1)],machines=[dict(behaviors=[])],states=[dict(motion='not-in-archive')],blends=[])
        with self.assertRaisesRegex(ValueError,'Missing reachable motion'):
            control_dependencies(dict(controllers=[graph],limitations=[]),dict(motions=[]))

    def test_neutral_sdk_hand_proxy_has_an_explicit_limited_fallback(self):
        identity='14980fc5fe40191418954549174fe63e'
        data=dict(controllers=[dict(layers=[dict(synced=-1)],machines=[dict(behaviors=[])],states=[dict(motion=identity)],blends=[])],limitations=[])
        control_dependencies(data,dict(motions=[]))
        self.assertEqual(data['baselineFallbackMotions'],[identity])
        self.assertEqual(data['limitations'][0]['kind'],'host-neutral-hand-adaptation')
        data['controllers'][0]['states'].append(dict(motion='unreviewed-proxy'))
        with self.assertRaises(ValueError):control_dependencies(data,dict(motions=[]))


if __name__=='__main__':unittest.main()
