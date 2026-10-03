#!/usr/bin/env python3
"""Generate offline asset attribution without regenerating an Xcode workspace."""
import json
from pathlib import Path


def package_text(folder: Path, relative: str) -> str:
    path = (folder / relative).resolve()
    if not path.is_relative_to(folder.resolve()):
        raise ValueError(f'Unsafe asset notice path: {relative}')
    return path.read_text(encoding='utf-8')


def character_notice(folder: Path, manifest: dict) -> str:
    display, license_info = manifest['display'], manifest['license']
    header = [display['name'] + ' / ' + display.get('originalName', manifest['id']),
              '素材原作者：' + '；'.join(license_info['authors']),
              '许可：' + license_info['name'],
              '固定来源：' + license_info['source']]
    preview = manifest.get('extensions', {}).get('app.starry.private-preview')
    if preview and not preview.get('redistributionAllowed', True):
        header.append('本机个人预览素材：不得随公开版本或公开源码再分发；具体改作与分发权限见下方原模型许可。')
    primary = package_text(folder, license_info['notice'])
    sections = ['\n'.join(header), primary]
    # A package can have a main license and a separate upstream NOTICE. Both
    # must survive the native-resource generation; preserving just LICENSE.txt
    # loses animation attribution even though the package itself is complete.
    for name in ('NOTICE', 'NOTICE.txt', 'NOTICE.md'):
        if (folder / name).is_file():
            extra = package_text(folder, name)
            if extra.strip() and extra.strip() not in primary:
                sections.append('上游附加署名（原文，包含上游完整素材库说明）：\n' + extra)
    if preview and preview.get('metadata'):
        sections.append('原文件许可设置（保留原文）：\n' + package_text(folder, preview['metadata']))
    return '\n\n'.join(sections)


def generate_asset_credits(root: Path) -> dict[str, str]:
    resources = root / 'ios/StarryNight/Resources'
    credits = {
        'studio-robot': 'Luma / Studio Robot：星夜项目原创模型、材质与交互动作。',
        'hatsune-miku': (resources / 'MikuCredits.txt').read_text(encoding='utf-8'),
        'real-woman': (resources / 'RealCharacterCredits.txt').read_text(encoding='utf-8'),
    }
    active = set(json.loads((root / "assets/characters/active-roster.json").read_text())["characters"])
    credits = {k:v for k,v in credits.items() if k in active}
    package_notices = []
    for manifest_path in sorted((root / 'character-packages/imported').glob('*/character.json')):
        manifest = json.loads(manifest_path.read_text(encoding='utf-8'))
        if manifest['id'] not in active: continue
        notice = character_notice(manifest_path.parent, manifest)
        credits[manifest['id']] = notice
        package_notices.append(manifest['display']['name'] + ' · ' + manifest['packageVersion'] + '\n' + notice)
    for manifest_path in sorted((root / 'environment-packages/imported').glob('*/environment.json')):
        manifest = json.loads(manifest_path.read_text(encoding='utf-8'))
        notice = package_text(manifest_path.parent, manifest['license']['file'])
        package_notices.append('场景：' + manifest['display']['name'] + ' · ' + manifest['packageVersion'] + '\n' + notice)
    package_notices.append((resources / 'UnityToonCredits.txt').read_text(encoding='utf-8'))
    package_notices.append((resources / 'LilToonCredits.txt').read_text(encoding='utf-8'))
    if (resources / 'MusicCredits.txt').exists():
        package_notices.append('角色配乐来源与处理说明\n'+(resources / 'MusicCredits.txt').read_text(encoding='utf-8'))
    # Imported notices retain their text; trailing Markdown layout whitespace is
    # immaterial in this plain-text view and should not pollute source diffs.
    plain_notices='\n'.join(line.rstrip() for line in '\n\n'.join(package_notices).splitlines())
    (resources / 'CharacterPackageCredits.txt').write_text(plain_notices + '\n', encoding='utf-8')
    (resources / 'CharacterSourceCredits.json').write_text(json.dumps(credits, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    return credits


if __name__ == '__main__':
    result = generate_asset_credits(Path(__file__).resolve().parents[1])
    print(f'Generated offline source attribution for {len(result)} characters.')
