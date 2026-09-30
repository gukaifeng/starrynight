import gzip
import hashlib
import io
import json
from pathlib import Path
import sys
import tarfile
import tempfile
import unittest
import zipfile

sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from vrchat_batch_audit import Auditor, Blocks, checked_name, text_bytes
from vrchat_batch_stage import stage_package


def unitypackage(path='Assets/Avatar/Face.prefab', text=b'%YAML 1.1\n--- !u!1 &1\nGameObject:\n  m_Name: Face\n'):
    output=io.BytesIO()
    with tarfile.open(fileobj=output,mode='w:gz') as archive:
        for name,data in [('asset',text),('asset.meta',b'fileFormatVersion: 2\nguid: '+b'a'*32+b'\n'),('pathname',path.encode())]:
            info=tarfile.TarInfo('a'*32+'/'+name);info.size=len(data)
            archive.addfile(info,io.BytesIO(data))
    return output.getvalue()


class BatchAuditTests(unittest.TestCase):
    def test_nested_package_stream_and_verified_stage(self):
        with tempfile.TemporaryDirectory() as temporary:
            root=Path(temporary);source=root/'avatar.zip'
            inner=io.BytesIO()
            with zipfile.ZipFile(inner,'w') as archive:
                archive.writestr('角色.unitypackage',unitypackage())
                archive.writestr('License.txt','local test fixture')
            with zipfile.ZipFile(source,'w') as archive:archive.writestr('inside.zip',inner.getvalue())
            report=Auditor(root/'audit').audit(source)
            package=report['inventory']['packages'][0]
            self.assertEqual(package['location'][1:],['inside.zip','角色.unitypackage'])
            asset=package['assets'][0]
            self.assertEqual(asset['path'],'Assets/Avatar/Face.prefab')
            self.assertEqual(asset['inspection']['classes'],{'1':1})
            stage=root/'stage';stage.mkdir()
            copied=stage_package(report,package,stage)
            self.assertEqual(len(copied),1)
            self.assertEqual(hashlib.sha256((stage/asset['path']).read_bytes()).hexdigest(),asset['sha256'])
            self.assertTrue(Path(str(stage/asset['path'])+'.meta').is_file())
            source.write_bytes(b'changed input')
            with self.assertRaisesRegex(ValueError,'differs from audit'):stage_package(report,package,stage)

    def test_source_script_is_inventoried_but_not_staged(self):
        with tempfile.TemporaryDirectory() as temporary:
            root=Path(temporary);source=root/'avatar.zip'
            with zipfile.ZipFile(source,'w') as archive:
                archive.writestr('package.unitypackage',unitypackage('Assets/Editor/Untrusted.cs',b'using System; class Untrusted {}'))
            report=Auditor(root/'audit').audit(source);stage=root/'stage';stage.mkdir()
            package=report['inventory']['packages'][0]
            self.assertEqual(package['counts']['.cs'],1)
            self.assertEqual(stage_package(report,package,stage),[])
            self.assertFalse((stage/'Assets').exists())

    def test_alias_duplicate_and_traversal_rejected(self):
        for value in ['../escape','/absolute','C:/absolute','a/../../b','a\x00b']:
            with self.subTest(value=value),self.assertRaises(ValueError):checked_name(value)
        self.assertEqual(checked_name('Assets\\角色\\Face.prefab'),'Assets/角色/Face.prefab')
        with tempfile.TemporaryDirectory() as temporary:
            root=Path(temporary);source=root/'duplicate.zip'
            with zipfile.ZipFile(source,'w') as archive:
                archive.writestr('A.txt','a');archive.writestr('a.txt','b')
            with self.assertRaisesRegex(ValueError,'Duplicate'):Auditor(root/'audit').audit(source)

    def test_blocks_preserve_errors_and_validate_length(self):
        def fail():
            yield b'abc'
            raise ValueError('decompression failed')
        stream=Blocks(fail(),6)
        self.assertEqual(stream.read(8),b'abc')
        self.assertEqual(stream.read(8),b'')
        with self.assertRaisesRegex(ValueError,'decompression failed'):stream.finish()
        with self.assertRaisesRegex(ValueError,'Truncated'):Blocks(iter([b'a']),3).finish()

    def test_utf16_document(self):
        self.assertEqual(text_bytes('利用規約'.encode('utf-16')),'利用規約')
        self.assertIsNone(text_bytes(b'\x89PNG\r\n\x1a\n\x00'))


if __name__=='__main__':unittest.main()
