import copy
import json
from pathlib import Path
import unittest

from portable_avatar import validate


class PortableAvatarContractTests(unittest.TestCase):
    """Synthetic data for cross-file contracts; actual GLB binding is exercised
    separately by character_tool's importer tests and the private roster check.
    """
    def setUp(self):
        control=dict(id='smile',label='Smile',group='Expression',parameter='Smile',
                     kind='toggle',initial=0,value=1,minimum=0,maximum=1)
        self.controls=dict(schemaVersion=1,profile='mecanim-portable-v1',parameters=[
            dict(name='Smile',kind='float',initial=0)],controls=[control],controllers=[],masks=[],limitations=[])
        self.documents={
            'avatar-controls.json':self.controls,
            'avatar-motions.json':dict(motions=[]),
            'avatar-geometry.json':dict(nodes=[dict(path='Head')]),
            'materials.json':dict(schemaVersion=2,sourceProfile='liltoon-properties-v1',materials=[]),
            'secondary-motion.json':dict(schemaVersion=2,strands=[],colliders=[])}
        self.manifest=dict(compatibility=dict(required=['core.avatar-controls@1'],optional=['core.secondary-motion@2']),
            files=[dict(path=p) for p in self.documents],source=dict(model='model.glb'),
            performance=dict(options=[dict(control=copy.deepcopy(control))]))

    def check(self):
        def read(path):
            return self.documents[path.name] if path.name in self.documents else json.loads(path.read_text())
        validate(Path('.'),self.manifest,read,lambda root,p:root/p,
                 lambda _:dict(nodes=[dict(path='Avatar'),dict(path='Avatar/Head')]))

    def test_known_profile_accepts_optional_future_metadata(self):
        self.controls['futureMetadata']=dict(reviewedBy='fixture');self.check()

    def test_legacy_package_does_not_need_new_sidecars(self):
        self.manifest=dict(compatibility=dict(required=[],optional=[]),performance=dict(options=[dict(control={})]))
        self.check()

    def test_missing_sealed_sidecar_is_rejected(self):
        self.manifest['files']=self.manifest['files'][:-1]
        with self.assertRaisesRegex(ValueError,'sealed file list'):self.check()

    def test_stale_native_menu_binding_is_rejected(self):
        self.manifest['performance']['options'][0]['control']['parameter']='Other'
        with self.assertRaisesRegex(ValueError,'stale embedded control'):self.check()

    def test_unapproved_empty_motion_substitution_is_rejected(self):
        self.controls['baselineFallbackMotions']=['0'*32]
        with self.assertRaisesRegex(ValueError,'unreviewed motion fallback'):self.check()

    def test_recursive_blend_is_rejected_before_unity_import(self):
        self.controls['controllers']=[dict(states=[],machines=[],transitions=[],layers=[],
            blends=[dict(id='loop',children=[dict(motion='loop')])])]
        with self.assertRaisesRegex(ValueError,'blend tree cycle'):self.check()

    def test_nonfinite_transform_is_rejected(self):
        self.documents['avatar-motions.json']['motions']=[dict(guid='clip',duration=1,times=[0],tracks=[
            dict(path='Head',positions=[dict(x=0,y=float('inf'),z=0)],rotations=[dict(x=0,y=0,z=0,w=1)],scales=[dict(x=1,y=1,z=1)])])]
        with self.assertRaisesRegex(ValueError,'invalid transform sample'):self.check()


if __name__=='__main__':unittest.main()
