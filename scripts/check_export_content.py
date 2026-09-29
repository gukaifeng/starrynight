#!/usr/bin/env python3
"""Reject stale character or environment exports before linking the data-driven host."""
from check_character_collections import validate as validate_collections
import argparse
import json
import hashlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--platform', choices=['device', 'simulator'], required=True)
args = parser.parse_args()
stamp = ROOT / 'build' / f'unity-{args.platform}' / 'modelspace-export.json'
try:
    content = json.loads(stamp.read_text())
except (OSError, ValueError):
    content = {}
catalog_path=ROOT/'ios/CharacterHost/Resources/CharacterCatalog.json'
catalog=json.loads(catalog_path.read_text())
required={c['id'] for c in catalog['characters']}
if content.get('characterApi')!=1 or content.get('catalogSha256')!=hashlib.sha256(catalog_path.read_bytes()).hexdigest() or required!=set(content.get('models',[])):
    raise SystemExit('Character catalog differs from Unity export. Export the selected platform again before building.')
environment_catalog=ROOT/'ios/CharacterHost/Resources/EnvironmentCatalog.json'
if content.get('environmentApi')!=1 or not environment_catalog.exists() or content.get('environmentCatalogSha256')!=hashlib.sha256(environment_catalog.read_bytes()).hexdigest():
    raise SystemExit('Environment catalog differs from Unity export. Re-export this platform before building.')
images = ROOT / 'ios/CharacterHost/Resources/Assets.xcassets'
if content.get('autonomyRevision', 0) < 1:
    raise SystemExit('Unity export lacks natural idle v1; re-export this platform before building.')
if content.get('inspectionGestureRevision', 0) < 6:
    raise SystemExit('error: Unity export does not support unrestricted position editing v6. '
                     f'Run: python3 scripts/export_unity_ios.py --platform {args.platform}; then rebuild CharacterHost. '
                     'An unchanged character catalog does not prove that the runtime supports new native gestures. '
                     'The previously installed app is unchanged.')
if content.get('nativeGestureRevision', 0) < 2 or content.get('immersionRevision', 0) < 2 or content.get('portraitRevision', 0) < 1 or content.get('gazeRevision', 0) < 1 or content.get('contentVersion', 0) < 6 or content.get('studioProtocol', 0) < 1 or content.get('atmosphereRevision', 0) < 1 or content.get('framingProtocol', 0) < 8 or content.get('companionProtocol', 0) < 1 or not required.issubset(content.get('models', [])) or not all((images / (c['display']['thumbnail']+'.imageset')).is_dir() for c in catalog['characters']):
    raise SystemExit('error: Unity export is missing native gestures v2 or the v6 character studio, atmosphere and safe-area framing protocol v8 / bounded gaze v1 / portrait v1 / immersion v2, character content, or rendered thumbnail. '
                     f'Run: python3 scripts/export_unity_ios.py --platform {args.platform}; then rebuild CharacterHost. '
                     'The previously installed app is unchanged.')
print(f"Character API v1 / Environment API v1 catalog integrity PASS: {len(required)} characters, "
      f"{len(json.loads(environment_catalog.read_text())['environments'])} environments; framing v8, gaze v1, portrait v1, immersion v2, native gestures v2, position editing v6.")

validate_collections()
