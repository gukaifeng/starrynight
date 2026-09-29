import copy,json,pathlib,shutil,sys,tempfile,unittest,zipfile
sys.path.insert(0,str(pathlib.Path(__file__).resolve().parent))
from character_tool import validate,seal,unpack,read_json,inspect_glb
EXAMPLE=pathlib.Path(__file__).resolve().parents[1]/'examples/sample-robot'
class CharacterContractTests(unittest.TestCase):
 def setUp(self):
  self.temp=tempfile.TemporaryDirectory();self.root=pathlib.Path(self.temp.name)/'pkg';shutil.copytree(EXAMPLE,self.root)
 def tearDown(self):self.temp.cleanup()
 def mutate(self,fn):
  p=self.root/'character.json';m=read_json(p);fn(m);p.write_text(json.dumps(m))
 def test_thumbnail_cannot_escape_assets(self):
  self.mutate(lambda m:m['display'].update(thumbnail='../../Bad'))
  with self.assertRaises(ValueError):validate(self.root)
 def test_neutral_is_reserved(self):
  self.mutate(lambda m:m['expressions'][0].update(id='neutral'))
  with self.assertRaisesRegex(ValueError,'reserved'):validate(self.root)
 def test_color_is_portable(self):
  self.mutate(lambda m:m['parameters'][0]['bindings'][0].update(property='_UnityPrivateProperty'))
  with self.assertRaisesRegex(ValueError,'baseColor'):validate(self.root)
 def test_appearance_expression_conflict(self):
  def change(m):
   b=m['expressions'][0]['bindings'][0]
   m['parameters']=[dict(id='bad',label='bad',kind='morph',section='face',min=0,max=1,initial=0,options=[],bindings=[dict(path=b['renderer'],property=b['shape'],materialSlot=0)])]
  self.mutate(change)
  with self.assertRaisesRegex(ValueError,'overlaps'):validate(self.root)
 def test_inspection_has_real_bindings(self):
  data=inspect_glb(self.root/'model.glb')
  self.assertIn('Dance',data['animations'])
  self.assertTrue(any('Sad' in n.get('morphs',[]) for n in data['nodes']))
 def test_reference(self):self.assertEqual(validate(self.root)[0]['id'],'sample-robot')
 def test_source_only_idle_without_added_gaze_or_rules(self):
  def source_only(m):
   m['compatibility']['required']=['core.animation@1']
   m['compatibility']['optional']=[]
   m['actions']=[a for a in m['actions'] if a['id']=='Idle']
   m.pop('posture',None)
   m['behaviors']=[];m['interactions']=[];m['expressions']=[];m['effects']=[];m['parameters']=[]
   m['speech']['proceduralHeadMotion']=False
  self.mutate(source_only)
  result=validate(self.root)[0]
  self.assertFalse(result['speech']['proceduralHeadMotion'])
  self.assertEqual([a['id'] for a in result['actions']],['Idle'])
 def test_gaze_cue_cannot_require_disabled_capability(self):
  def disabled(m):
   m['compatibility']['required'].remove('core.gaze@1')
   m['behaviors'][0]['cues']=[dict(channel='gaze',target='camera',required=True,delay=0,duration=1,intensity=1)]
  self.mutate(disabled)
  with self.assertRaisesRegex(ValueError,'unresolved required cue'):validate(self.root)
 def test_procedural_head_motion_requires_boolean(self):
  self.mutate(lambda m:m['speech'].update(proceduralHeadMotion='false'))
  with self.assertRaises(ValueError):validate(self.root)
 def test_optional_future_extension(self):
  self.mutate(lambda m:m['compatibility']['optional'].append('future.cloth@1'));self.assertTrue(validate(self.root)[1])
 def test_required_future_extension(self):
  self.mutate(lambda m:m['compatibility']['required'].append('future.cloth@1'))
  with self.assertRaisesRegex(ValueError,'unknown required'):validate(self.root)
 def test_unknown_optional_cue(self):
  self.mutate(lambda m:m['behaviors'][0]['cues'].append(dict(channel='vendorAura',target='aurora',required=False,delay=0,duration=1,intensity=1)))
  self.assertTrue(any('ignored optional cue' in x for x in validate(self.root)[1]))
 def test_unknown_required_cue(self):
  self.mutate(lambda m:m['behaviors'][0]['cues'].append(dict(channel='vendorAura',target='aurora',required=True,delay=0,duration=1,intensity=1)))
  with self.assertRaisesRegex(ValueError,'required cue'):validate(self.root)
 def test_hash_tamper(self):
  with (self.root/'model.glb').open('ab') as f:f.write(b'x')
  with self.assertRaisesRegex(ValueError,'size mismatch'):validate(self.root)
 def test_unlisted_file(self):
  (self.root/'extra.txt').write_text('unlisted')
  with self.assertRaisesRegex(ValueError,'unlisted'):validate(self.root)
 def test_duplicate_key(self):
  (self.root/'character.json').write_text('{"id":1,"id":2}')
  with self.assertRaisesRegex(ValueError,'duplicate JSON'):validate(self.root)
 def test_expression_speech_ownership(self):
  self.mutate(lambda m:m['speech']['amplitude'].extend(m['expressions'][0]['bindings']))
  with self.assertRaisesRegex(ValueError,'speech-owned'):validate(self.root)
 def test_file_traversal(self):
  self.mutate(lambda m:m['files'][0].update(path='../model.glb'))
  with self.assertRaises(ValueError):validate(self.root)
 def test_zip_traversal(self):
  path=pathlib.Path(self.temp.name)/'bad.xcp'
  with zipfile.ZipFile(path,'w') as z:z.writestr('../outside','data')
  with self.assertRaisesRegex(ValueError,'unsafe'):unpack(path,pathlib.Path(self.temp.name)/'out')
  self.assertFalse((pathlib.Path(self.temp.name)/'outside').exists())
 def test_sealed_code_rejected(self):
  (self.root/'plugin.cs').write_text('code');seal(self.root)
  with self.assertRaisesRegex(ValueError,'executable'):validate(self.root)
 def test_missing_clip(self):
  self.mutate(lambda m:m['actions'][0].update(clip='Unknown'))
  with self.assertRaisesRegex(ValueError,'absent'):validate(self.root)
 def test_parameter_option_range(self):
  self.mutate(lambda m:m['parameters'][0].update(max=9))
  with self.assertRaisesRegex(ValueError,'integer range'):validate(self.root)
 def test_old_minor_accepts_optional_data(self):
  self.mutate(lambda m:m.update(futureSetting={'a':'value'},extensions={'org.example.aura':{'enabled':True}}))
  self.assertEqual(validate(self.root)[0]['schemaVersion'],1)
 def test_pack_unpack_roundtrip(self):
  path=pathlib.Path(self.temp.name)/'ok.xcp'
  with zipfile.ZipFile(path,'w') as z:
   for f in self.root.rglob('*'):
    if f.is_file():z.write(f,f.relative_to(self.root))
  dest=unpack(path,pathlib.Path(self.temp.name)/'out');self.assertEqual(validate(dest)[0]['id'],'sample-robot')
if __name__=='__main__':unittest.main(verbosity=2)
