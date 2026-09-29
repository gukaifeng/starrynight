"""Regression for the two Unity animation YAML encodings in supplied avatars."""
import sys
import unittest
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from vrchat_performance_catalog import float_curves, yaml_field


class SourceAnimationYAMLTests(unittest.TestCase):
    def test_legacy_list_unicode_and_dynamic_keys(self):
        text='''  m_FloatCurves:
  - curve:
      m_Curve:
      - serializedVersion: 3
        time: 0
        value: 0
      - serializedVersion: 3
        time: 0.25
        value: 100
    attribute: "blendShape.\\u307e\\u3070\\u305f\\u304d"
    path: Body
    classID: 137
  - curve:
      m_Curve:
      - serializedVersion: 3
        time: 0
        value: 1
    attribute: m_IsActive
    path: "Item_\\u8033"
    classID: 1
  m_PPtrCurves: []
'''
        curves=float_curves(text)
        self.assertEqual(len(curves),2)
        self.assertEqual(curves[0]['attribute'],'blendShape.まばたき')
        self.assertEqual(curves[0]['keys'],[{'time':0.0,'value':0.0},{'time':0.25,'value':100.0}])
        self.assertEqual(curves[1]['path'],'Item_耳')

    def test_modern_list_preserves_zero_values_and_paths(self):
        text='''  m_FloatCurves:
  - serializedVersion: 2
    curve:
      m_Curve:
      - serializedVersion: 3
        time: 0
        value: 0
    attribute: blendShape.eye_close
    path: Body
    classID: 137
  m_PPtrCurves: []
'''
        curve=float_curves(text)[0]
        self.assertEqual(curve['keys'][0]['value'],0)
        self.assertEqual(curve['path'],'Body')
        self.assertEqual(yaml_field('  name: "a b"','name'),'a b')
        self.assertEqual(yaml_field('    path: \n    classID: 95','path'),'')

if __name__=='__main__':unittest.main()
