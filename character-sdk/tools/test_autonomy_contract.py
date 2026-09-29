"""Optional idle capability must fail safely before a mobile build."""
import copy
import json
from pathlib import Path
import unittest
from unittest.mock import patch
from jsonschema import Draft202012Validator
from character_tool import validate_autonomy

ROOT=Path(__file__).resolve().parents[2]

class AutonomyContractTests(unittest.TestCase):
    def setUp(self):
        self.manifest=json.loads((ROOT/'character-sdk/examples/sample-robot/character.json').read_text())
        self.manifest['compatibility']['optional']+=['core.autonomy@1','core.performance@1']
        self.manifest['speech']={'mode':'amplitude','amplitude':[{'renderer':'armature/Body','shape':'vrc.v.aa','weight':1}],'visemes':[]}
        self.manifest['performance']={'schemaVersion':1,'groups':[{'id':'pose','label':'姿势','symbol':'figure.stand'}],
            'defaults':[],'options':[{'id':'stand','group':'pose','label':'站立','kind':'preset'}]}
        self.manifest['autonomy']={'schemaVersion':1,'blink':{
            'bindings':[{'renderer':'armature/Body','shape':'eye_close','weight':1}],
            'intervals':[3,5],'closeSeconds':.09,'closedSeconds':.02,'openSeconds':.14,'firstDelay':2,
            'suppressGroups':['expression'],'suppressOptions':[]},
            'breathing':{'clip':'VRC_kipfel_breath','bones':['armature/Hips'],'poseOptions':['stand']}}
        self.inventory={'animations':['VRC_kipfel_breath'],'nodes':[{'path':'armature/Body','morphs':['eye_close','vrc.v.aa']}]+
            [{'path':p} for p in self.manifest['autonomy']['breathing']['bones']]}
        self.schema=Draft202012Validator(json.loads((ROOT/'character-sdk/schemas/character.schema.json').read_text()))
    def validate(self):
        self.schema.validate(self.manifest)
        with patch('character_tool.inspect_glb',return_value=self.inventory):validate_autonomy(self.manifest,Path('fixture.glb'))
    def test_valid_source_profile(self):self.validate()
    def test_missing_lid_rejected(self):
        self.inventory['nodes'][0]['morphs']=[]
        with self.assertRaisesRegex(ValueError,'lid missing'):self.validate()
    def test_speech_overlap_rejected(self):
        self.manifest['autonomy']['blink']['bindings'][0]['shape']='vrc.v.aa'
        with self.assertRaisesRegex(ValueError,'overlaps speech'):self.validate()
    def test_unknown_static_pose_rejected(self):
        self.manifest['autonomy']['breathing']['poseOptions']=['missing']
        with self.assertRaisesRegex(ValueError,'pose option invalid'):self.validate()
    def test_unknown_expression_priority_rejected(self):
        self.manifest['autonomy']['blink']['suppressOptions']=['missing']
        with self.assertRaisesRegex(ValueError,'suppression option missing'):self.validate()
    def test_unbounded_blink_timing_rejected(self):
        self.manifest['autonomy']['blink']['intervals']=[0]
        self.assertTrue(list(self.schema.iter_errors(self.manifest)))
    def test_duplicate_lid_rejected(self):
        b=self.manifest['autonomy']['blink']['bindings'];b.append(copy.deepcopy(b[0]))
        with self.assertRaisesRegex(ValueError,'duplicate autonomy lid'):self.validate()

if __name__=='__main__':unittest.main()
