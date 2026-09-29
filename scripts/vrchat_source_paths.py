"""Resolve archived extraction paths after a checkout is moved, without rewriting evidence.

Only the exact project-local .local/vrchat-audit tree can be relocated. Other
explicit source paths keep their original meaning; missing files never trigger a
basename search. Consumers can enforce the recorded SHA-256 before reading data.
"""
import hashlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MARKER = ('.local', 'vrchat-audit')


def resolve_source_path(value, *, expected_sha256=None, extraction_root=None, project_root=ROOT):
    source = Path(value)
    if not source.is_absolute() or '..' in source.parts:
        raise ValueError('Audited source must be an absolute path without traversal: ' + str(source))
    if extraction_root is not None:
        extraction = Path(extraction_root)
        if not extraction.is_absolute() or '..' in extraction.parts or not source.is_relative_to(extraction):
            raise ValueError('Source is outside its audited extraction root: ' + str(source))
    positions = [i for i in range(len(source.parts) - 1) if source.parts[i:i + 2] == MARKER]
    if len(positions) > 1:
        raise ValueError('Ambiguous audit-root path: ' + str(source))
    if positions:
        root = Path(project_root).resolve()
        base = root.joinpath(*MARKER).resolve()
        if not base.is_relative_to(root):
            raise ValueError('Local audit directory escapes the project')
        source = base.joinpath(*source.parts[positions[0] + 2:]).resolve()
        if not source.is_relative_to(base):
            raise ValueError('Audited source symlink escapes the local audit directory')
    if not source.is_file():
        raise FileNotFoundError('Audited source unavailable: ' + str(source))
    if expected_sha256 is not None:
        with source.open('rb') as stream:
            digest = hashlib.file_digest(stream, 'sha256').hexdigest()
        if digest != expected_sha256:
            raise ValueError('Audited source digest mismatch: ' + str(source))
    return source
