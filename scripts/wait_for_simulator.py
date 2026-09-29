#!/usr/bin/env python3
"""Bound CoreSimulator boot notifications; actual install/UI tests remain authoritative."""
import json
from pathlib import Path
import subprocess
import sys

identifier = sys.argv[1]
try:
    subprocess.run(['xcrun','simctl','bootstatus',identifier,'-b'],check=True,timeout=90)
except subprocess.TimeoutExpired:
    devices=json.loads(subprocess.check_output(['xcrun','simctl','list','devices','available','-j'],text=True,timeout=20))
    device=next((d for group in devices['devices'].values() for d in group if d['udid']==identifier),None)
    if not device or device['state']!='Booted':
        raise SystemExit('Simulator did not boot within 90 seconds. Inspect CoreSimulator before retrying.')
    path=Path(__file__).resolve().parents[1]/'.local/checks'/f'simulator-boot-{identifier}.png'
    path.parent.mkdir(parents=True,exist_ok=True)
    subprocess.run(['xcrun','simctl','io',identifier,'screenshot',str(path)],check=True,timeout=30)
    print('CoreSimulator boot notification timed out, but the booted device has a readable display. Continuing to actual app installation/tests.',flush=True)
