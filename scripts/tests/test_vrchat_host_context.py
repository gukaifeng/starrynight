import copy
import pathlib
import sys
import unittest
sys.path.insert(0,str(pathlib.Path(__file__).resolve().parents[1]))
from vrchat_host_context import specialize,condition_known_false

def controller():
    def transition(id,target,parameter,threshold):return dict(id=id,target=target,machine='0',muted=False,conditions=[dict(parameter=parameter,mode=6,threshold=threshold)])
    return dict(id='test',layers=[dict(root='root')],machines=[dict(id='root',default='idle',states=['idle','walk','smile'],children=[],any=['to-walk','to-smile'],entry=[],machineTransitions=[],behaviors=[])],
        states=[dict(id=n,motion=n+'-source',transitions=[],behaviors=[]) for n in ('idle','walk','smile')],blends=[],
        transitions=[transition('to-walk','walk','VelocityX',1),transition('to-smile','smile','GestureLeft',2)])

def controls():return dict(parameters=[dict(name='VelocityX',initial=0)],controls=[],controllers=[controller()],limitations=[])

class HostContextTests(unittest.TestCase):
    def test_only_proven_unreachable_world_motion_is_removed(self):
        data=controls();original=copy.deepcopy(data['controllers'][0]);specialize(data)
        self.assertEqual([s['id'] for s in data['controllers'][0]['states']],['idle','smile'])
        self.assertEqual([s['motion'] for s in data['controllers'][0]['states']],['idle-source','smile-source'])
        self.assertEqual(len(original['states']),3)
    def test_user_controlled_platform_named_parameter_remains_dynamic(self):
        data=controls();data['controls']=[dict(parameter='VelocityX')];specialize(data)
        self.assertEqual(len(data['controllers'][0]['states']),3)
    def test_animated_or_driver_written_parameter_is_not_frozen(self):
        data=controls();specialize(data,['VelocityX']);self.assertEqual(len(data['controllers'][0]['states']),3)
        data=controls();data['controllers'][0]['states'][0]['behaviors']=[dict(kind='parameter-driver',parameters=[dict(name='VelocityX')])]
        specialize(data);self.assertEqual(len(data['controllers'][0]['states']),3)
    def test_menu_gates_are_writable_and_unknown_condition_is_conservative(self):
        data=controls();data['controls']=[dict(parameter='Hat',gates=[dict(parameter='VelocityX',value=1)])]
        specialize(data);self.assertEqual(len(data['controllers'][0]['states']),3)
        self.assertFalse(condition_known_false(dict(parameter='VelocityX',mode=99),{'VelocityX':0}))
    def test_exact_stationary_blend_does_not_require_walk_children(self):
        data=controls();graph=data['controllers'][0];graph['states'][0]['motion']='locomotion'
        graph['blends']=[dict(id='locomotion',kind=0,x='VelocityX',y='',children=[dict(motion='idle-source',threshold=0),dict(motion='walk-source',threshold=1)])]
        specialize(data);self.assertEqual(graph['states'][0]['motion'],'locomotion')
        self.assertEqual(data['controllers'][0]['blends'][0]['children'],[dict(motion='idle-source',threshold=0)])

if __name__=='__main__':unittest.main()
