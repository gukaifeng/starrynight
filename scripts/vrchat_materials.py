#!/usr/bin/env python3
"""Read Unity material/FBX metadata; emit a renderer-independent conversion catalog.

No Unity import, image rewriting, SDK loading or source-script execution. Values in
`source` are serialized author settings. `conversionHints` are explicitly a lossy
PBR starting point; they never pretend lilToon/MatCap is equivalent to glTF PBR.
"""
import argparse
import json
from pathlib import Path
import re
import struct

from audit_vrchat_archives import ROOT, material_inventory, model_importer_inventory, sha256, text_file
from vrchat_source_paths import resolve_source_path


def png_info(path):
    with path.open('rb') as stream:
        header = stream.read(33)
    if len(header) != 33 or header[:8] != b'\x89PNG\r\n\x1a\n' or header[12:16] != b'IHDR':
        return None
    width, height, depth, color, compression, filtering, interlace = struct.unpack('>IIBBBBB', header[16:29])
    return {'width': width, 'height': height, 'bitDepth': depth, 'colorType': color,
            'hasAlphaChannel': color in (4, 6), 'interlace': interlace}


def vector(raw, axes, fallback):
    values = dict(re.findall(r'([xyzwrgba]):\s*([-+\d.eE]+)', raw or ''))
    return [float(values.get(axis, fallback[index])) for index, axis in enumerate(axes)]


def color(source, name, fallback):
    value = source['colors'].get(name, {})
    return [float(value.get(axis, fallback[index])) for index, axis in enumerate('rgba')]


def texture_info(binding, guid_index, cache):
    ref = binding['texture']
    result = {'property': binding['property'], 'fileID': ref.get('fileID'), 'guid': ref.get('guid'),
              'scale': vector(binding.get('scale'), 'xy', [1, 1]),
              'offset': vector(binding.get('offset'), 'xy', [0, 0])}
    asset = guid_index.get(ref.get('guid'))
    if asset:
        path = resolve_source_path(asset['extractedPath'], expected_sha256=asset.get('sha256'))
        if str(path) not in cache:
            cache[str(path)] = {'path': asset['path'], 'extractedPath': str(path), 'sha256': sha256(path),
                                'bytes': path.stat().st_size, 'image': png_info(path) if path.suffix.lower() == '.png' else None}
        result.update(cache[str(path)], resolution='package-asset')
    elif not ref.get('guid') or ref['guid'].startswith('0000000000000000'):
        result['resolution'] = 'unity-built-in'
    else:
        result['resolution'] = 'unresolved-external'
    return result


def conversion_hints(source, textures):
    floats = source['floats']
    main = next((textures[name] for name in ('_MainTex', '_BaseMap', '_BaseColorMap') if name in textures), None)
    # These are serialized blend factors, not filename guesses. Src=0,Dst=3 is
    # multiplicative fake shadow; it needs a dedicated pass and is not alpha blend.
    src, dst = floats.get('_SrcBlend'), floats.get('_DstBlend')
    alpha = 'BLEND' if dst == 10 else ('OPAQUE' if dst == 0 else 'requires-review')
    notes = ['Shader is external; this catalog does not recreate or redistribute it.']
    if alpha == 'requires-review':
        notes.append('Nonstandard/multiplicative blend cannot be represented by a glTF alphaMode alone.')
    if floats.get('_UseReflection', 0) == 0:
        notes.append('Toon reflection is disabled: do not turn serialized Smoothness=1 into roughness=0.')
    emission = {'enabled': floats.get('_UseEmission', 0) != 0,
                'color': color(source, '_EmissionColor', [0, 0, 0, 1]),
                'map': textures.get('_EmissionMap'), 'blendMask': textures.get('_EmissionBlendMask'),
                'mainStrength': floats.get('_EmissionMainStrength', 0)}
    if emission['enabled'] and emission['blendMask']:
        notes.append('Emission has a blend mask: preserve/bake its authored mask before any glTF emissive export.')
    matcaps = []
    for index, prefix, enable in [(1, '_MatCap', '_UseMatCap'), (2, '_MatCap2nd', '_UseMatCap2nd')]:
        if floats.get(enable, 0):
            matcaps.append({'layer': index, 'texture': textures.get(prefix + 'Tex'), 'mask': textures.get(prefix + 'BlendMask'),
                            'color': color(source, prefix + 'Color', [1, 1, 1, 1]), 'blend': floats.get(prefix + 'Blend', 1),
                            'blendMode': floats.get(prefix + 'BlendMode')})
    if matcaps: notes.append('Enabled MatCap is view-dependent; retain in a compatible shader or document the chosen approximation.')
    normal_enabled = floats.get('_UseBumpMap', 0) != 0
    return {'baseColorTexture': main, 'baseColorFactor': color(source, '_Color', [1, 1, 1, 1]),
            'mainHSVG': color(source, '_MainTexHSVG', [0, 1, 1, 1]),
            'alphaModeCandidate': alpha, 'alphaCutoffSource': floats.get('_Cutoff'),
            'blendFactorsSource': {'src': src, 'dst': dst},
            'doubleSided': floats.get('_Cull') == 0, 'frontFaceCull': floats.get('_Cull') == 1,
            'zWriteSource': floats.get('_ZWrite'),
            'normal': {'enabled': normal_enabled, 'map': textures.get('_BumpMap') if normal_enabled else None, 'scale': floats.get('_BumpScale', 1)},
            'reflectionEnabled': floats.get('_UseReflection', 0) != 0,
            'metallicSource': floats.get('_Metallic', 0), 'smoothnessSource': floats.get('_Smoothness'),
            'emission': emission, 'matcaps': matcaps, 'notes': notes}


def parse_material(path, guid_index, texture_cache=None):
    """Return source settings plus resolved textures; no inferred mesh visibility."""
    source = material_inventory(text_file(Path(path)), guid_index)
    cache = texture_cache if texture_cache is not None else {}
    textures = {binding['property']: texture_info(binding, guid_index, cache) for binding in source['textureBindings']}
    return {'source': source, 'textures': textures, 'conversionHints': conversion_hints(source, textures)}


def build_catalog(audit):
    catalog = {'schemaVersion': 1, 'auditTool': 'scripts/vrchat_materials.py',
               'scope': 'Local source material metadata and explicitly approximate conversion hints; no image/shader conversion executed.',
               'archives': []}
    texture_cache = {}
    for archive in audit['archives']:
        record = {'slug': archive['slug'], 'archiveSHA256': archive['archiveSHA256'], 'packages': []}
        for package in archive['unityPackages']:
            by_guid = {asset['guid']: asset for asset in package['assets']}
            materials = {}
            for asset in package['assets']:
                if asset['extension'] != '.mat' or asset['folder']: continue
                path = resolve_source_path(asset['extractedPath'], expected_sha256=asset.get('sha256'), extraction_root=archive['extractionRoot'])
                materials[asset['guid']] = dict(guid=asset['guid'], name=path.stem, path=asset['path'],
                    extractedPath=str(path), sha256=sha256(path), **parse_material(path, by_guid, texture_cache))
            models = []
            for asset in package['assets']:
                if asset['extension'] != '.fbx' or asset['folder'] or not asset.get('metaPath'): continue
                importer = model_importer_inventory(text_file(resolve_source_path(asset['metaPath'], extraction_root=archive['extractionRoot'])), by_guid)
                models.append({'guid': asset['guid'], 'path': asset['path'], 'extractedPath': asset['extractedPath'],
                    'materialRemaps': {item['sourceName']: item['target'] for item in importer['externalObjects'] if item['type'] == 'UnityEngine:Material'},
                    'humanoidBoneMap': importer['humanoidBoneMap'],
                    'note': 'Prefab renderer material overrides take precedence over these FBX importer defaults.'})
            record['packages'].append({'sourcePackage': package['file'], 'materialsByGUID': materials, 'models': models})
        catalog['archives'].append(record)
    catalog['uniqueTextureCount'] = len(texture_cache)
    return catalog


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--audit', type=Path, default=ROOT / 'docs/verification/vrchat-import/source-audit.json')
    parser.add_argument('--output', type=Path, default=ROOT / 'docs/verification/vrchat-import/source-materials.json')
    args = parser.parse_args()
    catalog = build_catalog(json.loads(args.audit.read_text()))
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(catalog, ensure_ascii=False, indent=2) + '\n')
    print('Material catalog: ' + str(args.output))
    print('Material count: ' + str(sum(len(p['materialsByGUID']) for a in catalog['archives'] for p in a['packages'])))
    print('Resolved unique textures: ' + str(catalog['uniqueTextureCount']))


if __name__ == '__main__':
    main()
