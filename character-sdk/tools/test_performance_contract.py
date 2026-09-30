"""Reject performance data that Unity's CharacterPerformanceContract rejects.

Mocking GLB inventory isolates protocol validation; real avatar package validation
runs separately so parser/schema or conversion changes cannot hide this boundary.
"""
import copy
import pathlib
import sys
import unittest
from unittest.mock import patch
sys.path.insert(0,str(pathlib.Path(__file__).resolve().parent))
from character_tool import validate_performances


def track(shape='smile'):
    return {'renderer':'Rig/Face','shape':shape,'keys':[{'time':0,'value':0},{'time':1,'value':1}]}


class PerformanceContractTests(unittest.TestCase):
    def setUp(self):
        self.m={'compatibility':{'required':[],'optional':['core.performance@1']},'performance':{
            'schemaVersion':1,'groups':[{'id':'expression','label':'表情'},{'id':'appearance','label':'配件'}],
            'defaults':[{'path':'Rig/Face','visible':True}],
            'options':[{'id':'smile','group':'expression','label':'微笑','kind':'preset','duration':1,
                        'morphs':[{'renderer':'Rig/Face','shape':'smile','weight':1}],'morphTracks':[track()]},
                       {'id':'hat','group':'appearance','label':'帽子','kind':'toggle','defaultOn':True,
                        'visibility':[{'path':'Rig/Hat','visible':True}],'offVisibility':[{'path':'Rig/Hat','visible':False}]}]}}
        self.inventory={'animations':['Idle','Wave'],'nodes':[{'path':'Rig','name':'Rig'},
            {'path':'Rig/Face','morphs':['smile','blink'],'materials':['Face']},
            {'path':'Rig/Hat','materials':['Hat']}]}
    def validate(self):
        with patch('character_tool.inspect_glb',return_value=self.inventory):
            validate_performances(self.m,pathlib.Path('unused.glb'))
    def reject(self,change,pattern):
        original=copy.deepcopy(self.m)
        try:
            change(self.m['performance'])
            with self.assertRaisesRegex(ValueError,pattern):self.validate()
        finally:self.m=original
    def test_valid_profile_and_nonloop_continuation(self):
        self.validate()
        source=self.m['performance']['options'][0];source.update(kind='motion',next='rest')
        self.m['performance']['options'].append({'id':'rest','group':'expression','label':'自然','kind':'preset'})
        self.validate()
    def test_v2_extensible_groups_require_explicit_host_capability(self):
        p=self.m['performance'];p['schemaVersion']=2
        p['groups'] += [{'id':'author.extra'+str(i),'label':'扩展表现'} for i in range(8)]
        p['options'].append({'id':'extra','group':'author.extra0','label':'灵光','kind':'preset'})
        self.m['compatibility']['required']=['core.performance@2'];self.validate()
        self.m['compatibility']['required']=[]
        with self.assertRaisesRegex(ValueError,'matching core.performance'):self.validate()
    def test_total_track_budget_cannot_be_split_across_options(self):
        def exceed(p):
            base=p['options'][0];base['morphTracks']=[track(),track('blink')]
            p['options']=[dict(copy.deepcopy(base),id='variant-'+str(i)) for i in range(129)]
        self.reject(exceed,'profile exceeds 256 morph tracks')
    def test_ai_semantics_are_bounded_and_conflicts_reference_real_groups(self):
        self.m['performance']['options'][0]['ai']=dict(intent='smile',effects=['轻轻微笑'],moods=['happy'],automatic=True,speechCompatible=True,conflicts=['appearance'])
        self.validate()
        self.reject(lambda p:p['options'][0]['ai'].update(conflicts=['unknown']),'AI moods/conflicts')
        self.reject(lambda p:p['options'][0]['ai'].update(effects=[]),'AI effects')
        self.reject(lambda p:p['options'][0]['ai'].update(cooldownSeconds=float('nan')),'AI policy')
    def test_next_must_be_nonloop_motion_and_target_nontoggle(self):
        p=self.m['performance'];p['options'].append({'id':'rest','group':'expression','label':'自然','kind':'preset'})
        self.reject(lambda p:p['options'][0].update(next='rest'),'invalid continuation')
        p['options'][0]['kind']='motion'
        self.reject(lambda p:p['options'][0].update(next='rest',loop=True),'invalid continuation')
        self.reject(lambda p:(p['options'][0].update(next='rest'),p['options'][2].update(kind='toggle')),'invalid continuation')
        self.reject(lambda p:p['options'][0].update(next='hat'),'invalid continuation')
        self.reject(lambda p:p['options'][0].update(next='smile'),'invalid continuation')
    def test_non_toggle_group_defaults_are_exclusive(self):
        def conflict(p):
            p['options'][0]['defaultOn']=True
            p['options'].append(dict(copy.deepcopy(p['options'][0]),id='another-smile'))
        self.reject(conflict,'conflicting non-toggle defaults')
        self.m['performance']['options'].append(dict(copy.deepcopy(self.m['performance']['options'][1]),id='hat-two'))
        self.validate()  # independent toggle defaults are intentionally allowed
    def test_off_fields_require_toggle(self):
        self.reject(lambda p:p['options'][0].update(offMorphs=[{'renderer':'Rig/Face','shape':'smile','weight':0}]),'off bindings require toggle')
        self.reject(lambda p:p['options'][0].update(offVisibility=[{'path':'Rig/Face','visible':False}]),'off bindings require toggle')
        self.reject(lambda p:p['options'][0].update(offClip='Idle',bones=['Rig']),'offClip requires toggle')
    def test_duplicate_bindings_are_rejected_per_array(self):
        fields=[('defaults',None),('morphs',0),('morphTracks',0),('visibility',1),('offVisibility',1)]
        for field,index in fields:
            with self.subTest(field=field):
                def duplicate(p):
                    values=p[field] if index is None else p['options'][index][field]
                    values.append(copy.deepcopy(values[0]))
                self.reject(duplicate,'duplicate')
        self.reject(lambda p:p['options'][1].update(offMorphs=[{'renderer':'Rig/Face','shape':'smile','weight':0}]*2),'duplicate')
        self.reject(lambda p:p['options'][0].update(bones=['Rig','Rig']),'duplicate bone')
    def test_name_path_bounds_and_unicode_match_runtime_utf16(self):
        self.reject(lambda p:p['options'][0].update(label=' '),'option fields')
        self.reject(lambda p:p['groups'][0].update(label='a'*129),'group is invalid')
        self.reject(lambda p:p['options'][0].update(id='😀'*65),'option id')
        for path in ['a'*129,'/Rig','Rig//Face','Rig/./Face','Rig/../Face','Rig\\Face']:
            with self.subTest(path=path):
                self.reject(lambda p:p['defaults'][0].update(path=path),'path is invalid')
        self.reject(lambda p:p['options'][0]['morphs'][0].update(shape='a'*129),'binding path/name')
        self.reject(lambda p:p['options'][0]['morphTracks'][0].update(renderer='a'*129),'track path/name')
        self.m['performance']['options'][0]['label']='😀'*64
        self.validate()
    def test_clip_and_motion_must_have_driven_resources(self):
        self.reject(lambda p:p['options'][0].update(clip='Idle'),'bone bindings')
        self.reject(lambda p:p['options'][0].update(kind='motion',morphTracks=[]),'motion needs')
        self.reject(lambda p:p['options'][0].update(clip=' '*2,bones=['Rig']),'valid name')
    def test_keys_and_normalized_values(self):
        self.reject(lambda p:p['options'][0]['morphTracks'][0].update(keys=[]),'must contain keys')
        self.reject(lambda p:p['options'][0]['morphTracks'][0]['keys'][1].update(time=0),'strictly increase')
        self.reject(lambda p:p['options'][0]['morphTracks'][0]['keys'][1].update(value=float('nan')),'time/value')
        self.reject(lambda p:p['options'][0]['morphs'][0].update(weight=1.01),'binding path/name/weight')
    def test_existing_glb_binding_check_remains_active(self):
        self.reject(lambda p:p['options'][0]['morphs'][0].update(shape='missing'),'shape absent')
        self.reject(lambda p:p['options'][0].update(clip='Missing',bones=['Rig']),'clip absent')
        self.reject(lambda p:p['options'][1]['visibility'][0].update(path='Rig/Missing'),'renderer absent')

if __name__=='__main__':unittest.main(verbosity=2)
