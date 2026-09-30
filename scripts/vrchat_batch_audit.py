#!/usr/bin/env python3
"""Stream ZIP/RAR/7z and nested UnityPackages without expanding their binary assets.

The report is a source inventory, not a claim of renderer/runtime compatibility.
Only inert metadata is retained; original archives are never modified. Requires
libarchive-c (the OS libarchive supplies the format decoders).
"""
from __future__ import annotations

import argparse
from collections import Counter
import hashlib
import io
import json
from pathlib import Path, PurePosixPath
import re
import tempfile
import subprocess
import unicodedata
from contextlib import contextmanager

import libarchive

from audit_vrchat_archives import animation_inventory, field, sha256, unity_blocks

ARCHIVES = {'.zip', '.rar', '.7z', '.unitypackage'}
MAX_MEMBER = 4 * 1024**3
MAX_EXPANDED = 40 * 1024**3
MAX_METADATA = 64 * 1024**2
MAX_DEPTH = 5
AUDIT_REVISION = 3
METADATA_EXT = {'.meta', '.prefab', '.asset', '.controller', '.overridecontroller',
                '.anim', '.mat', '.txt', '.md', '.json', '.url', '.shader', '.cs', '.asmdef'}


class SevenZipEntry:
    """Use 7-Zip for RAR5 v6; macOS libarchive can misidentify an inner ZIP."""
    def __init__(self, archive, fields):
        self.archive = archive
        self.pathname = checked_name(fields['Path'])
        self.size = int(fields.get('Size', '0'))
        self.isdir = fields.get('Folder') == '+'
        self.issym = bool(fields.get('Symbolic Link'))
        self.islnk = bool(fields.get('Hard Link') or fields.get('Copy Link'))
        self.isfile = not self.isdir
        if fields.get('Encrypted') == '+' or fields.get('Alternate Stream') == '+':
            raise ValueError('Encrypted/alternate stream archive entries are not accepted')

    def get_blocks(self):
        command = ['7zz', 'x', '-so', '-y', '-spd', '--', str(self.archive), self.pathname]
        with subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE) as process:
            while chunk := process.stdout.read(1024 * 1024):
                yield chunk
            error = process.stderr.read().decode('utf-8', errors='replace')
            if process.wait() != 0:
                raise ValueError('7-Zip extraction failed: ' + error[:1000])


@contextmanager
def open_archive(path):
    if Path(path).suffix.lower() == '.rar':
        result = subprocess.run(['7zz', 'l', '-slt', '-ba', '-sccUTF-8', '--', str(path)],
                                check=True, capture_output=True, text=True)
        entries = []
        for block in result.stdout.split('\n\n'):
            fields = dict(line.split(' = ', 1) for line in block.splitlines() if ' = ' in line)
            if 'Path' in fields:
                entries.append(SevenZipEntry(path, fields))
        expected = {(unicodedata.normalize('NFC',e.pathname), e.size) for e in entries if not e.isdir}
        # Apple's libarchive decodes conventional RAR compression, whereas the
        # Homebrew 7-Zip build decodes the new stored RAR6 headers that libarchive
        # may skip. Cross-check the *whole* inventory before choosing a reader.
        try:
            with libarchive.file_reader(str(path)) as reader:
                observed = {(unicodedata.normalize('NFC',checked_name(e.pathname)), e.size) for e in reader if not e.isdir}
        except libarchive.exception.ArchiveError:
            observed = set()
        if observed == expected:
            with libarchive.file_reader(str(path)) as reader:
                yield reader
        else:
            yield entries
    else:
        with libarchive.file_reader(str(path)) as reader:
            yield reader


def dump(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + '.tmp')
    temporary.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n')
    temporary.replace(path)


def checked_name(value):
    if isinstance(value, bytes):
        # Some Japanese archives omit the ZIP UTF-8 flag.
        for codec in ('utf-8', 'cp932', 'gb18030'):
            try:
                value = value.decode(codec)
                break
            except UnicodeError:
                pass
        else:
            raise ValueError('Archive pathname cannot be decoded')
    value = value.replace('\\', '/')
    p = PurePosixPath(value)
    if '\x00' in value or p.is_absolute() or '..' in p.parts or re.match(r'^[A-Za-z]:', value):
        raise ValueError('Unsafe archive member: ' + repr(value))
    return str(p)


class Blocks(io.RawIOBase):
    """Bounded forward-only bridge between libarchive readers; hashes all bytes."""
    def __init__(self, blocks, expected):
        self.blocks = iter(blocks)
        self.pending = b''
        self.expected = expected
        self.count = 0
        self.digest = hashlib.sha256()
        self.error = None

    def readable(self):
        return True

    def readinto(self, target):
        if not self.pending:
            try:
                self.pending = next(self.blocks, b'')
            except Exception as error:
                # Python exceptions cannot cross libarchive's ctypes callback.
                # Return EOF there and surface the original error at finish().
                self.error = error
                self.pending = b''
        size = min(len(target), len(self.pending))
        if size:
            chunk = self.pending[:size]
            target[:size] = chunk
            self.pending = self.pending[size:]
            self.count += size
            if self.count > self.expected:
                raise ValueError('Member exceeded declared length')
            self.digest.update(chunk)
        return size

    def finish(self):
        scratch = bytearray(1024 * 1024)
        while self.readinto(scratch):
            pass
        if self.error:
            raise self.error
        if self.count != self.expected:
            raise ValueError(f'Truncated member: {self.count}/{self.expected}')
        return self.digest.hexdigest()


def text_bytes(data):
    if data.startswith((b'\xff\xfe', b'\xfe\xff')):
        try:
            return data.decode('utf-16')
        except UnicodeError:
            return None
    if not data or b'\x00' in data[:1024]:
        return None
    for codec in ('utf-8-sig', 'cp932', 'gb18030'):
        try:
            result = data.decode(codec)
            if sum(ord(c) < 32 and c not in '\r\n\t' for c in result[:4096]) > 3:
                return None
            return result
        except UnicodeError:
            pass
    return None


def metadata_summary(text, extension):
    result = {}
    if text.startswith('%YAML'):
        blocks = unity_blocks(text)
        result['classes'] = dict(Counter(str(b['classID']) for b in blocks))
        result['references'] = sorted(set(re.findall(r'guid: ([a-fA-F0-9]{32})', text)))
        result['scripts'] = sorted(set(re.findall(r'm_Script: \{[^}]*guid: ([a-fA-F0-9]{32})', text)))
        result['markers'] = sorted({name for name in (
            'lipSync', 'VisemeBlendShapes', 'enableEyeLook', 'customEyeLookSettings',
            'baseAnimationLayers', 'specialAnimationLayers', 'expressionsMenu',
            'expressionParameters', 'controls', 'subMenu', 'subParameters',
            'rootTransform', 'pull', 'spring', 'collisionTags', 'receiverType',
            'FreezeToWorld', 'freezeToWorld', 'm_Sources', 'Sources',
            'm_AnimatorLayers', 'm_AnimatorParameters', 'm_Childs',
            'm_StateMachineBehaviours', 'm_Conditions', 'm_Materials',
            'm_PPtrCurves', 'm_Events') if re.search(r'^\s*' + name + r':', text, re.M)})
        if extension == '.anim':
            result['animation'] = animation_inventory(text)
        if extension == '.prefab':
            result['names'] = [field(b['text'], 'm_Name') for b in blocks if b['classID'] == 1]
            result['physicsChains'] = sum(b['classID'] == 114 and field(b['text'], 'pull') is not None for b in blocks)
            result['contacts'] = sum(b['classID'] == 114 and field(b['text'], 'collisionTags') is not None for b in blocks)
            result['descriptors'] = sum(b['classID'] == 114 and field(b['text'], 'lipSync') is not None for b in blocks)
        if extension == '.controller':
            result['stateCount'] = sum(b['classID'] == 1102 for b in blocks)
            result['blendTreeCount'] = sum(b['classID'] == 206 for b in blocks)
            result['transitionCount'] = sum(b['classID'] in (1101, 1109) for b in blocks)
    return result


class Auditor:
    def __init__(self, output):
        self.output = output
        self.metadata = output / 'metadata'
        self.metadata.mkdir(parents=True, exist_ok=True)
        self.total_expanded = 0

    def save_metadata(self, data):
        digest = hashlib.sha256(data).hexdigest()
        target = self.metadata / (digest + '.txt')
        if not target.exists():
            target.write_bytes(data)
            target.chmod(0o600)
        return str(target.resolve())

    def entries(self, archive, location, unity=False, depth=0):
        if depth > MAX_DEPTH:
            raise ValueError('Nested archive depth exceeded')
        rows, packages, nested = [], [], []
        seen, guid_rows = set(), {}
        for entry in archive:
            name = checked_name(entry.pathname)
            if entry.isdir:
                continue
            if not entry.isfile or entry.issym or entry.islnk:
                raise ValueError('Links and special archive members are not accepted: ' + name)
            identity = unicodedata.normalize('NFC', name).casefold()
            if identity in seen:
                raise ValueError('Duplicate archive pathname: ' + name)
            seen.add(identity)
            size = entry.size
            if size < 0 or size > MAX_MEMBER:
                raise ValueError('Member exceeds audit budget: ' + name)
            self.total_expanded += size
            if self.total_expanded > MAX_EXPANDED:
                raise ValueError('Archive tree exceeds audit budget')
            suffix = PurePosixPath(name).suffix.lower()
            row = dict(path=name, bytes=size)
            stream = Blocks(entry.get_blocks(), size)
            if not unity and suffix in ARCHIVES:
                if suffix == '.unitypackage':
                    with libarchive.stream_reader(stream, format_name='tar') as inner:
                        data = self.entries(inner, location + [name], unity=True, depth=depth+1)
                    packages.append(data)
                else:
                    # Nested 7z/RAR may require seeking. Retain only one compressed
                    # nested file at a time; dispose only this task's temporary file.
                    with tempfile.TemporaryFile(dir=self.output) as tmp:
                        while chunk := stream.read(1024 * 1024):
                            tmp.write(chunk)
                        tmp.seek(0)
                        with libarchive.stream_reader(tmp) as inner:
                            data = self.entries(inner, location + [name], depth=depth+1)
                        packages += data['packages']
                        nested.append(data)
            else:
                keep = size <= MAX_METADATA and (unity or suffix in METADATA_EXT)
                data = bytearray()
                # Detect metadata early so large binary meshes/textures aren't
                # accumulated in RAM merely because pathname is later in a TAR.
                first = stream.read(min(size, 4096))
                likely = keep and (text_bytes(first) is not None)
                if likely:
                    data.extend(first)
                while chunk := stream.read(1024 * 1024):
                    if likely:
                        data.extend(chunk)
                if likely and text_bytes(data) is not None:
                    row['metadataPath'] = self.save_metadata(data)
            row['sha256'] = stream.finish()
            rows.append(row)
            if unity:
                match = re.fullmatch(r'([a-fA-F0-9]{32})/(asset|asset\.meta|pathname|preview\.png)', name)
                if not match:
                    raise ValueError('Unexpected UnityPackage member: ' + name)
                guid_rows.setdefault(match[1].lower(), {})[match[2]] = row
        if not unity:
            return dict(location=location, files=rows, nested=nested, packages=packages)
        assets = []
        identities = set()
        for guid, members in sorted(guid_rows.items()):
            pathname = members.get('pathname', {}).get('metadataPath')
            if not pathname:
                raise ValueError('Unity asset has no readable pathname: ' + guid)
            path = checked_name(text_bytes(Path(pathname).read_bytes()).strip('\x00\r\n'))
            if not path.startswith(('Assets/', 'Packages/')):
                raise ValueError('Unexpected Unity asset root: ' + path)
            identity = unicodedata.normalize('NFC', path).casefold()
            if identity in identities:
                raise ValueError('Aliased Unity asset pathname: ' + path)
            identities.add(identity)
            item = dict(guid=guid, path=path, extension=PurePosixPath(path).suffix.lower(),
                        folder='asset' not in members, **{k:v for k,v in members.get('asset', {}).items() if k != 'path'})
            if 'asset.meta' in members:
                item['metaPath'] = members['asset.meta'].get('metadataPath')
            if item.get('metadataPath'):
                item['inspection'] = metadata_summary(text_bytes(Path(item['metadataPath']).read_bytes()), item['extension'])
            assets.append(item)
        by_guid = {a['guid']: a for a in assets}
        missing = {}
        for a in assets:
            for guid in a.get('inspection', {}).get('references', []):
                if guid not in by_guid and not guid.startswith('0000000000000000'):
                    missing.setdefault(guid, []).append(a['path'])
        return dict(location=location, assets=assets, uncompressedBytes=sum(r['bytes'] for r in rows),
                    counts=dict(sorted(Counter(a['extension'] for a in assets if not a['folder']).items())),
                    unresolvedReferences=missing)

    def audit(self, path):
        self.total_expanded = 0
        with open_archive(path) as archive:
            result = self.entries(archive, [str(path)], unity=path.suffix.lower() == '.unitypackage')
        return dict(source=str(path.resolve()), bytes=path.stat().st_size, sha256=sha256(path),
                    expandedBytes=self.total_expanded, inventory=result)


def rebuild_index(source, output):
    """A filtered retry must never remove previously audited source archives."""
    rows = []
    for path in sorted(p for p in source.rglob('*') if p.is_file() and p.suffix.lower() in ARCHIVES):
        key = hashlib.sha256(str(path.resolve()).encode()).hexdigest()[:16]
        report_path = output / 'archives' / (key + '.json')
        row = dict(source=str(path), report=str(report_path.resolve()), status='pending')
        if report_path.exists():
            result = json.loads(report_path.read_text())
            row['status'] = result['status']
            if result['status'] == 'audited':
                packages = result['inventory'].get('packages', [])
                counts = Counter()
                for package in packages:
                    counts.update(package['counts'])
                row.update(sha256=result['sha256'], packages=len(packages), counts=dict(counts))
            else:
                row['error'] = result.get('error', 'Unknown audit failure')
        rows.append(row)
    dump(output / 'index.json', dict(schemaVersion=1, sourceRoot=str(source.resolve()), archives=rows))
    return rows


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path)
    parser.add_argument('--output', type=Path, default=Path('.local/vrchat-batch'))
    parser.add_argument('--only', help='Process matching source directory/file names only')
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    sources = sorted(p for p in args.source.rglob('*') if p.is_file() and p.suffix.lower() in ARCHIVES)
    auditor = Auditor(args.output)
    summary = []
    for path in sources:
        if args.only and args.only.casefold() not in str(path).casefold():
            continue
        key = hashlib.sha256(str(path.resolve()).encode()).hexdigest()[:16]
        report_path = args.output / 'archives' / (key + '.json')
        previous = json.loads(report_path.read_text()) if report_path.exists() else None
        fingerprint = dict(size=path.stat().st_size, mtimeNS=path.stat().st_mtime_ns)
        try:
            compatible_revision = previous and (previous.get('auditRevision') == AUDIT_REVISION or
                                                path.suffix.lower() != '.rar' and previous.get('auditRevision') is None)
            if previous and previous.get('fingerprint') == fingerprint and previous.get('status') == 'audited' and compatible_revision:
                result = previous
            else:
                result = dict(schemaVersion=1, auditRevision=AUDIT_REVISION, status='audited', fingerprint=fingerprint, **auditor.audit(path))
                dump(report_path, result)
            packages = result['inventory'].get('packages', [])
            counts = Counter()
            for package in packages:
                counts.update(package['counts'])
            row = dict(source=str(path), report=str(report_path.resolve()), status='audited',
                       sha256=result['sha256'], packages=len(packages), counts=dict(counts))
            print(path.parent.name, len(packages), 'packages', dict(counts), flush=True)
        except Exception as error:
            row = dict(source=str(path), report=str(report_path.resolve()), status='failed', error=str(error))
            dump(report_path, dict(schemaVersion=1, fingerprint=fingerprint, **row))
            print('AUDIT_FAILED', path.name, str(error), flush=True)
        summary.append(row)
        rebuild_index(args.source, args.output)
    if any(row['status'] != 'audited' for row in summary):
        raise SystemExit(1)


if __name__ == '__main__':
    main()
