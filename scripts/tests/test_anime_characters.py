"""Content regressions: retarget basis, feet, seamless endpoints, resource budget."""
import json
from pathlib import Path
import sys
import unittest
import numpy as np

ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'scripts'))
from prepare_anime_characters import GLB, ROLES, SOURCES, motion_tracks

class AnimeContentTests(unittest.TestCase):
    def test_source_rest_basis_is_removed(self):
        # The FBX-derived source thigh has an approximately 180 degree rest
        # rotation. A naive node-name mapping passes schema checks but folds both
        # legs over the head. This regression checks the normalized result.
        tracks=motion_tracks('idle')
        for bone in ['leftUpperLeg','rightUpperLeg','leftLowerLeg','rightLowerLeg']:
            q=tracks[(bone,'rotation')][1]
            self.assertLess(float(np.max(2*np.degrees(np.arccos(np.clip(np.abs(q[:,3]),0,1))))),30,bone)

    def test_packages_have_seamless_bounded_motion_and_compressed_texture_sources(self):
        for role in ROLES:
            root=ROOT/'character-packages/imported'/role['id'];b=GLB(root/'model.glb');g=b.doc
            self.assertEqual(len(g['animations']),9)
            self.assertLessEqual(sum(len(m['primitives'])for m in g['meshes']),20)
            self.assertEqual(json.loads((root/'character.json').read_text())['source']['yaw'],180)
            baseline={}
            for clip in g['animations']:
                for channel in clip['channels']:
                    path=channel['target']['path'];node=channel['target']['node'];name=g['nodes'][node]['name']
                    values=b.array(clip['samplers'][channel['sampler']]['output'])
                    self.assertTrue(np.isfinite(values).all())
                    if path=='rotation':
                        self.assertTrue(np.allclose(np.linalg.norm(values,axis=1),1,atol=1e-5))
                        if clip['name']=='Idle':baseline[node]=values[0]
                        self.assertGreater(abs(float(np.dot(values[0],baseline[node]))),.99999)
                        self.assertGreater(abs(float(np.dot(values[-1],baseline[node]))),.99999)
                        if any(s in name for s in ['UpperLeg','LowerLeg','Foot','Toe','Hips']):self.assertTrue(np.allclose(values,values[0],atol=1e-6),role['id']+'/'+name)
                self.assertFalse(any(c['target']['path']=='scale'for c in clip['channels']))
            textures=json.loads((root/'materials.json').read_text())['materials']
            self.assertTrue(all(not m['texture'] or (root/m['texture']).is_file()for m in textures))
            self.assertTrue(any(m.get('normal') for m in textures),role['id']+' missing authored surface detail')
            self.assertTrue(any(m.get('matcap') for m in textures),role['id']+' missing authored hair reflectance')
            for material in textures:
                for key in ['normal','matcap']:
                    if material.get(key):self.assertTrue((root/material[key]).is_file())
            data=json.loads((root/'secondary-motion.json').read_text())
            self.assertLessEqual(len(data['strands']),128)
            self.assertEqual(len({s['bone']for s in data['strands']}),len(data['strands']))
            self.assertTrue(all(0<s['angle']<=16 for s in data['strands']))

if __name__=='__main__':unittest.main(verbosity=2)
