"""Stage only active character artwork; originals remain available on this Mac."""
import json
from pathlib import Path
import shutil

def active_resources(root: Path):
    resources = root/'ios/StarryNight/Resources'
    catalog = json.loads((resources/'CharacterCatalog.json').read_text())['characters']
    covers = json.loads((resources/'CharacterCoverCatalog.json').read_text())['covers']
    artwork = {c['display']['thumbnail'] for c in catalog}
    artwork |= {name+'Portrait' for name in list(artwork)}
    artwork |= {c[k] for c in covers for k in ('asset','avatar') if k in c}
    openings = json.loads((resources/'CharacterOpenings.json').read_text())['characters']
    audio = {v['audio'] for c in openings for v in c['variants']+c.get('legacyVariants',[])}
    return artwork, audio

def stage_catalog(root: Path, source: Path, artwork: set[str]):
    destination = root/'.local/active-character-resources'/source.relative_to(root/'ios/StarryNight')
    destination.mkdir(parents=True,exist_ok=True)
    # Delete only this generated staging catalog, never the source artwork.
    for child in destination.iterdir():
        if child.is_dir(): shutil.rmtree(child)
        else: child.unlink()
    removed=[]
    for child in source.iterdir():
        character_art = child.stem.startswith(('Anime_', 'Avatar_', 'Cover_', 'Package_')) or child.stem in {
            'FirstCompanionBackdrop',
            'RobotThumbnail','RobotThumbnailPortrait','MikuThumbnail','MikuThumbnailPortrait',
            'HumanThumbnail','HumanThumbnailPortrait','RealCharacterThumbnail','RealCharacterThumbnailPortrait'}
        if character_art and child.stem not in artwork:
            removed.append(child.stem); continue
        if child.is_dir(): shutil.copytree(child,destination/child.name)
        else: shutil.copy2(child,destination/child.name)
    return destination, removed
