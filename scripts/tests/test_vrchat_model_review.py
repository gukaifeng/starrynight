"""Real import regressions using synthetic data; no author assets or Unity process."""
import copy
import hashlib
import json
from pathlib import Path
import struct
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from audit_vrchat_archives import prefab_inventory
from vrchat_blink import select_blink_bindings
from vrchat_physics import build_physics
from vrchat_portable_convert import portable_secondary


class BlinkTests(unittest.TestCase):
    def select(self, names, descriptor=None, values=None):
        with tempfile.TemporaryDirectory() as directory:
            binary=Path(directory)/'geometry.bin'
            values=values or [.01]*len(names)
            binary.write_bytes(b''.join(struct.pack('<fff',v,0,0) for v in values))
            skin=dict(path='Face',shapes=[dict(name=n,frames=[dict(position=dict(
                type='f32',width=3,count=1,offset=i*12))]) for i,n in enumerate(names)])
            return select_blink_bindings(descriptor or {},skin,binary)

    def test_unused_descriptor_index_zero_never_selects_mouth(self):
        descriptor=dict(customEyeLookSettings=dict(eyelidType=0,eyelidsBlendshapes='000000000000000000000000'),
                        VisemeBlendShapes=['mouth_a'])
        bindings,origin=self.select(['mouth_a','vrc.Blink'],descriptor)
        self.assertEqual([b['shape'] for b in bindings],['vrc.Blink'])
        self.assertEqual(origin,'source-neutral-eyelid')

    def test_declared_eyelid_is_verified_and_mouth_collision_is_rejected(self):
        descriptor=dict(customEyeLookSettings=dict(eyelidType=2,eyelidsBlendshapes='01000000ffffffffffffffff'))
        self.assertEqual(self.select(['mouth_a','AuthorLid'],descriptor)[0][0]['shape'],'AuthorLid')
        descriptor['VisemeBlendShapes']=['AuthorLid']
        self.assertEqual(self.select(['mouth_a','AuthorLid'],descriptor)[0],[])

    def test_exact_pair_closes_both_eyes_on_one_renderer(self):
        bindings,origin=self.select(['bs.eye_close_L','bs.eye_close_R'])
        self.assertEqual(len(bindings),2)
        self.assertEqual({b['renderer'] for b in bindings},{'Avatar/Face'})
        self.assertEqual(origin,'source-paired-eyelids')
        self.assertEqual(self.select(['bs.eye_close_L'])[0],[])

    def test_zero_shape_is_skipped_and_expression_alias_is_not_a_blink(self):
        bindings,_=self.select(['vrc.blink','まばたき'],values=[0,.01])
        self.assertEqual(bindings[0]['shape'],'まばたき')
        self.assertEqual(self.select(['vrc.blink_animation_pupil_big','blink_highlight_up','wink'])[0],[])
        self.assertEqual(self.select(['blink','blink'])[0],[])

    def test_nonfinite_and_out_of_bounds_data_fail(self):
        with self.assertRaisesRegex(ValueError,'Nonfinite'):
            self.select(['blink'],values=[float('nan')])
        with tempfile.TemporaryDirectory() as directory:
            binary=Path(directory)/'geometry.bin';binary.write_bytes(struct.pack('<fff',.01,0,0))
            span=dict(type='f32',width=3,count=1,offset=0)
            skin=dict(path='Face',shapes=[dict(name='blink',frames=[dict(position=span),dict(position=dict(span,offset=12))])])
            with self.assertRaisesRegex(ValueError,'exceeds'):
                select_blink_bindings({},skin,binary)


class PhysicsTests(unittest.TestCase):
    def test_variant_resolves_base_physics_in_another_package(self):
        base_guid='1'*32;variant_guid='2'*32
        base='''%YAML 1.1
%TAG !u! tag:unity3d.com,2011:
--- !u!1 &10
GameObject:
  m_Name: Root
  m_IsActive: 1
--- !u!4 &1
Transform:
  m_GameObject: {fileID: 10}
  m_Father: {fileID: 0}
--- !u!1 &20
GameObject:
  m_Name: Hair
  m_IsActive: 1
--- !u!4 &2
Transform:
  m_GameObject: {fileID: 20}
  m_Father: {fileID: 1}
--- !u!114 &30
MonoBehaviour:
  m_GameObject: {fileID: 20}
  m_Enabled: 1
  rootTransform: {fileID: 2}
  pull: 0.2
  ignoreTransforms: []
  colliders: []
'''
        variant='''%YAML 1.1
%TAG !u! tag:unity3d.com,2011:
--- !u!1001 &40
PrefabInstance:
  m_Modification:
    m_TransformParent: {fileID: 0}
  m_SourcePrefab: {fileID: 100100000, guid: '''+base_guid+''', type: 3}
'''
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory)
            def asset(guid,name,text):
                path=root/name;path.write_text(text)
                return dict(guid=guid,path='Assets/'+name,extractedPath=str(path),
                            sha256=hashlib.sha256(path.read_bytes()).hexdigest(),prefab=prefab_inventory(text))
            b=asset(base_guid,'base.prefab',base);v=asset(variant_guid,'variant.prefab',variant)
            audit=dict(archives=[dict(unityPackages=[dict(assets=[v]),dict(assets=[b])])])
            nodes=[dict(path=path,sourceGUID=base_guid,sourceID=i,active=True,scale=dict(x=1,y=1,z=1),
                        sources=[dict(guid=base_guid,transformID=i,gameObjectID=go)])
                   for path,i,go in [('',1,10),('Hair',2,20),('Hair/Tip',3,21)]]
            (root/'role-prefab.json').write_text(json.dumps(dict(role='role',prefab=v['path'],nodes=nodes)))
            (root/'role-fbx.json').write_text(json.dumps(dict(nodes=nodes)))
            result=build_physics(audit,root)['roles'][0]
            self.assertEqual(result['unresolved'],[])
            self.assertEqual(result['chains'][0]['rootPath'],'Hair')
            self.assertEqual(result['chains'][0]['transformPaths'],['Hair','Hair/Tip'])
            conflict=copy.deepcopy(b);conflict['sha256']='changed'
            audit['archives'][0]['unityPackages'].append(dict(assets=[conflict]))
            with self.assertRaisesRegex(ValueError,'Conflicting source asset GUID'):
                build_physics(audit,root)

    def test_overlapping_endpoints_are_distinct_and_rebuild_is_idempotent(self):
        geometry=dict(nodes=[dict(path=''),dict(path='Hair')])
        document=dict(nodes=[dict(name='Avatar',children=[1]),dict(name='Hair')])
        chains=[dict(enabled=True,activeInHierarchy=True,rootPath='Hair',transformPaths=['Hair'],
                     parameters=dict(radius=.005),endpointPositionLocal=dict(x=0,y=length,z=0)) for length in (.03,.015)]
        source=dict(chains=chains,colliders=[dict(enabled=True,activeInHierarchy=True,rootPath='Hair',
                    shape=dict(shapeType=0,insideBounds=False,radius=.7,height=0,position=None,rotation=None))])
        with tempfile.TemporaryDirectory() as directory,patch('vrchat_physics.build_physics',return_value=dict(roles=[source])):
            root=Path(directory);(root/'source-audit.json').write_text('{}')
            first,_=portable_secondary(root,'role',SimpleNamespace(doc=document),geometry)
            snapshot=copy.deepcopy(document)
            second,_=portable_secondary(root,'role',SimpleNamespace(doc=document),geometry)
            self.assertEqual(document,snapshot)
            self.assertEqual(first,second)
            self.assertEqual(len({n['name'] for n in document['nodes']}),len(document['nodes']))
            self.assertTrue(first['colliders'][0]['localRadius'])
            self.assertEqual(first['colliders'][0]['radius'],.7)


if __name__=='__main__':unittest.main()
