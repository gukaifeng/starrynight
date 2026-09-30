"""Boundary checks against the actual bundled collection/audio files; no app build."""
import contextlib
import io
import json
from pathlib import Path
import shutil
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from check_character_collections import ROOT, validate


class CharacterMusicTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.resources = Path(self.temporary.name)
        source = ROOT / 'ios/CharacterHost/Resources'
        for name in ['CharacterCatalog.json', 'EnvironmentCatalog.json', 'CharacterCollections.json']:
            shutil.copyfile(source / name, self.resources / name)
        for asset in source.glob('Music_*.caf'):
            (self.resources / asset.name).symlink_to(asset)
        self.catalog = json.loads((self.resources / 'CharacterCollections.json').read_text())

    def tearDown(self):
        self.temporary.cleanup()

    def check(self):
        (self.resources / 'CharacterCollections.json').write_text(json.dumps(self.catalog))
        with contextlib.redirect_stdout(io.StringIO()):
            validate(self.resources)

    def test_actual_bundled_files_have_unique_owned_content(self):
        self.check()

    def test_a_foreign_recording_cannot_hide_behind_own_title_and_id(self):
        own = self.catalog['collections'][0]['music'][0]
        other = self.catalog['collections'][1]['music'][0]
        for field in ['asset', 'sha256', 'sourceModelID']:
            own[field] = other[field]
        with self.assertRaisesRegex(AssertionError, 'belongs to another role'):
            self.check()

    def test_legacy_multiple_options_are_rejected(self):
        first = self.catalog['collections'][0]['music'][0]
        self.catalog['collections'][0]['music'].append({**first,'id':first['sourceModelID']+'/extra'})
        with self.assertRaisesRegex(AssertionError, 'exactly one theme'):
            self.check()

    def test_changed_audio_bytes_are_rejected(self):
        first = self.catalog['collections'][0]['music'][0]
        path = self.resources / (first['asset'] + '.caf')
        payload = bytearray(path.read_bytes()); payload[-10] ^= 1
        path.unlink(); path.write_bytes(payload)
        with self.assertRaisesRegex(AssertionError, 'hash differs'):
            self.check()


if __name__ == '__main__':
    unittest.main()
