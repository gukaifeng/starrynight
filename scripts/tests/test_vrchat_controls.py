"""Regression cases from distinct author serialization/dependency failures."""
import copy
import hashlib
import json
import pathlib
import sys
import tempfile
import unittest
import zipfile

sys.path.insert(0,str(pathlib.Path(__file__).resolve().parents[1]))
from vrchat_controls import documents,prune_graph,BlendReader,prefab_build_requirements
from package_vrchat_library import control_dependencies,require_selected_inspection,ROOT
from vrchat_conversion_signature import require_reusable
from preflight_vrchat_library import official_reference_paths


class UnityDataTests(unittest.TestCase):
    def test_official_reference_audit_is_hash_pinned_and_does_not_extract_assets(self):
        with tempfile.TemporaryDirectory() as folder:
            root=pathlib.Path(folder);archive=root/'sdk.zip';identity='1234567890abcdef1234567890abcdef'
            with zipfile.ZipFile(archive,'w') as out:
                out.writestr('Sample.anim.meta','fileFormatVersion: 2\nguid: '+identity+'\n')
                out.writestr('Sample.anim','not installed or evaluated')
            checksum=hashlib.sha256(archive.read_bytes()).hexdigest()
            self.assertEqual(official_reference_paths(archive,checksum),{identity:'Sample.anim'})
            self.assertEqual(list(root.iterdir()),[archive])
            with self.assertRaisesRegex(ValueError,'hash mismatch'):official_reference_paths(archive,'stale')

    def test_changed_prefab_or_source_cannot_reuse_an_old_inspection(self):
        row=dict(sourceSHA256='archive-one',prefab='Complete.prefab')
        stamp=dict(row,toolSHA256=hashlib.sha256((ROOT/'scripts/vrchat/VrcPortableGeometry.cs').read_bytes()).hexdigest())
        with tempfile.TemporaryDirectory() as folder:
            root=pathlib.Path(folder)
            (root/'geometry.json').write_text(json.dumps(dict(prefab=row['prefab'])))
            (root/'inspection-stamp.json').write_text(json.dumps(stamp))
            require_selected_inspection(row,root)
            for changed in [dict(row,prefab='Simple.prefab'),dict(row,sourceSHA256='archive-two')]:
                with self.assertRaisesRegex(ValueError,'rerun inspect'):require_selected_inspection(changed,root)
            (root/'geometry.json').write_text(json.dumps(dict(prefab='Simple.prefab')))
            with self.assertRaisesRegex(ValueError,'rerun inspect'):require_selected_inspection(row,root)

    def test_nested_author_build_directives_are_not_an_empty_avatar(self):
        files={'root':{'1':dict(m_SourcePrefab={'guid':'nested'}),'2':dict(m_SourcePrefab={'guid':'nested'})},
               'nested':{'3':dict(matchAvatarWriteDefaults=0,layerType=5,animator={'guid':'author-fx'}),
                         '4':dict(m_SourcePrefab={'guid':'root'})}}
        notes=prefab_build_requirements('root',lambda g:files.get(g,{}))
        self.assertEqual(len(notes),1)
        self.assertEqual(notes[0]['kind'],'unsupported-build-merge-animator')
        self.assertEqual(notes[0]['controller'],'author-fx')
        self.assertEqual(prefab_build_requirements('plain',lambda g:{}),[])

    def test_metadata_reuse_rejects_missing_or_changed_conversion_provenance(self):
        signature={'tools':{'reader':'one'},'inputs':{'geometry':'two'}}
        require_reusable(copy.deepcopy(signature),signature)
        for stale in [None,{},dict(signature,tools={'reader':'changed'}),dict(signature,inputs={'geometry':'changed'})]:
            with self.assertRaisesRegex(ValueError,'without --reuse-conversion'):require_reusable(stale,signature)
    def test_external_blend_trees_preserve_subasset_identity_and_nested_refs(self):
        def tree(*refs):return dict(classID=206,m_Childs=[dict(m_Motion=r) for r in refs])
        files={'controller':{'42':tree({'guid':'a','fileID':20600000},{'guid':'b','fileID':20600000})},
               'a':{'20600000':tree({'fileID':20600001}),'20600001':tree({'guid':'clip-a','fileID':7400000})},
               'b':{'20600000':tree({'guid':'clip-b','fileID':7400000})}}
        graph={'blends':[]};reader=BlendReader('controller',lambda g:files.get(g,{}),graph)
        self.assertEqual(reader.motion({'fileID':42}),'42')
        indexed={b['id']:b for b in graph['blends']}
        self.assertEqual(set(indexed),{'42','a:20600000','a:20600001','b:20600000'})
        self.assertEqual(indexed['a:20600000']['children'][0]['motion'],'a:20600001')
        self.assertEqual(indexed['a:20600001']['children'][0]['motion'],'clip-a')
        self.assertEqual(indexed['b:20600000']['children'][0]['motion'],'clip-b')
        reader.motion({'fileID':42});self.assertEqual(len(graph['blends']),4)

    def test_blend_cycle_stays_explicit_for_the_sdk_to_reject(self):
        data={'20600000':dict(classID=206,m_Childs=[dict(m_Motion={'fileID':20600000})])}
        graph={'blends':[]};reader=BlendReader('controller',lambda g:data if g=='a' else {},graph)
        self.assertEqual(reader.motion({'guid':'a','fileID':20600000}),'a:20600000')
        self.assertEqual(graph['blends'][0]['children'][0]['motion'],'a:20600000')

    def test_names_and_packed_hex_are_not_yaml_booleans_or_octal(self):
        text='%YAML 1.1\n%TAG !u! tag:unity3d.com,2011:\n--- !u!319 &31900000\nAvatarMask:\n  m_Name: ON\n  m_Mask: 0000000001000000\n  eyelidsBlendshapes: 00000000ffffffffffffffff\n'
        with tempfile.TemporaryDirectory() as root:
            path=pathlib.Path(root)/'test.mask';path.write_text(text)
            data=documents(path)['31900000']
        self.assertEqual(data['m_Name'],'ON')
        self.assertEqual(data['m_Mask'],'0000000001000000')
        self.assertEqual(data['eyelidsBlendshapes'],'00000000ffffffffffffffff')

    def test_orphaned_sdk_clips_do_not_become_live_dependencies(self):
        def machine(id,states):return dict(id=id,states=states,children=[],any=[],entry=[],machineTransitions=[])
        graph=dict(layers=[dict(root='root')],machines=[machine('root',['live']),machine('orphan',['obsolete'])],
            states=[dict(id='live',motion='good',transitions=[]),dict(id='obsolete',motion='absent',transitions=[])],blends=[],transitions=[])
        result=prune_graph(graph)
        self.assertEqual([s['id'] for s in result['states']],['live'])
        self.assertEqual([m['id'] for m in result['machines']],['root'])

    def test_actual_missing_motion_is_not_silently_dropped(self):
        graph=dict(layers=[dict(synced=-1)],machines=[dict(behaviors=[])],states=[dict(motion='not-in-archive')],blends=[])
        with self.assertRaisesRegex(ValueError,'Missing reachable motion'):
            control_dependencies(dict(controllers=[graph],limitations=[]),dict(motions=[]))

    def test_neutral_sdk_hand_proxy_has_an_explicit_limited_fallback(self):
        identity='14980fc5fe40191418954549174fe63e'
        data=dict(controllers=[dict(layers=[dict(synced=-1)],machines=[dict(behaviors=[])],states=[dict(motion=identity)],blends=[])],limitations=[])
        control_dependencies(data,dict(motions=[]))
        self.assertEqual(data['baselineFallbackMotions'],[identity])
        self.assertEqual(data['limitations'][0]['kind'],'host-neutral-hand-adaptation')
        data['controllers'][0]['states'].append(dict(motion='unreviewed-proxy'))
        with self.assertRaises(ValueError):control_dependencies(data,dict(motions=[]))


if __name__=='__main__':unittest.main()
