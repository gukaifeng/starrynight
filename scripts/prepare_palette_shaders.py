#!/usr/bin/env python3
"""Generate host-owned lilToon palette variants without modifying source avatars.

The shader dependency is restored by prepare_liltoon.py. Generated third-party
shader copies remain private/reproducible; this script and our grading hook are
the only additions committed to the public client repository.
"""
from pathlib import Path
import re
import shutil

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / '.local/dependencies/liltoon-2.3.4-source'
TARGET = ROOT / 'unity/CharacterRuntime/Assets/GeneratedPaletteShaders'
PREFIX = 'StarryNight/Palette/'
PROPERTIES = '\n'.join(f'        [HideInInspector] _StarryPalette{x} ("Starry palette {x}", Vector) = (0,1,0,0)' for x in ['Main', 'Shadow', 'Highlight'])
UNIFORMS = '\n'.join(f'float4 _StarryPalette{x};' for x in ['Main', 'Shadow', 'Highlight'])

def write(path, text):
    path.parent.mkdir(parents=True, exist_ok=True)
    if not path.exists() or path.read_text() != text:
        path.write_text(text)

def main():
    if not (SOURCE / 'Shader/lts.shader').exists():
        raise SystemExit('Restore the pinned lilToon dependency first')
    names = set()
    for path in (SOURCE / 'Shader').rglob('*.shader'):
        match = re.search(r'Shader\s+"([^"]+)"', path.read_text())
        if match:
            names.add(match[1])
    count = 0
    for path in (SOURCE / 'Shader').rglob('*'):
        if path.suffix not in {'.shader', '.hlsl', '.cginc'}:
            continue
        text = path.read_text()
        if path.suffix == '.shader':
            text = re.sub(r'Shader\s+"([^"]+)"', lambda m: 'Shader "'+PREFIX+m[1]+'"', text, count=1)
            text = re.sub(r'(UsePass\s+")([^"]+)(")', lambda m: m[1]+(PREFIX if m[2].rsplit('/', 1)[0] in names else '')+m[2]+m[3], text)
            text = re.sub(r'(Fallback\s+")([^"]+)(")', lambda m: m[1]+(PREFIX if m[2] in names else '')+m[2]+m[3], text)
            text = re.sub(r'(Properties\s*\{)', lambda m: m[1]+'\n'+PROPERTIES, text, count=1)
            # lilToon's registration-only dummy pass uses a legacy POSITION
            # output semantic. Metal requires SV_POSITION even for this unused
            # pass; fix only its v2f, never the vertex input or real geometry.
            text = re.sub(r'(struct v2f\s*\{\s*float4 pos\s*:)\s*POSITION;', r'\1 SV_POSITION;', text)
        if path.name == 'lil_common_input.hlsl':
            text = text.replace('#if defined(LIL_CUSTOM_PROPERTIES)', UNIFORMS+'\n#if defined(LIL_CUSTOM_PROPERTIES)', 1)
        if path.name == 'lil_common_frag.hlsl':
            text = '#include "StarryPalette.hlsl"\n'+text
            text = text.replace('#define BEFORE_OUTPUT', '#define BEFORE_OUTPUT fd.col.rgb = StarryPaletteGrade(fd.col.rgb);', 1)
        if path.name in {'lil_pass_forward_fakeshadow.hlsl', 'lil_pass_universal2d.hlsl'}:
            text = '#include "StarryPalette.hlsl"\n'+text
            text = text.replace('return fd.col;', 'fd.col.rgb = StarryPaletteGrade(fd.col.rgb);\n    return fd.col;')
        write(TARGET / path.relative_to(SOURCE), text)
        count += 1
    write(TARGET / 'Shader/Includes/StarryPalette.hlsl', (ROOT / 'unity/CharacterRuntime/Assets/Shaders/CharacterPalette.hlsl').read_text())
    for path in SOURCE.glob('*LICENSE*'):
        shutil.copyfile(path, TARGET / path.name)
    print(f'PALETTE_SHADERS_GENERATED files={count} shaderNames={len(names)}')

if __name__ == '__main__':
    main()
