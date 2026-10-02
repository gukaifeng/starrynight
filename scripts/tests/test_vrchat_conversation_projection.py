"""Projection must omit unsupported layers, never invent an SDK animation."""
import unittest
from copy import deepcopy
import sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from vrchat_conversation_projection import project

def fixture():
    graph=dict(playable=5, layers=[dict(name='face',root='m',synced=-1)],
        machines=[dict(id='m',states=['s'],children=[],behaviors=[],any=['t'],entry=[],machineTransitions=[])],
        states=[dict(id='s',motion='author',transitions=[])],blends=[],
        transitions=[dict(id='t',target='s',machine='0',conditions=[dict(parameter='Face',mode=6,threshold=1)])])
    return dict(schemaVersion=1,profile='mecanim-portable-v1',parameters=[],masks=[],controllers=[graph],
        controls=[dict(id='face',label='Smile',parameter='Face'),dict(id='dance',label='Dance',parameter='VRCEmote')])

class ProjectionTests(unittest.TestCase):
    def test_author_face_is_retained_without_modifying_source(self):
        source=fixture();before=deepcopy(source)
        projected,evidence=project(source,dict(motions=[dict(guid='author')]))
        self.assertEqual(source,before)
        self.assertEqual([c['id'] for c in projected['controls']],['face'])
        self.assertEqual(evidence['unavailableControls'][0]['id'],'dance')
        self.assertEqual(projected['controllers'][0]['states'][0]['motion'],'author')
    def test_missing_motion_removes_layer_without_a_placeholder(self):
        projected,evidence=project(fixture(),dict(motions=[]))
        self.assertFalse(projected['controllers'])
        self.assertFalse(projected['controls'])
        self.assertEqual(evidence['omittedLayers'][0]['missing'],['author'])
        self.assertEqual(projected['baselineFallbackMotions'],[])
    def test_stationary_host_does_not_enable_a_walking_base(self):
        source=fixture();source['controllers'][0]['playable']=0
        projected,evidence=project(source,dict(motions=[dict(guid='author')]))
        self.assertFalse(projected['controllers'])
        self.assertEqual(evidence['omittedLayers'][0]['reason'],'host-stationary-body-baseline')

if __name__=='__main__':unittest.main()
