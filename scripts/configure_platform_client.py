#!/usr/bin/env python3
"""Write the public API origin only. Tokens always come from account login."""
import argparse
import json
from pathlib import Path
from urllib.parse import urlsplit

parser = argparse.ArgumentParser()
parser.add_argument('--url', required=True, help='HTTPS API origin, or loopback/.local for development')
parser.add_argument('--platform', choices=['simulator', 'device'], required=True)
args = parser.parse_args()
url = urlsplit(args.url)
local = url.hostname == '127.0.0.1' or (url.hostname or '').endswith('.local')
if not url.hostname or url.username or url.password or url.query or url.fragment or url.path not in ('', '/'):
    parser.error('Use an origin without credentials, query, fragment or path')
if url.scheme != 'https' and not (url.scheme == 'http' and local):
    parser.error('Use HTTPS; HTTP is restricted to loopback or .local development hosts')
if args.platform == 'device' and url.hostname == '127.0.0.1':
    parser.error('An iPhone cannot reach the Mac through its own loopback address; use the Mac .local hostname')
root = Path(__file__).resolve().parents[1]
path = root / '.local/platform-client' / args.platform / 'PlatformConnection.json'
path.parent.mkdir(parents=True, exist_ok=True)
path.write_text(json.dumps({'baseURL': args.url.rstrip('/')}, indent=2) + '\n')
print(f'Configured {args.platform}: {path.relative_to(root)} (no secrets)')
