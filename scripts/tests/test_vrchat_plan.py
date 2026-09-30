"""Selection regressions: complete author roots can inherit their descriptor."""
import pathlib
import sys
import tempfile
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1]))
from plan_vrchat_library import avatar_prefabs, prefab_score


class AvatarPlanTests(unittest.TestCase):
    def test_nested_complete_root_is_preferred_over_simplified_variant(self):
        with tempfile.TemporaryDirectory() as folder:
            def asset(number, name, text='', descriptor=False):
                path = pathlib.Path(folder)/str(number)
                path.write_text(text)
                return dict(guid=f'{number:032x}', path=name, extension='.prefab',
                            metadataPath=str(path), inspection=dict(descriptors=int(descriptor)))
            base = asset(1, 'Base/Ramune_Base.prefab', descriptor=True)
            root = asset(2, 'Ramune.prefab', f'm_SourcePrefab: {{fileID: 100100000, guid: {1:032x}, type: 3}}')
            simple = asset(3, 'GomenneRamuneChan.prefab', descriptor=True)
            unrelated = asset(4, 'Menu.prefab', f'm_Motion: {{fileID: 1, guid: {1:032x}, type: 3}}')
            candidates = avatar_prefabs(dict(assets=[simple, unrelated, root, base]))
            self.assertEqual({a['guid'] for a in candidates}, {base['guid'], root['guid'], simple['guid']})
            self.assertEqual(max(candidates, key=lambda a: prefab_score(a, 'ramune')), root)

    def test_cycle_does_not_hide_reachable_descriptor_or_add_empty_roots(self):
        with tempfile.TemporaryDirectory() as folder:
            assets = []
            for number, refs in [(1, [2]), (2, [1, 3]), (3, []), (4, [4, 99])]:
                path = pathlib.Path(folder)/str(number)
                path.write_text('\n'.join(f'm_SourcePrefab: {{fileID: 1, guid: {v:032x}}}' for v in refs))
                assets.append(dict(guid=f'{number:032x}', extension='.prefab', metadataPath=str(path),
                                   inspection=dict(descriptors=int(number == 3))))
            self.assertEqual(len(avatar_prefabs(dict(assets=assets))), 3)


if __name__ == '__main__':
    unittest.main()
