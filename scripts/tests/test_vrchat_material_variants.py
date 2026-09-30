import pathlib,sys,tempfile,unittest
sys.path.insert(0,str(pathlib.Path(__file__).resolve().parents[1]))
from vrchat_material_variants import effective_material

class VariantTests(unittest.TestCase):
    def test_inherited_textures_and_explicit_override_are_distinct(self):
        with tempfile.TemporaryDirectory() as directory:
            root=pathlib.Path(directory)
            shader='a'*32;parent='b'*32;child='c'*32;tex='d'*32
            def file(guid,body):
                path=root/(guid+'.mat');path.write_text('Material:\n  m_Shader: {fileID: 4800000, guid: '+shader+', type: 3}\n'+body)
                return dict(extension='.mat',extractedPath=str(path))
            base=file(parent,'  m_CustomRenderQueue: 2460\n  m_SavedProperties:\n    m_TexEnvs:\n    - _MainTex:\n        m_Texture: {fileID: 2800000, guid: '+tex+', type: 3}\n        m_Scale: {x: 1, y: 1}\n        m_Offset: {x: 0, y: 0}\n    m_Floats:\n    - _UseShadow: 1\n')
            variant=file(child,'  m_Parent: {fileID: 2100000, guid: '+parent+', type: 2}\n  m_CustomRenderQueue: -1\n  m_SavedProperties:\n    m_Floats:\n    - _UseShadow: 0\n')
            assets={parent:base,child:variant};data=effective_material(child,assets)
            self.assertEqual(data['textureBindings'][0]['texture']['guid'],tex)
            self.assertEqual(data['floats']['_UseShadow'],0);self.assertEqual(data['customRenderQueue'],2460)
            path=pathlib.Path(variant['extractedPath']);path.write_text(path.read_text()+'    m_TexEnvs:\n    - _MainTex:\n        m_Texture: {fileID: 0}\n        m_Scale: {x: 1, y: 1}\n        m_Offset: {x: 0, y: 0}\n')
            self.assertEqual(effective_material(child,assets)['textureBindings'],[])
            # A cutout child can retain inherited color/texture properties from
            # an opaque parent while selecting its own shader.
            path.write_text(path.read_text().replace(shader,'e'*32))
            self.assertEqual(effective_material(child,assets)['shader']['guid'],'e'*32)
            with self.assertRaisesRegex(ValueError,'Missing material parent'):effective_material(child,{child:variant})

if __name__=='__main__':unittest.main()
