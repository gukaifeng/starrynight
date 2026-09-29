"""Relocation keeps audited identity and rejects path/hash ambiguity."""
import hashlib
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from vrchat_source_paths import resolve_source_path


class SourcePathTests(unittest.TestCase):
    def test_relocated_asset_keeps_digest(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            target = root / '.local/vrchat-audit/avatar/texture.png'
            target.parent.mkdir(parents=True)
            target.write_bytes(b'original texture')
            old_root = '/missing/old-checkout/.local/vrchat-audit/avatar'
            old_path = old_root + '/texture.png'
            digest = hashlib.sha256(target.read_bytes()).hexdigest()
            self.assertEqual(resolve_source_path(old_path, expected_sha256=digest,
                extraction_root=old_root, project_root=root), target.resolve())
            with self.assertRaises(ValueError):
                resolve_source_path(old_path, expected_sha256='0' * 64, project_root=root)
            with self.assertRaises(ValueError):
                resolve_source_path(old_path, extraction_root=old_root + '/different', project_root=root)
            with self.assertRaises(ValueError):
                resolve_source_path(old_root + '/../avatar/texture.png', project_root=root)
            with self.assertRaises(FileNotFoundError):
                resolve_source_path('/missing/unrelated/texture.png', project_root=root)

    def test_audit_symlink_cannot_escape(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            base = root / '.local/vrchat-audit/avatar'
            base.mkdir(parents=True)
            outside = root / 'outside.txt'
            outside.write_text('not audited')
            (base / 'linked.txt').symlink_to(outside)
            with self.assertRaises(ValueError):
                resolve_source_path('/old/.local/vrchat-audit/avatar/linked.txt', project_root=root)


if __name__ == '__main__':
    unittest.main()
