import unittest,tempfile,shutil,json,sys,zipfile
from pathlib import Path
from environment_tool import validate,seal,compare,unpack
ROOT=Path(__file__).resolve().parents[2]
class EnvironmentTests(unittest.TestCase):
 def setUp(self):
  self.temp=tempfile.TemporaryDirectory();self.root=Path(self.temp.name)/'source';shutil.copytree(ROOT/'environment-sdk/examples/courtyard',self.root)
 def tearDown(self):self.temp.cleanup()
 def edit(self,fn):
  p=self.root/'environment.json';m=json.loads(p.read_text());fn(m);p.write_text(json.dumps(m));return m
 def test_valid_source(self):self.assertEqual(validate(self.root)[0]['id'],'courtyard')
 def test_corrupt_resource(self):
  (self.root/'environment.glb').write_bytes(b'bad')
  with self.assertRaisesRegex(ValueError,'integrity'):validate(self.root)
 def test_path_traversal(self):
  self.edit(lambda m:m['files'][0].update(path='../escape'))
  with self.assertRaises(ValueError):validate(self.root)
 def test_nested_manifest_is_hashed(self):
  nested=self.root/'notes';nested.mkdir();(nested/'environment.json').write_text('{}');seal(self.root)
  self.assertEqual(len(validate(self.root)[0]['files']),3)
  (nested/'environment.json').write_text('{"changed":true}')
  with self.assertRaisesRegex(ValueError,'integrity'):validate(self.root)
 def test_unity_metadata_rejected(self):
  (self.root/'foreign.meta').write_text('guid: invalid');seal(self.root)
  with self.assertRaisesRegex(ValueError,'unsupported'):validate(self.root)
 def test_unknown_required(self):
  self.edit(lambda m:m['compatibility']['required'].append('environment.weather@9'))
  with self.assertRaisesRegex(ValueError,'required'):validate(self.root)
 def test_optional_future(self):
  self.edit(lambda m:m['compatibility']['optional'].append('environment.weather@9'));self.assertEqual(len(validate(self.root)[1]),2)
 def test_no_code(self):
  (self.root/'run.cs').write_text('ignored');seal(self.root)
  with self.assertRaisesRegex(ValueError,'Executable'):validate(self.root)
 def test_no_builtin_external(self):
  self.edit(lambda m:m['source'].update(kind='builtin'))
  with self.assertRaisesRegex(ValueError,'GLB'):validate(self.root)
 def test_palette_ids_unique(self):
  self.edit(lambda m:m['palettes'].append(m['palettes'][0]))
  with self.assertRaisesRegex(ValueError,'palette'):validate(self.root)
 def test_saved_palette_removal(self):
  old=validate(self.root)[0];new=json.loads(json.dumps(old));new['palettes'].pop();new['packageVersion']='1.1.0'
  with self.assertRaisesRegex(ValueError,'palette'):compare(old,new)
 def test_safe_additive_update(self):
  old=validate(self.root)[0];new=json.loads(json.dumps(old));new['packageVersion']='1.1.0';new['display']['description']='new';compare(old,new)
 def test_changes_need_version(self):
  old=validate(self.root)[0];new=json.loads(json.dumps(old));new['display']['name']='changed'
  with self.assertRaisesRegex(ValueError,'version'):compare(old,new)
 def test_archive_traversal(self):
  file=Path(self.temp.name)/'bad.xep'
  with zipfile.ZipFile(file,'w') as z:z.writestr('../escape','x')
  with self.assertRaises(ValueError):unpack(file,Path(self.temp.name)/'unpacked')
 def test_roundtrip_archive(self):
  file=Path(self.temp.name)/'ok.xep'
  with zipfile.ZipFile(file,'w') as z:
   for p in self.root.iterdir():z.write(p,p.name)
  self.assertEqual(validate(unpack(file,Path(self.temp.name)/'unpacked'))[0]['id'],'courtyard')
if __name__=='__main__':unittest.main(verbosity=2)
