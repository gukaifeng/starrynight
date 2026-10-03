#!/usr/bin/env python3
"""Compile the real download store with ZIPFoundation in an isolated macOS test package."""
from pathlib import Path
import shutil
import subprocess

root=Path(__file__).resolve().parents[1]
out=root/'.local/tests/character-downloads'
(out/'Sources/DownloadCore').mkdir(parents=True,exist_ok=True)
(out/'Tests/DownloadCoreTests').mkdir(parents=True,exist_ok=True)
shutil.copy2(root/'ios/StarryNight/Features/Resources/CharacterDownloadStore.swift',out/'Sources/DownloadCore/CharacterDownloadStore.swift')
shutil.copy2(root/'scripts/tests/CharacterDownloadTests.swift',out/'Tests/DownloadCoreTests/CharacterDownloadTests.swift')
(out/'Package.swift').write_text('''// swift-tools-version:6.0
import PackageDescription
let package=Package(name:"DownloadCore",platforms:[.macOS(.v14)],dependencies:[.package(url:"https://github.com/weichsel/ZIPFoundation.git",exact:"0.9.20")],targets:[.target(name:"DownloadCore",dependencies:["ZIPFoundation"]),.testTarget(name:"DownloadCoreTests",dependencies:["DownloadCore","ZIPFoundation"])])
''')
subprocess.run(['swift','test','--package-path',str(out)],check=True)
