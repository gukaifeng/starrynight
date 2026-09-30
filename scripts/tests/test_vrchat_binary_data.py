"""Binary build outputs must retain exact object and state graph identities."""
import copy
import json
from pathlib import Path
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from vrchat_binary_data import normalize,unity_guid,verify_native_references
from vrchat_controls import controller_documents,build,documents


class BinaryDataTests(unittest.TestCase):
    def test_text_asset_with_bom_stays_on_the_yaml_path(self):
        with tempfile.TemporaryDirectory() as folder:
            path=Path(folder)/'menu.asset'
            path.write_text('\ufeff%YAML 1.1\n%TAG !u! tag:unity3d.com,2011:\n--- !u!114 &11400000\nMonoBehaviour:\n  m_Name: ON\n',encoding='utf-8')
            self.assertEqual(documents(path)['11400000']['m_Name'],'ON')

    def test_editor_guid_nibbles_are_not_uuid_endian_words(self):
        # Independently checked against the pinned NDMF source .cs.meta file.
        raw=bytes.fromhex('e44e17a37ce1f4a819a145ed954b28d9')
        self.assertEqual(unity_guid(raw),'4ee4713ac71e4f8a911a54de59b4829d')
        with self.assertRaises(ValueError):unity_guid(b'short')

    def test_pointers_maps_and_nulls_preserve_binary_semantics(self):
        ext=[SimpleNamespace(guid=bytes.fromhex('e44e17a37ce1f4a819a145ed954b28d9'),type=3)]
        value={'map':[({'m_FileID':0,'m_PathID':7},[{'m_FileID':1,'m_PathID':-12}])],
               'null':{'m_FileID':0,'m_PathID':0}}
        converted=normalize(value,ext)
        self.assertEqual(converted['map'][0],dict(first={'fileID':7},second=[dict(fileID=-12,guid='4ee4713ac71e4f8a911a54de59b4829d',type=3)]))
        self.assertEqual(converted['null'],{'fileID':0})
        with self.assertRaises(ValueError):normalize({'m_FileID':2,'m_PathID':7},ext)

    def test_multiple_controllers_and_external_states_are_not_conflated(self):
        controller=lambda root:dict(classID=91,m_AnimatorLayers=[dict(m_StateMachine=root)])
        files={'a':{'91':controller({'fileID':1}),'92':controller({'guid':'b','fileID':1}),
                    '1':dict(classID=1107,m_Name='unrelated')},
               'b':{'1':dict(classID=1107,m_DefaultState={'fileID':2},
                    m_ChildStates=[dict(m_State={'fileID':2})]),
                    '2':dict(classID=1102,m_Name='selected',m_Motion={'fileID':74},
                        m_Transitions=[{'guid':'a','fileID':3}])},
               }
        files['a']['3']=dict(classID=1101,m_DstState={'guid':'b','fileID':2},m_DstStateMachine={'fileID':0})
        original=copy.deepcopy(files)
        selected,docs=controller_documents('a','92',lambda guid:files.get(guid,{}))
        self.assertEqual(selected['m_AnimatorLayers'][0]['m_StateMachine'],{'fileID':'b:1'})
        self.assertEqual(set(docs),{'b:1','b:2','3'})
        self.assertEqual(docs['b:2']['m_Motion'],{'guid':'b','fileID':74})
        self.assertEqual(docs['3']['m_DstState'],{'fileID':'b:2'})
        self.assertEqual(files,original)
        with self.assertRaisesRegex(ValueError,'exact controller'):controller_documents('a','missing',lambda g:files.get(g,{}))

    def test_native_evidence_rejects_missing_and_extra_links(self):
        evidence=dict(objects=[dict(guid='a',fileID=10,references=[dict(property='m_Children.Array.data[0]',guid='b',fileID=12)])])
        docs={'10':dict(classID=91,m_Children=[dict(guid='b',fileID=12)])}
        index={'a':{'extractedPath':'a'}}
        result=verify_native_references(evidence,index,lambda _:docs)
        self.assertEqual(result,dict(objects=1,references=1,status='passed'))
        for changed in [{'10':dict(classID=91,m_Children=[])},
                        {'10':dict(classID=91,m_Children=[dict(guid='b',fileID=12)],extra=dict(fileID=99))},{}]:
            with self.assertRaises(ValueError):verify_native_references(evidence,index,lambda _:changed)

    def test_sibling_menus_in_one_container_are_independent(self):
        root=dict(classID=114,VisemeBlendShapes=[],expressionsMenu={'guid':'bundle','fileID':10},
            expressionParameters={'guid':'bundle','fileID':20},baseAnimationLayers=[],specialAnimationLayers=[])
        menu=lambda name,child:dict(name=name,type=3,subMenu={'fileID':child})
        toggle=lambda name,param:dict(name=name,type=2,parameter={'name':param},value=1)
        files={'root':{'1':root},'bundle':{'10':dict(controls=[menu('脸',11),menu('衣服',12)]),
            '11':dict(controls=[toggle('笑','Smile')]),'12':dict(controls=[toggle('外套','Coat')]),
            '20':dict(parameters=[dict(name='Smile',valueType=2,defaultValue=0),dict(name='Coat',valueType=2,defaultValue=1)])}}
        with tempfile.TemporaryDirectory() as folder:
            stage=Path(folder)
            assets=[dict(guid=k,path=k+'.prefab' if k=='root' else k+'.asset',extension='.prefab' if k=='root' else '.asset',extractedPath=k) for k in files]
            (stage/'source-audit.json').write_text(json.dumps(dict(archives=[dict(unityPackages=[dict(assets=assets)])])))
            with patch('vrchat_controls.documents',side_effect=lambda p:files[str(p)]):
                controls,_=build(stage,dict(prefab='root.prefab',role='test'))
            self.assertEqual([(x['label'],x['group'],x['initial']) for x in controls['controls']],[('笑','脸',0),('外套','衣服',1)])
            self.assertEqual(len({x['id'] for x in controls['controls']}),2)
            audit=json.loads((stage/'source-audit.json').read_text());audit['bake']={'role':'test'}
            (stage/'source-audit.json').write_text(json.dumps(audit))
            with patch('vrchat_controls.documents',side_effect=lambda p:files[str(p)]):
                before,_=build(stage,dict(prefab='root.prefab',role='test'))
            root['expressionsMenu']['guid']='new-container';root['expressionParameters']['guid']='new-container'
            files['new-container']=files.pop('bundle')
            asset=audit['archives'][0]['unityPackages'][0]['assets'][1]
            asset.update(guid='new-container',path='new-container.asset',extractedPath='new-container')
            (stage/'source-audit.json').write_text(json.dumps(audit))
            with patch('vrchat_controls.documents',side_effect=lambda p:files[str(p)]):
                after,_=build(stage,dict(prefab='root.prefab',role='test'))
            self.assertEqual([x['id'] for x in before['controls']],[x['id'] for x in after['controls']])


if __name__=='__main__':unittest.main()
