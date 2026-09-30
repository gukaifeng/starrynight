"""Invalidate metadata-only reuse when the converter or inspected input changes."""
import hashlib
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
TOOLS=('vrchat_conversion_signature.py','vrchat_portable_convert.py','vrchat_controls.py','vrchat_physics.py','prepare_liltoon.py',
       'audit_vrchat_archives.py','vrchat_materials.py','prepare_anime_characters.py',
       'vrchat/VrcSourceInspector.cs','vrchat/VrcPortableGeometry.cs','vrchat/requirements.txt')

def digest(path):
    result=hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda:stream.read(1024*1024),b''):result.update(block)
    return result.hexdigest()

def signature(stage,role,root=ROOT):
    snapshot=stage/'Inspection/Portable'/role
    return dict(version=1,tools={name:digest(root/'scripts'/name) for name in TOOLS},
        inputs={name:digest(snapshot/name) for name in ('geometry.json','geometry.bin','motions.json','host-standing.json')},
        sourceAudit=digest(stage/'source-audit.json'))

def require_reusable(record,current):
    if record!=current:raise ValueError('Conversion inputs/tools changed or signature is absent; run without --reuse-conversion')
