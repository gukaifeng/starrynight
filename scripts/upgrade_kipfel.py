#!/usr/bin/env python3
"""Upgrade the existing companion to the audited Kipfel 1.1.1 PC data.

Author archives remain untouched. A candidate is written privately; --apply
preserves the existing identity and collection, and retires only the duplicate
preview entry. Rendering and device validation are separate required steps.
"""
from __future__ import annotations
import argparse
import copy
import json
from pathlib import Path
import shutil
import sys
import time
import numpy as np

ROOT = Path(__file__).resolve().parents[1]
IDENTITY = 'anime-kipfel'
PREVIEW = 'anime-kipfel-v111'
SOURCE_SHA = '496789394fede7375f669c73b5c5943fb4b8870c6bac0c9d324aecdf113c7c2e'
sys.path.insert(0, str(ROOT/'character-sdk/tools'))
from character_tool import seal, validate
from vrchat_portable_convert import convert_geometry, append_motions, export_materials, portable_secondary, write_json
from vrchat_performance_catalog import build_character
from vrchat_performance_export import source_recipe, convert_profile, append_source_idle
from vrchat_autonomy import append_visible_idle, profile, configure_wind, provenance, notice


def complete_secondary(secondary, physics, recipe):
    """Retain authored collision associations and all five plane colliders."""
    from vrchat_performance_export import rotate
    source=physics['source']
    associations={};chains={}
    for chain in source['chains']:
        if not chain['enabled']:
            continue
        for path in chain['transformPaths']:
            associations.setdefault('Avatar/'+path,set()).update(chain['colliderIDs'])
            chains.setdefault('Avatar/'+path,[]).append(chain)
    for strand in secondary['strands']:
        strand['colliderIDs']=sorted(associations.get(strand['bone'],set()))
        source_chains=chains[strand['bone']]
        strand['chainIDs']=[c['id'] for c in source_chains]
        strand['initialEnabled']=any(c['activeInHierarchy'] for c in source_chains)
    spheres=[];planes=[]
    for collider in source['colliders']:
        if not collider['enabled'] or not collider['activeInHierarchy']:
            continue
        shape=collider['shape']
        if shape['insideBounds']:
            raise ValueError('Inside-bounds collider needs a separate adapter')
        kind=shape['shapeType'];q=shape['rotation'] or dict(x=0,y=0,z=0,w=1)
        q=np.array([q[k] for k in 'xyzw']);q=q/max(np.linalg.norm(q),1e-12)
        center=np.array([(shape['position'] or {}).get(k,0) for k in 'xyz'])
        common=dict(id=collider['id'],bone='Avatar/'+collider['rootPath'])
        if kind==2:
            normal=rotate(q,np.array([0.,1.,0.]))*np.array([-1.,1.,1.])
            planes.append(dict(common,offset=dict(zip('xyz',center*np.array([-1.,1.,1.]))),normal=dict(zip('xyz',normal))))
        elif kind in (0,1):
            radius=float(shape['radius'] or 0)
            half=max(0,float(shape['height'] or 0)*.5-radius) if kind==1 else 0
            for distance in ([-half,0,half] if half else [0]):
                position=(center+rotate(q,np.array([0.,distance,0.])))*np.array([-1.,1.,1.])
                spheres.append(dict(common,offset=dict(zip('xyz',position)),radius=radius,localRadius=True))
        else:
            raise ValueError('Unknown collider shape')
    owners={c['ownerPath']:dict(id=c['id'],kind=kind) for kind,items in
            [('chain',source['chains']),('collider',source['colliders'])] for c in items}
    controls=[];adapted=set()
    for option in recipe['performance']['options']:
        control=dict(option=option['id'],kind=option['kind'],on=[],off=[])
        for source_key,destination in [('visibility','on'),('offVisibility','off')]:
            for binding in option.get(source_key,[]):
                if binding['path'] in owners:
                    control[destination].append(dict(owners[binding['path']],enabled=binding['visible']))
                    adapted.add((option['id'],binding['path']))
        if control['on'] or control['off']:controls.append(control)
    secondary.update(schemaVersion=4,colliders=spheres,planes=planes,controls=controls)
    physics['limitations']=[x for x in physics['limitations'] if x['kind']!='unadapted-collider']
    return adapted


def read(path):
    return json.loads(path.read_text())


def constraints(stage, inspection):
    """Resolve the five authored rotation constraints by GUID/fileID, not names."""
    from audit_vrchat_performances import unity_documents
    from vrchat_physics import PhysicsResolver
    audit = read(stage/'source-audit.json')
    assets = [a for ar in audit['archives'] for p in ar['unityPackages'] for a in p['assets']]
    resolver = PhysicsResolver(assets, inspection, read(stage/'Inspection/kipfel-fbx.json'))
    main = next(a for a in assets if a['path'] == inspection['prefab'])
    occurrence = dict(guid=main['guid'], prefix='', asset=main, overrides=[])
    records = []
    for document in unity_documents(Path(main['extractedPath']).read_text()):
        value = document.get('MonoBehaviour', {})
        if 'Sources' not in value or 'GlobalWeight' not in value:
            continue
        if value.get('m_Script', {}).get('fileID') != 1788371120:
            raise ValueError('Unreviewed constraint type')
        if value.get('SolveInLocalSpace') or value.get('FreezeToWorld'):
            raise ValueError('Local/frozen constraint requires a separate adapter')
        target = resolver.component_owner_path(occurrence, dict(gameObject=value['m_GameObject']))
        if target is None:
            raise ValueError('Constraint target is unresolved')
        sources = []
        for source in value['Sources'].values():
            if not isinstance(source, dict) or 'SourceTransform' not in source:
                continue
            if not source['SourceTransform'].get('fileID') or not source['Weight']:
                continue
            path = resolver.resolve_transform(source['SourceTransform'], occurrence)
            if path is None:
                raise ValueError('Constraint source is unresolved')
            sources.append(dict(path='Avatar/'+path, weight=float(source['Weight'])))
        if not sources:
            raise ValueError('Constraint has no effective source')
        records.append(dict(path='Avatar/'+target, sources=sources,
            weight=float(value['GlobalWeight']), active=bool(value['IsActive'] and value['m_Enabled']),
            rest=value['RotationAtRest'], offset=value['RotationOffset'],
            axes=[bool(value['AffectsRotation'+axis]) for axis in 'XYZ']))
    if len(records) != 5:
        raise ValueError('Selected Kipfel PC constraint inventory changed')
    return dict(schemaVersion=1, coordinateSystem='unity-source-mirror-x', rotations=records)


def prepare(output):
    plan = read(ROOT/'.local/vrchat-batch/plan.json')
    row = next(r for r in plan['models'] if r['role'] == 'kipfel')
    if row['version'] != '1.1.1' or row['sourceSHA256'] != SOURCE_SHA:
        raise ValueError('Unexpected source version or archive identity')
    stage = ROOT/'.local/vrchat-batch/stages/kipfel'
    snapshot = stage/'Inspection/Portable/kipfel'
    stamp = read(snapshot/'inspection-stamp.json')
    if stamp['sourceSHA256'] != SOURCE_SHA or stamp['prefab'] != row['prefab']:
        raise ValueError('Snapshot does not match selected PC source')
    if output.exists():
        raise ValueError('Use a fresh private candidate directory')
    output.mkdir(parents=True)
    old = read(ROOT/'character-packages/imported'/IDENTITY/'character.json')
    catalog = dict(schemaVersion=1, characters=[build_character('kipfel', stage/'source-audit.json', True)])
    write_json(output/'source-catalog.json', catalog)
    recipe = source_recipe('kipfel', output/'source-catalog.json', stage/'Inspection/Performances/kipfel.json')
    morph_scales={}
    for tracks in recipe['sampledMorphs'].values():
        for track in tracks:
            if min(track['values'])<-.0001:raise ValueError('Negative morph needs a separate adapter')
            peak=max(track['values'])
            if peak>1.0001:
                key=(track['renderer'].split('/')[-1],track['shape'])
                morph_scales[key]=max(morph_scales.get(key,1),float(np.ceil(peak*1000)/1000))
    b, geometry, index, report = convert_geometry(snapshot,morph_scales)
    if report['nonlinearMorphFrames']:
        raise ValueError('Nonlinear morph adapter required')
    # Keep every author clip, including bonus expressions not reachable from
    # the default VRChat menu. SDK platform emotes are not author-owned clips.
    source, motion_map = append_motions(b, geometry, index, snapshot)
    b.doc['animations'] = [a for a in b.doc['animations'] if a['name'] != 'Idle']
    by_clip = {a['name']:a for a in b.doc['animations']}
    mapped = {}
    for motion in source['motions']:
        if motion['guid'] not in motion_map:
            continue
        entry = motion_map[motion['guid']]
        animation = by_clip[entry['clip']]
        animation['name'] = 'VRC_'+motion['name']
        # The original additive breath contains a fixed body pose. Its overlay
        # must only key varying channels, otherwise it overwrites a sitting pose.
        additive = motion['name'].endswith('_breath')
        if additive:
            animation['channels'] = [c for c in animation['channels'] if
                np.max(np.abs(b.array(animation['samplers'][c['sampler']]['output'])-
                    b.array(animation['samplers'][c['sampler']]['output'])[0])) > 1e-5]
        mapped[motion['path']] = dict(entry, clip=animation['name'], additive=additive,
            sourceDuration=motion['duration'], duration=max(motion['duration'], 1 if motion['duration']==0 else 0))
    inspection = read(stage/'Inspection/kipfel-prefab.json')
    performance, limitations = convert_profile(b, inspection, recipe, mapped,morph_scales)
    performance['schemaVersion']=2
    performance['groups'].append(dict(id='interaction',label='摸头反馈',symbol='hand.tap'))
    for mode, label in [('off','关闭摸头反馈'),('happy','被摸头时开心'),('unhappy','被摸头时不满')]:
        performance['options'].append(dict(id='pet-mode-'+mode,group='interaction',label=label,
            kind='preset',interactionMode=mode,defaultOn=mode=='happy',duration=0,loop=False,
            bones=[],morphs=[],offMorphs=[],morphTracks=[],visibility=[],offVisibility=[]))
    neutral = {('Avatar/'+skin['path'], shape['name']):shape['weight']/100/morph_scales.get((skin['path'].split('/')[-1],shape['name']),1)
               for skin in geometry['skins'] for shape in skin['shapes']}
    # Full geometry retains every morph, including the hundreds of zeroed
    # reset channels in each source expression. A zero equal to neutral needs
    # no redundant override: the host restores its baseline before evaluation.
    # Explicit zero overrides of nonzero author defaults remain necessary.
    for option in performance['options']:
        for key in ('morphs', 'offMorphs'):
            option[key] = [binding for binding in option[key] if binding['weight'] or
                neutral[(binding['renderer'], binding['shape'])]]
        option['morphTracks'] = [track for track in option['morphTracks'] if
            any(key['value'] for key in track['keys']) or neutral[(track['renderer'], track['shape'])]]
    # Mobile-only bindings in shared author clips are filtered by the converter;
    # the PC binding in the same clip must still be retained.
    source_idle = append_source_idle(b, 'kipfel', mapped, performance)
    source_idle['adaptation'] = append_visible_idle(b, 'kipfel', source_idle)
    material_limits = export_materials(stage, geometry, output,
        ROOT/'.local/dependencies/liltoon-2.3.4-source', source)
    # This Silver mask is absent from both supplied author versions (and from
    # the shader distribution). Keep the unresolved identity explicit and let
    # the original shader handle its null texture; never invent a replacement.
    for limitation in material_limits:
        if not (limitation.get('material') == '5a25059bfc7ed7c4aa810cd20ff5fe3c' and
                limitation.get('property') in ('_EmissionBlendMask', '_GlitterColorTex') and
                limitation.get('reference', {}).get('guid') == 'e025416a8dd03174e8617922a4b33bda' and
                limitation.get('reason') == 'Unresolved source texture'):
            raise ValueError('Material dependencies need resolution: '+str(material_limits))
    secondary, physics = portable_secondary(stage, 'kipfel', b, geometry,include_inactive=True)
    adapted=complete_secondary(secondary, physics,recipe)
    limitations=[n for n in limitations if (n.get('option'),n.get('sourcePath')) not in adapted]
    wind = configure_wind(secondary)
    write_json(output/'secondary-motion.json', secondary)
    write_json(output/'physics-source.json', physics)
    write_json(output/'rig-constraints.json', constraints(stage, inspection))
    write_json(output/'pet-feedback.json',dict(initialMode=1,happyOption='kipfel-facial-happy',
        unhappyOption='kipfel-facial-unhappy',duration=1.6))
    b.write(output/'model.glb')
    manifest = copy.deepcopy(old)
    manifest['packageVersion'] = '3.3.0'
    manifest['compatibility']['required'].append('core.materials.liltoon@1')
    manifest['compatibility']['required'].append('core.performance@2')
    manifest['compatibility']['optional']=[c for c in manifest['compatibility']['optional'] if c!='core.performance@1']
    manifest['display'].update(name='小猫', originalName='Kipfel 1.1.1 · もち山金魚')
    human = {h['human']:'Avatar/'+h['path'] for h in geometry['human']}
    renderer = 'Avatar/Body'
    manifest['rig'].update(head=human['Head'], neck=human['Neck'],
        leftEye=human['LeftEye'], rightEye=human['RightEye'], headRenderer=renderer)
    manifest['performance'] = performance
    manifest['autonomy'] = profile('kipfel', manifest, source_idle)
    for bindings in [manifest['speech']['amplitude']]+[v['bindings'] for v in manifest['speech']['visemes']]:
        for binding in bindings:
            binding['renderer'] = renderer
    manifest['extensions']['app.starry.secondary-motion'] = dict(version=4, file='secondary-motion.json')
    manifest['extensions']['app.starry.rig-constraints'] = dict(version=1, file='rig-constraints.json')
    manifest['extensions']['app.starry.pet-feedback'] = dict(version=1,file='pet-feedback.json')
    manifest['compatibility']['optional'].append('core.interaction@1')
    manifest['interactions']=[dict(id='head',bone=human['Head'],renderer=renderer,eventName='interaction.head.tap',radius=.12)]
    manifest['compatibility']['optional'] = [c for c in manifest['compatibility']['optional'] if not c.startswith('core.secondary-motion@')]+['core.secondary-motion@4']
    manifest['compatibility']['required']=list(dict.fromkeys(manifest['compatibility']['required']))
    manifest['compatibility']['optional']=list(dict.fromkeys(manifest['compatibility']['optional']))
    manifest['files'] = []
    write_json(output/'character.json', manifest)
    write_json(output/'source-meta.json', dict(original='Kipfel 1.1.1', author='もち山金魚',
        sourceVersion='1.1.1', sourceSHA256=SOURCE_SHA, prefab=row['prefab'],
        use='private-local-preview-only', sdkIncluded=False, visualOnly=False,
        preservedIdentity=IDENTITY, retiredPreview=PREVIEW,
        sourceIdle=source_idle, autonomy=provenance('kipfel'),
        unresolvedSourceTextures=material_limits,
        missingTexturePolicy='Preserve null reference behavior of the pinned original shader; no substitute image is fabricated.'))
    for name in ['LICENSE.txt']:
        text=(ROOT/'character-packages/imported'/IDENTITY/name).read_text()
        (output/name).write_text(text.replace('Kipfel 1.0.3','Kipfel 1.1.1'))
    (output/'NOTICE.md').write_text(notice('kipfel')+'\nThe upgraded source is Kipfel 1.1.1 PC. Typed original lilToon properties and five native rotation constraints are retained.\n')
    write_json(output/'conversion-report.json', dict(report, id=IDENTITY, sourceVersion='1.1.1',
        sourceClipCount=len(source['motions']), performanceOptions=len(performance['options']),
        morphNormalization=[dict(renderer=k[0],shape=k[1],geometryGain=v,weightScale=1/v,
            policy='Scaled target delta and reciprocal weight preserve original displacement without curve clipping.') for k,v in morph_scales.items()],
        performanceLimitations=limitations, materialLimitations=material_limits,
        rigConstraints=5, sourceIdle=source_idle, environmentWind=wind,
        sourceCoverage=catalog['characters'][0]['coverage']))
    seal(output)
    validate(output)
    print('KIPFEL_UPGRADE_CANDIDATE', output, len(performance['options']), 'options', flush=True)


def apply(output):
    manifest, _ = validate(output)
    if manifest['id'] != IDENTITY or read(output/'source-meta.json')['sourceSHA256'] != SOURCE_SHA:
        raise ValueError('Unexpected candidate identity')
    resources = ROOT/'ios/CharacterHost/Resources'
    collection_path = resources/'CharacterCollections.json'
    collections = read(collection_path)
    collection = next(c for c in collections['collections'] if c['modelID'] == IDENTITY)
    if collection.get('previewOnly'):
        raise ValueError('Existing full companion must not be replaced by a preview collection')
    collection['modelPackageVersion'] = manifest['packageVersion']
    collections['collections'] = [c for c in collections['collections'] if c['modelID'] != PREVIEW]
    roster_path = ROOT/'assets/characters/active-roster.json'
    roster = read(roster_path)
    roster['characters'] = [c for c in roster['characters'] if c != PREVIEW]
    backup = ROOT/'.local/kipfel-upgrade/backups'/str(time.time_ns())
    backup.mkdir(parents=True)
    for path in [collection_path, roster_path]:
        shutil.copy2(path, backup/path.name)
    destination = ROOT/'character-packages/imported'/IDENTITY
    pending=backup/'candidate'
    shutil.copytree(output,pending)
    destination.rename(backup/IDENTITY)
    pending.rename(destination)
    write_json(collection_path, collections)
    write_json(roster_path, roster)
    # Keep retired generated files privately for rollback, outside active imports.
    preview = ROOT/'character-packages/imported'/PREVIEW
    if preview.exists():
        preview.rename(backup/PREVIEW)
    profile_path=resources/'CharacterPublicProfiles.json'
    if profile_path.exists():
        profiles=read(profile_path)
        shutil.copy2(profile_path,backup/profile_path.name)
        for entry in profiles['characters']:
            if entry['id']==IDENTITY:
                entry['name']='小猫';entry['story']=entry['story'].replace('琪宝','小猫')
                entry['profileRevision']='2026-10-02-kipfel-1.1.1'
        profiles['characters']=[p for p in profiles['characters'] if p['id']!=PREVIEW]
        write_json(profile_path,profiles)
    cover_path=resources/'CharacterCoverCatalog.json'
    if cover_path.exists():
        covers=read(cover_path)
        shutil.copy2(cover_path,backup/cover_path.name)
        covers['covers']=[c for c in covers['covers'] if c['runtimeID']!=PREVIEW]
        write_json(cover_path,covers)
    print('KIPFEL_UPGRADE_ACTIVATED', IDENTITY, manifest['packageVersion'], 'backup', backup, flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--apply', action='store_true')
    args = parser.parse_args()
    output = args.output.resolve()
    if not output.is_relative_to(ROOT/'.local'):
        raise ValueError('Candidate must be private under .local')
    apply(output) if args.apply else prepare(output)


if __name__ == '__main__':
    main()
