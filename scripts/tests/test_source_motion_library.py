import unittest
from pathlib import Path
import sys

sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from prepare_source_motion_library import project_motion

class SourceProjectionTests(unittest.TestCase):
    def setUp(self):
        self.geometry={'nodes':[{'path':'Head'},{'path':'Arm'}],'skins':[{'path':'Head'}],'human':[{'human':'LeftUpperArm','path':'Arm'}]}
        self.model={'nodes':[{'path':'Avatar/Head','morphs':['Smile']}]}
        self.motion={'guid':'a'*32,'name':'Smile','duration':1,'loop':False,'times':[0,1], 'tracks':[],'curves':[],'objects':[]}
    def project(self):return project_motion(self.motion,self.geometry,self.model,'Head')
    def curve(self,component,path,prop,value):return dict(component=component,path=path,property=prop,keys=[dict(time=0,value=value)])
    def test_authored_dynamic_face_is_not_flattened(self):
        c=self.curve('UnityEngine.SkinnedMeshRenderer','Head','blendShape.Smile',30)
        c['keys'].append(dict(time=1,value=100));self.motion['curves']=[c]
        result,omitted=self.project();self.assertEqual(result['curves'][0]['keys'],c['keys']);self.assertFalse(omitted)
    def test_missing_platform_channels_are_never_empty_supported_clips(self):
        self.motion['curves']=[self.curve('UnityEngine.Animator','','VRCEmote',1)]
        self.assertIsNone(self.project()[0]);self.assertEqual(self.project()[1][0]['reason'],'platform-parameter')
    def test_missing_nodes_and_required_face_hiding_are_reported(self):
        self.motion['curves']=[self.curve('UnityEngine.GameObject','Missing','m_IsActive',1),self.curve('UnityEngine.GameObject','Head','m_IsActive',0)]
        result,omitted=self.project();self.assertIsNone(result);self.assertEqual(len(omitted),2)
    def test_static_tracks_are_losslessly_compressed(self):
        self.motion['times']=[0,.5,1]
        self.motion['tracks']=[dict(path='Arm',positions=[{'x':0,'y':1,'z':0}]*3,scales=[{'x':1,'y':1,'z':1}]*3,rotations=[{'x':0,'y':0,'z':0,'w':1}]*3)]
        result,_=self.project();self.assertEqual(result['tracks'][0]['times'],[0,1]);self.assertEqual(len(result['tracks'][0]['rotations']),2)
    def test_humanoid_channels_are_not_evaluated_again(self):
        self.motion['humanoid']=True;self.motion['humanoidProperties']=['Chest Front-Back']
        self.motion['curves']=[self.curve('UnityEngine.Animator','','Chest Front-Back',.1),self.curve('UnityEngine.SkinnedMeshRenderer','Head','blendShape.Smile',30)]
        result,omitted=self.project();self.assertEqual(len(result['curves']),1);self.assertFalse(omitted)
    def test_unnamed_original_gets_stable_readable_label(self):
        self.motion['name']='';self.motion['curves']=[self.curve('UnityEngine.SkinnedMeshRenderer','Head','blendShape.Smile',30)]
        self.assertEqual(self.project()[0]['name'],'未命名片段 aaaaaaaa')
    def test_omitted_callback_never_claims_complete_source_behavior(self):
        self.motion['omittedEventCount']=1;self.motion['curves']=[self.curve('UnityEngine.SkinnedMeshRenderer','Head','blendShape.Smile',30)]
        projected,omitted=self.project();self.assertFalse(projected['projectionComplete']);self.assertEqual(omitted[0]['reason'],'animation-events-are-not-executable')

if __name__=='__main__':unittest.main()
