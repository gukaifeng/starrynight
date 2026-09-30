#!/usr/bin/env python3
"""Extract one audited avatar package into an isolated data-only Unity project."""
from __future__ import annotations
import argparse
import json
from pathlib import Path
import shutil
import tempfile
import libarchive
from vrchat_batch_audit import Blocks, checked_name, sha256, open_archive
from audit_vrchat_archives import safe_target

ROOT = Path(__file__).resolve().parents[1]
ALLOWED = {'.fbx', '.prefab', '.mat', '.png', '.jpg', '.jpeg', '.tga', '.anim',
           '.controller', '.overridecontroller', '.asset', '.mask', '.wav', '.ogg',
           '.mp3', '.rendertexture'}
TRUSTED = ['VrcSourceInspector.cs', 'VrcPerformanceSampler.cs', 'VrcPortableGeometry.cs']


def visit_archive(reader, chain, consume, temporary_root):
    """Follow an exact audited member chain; no shell globs or archive-wide extraction."""
    if not chain:
        consume(reader)
        return
    for entry in reader:
        if checked_name(entry.pathname) != chain[0]:
            continue
        if not entry.isfile or entry.issym or entry.islnk:
            raise ValueError('Invalid nested archive member')
        stream = Blocks(entry.get_blocks(), entry.size)
        if Path(chain[0]).suffix.lower() == '.unitypackage':
            with libarchive.stream_reader(stream, format_name='tar') as child:
                visit_archive(child, chain[1:], consume, temporary_root)
        else:
            with tempfile.TemporaryFile(dir=temporary_root) as tmp:
                while chunk := stream.read(1024 * 1024):
                    tmp.write(chunk)
                tmp.seek(0)
                with libarchive.stream_reader(tmp) as child:
                    visit_archive(child, chain[1:], consume, temporary_root)
        stream.finish()
        return
    raise ValueError('Audited nested archive is missing: ' + chain[0])


def stage_package(report, package, stage):
    source = Path(report['source'])
    if sha256(source) != report['sha256']:
        raise ValueError('Original archive differs from audit')
    wanted = {a['guid']: a for a in package['assets'] if not a['folder'] and a['extension'] in ALLOWED
              and a['path'].startswith('Assets/')
              and not a['path'].startswith(('Assets/lilToon/', 'Assets/VRCSDK/', 'Assets/Poiyomi/'))}
    copied = set()
    previous = stage / 'source-audit.json'
    owned = {}
    if previous.exists():
        for archive in json.loads(previous.read_text()).get('archives', []):
            if archive.get('archiveSHA256') == report['sha256']:
                for old_package in archive['unityPackages']:
                    owned.update({a['path']:a.get('sha256') for a in old_package['assets']})

    def extract(reader):
        for entry in reader:
            name = checked_name(entry.pathname)
            guid, _, kind = name.partition('/')
            if kind != 'asset' or guid not in wanted:
                continue
            item = wanted[guid]
            target = safe_target(stage, item['path'])
            # Unity upgrades serialized animation metadata in its private copy.
            # Re-extraction may restore only files tracked by this stage's source
            # receipt; unrelated or differently sourced files remain protected.
            if target.exists() and sha256(target) != item['sha256'] and owned.get(item['path']) != item['sha256']:
                raise ValueError('Stage collision; use a separate avatar stage: ' + item['path'])
            target.parent.mkdir(parents=True, exist_ok=True)
            stream = Blocks(entry.get_blocks(), entry.size)
            temporary = target.with_name(target.name + '.extracting')
            with temporary.open('wb') as output:
                while chunk := stream.read(1024 * 1024):
                    output.write(chunk)
            if stream.finish() != item['sha256']:
                temporary.unlink()
                raise ValueError('Extracted asset digest differs from audit: ' + item['path'])
            temporary.chmod(0o600)
            temporary.replace(target)
            if item.get('metaPath'):
                shutil.copyfile(item['metaPath'], str(target) + '.meta')
            copied.add(guid)
    with open_archive(source) as reader:
        visit_archive(reader, package['location'][1:], extract, stage)
    if copied != set(wanted):
        raise ValueError('Incomplete stage extraction')
    return [dict(a, extractedPath=str(stage / a['path']), metaPath=str(stage / (a['path']+'.meta')))
            for a in wanted.values()]


def prepare(report_path, package_index, stage, specs, extra_packages=(), dependency_assets=()):
    if not stage.resolve().is_relative_to(ROOT / '.local'):
        raise ValueError('Isolated stages must be inside project .local')
    stage.mkdir(parents=True, exist_ok=True)
    for p in (stage / 'Assets').rglob('*'):
        if p.suffix.lower() in {'.cs', '.dll', '.shader', '.compute', '.dylib'} and p.name not in TRUSTED:
            raise ValueError('Unexpected executable code in data-only stage: ' + str(p))
    report = json.loads(report_path.read_text())
    packages=[report['inventory']['packages'][i] for i in dict.fromkeys([package_index,*extra_packages])]
    package_assets=[(p,stage_package(report,p,stage)) for p in packages]
    editor = stage / 'Assets/Editor'
    editor.mkdir(parents=True, exist_ok=True)
    for name in TRUSTED:
        if (ROOT / 'scripts/vrchat' / name).exists():
            shutil.copyfile(ROOT / 'scripts/vrchat' / name, editor / name)
    (stage / 'Packages').mkdir(exist_ok=True)
    (stage / 'Packages/manifest.json').write_text(json.dumps(dict(dependencies={
        'com.unity.modules.' + module: '1.0.0' for module in
        ['animation', 'imageconversion', 'jsonserialize', 'audio', 'particlesystem']}), indent=2)+'\n')
    (stage / 'ProjectSettings').mkdir(exist_ok=True)
    (stage / 'ProjectSettings/ProjectVersion.txt').write_text('m_EditorVersion: 6000.3.25f1\n')
    (stage / 'InspectionConfig.json').write_text(json.dumps(dict(specs=specs), ensure_ascii=False, indent=2)+'\n')
    # Compatibility view for existing material and physics analyzers. Binary
    # contents remain one copy in the isolated stage, referenced by digest.
    audit = dict(archives=[dict(slug=specs[0]['role'], extractionRoot=str(stage),
                archiveSHA256=report['sha256'], unityPackages=[dict(file='/'.join(package['location']), assets=assets) for package,assets in package_assets])])
    for dependency in dependency_assets:
        external=json.loads(Path(dependency['report']).read_text())
        package=external['inventory']['packages'][dependency['package']]
        matches=[a for a in package['assets'] if a['guid']==dependency['guid'] and a['sha256']==dependency['sha256']]
        if len(matches)!=1 or matches[0]['extension'] not in {'.anim','.png','.jpg','.jpeg','.tga'}:
            raise ValueError('Dependency must match one audited data asset by GUID and digest')
        assets=stage_package(external,dict(package,assets=matches),stage)
        audit['archives'].append(dict(slug='verified-dependency',extractionRoot=str(stage),archiveSHA256=external['sha256'],
            unityPackages=[dict(file='/'.join(package['location']),assets=assets)]))
    from audit_vrchat_archives import enrich_package
    for archive in audit['archives']:
        for package in archive['unityPackages']:enrich_package(package)
    (stage / 'source-audit.json').write_text(json.dumps(audit, ensure_ascii=False, indent=2)+'\n')
    print('STAGED', specs[0]['role'], sum(len(assets) for _,assets in package_assets), 'data assets', flush=True)


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--report', type=Path, required=True)
    p.add_argument('--package', type=int, default=0)
    p.add_argument('--stage', type=Path, required=True)
    p.add_argument('--specs', type=Path, required=True)
    a = p.parse_args()
    prepare(a.report, a.package, a.stage.resolve(), json.loads(a.specs.read_text())['specs'])


if __name__ == '__main__':
    main()
