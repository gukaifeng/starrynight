#!/usr/bin/env python3
"""Prepare pinned iOS speech binaries + model folder; --check never uses the network."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import zipfile

ROOT = Path(__file__).resolve().parents[1]
CACHE = ROOT / '.local/speech-ios'
RUNTIMES = [
    ('sherpa', 'https://github.com/k2-fsa/sherpa-onnx/releases/download/xcframework/sherpa-onnx-v1.13.8-ios-static.xcframework.zip',
     '6b8e769cb153343270fdccbe92e3b3db0d1c421d67fa0989ab01fdf5b2fcf2de', 'sherpa-onnx.xcframework'),
    ('onnxruntime', 'https://github.com/csukuangfj/onnxruntime-libs/releases/download/v1.28.1/onnxruntime-ios-static-xcframework-1.28.1.xcframework.zip',
     '992d8a0cc6014cccc3a7815c36bbff5e5a06833ea2c4d47dd43ef071f639cf9d', 'onnxruntime.xcframework'),
]

def digest(path):
    checksum = hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''): checksum.update(block)
    return checksum.hexdigest()

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true', help='Verify prepared build resources without downloading')
    parser.add_argument('--proxy', help='Optional download transport proxy; never written into the App')
    args = parser.parse_args()
    CACHE.mkdir(parents=True, exist_ok=True)
    manifest = CACHE / 'VoiceModels/manifest.json'
    if args.check:
        if not manifest.exists():
            raise SystemExit('Prepare offline voice first: python3 scripts/prepare_ios_speech.py')
        for entry in json.loads(manifest.read_text())['files']:
            path = manifest.parent / entry['path']
            if not path.exists() or path.stat().st_size != entry['bytes'] or digest(path) != entry['sha256']:
                raise SystemExit('Missing/corrupt bundled voice resource: ' + entry['path'])
        for _, _, _, directory in RUNTIMES:
            if not (CACHE / 'Frameworks' / directory / 'Info.plist').exists():
                raise SystemExit('Missing speech framework: ' + directory)
        print('Offline speech build resources verified (no network).')
        return

    (CACHE / 'downloads').mkdir(exist_ok=True)
    for name, url, expected, directory in RUNTIMES:
        archive = CACHE / 'downloads' / (name + '.zip')
        if not archive.exists() or digest(archive) != expected:
            tmp = archive.with_suffix('.partial')
            cmd = ['curl', '-fLsS', '--retry', '3', '--retry-all-errors', '--connect-timeout', '20', '--max-time', '600']
            if args.proxy: cmd += ['--proxy', args.proxy]
            subprocess.run(cmd + ['-o', str(tmp), url], check=True)
            if digest(tmp) != expected: raise RuntimeError('Framework checksum mismatch: ' + name)
            tmp.replace(archive)
        # Always restore the verified archive; downloads are cached, not trusted extracted binaries.
        destination = CACHE / 'Frameworks' / directory
        if destination.exists(): shutil.rmtree(destination)
        with zipfile.ZipFile(archive) as package:
            for item in package.infolist():
                if not (CACHE / 'Frameworks' / item.filename).resolve().is_relative_to((CACHE / 'Frameworks').resolve()):
                    raise RuntimeError('Unsafe framework archive member')
            package.extractall(CACHE / 'Frameworks')

    files = []
    entries = json.loads((ROOT / 'local-services/voice/models.lock.json').read_text())['files']
    for entry in entries:
        if entry['model'] not in ('sensevoice', 'melo') or entry['path'].startswith('test_wavs/'): continue
        source = ROOT / '.local/voice-models' / entry['model'] / entry['path']
        if not source.exists() or digest(source) != entry['sha256']:
            raise SystemExit('Missing/corrupt model; run scripts/prepare_voice.py: ' + str(source))
        relative = entry['model'] + '/' + entry['path']
        target = manifest.parent / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, target)
        files.append({'path':relative, 'bytes':entry['bytes'], 'sha256':entry['sha256']})
    for entry in json.loads((ROOT / 'assets/voice/runtime-licenses.lock.json').read_text())['files']:
        source = ROOT / 'assets/voice/licenses' / entry['path']
        if digest(source) != entry['sha256']: raise RuntimeError('License checksum mismatch')
        target = manifest.parent / 'licenses' / entry['path']
        target.parent.mkdir(parents=True, exist_ok=True); shutil.copy2(source, target)
        files.append({'path':'licenses/' + entry['path'], 'bytes':source.stat().st_size, 'sha256':entry['sha256']})
    result = {'schema':1, 'runtime':'sherpa-onnx 1.13.8 / ONNX Runtime 1.28.1',
              'networkRequired':False, 'files':files}
    manifest.write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n')
    print(f"Prepared {len(files)} voice resources, {sum(f['bytes'] for f in files)/1024**2:.1f} MiB; device + simulator frameworks.")

if __name__ == '__main__': main()
