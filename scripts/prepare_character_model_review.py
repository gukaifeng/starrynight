#!/usr/bin/env python3
"""Prepare private model-review candidates without invoking Unity or any API.

Preserve the active model's reviewed appearance and available author controls,
restore source-derived blinking/secondary motion, and report remaining full-
import blockers. Never activate candidates or claim device verification here.
"""
from __future__ import annotations
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import struct
import sys
from types import SimpleNamespace

from package_vrchat_library import missing_motion_dependencies, require_selected_inspection, NEUTRAL_BASELINE_PROXIES
from prepare_anime_characters import paths
from vrchat_blink import select_blink_bindings
from vrchat_portable_convert import portable_secondary, write_json
from vrchat_physics import PhysicsResolver
from vrchat_source_paths import resolve_source_path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT/'character-sdk/tools'))
from character_tool import seal, validate, inspect_glb, node_scale_factors


def read(path):
    return json.loads(path.read_text())


def digest(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def source_effects(stage, role):
    audit = read(stage/'source-audit.json')
    assets = {a['guid']: a for arc in audit['archives'] for pkg in arc['unityPackages'] for a in pkg['assets']}
    resolver = PhysicsResolver(list(assets.values()), read(stage/'Inspection'/f'{role}-prefab.json'),
                               read(stage/'Inspection'/f'{role}-fbx.json'))
    result = []
    seen = set()
    for instance in resolver.occurrences:
        asset = instance['asset']
        if asset['guid'] in seen:
            continue
        seen.add(asset['guid'])
        source = resolve_source_path(asset['extractedPath'], expected_sha256=asset.get('sha256'))
        text = source.read_text(errors='replace')
        for component in ('ParticleSystem', 'ParticleSystemRenderer', 'ParentConstraint', 'PositionConstraint',
                          'RotationConstraint', 'ScaleConstraint', 'AimConstraint', 'LookAtConstraint', 'Cloth'):
            count = len(re.findall(r'^' + component + r':\s*$', text, re.M))
            if count:
                result.append(dict(component=component, count=count, sourceGUID=asset['guid']))
    return result


def restore_secondary(stage, role, model):
    geometry = read(stage/'Inspection/Portable'/role/'geometry.json')
    raw = model.read_bytes()
    size, kind = struct.unpack_from('<II', raw, 12)
    if raw[:4] != b'glTF' or kind != 0x4e4f534a or struct.unpack_from('<I', raw, 8)[0] != len(raw):
        raise ValueError('Invalid active GLB')
    document = json.loads(raw[20:20+size])
    node_paths = paths(document)
    for i, node in enumerate(geometry['nodes']):
        expected = 'Avatar' + ('/' + node['path'] if node['path'] else '')
        if i >= len(node_paths) or node_paths[i] != expected:
            raise ValueError('Active model node identity differs from inspected source: ' + expected)
    before = json.dumps(document['nodes'], sort_keys=True)
    secondary, evidence = portable_secondary(stage, role, SimpleNamespace(doc=document), geometry)
    contact_ids = {c['sourceComponentFileID'] for c in evidence['source']['contacts']}
    spring_ids = {c['sourceComponentFileID'] for c in evidence['source']['chains'] + evidence['source']['colliders']}
    required_unresolved = [e for e in evidence['source']['unresolved'] if
                           not (e.get('componentID') in contact_ids - spring_ids)]
    if required_unresolved:
        raise ValueError('Unresolved source physics: ' + str(required_unresolved))
    if evidence['source']['unresolved']:
        evidence['limitations'].append(dict(kind='unresolved-source-contact-references',
                                           detail=evidence['source']['unresolved']))
    if len(secondary['strands']) > 512 or len(secondary['colliders']) > 256:
        raise ValueError('Secondary-motion runtime budget exceeded')
    # Use the same hierarchy/rotation-aware radius check as XCP preflight.
    scales = node_scale_factors(document)
    indices = {path: i for i, path in paths(document).items()}
    for collider in secondary['colliders']:
        radius = collider['radius']
        if collider.get('localRadius'):
            radius *= max(scales[indices[collider['bone']]])
        if not 0 <= radius <= .5:
            raise ValueError('Collider effective model radius exceeds runtime budget')
    if json.dumps(document['nodes'], sort_keys=True) != before:
        payload = json.dumps(document, ensure_ascii=False, separators=(',', ':')).encode()
        payload += b' ' * (-len(payload) % 4)
        binary = raw[20+size:]
        model.write_bytes(b'glTF' + struct.pack('<II', 2, 20+len(payload)+len(binary)) +
                          struct.pack('<II', len(payload), 0x4e4f534a) + payload + binary)
    return geometry, secondary, evidence


def prepare(identity, row, output):
    source = ROOT/'character-packages/imported'/identity
    validate(source)
    folder = output/identity
    marker = folder/'model-review-origin.json'
    if folder.exists() and (not marker.exists() or read(marker).get('id') != identity):
        raise ValueError('Candidate destination already contains unowned data: ' + str(folder))
    folder.mkdir(parents=True, exist_ok=True)
    write_json(marker, dict(schemaVersion=1, id=identity, sourceManifestSHA256=digest(source/'character.json')))
    shutil.copytree(source, folder, dirs_exist_ok=True)
    manifest = read(folder/'character.json')
    manifest['packageVersion'] = '3.2.0'
    manifest['speech'] = dict(mode='none', proceduralHeadMotion=False, amplitude=[], visemes=[])
    for option in manifest.get('performance', {}).get('options', []):
        option.pop('ai', None)
    ai_evidence = folder/'ai-expression-evidence.json'
    if ai_evidence.exists():
        ai_evidence.unlink()
    blockers = []
    if row:
        role = row['role']
        stage = ROOT/'.local/vrchat-batch/stages'/role
        snapshot = stage/'Inspection/Portable'/role
        # Reuse the verified source selection for private pending-review data;
        # do not rewrite its stamp or pretend the current Inspector ran.
        require_selected_inspection(row, snapshot, appearance_only=True)
        geometry, secondary, physics = restore_secondary(stage, role, folder/'model.glb')
        write_json(folder/'secondary-motion.json', secondary)
        write_json(folder/'physics-source.json', physics)
        manifest['compatibility']['optional']=[c for c in manifest['compatibility']['optional'] if c!='core.secondary-motion@2']
        manifest['compatibility']['optional'].append('core.secondary-motion@3')
        manifest['extensions']['app.starry.secondary-motion']['version']=3
        renderer = manifest['rig']['headRenderer'].removeprefix('Avatar/')
        skin = next(s for s in geometry['skins'] if s['path'] == renderer)
        bindings, selection = select_blink_bindings(read(folder/'avatar-descriptor.json'), skin, snapshot/'geometry.bin')
        if not bindings:
            raise ValueError('No verified neutral eyelid binding: ' + identity)
        available = {n['path']: set(n.get('morphs', [])) for n in inspect_glb(folder/'model.glb')['nodes']}
        if any(b['shape'] not in available.get(b['renderer'], set()) for b in bindings):
            raise ValueError('Eyelid binding absent from active model')
        manifest['autonomy'] = dict(schemaVersion=1, blink=dict(bindings=bindings,
            intervals=[3.2,4.7,5.8,3.9,4.4], closeSeconds=.16, closedSeconds=.035, openSeconds=.26,
            firstDelay=1.8, suppressGroups=[], suppressOptions=[]))
        converted = ROOT/'.local/vrchat-batch/converted'/role
        controls = read(converted/'avatar-controls.json')
        motions = read(converted/'avatar-motions.json')
        missing = sorted(missing_motion_dependencies(controls, motions) - NEUTRAL_BASELINE_PROXIES)
        blockers.extend(controls.get('limitations', []))
        if missing:
            blockers.append(dict(kind='missing-reachable-motions', guids=missing))
        report = read(converted/'portable-conversion.json')
        blockers.extend(report.get('materialLimitations', []))
        if report.get('nonlinearMorphFrames'):
            blockers.append(dict(kind='nonlinear-morph-frames', detail=report['nonlinearMorphFrames']))
        effects = source_effects(stage, role)
        if effects:
            blockers.append(dict(kind='source-components-require-runtime-adapter', components=effects))
        if physics['source'].get('contacts'):
            blockers.append(dict(kind='source-contacts-require-interaction-adapter', count=len(physics['source']['contacts'])))
        blockers.extend(physics['limitations'])
        source_count = len(controls['controls'])
        active_count = len(manifest.get('performance', {}).get('options', []))
        if source_count != active_count:
            blockers.append(dict(kind='unavailable-author-controls', source=source_count, candidate=active_count))
        provenance = dict(role=role, geometry=str(snapshot/'geometry.json'),
                          sourceSHA256=row['sourceSHA256'], prefab=row['prefab'],
                          geometrySHA256=digest(snapshot/'geometry.json'),
                          geometryBinarySHA256=digest(snapshot/'geometry.bin'),
                          stageAuditSHA256=digest(stage/'source-audit.json'),
                          inspectionStampSHA256=digest(snapshot/'inspection-stamp.json'),
                          inspectionScope='Existing verified source snapshot; current Unity reinspection pending',
                          blinkSelection=selection, sourceControls=source_count)
    else:
        role = identity.removeprefix('anime-')
        bindings = manifest.get('autonomy', {}).get('blink', {}).get('bindings', [])
        secondary = read(folder/'secondary-motion.json')
        # Keep these earlier native imports' existing authored performance and
        # breathing; do not send them through the newer source-specific recipe.
        provenance = dict(role=role, geometry=str(ROOT/'.local/vrchat-stage/Inspection'/f'{role}-prefab.json'),
                          inspectionScope='Existing authored native import; current Unity reinspection pending')
        blockers.append(dict(kind='legacy-import-full-effects-review-pending'))
    optional = manifest['compatibility']['optional']
    optional[:] = [c for c in optional if not c.startswith('core.speech.')]
    if bindings and 'core.autonomy@1' not in optional:
        optional.append('core.autonomy@1')
    pending = dict(schemaVersion=1, id=identity, modelOnly=True, complete=False, deviceVerified=False,
                   source=provenance, remaining=blockers,
                   tools={name:digest(ROOT/name) for name in ('scripts/prepare_character_model_review.py',
                       'scripts/vrchat_blink.py','scripts/vrchat_physics.py','scripts/vrchat_portable_convert.py',
                       'character-sdk/tools/character_tool.py','character-sdk/tools/portable_avatar.py')})
    write_json(folder/'model-review-status.json', pending)
    manifest['extensions']['app.starry.model-review'] = dict(version=1, file='model-review-status.json')
    # A rejected earlier attempt was kept as an explicitly suspended manifest.
    # It belongs to this scratch directory, and must not enter a sealed package.
    suspended=folder/'suspended-character.json'
    if suspended.exists():suspended.unlink()
    write_json(folder/'character.json', manifest)
    seal(folder)
    validate(folder)
    return dict(id=identity, role=role, status='candidate-prepared', complete=False, deviceVerified=False,
                folder=str(folder.relative_to(ROOT)), manifestSHA256=digest(folder/'character.json'),
                blinkBindings=len(bindings), physicsStrands=len(secondary['strands']),
                colliders=len(secondary['colliders']), remaining=blockers, geometry=provenance['geometry'])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--only', help='Comma-separated active character IDs')
    parser.add_argument('--output-root', type=Path, default=ROOT/'.local/vrchat-batch/model-review')
    args = parser.parse_args()
    output = args.output_root.resolve()
    if not output.is_relative_to(ROOT/'.local'):
        raise SystemExit('Model review output must stay in the private .local directory')
    output.mkdir(parents=True, exist_ok=True)
    rows = {r['id']: r for r in read(ROOT/'.local/vrchat-batch/plan.json')['models']}
    identities = read(ROOT/'assets/characters/active-roster.json')['characters']
    preview_ids = {c['modelID'] for c in read(ROOT/'ios/StarryNight/Resources/CharacterCollections.json')['collections'] if c.get('previewOnly') is True}
    if args.only:
        chosen = set(args.only.split(','))
        if chosen - set(identities):
            raise SystemExit('Unknown active character ID: ' + str(sorted(chosen - set(identities))))
        identities = [i for i in identities if i in chosen]
        if chosen-preview_ids:
            raise SystemExit('Complete conversation characters cannot become model-only previews: '+str(sorted(chosen-preview_ids)))
    identities = [i for i in identities if i in preview_ids]
    previous = read(output/'status.json')['characters'] if (output/'status.json').exists() else []
    results = {r['id']: r for r in previous}
    failed = False
    for identity in identities:
        try:
            result = prepare(identity, rows.get(identity), output)
        except Exception as error:
            failed = True
            result = dict(id=identity, status='blocked', complete=False, deviceVerified=False, reason=str(error))
            folder = output/identity
            marker = folder/'model-review-origin.json'
            if marker.exists() and read(marker).get('id') == identity:
                if (folder/'character.json').exists():
                    (folder/'character.json').replace(folder/'suspended-character.json')
                write_json(folder/'model-review-status.json', result)
        results[identity] = result
        write_json(output/'status.json', dict(schemaVersion=1, characters=list(results.values())))
        print(identity, result['status'], result.get('reason', ''), flush=True)
    write_json(output/'review-request.json', dict(entries=[dict(role=r['id'], source=r['folder'], geometry=r['geometry'])
               for r in results.values() if r['status'] == 'candidate-prepared' and r['id'] in preview_ids],
               outputRoot=str((output/'render').relative_to(ROOT)), reuseImportedMirror=True))
    raise SystemExit(1 if failed else 0)


if __name__ == '__main__':
    main()
