import pathlib,sys,unittest
import numpy as np
sys.path.insert(0,str(pathlib.Path(__file__).resolve().parents[1]))
from vrchat_portable_convert import compact_skin

class SkinTests(unittest.TestCase):
    def test_compaction_preserves_deformation_including_small_weights(self):
        joints=np.array([[300,12,0,0],[1,300,12,0]])
        weights=np.array([[.999,.001,0,0],[.5,.3,.2,0]])
        remapped,used=compact_skin(joints,weights,400)
        positions=np.arange(400*3).reshape(400,3)
        before=(positions[joints]*weights[:,:,None]).sum(axis=1)
        after=(positions[used][remapped]*weights[:,:,None]).sum(axis=1)
        np.testing.assert_array_equal(before,after)
        self.assertEqual(used.tolist(),[1,12,300])

    def test_invalid_weighted_joint_is_not_silently_removed(self):
        with self.assertRaises(ValueError):compact_skin(np.array([[30]]),np.array([[1.]]),20)

if __name__=='__main__':unittest.main()
