import pathlib,sys,unittest
sys.path.insert(0,str(pathlib.Path(__file__).resolve().parents[1]))
from vrchat_ai_semantics import hints,classify

def clip(guid,name,shape):return dict(guid=guid,name=name,objects=[],curves=[dict(component='UnityEngine.SkinnedMeshRenderer',property='blendShape.'+shape,keys=[dict(value=100)])])

class SemanticsTests(unittest.TestCase):
    def test_same_hand_value_uses_actual_source_expression(self):
        controls=dict(parameters=[dict(name='GestureLeft',initial=0)],controls=[dict(id='left3',parameter='GestureLeft',kind='toggle',value=3)],
            controllers=[dict(playable=5,states=[dict(id='face',motion='source')],transitions=[dict(target='face',conditions=[dict(parameter='GestureLeft',mode=6,threshold=3)])])])
        for name,shape,intent in [('Sad','eye_sad','sad'),('Happy','mouth_smile','soft_smile')]:
            values,evidence=hints(controls,dict(motions=[clip('source',name,shape)]))
            self.assertEqual(values['left3']['intent'],intent);self.assertEqual(evidence['left3']['motions'][0]['name'],name)
    def test_clothes_and_ambiguous_effects_are_not_automatic(self):
        self.assertIsNone(classify(clip('x','Happy','breasts_big')))
        self.assertIsNone(classify(clip('x','Unknown','shape_001')))
        data=clip('x','Smile','mouth_smile');data['objects']=[{}];self.assertIsNone(classify(data))

if __name__=='__main__':unittest.main()
