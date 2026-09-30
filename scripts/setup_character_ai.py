#!/usr/bin/env python3
"""Import a local key CSV without echoing any credentials. No paid calls."""
import argparse, csv, json, os, secrets, subprocess
from pathlib import Path
from urllib.parse import urlparse

ROOT=Path(__file__).resolve().parents[1]
parser=argparse.ArgumentParser()
parser.add_argument('--key-csv',type=Path,required=True)
parser.add_argument('--base-url',help='Development gateway URL, or deployed HTTPS URL')
args=parser.parse_args()
rows=dict(csv.reader(args.key_csv.open(encoding='utf-8-sig')))
key=rows.get('apiKey','').strip()
if not key:raise SystemExit('CSV has no apiKey field')
host=rows.get('apiHost','').strip().rstrip('/')
if not host.startswith('https://'):host='https://'+host
parsed=urlparse(host)
if parsed.scheme!='https' or not parsed.hostname or not parsed.hostname.endswith('.aliyuncs.com'):raise SystemExit('Unexpected API host')
folder=ROOT/'.local/character-ai';folder.mkdir(parents=True,exist_ok=True,mode=0o700)
path=folder/'settings.json'
config=json.loads(path.read_text()) if path.exists() else {}
config.update(api_key=key,host='https://'+parsed.netloc,data_dir=str(folder))
config.setdefault('client_token',secrets.token_urlsafe(32));config.setdefault('admin_token',secrets.token_urlsafe(40))
# Optional operator limits; disabled for conversation by the user's request.
config['enforce_conversation_limits']=False
config.setdefault('max_daily_calls',60);config.setdefault('max_daily_tts_characters',2500)
config.setdefault('max_daily_asr_seconds',120);config.setdefault('max_voice_designs',2)
path.write_text(json.dumps(config,indent=2));path.chmod(0o600)
client=ROOT/'.local/character-ai-client';client.mkdir(exist_ok=True,mode=0o700)
host_name=subprocess.check_output(['scutil','--get','LocalHostName'],text=True).strip()
connection=dict(baseURL=args.base_url or 'http://'+host_name+'.local:8766',clientToken=config['client_token'])
connection_path=client/'Connection.json';connection_path.write_text(json.dumps(connection,indent=2));connection_path.chmod(0o600)
print('Private gateway settings and restricted client connection saved. No provider request made.')
