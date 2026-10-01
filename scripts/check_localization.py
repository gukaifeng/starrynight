#!/usr/bin/env python3
"""Validate shipped catalogs and optionally the compiler's extracted UI keys.

Does not translate character content or contact a paid model.
"""
import argparse
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LANGUAGES = {'zh-Hans', 'zh-Hant', 'en'}
FORMATS = re.compile(r'%(?:\d+\$)?(?:lld|ld|\.[0-9]+f|d|f|@)')

def check(extracted=None):
    errors=[];count=0;catalogs={}
    for path in (ROOT/'ios/CharacterHost/Resources').glob('*.xcstrings'):
        catalog=json.loads(path.read_text());catalogs[path.stem]=catalog['strings']
        if catalog['sourceLanguage']!='zh-Hans':errors.append(f'{path.name}: incorrect source language')
        for key,entry in catalog['strings'].items():
            count+=1
            values=entry.get('localizations',{})
            if set(values)!=LANGUAGES:errors.append(f'{path.name}: missing language for {key!r}')
            source=values.get('zh-Hans',{}).get('stringUnit',{}).get('value',key)
            for language,value in values.items():
                text=value.get('stringUnit',{}).get('value','')
                if not text or sorted(FORMATS.findall(source))!=sorted(FORMATS.findall(text)):
                    errors.append(f'{path.name}: invalid text/placeholders for {key!r} ({language})')
    if extracted:
        for path in Path(extracted).glob('*.stringsdata'):
            data=json.loads(path.read_text())
            if '/scripts/tests/' in data.get('source',''):continue
            for table,entries in data.get('tables',{}).items():
                for entry in entries:
                    if re.search(r'[\u3400-\u9fff]',entry['key']) and entry['key'] not in catalogs.get(table,{}):
                        errors.append(f'{path.name}: untranslated UI key {entry["key"]!r}')
    if errors:raise SystemExit('\n'.join(errors))
    print(f'PASS: {count} UI/system strings, 3 languages, matching interpolation formats')

if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--stringsdata-dir')
    check(parser.parse_args().stringsdata_dir)
