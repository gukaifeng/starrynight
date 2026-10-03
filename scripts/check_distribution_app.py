#!/usr/bin/env python3
"""Check the generated distribution project and its built native application."""
import argparse
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--platform', choices=['simulator', 'device'], default='simulator')
parser.add_argument('--app', type=Path, help='Override the built .app directory')
args = parser.parse_args()
project = ROOT / 'ios' / ('StarryNight-Simulator.xcodeproj' if args.platform == 'simulator' else 'StarryNight.xcodeproj')
objects = json.loads(subprocess.check_output(['plutil', '-convert', 'json', '-o', '-', str(project/'project.pbxproj')]))['objects']
for item in objects.values():
    if item.get('isa') == 'XCBuildConfiguration':
        if 'STARRY_TEST_TOOLS' in item.get('buildSettings', {}).get('SWIFT_ACTIVE_COMPILATION_CONDITIONS', ''):
            raise SystemExit('Developer compilation flag present; regenerate with --distribution.')
for item in objects.values():
    if item.get('isa') == 'PBXFileReference':
        path = item.get('path', '')
        if '/Developer/' in path or 'AIInspectionPanel.swift' in path or 'ClientAIRules.txt' in path:
            raise SystemExit('Private developer source/resource reference remains: '+path)
folder = 'DerivedData' if args.platform == 'simulator' else 'DeviceDerivedData'
sdk = 'iphonesimulator' if args.platform == 'simulator' else 'iphoneos'
app = args.app or ROOT / f'.local/build/{folder}/Build/Products/Release-{sdk}/StarryNight.app'
if not (app/'StarryNight').is_file():
    raise SystemExit('Build the distribution app first: '+str(app))
if (app/'ClientAIRules.txt').exists():
    raise SystemExit('Private inspection rules remain in the app bundle; rebuild in a clean derived-data directory.')
symbols = subprocess.check_output(['nm', str(app/'StarryNight')], stderr=subprocess.DEVNULL, text=True)
for name in ('AIInspectionPanel', 'AIInspectionSectionPage', 'AppDeveloperPanel', 'CharacterDeveloperPanel',
             'DeveloperEntry', 'CharacterPerformancePanel', 'AvatarControlSlider'):
    if name in symbols:
        raise SystemExit('Developer view remains in native binary: '+name)
print('PASS: distribution project and application exclude developer pages, manual performance views and private AI rules.')
