import copy,json,pathlib,sys,tempfile,shutil,unittest
sys.path.insert(0,str(pathlib.Path(__file__).resolve().parent))
from character_tool import validate,read_json,posture_compatibility
EXAMPLE=pathlib.Path(__file__).resolve().parents[1]/'examples/sample-robot'
class PostureContractTests(unittest.TestCase):
 def setUp(self):
  self.temp=tempfile.TemporaryDirectory();self.root=pathlib.Path(self.temp.name)/'pkg';shutil.copytree(EXAMPLE,self.root)
 def tearDown(self):self.temp.cleanup()
 def modify(self,fn):
  m=read_json(self.root/'character.json');fn(m);(self.root/'character.json').write_text(json.dumps(m));return m
 def test_complete_portable_posture_package(self):self.assertEqual(len(validate(self.root)[0]['posture']['poses']),2)
 def test_profile_requires_capability(self):
  self.modify(lambda m:m['compatibility']['required'].remove('core.posture@1'))
  with self.assertRaisesRegex(ValueError,'core.posture'):validate(self.root)
 def test_profile_requires_minor(self):
  self.modify(lambda m:m['compatibility'].update(minApiMinor=0))
  with self.assertRaisesRegex(ValueError,'minor 1'):validate(self.root)
 def test_pose_clip_must_exist(self):
  self.modify(lambda m:m['posture']['poses'][1].update(clip='Missing'))
  with self.assertRaisesRegex(ValueError,'absent'):validate(self.root)
 def test_parameter_range(self):
  self.modify(lambda m:m['posture']['poses'][1]['parameters'][0].update(initial=30))
  with self.assertRaisesRegex(ValueError,'range'):validate(self.root)
 def test_stand_required(self):
  self.modify(lambda m:m['posture']['poses'].pop(0))
  with self.assertRaisesRegex(ValueError,'include stand'):validate(self.root)
 def test_duplicate_pose(self):
  self.modify(lambda m:m['posture']['poses'].append(m['posture']['poses'][0]))
  with self.assertRaisesRegex(ValueError,'unique'):validate(self.root)
 def test_unknown_action(self):
  self.modify(lambda m:m['posture']['poses'][1]['actions'][0].update(action='NotMade'))
  with self.assertRaisesRegex(ValueError,'action map'):validate(self.root)
 def test_furniture_support_not_claimed(self):
  self.modify(lambda m:m['posture']['poses'][1].update(support='seat'))
  with self.assertRaises(ValueError):validate(self.root)
 def test_unsafe_bone_path(self):
  self.modify(lambda m:m['posture']['bones'].append('../root'))
  with self.assertRaises(ValueError):validate(self.root)
 def test_saved_value_compatibility(self):
  m=read_json(self.root/'character.json');n=copy.deepcopy(m);n['posture']['poses'][1]['parameters'][0]['max']=5
  self.assertTrue(posture_compatibility(m,n));self.assertFalse(posture_compatibility(m,m))
 def test_removed_pose_compatibility(self):
  m=read_json(self.root/'character.json');n=copy.deepcopy(m);n.pop('posture');self.assertTrue(posture_compatibility(m,n))
 def test_old_package_without_postures(self):
  def old(m):m.pop('posture');m['compatibility']['minApiMinor']=0;m['compatibility']['required'].remove('core.posture@1')
  self.modify(old);self.assertEqual(validate(self.root)[0]['compatibility']['minApiMinor'],0)
if __name__=='__main__':unittest.main(verbosity=2)
