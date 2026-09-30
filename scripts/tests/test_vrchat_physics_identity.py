"""Stripped bones and repeated prefab instances must not bind to the root."""
import pathlib
import sys
import unittest
sys.path.insert(0,str(pathlib.Path(__file__).resolve().parents[1]))
from vrchat_physics import PhysicsResolver

class PhysicsIdentityTests(unittest.TestCase):
    def resolver(self):
        p=dict(transforms=[],strippedSourceObjects=[dict(fileID=900,classID=1,source=dict(guid='fbx',fileID=20))],prefabInstances=[])
        a=dict(guid='prefab',path='Avatar.prefab',prefab=p)
        nodes=[dict(path='',sourceGUID='prefab',sourceID=1,sources=[dict(guid='prefab',transformID=1,gameObjectID=2)]),
               dict(path='Head/Hair',sourceGUID='prefab',sourceID=3,sources=[dict(guid='fbx',transformID=10,gameObjectID=20)])]
        return PhysicsResolver([a],dict(prefab='Avatar.prefab',nodes=nodes),dict(nodes=[]))

    def test_stripped_bone_component_resolves_exact_gameobject(self):
        r=self.resolver();o=r.occurrences[0]
        self.assertEqual(r.component_owner_path(o,dict(gameObject=dict(fileID=900))),'Head/Hair')
        self.assertEqual(r.resolve_transform(dict(guid='fbx',fileID=10),o),'Head/Hair')
        self.assertIsNone(r.component_owner_path(o,dict(gameObject=dict(fileID=999))))

    def test_repeated_prefab_identity_uses_occurrence_not_last_node(self):
        r=self.resolver();r.source_objects[('prop',20)]={'Left/Prop','Right/Prop'}
        self.assertEqual(r.source_path('prop',20,'Left',objects=True),'Left/Prop')
        self.assertIsNone(r.source_path('prop',20,'',objects=True))

    def test_variant_root_can_keep_renamed_outer_root(self):
        r=self.resolver();r.source_transforms[('base',5)]={''}
        child=dict(guid='base',prefab=dict(transforms=[dict(fileID=5,parent=dict(fileID=0))]))
        self.assertEqual(r.nested_prefix(r.occurrences[0],{},child),'')

if __name__=='__main__':unittest.main()
