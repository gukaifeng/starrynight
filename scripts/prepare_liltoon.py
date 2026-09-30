#!/usr/bin/env python3
"""Restore the reviewed MIT lilToon dependency from its official tagged source."""
import hashlib
import json
from pathlib import Path
import urllib.request
import zipfile

ROOT=Path(__file__).resolve().parents[1]
VERSION='2.3.4'
SHA256='e81579d355878ed73880d99a68ab30a8552d55051be603c450f56491bdc66322'
URL='https://codeload.github.com/lilxyzw/lilToon/zip/refs/tags/'+VERSION


def main():
    archive=ROOT/'.local/dependencies'/('liltoon-'+VERSION+'-source.zip')
    folder=archive.with_suffix('')
    archive.parent.mkdir(parents=True,exist_ok=True)
    if not archive.exists():urllib.request.urlretrieve(URL,archive)
    if hashlib.sha256(archive.read_bytes()).hexdigest()!=SHA256:raise ValueError('lilToon source checksum mismatch')
    prefix='lilToon-'+VERSION+'/Assets/lilToon/'
    with zipfile.ZipFile(archive) as data:
        for entry in data.infolist():
            if entry.is_dir() or not entry.filename.startswith(prefix):continue
            relative=Path(entry.filename[len(prefix):])
            if relative.is_absolute() or '..' in relative.parts:raise ValueError('Unsafe dependency path')
            target=folder/relative;target.parent.mkdir(parents=True,exist_ok=True)
            content=data.read(entry)
            if not target.exists() or target.read_bytes()!=content:target.write_bytes(content)
    package=json.loads((folder/'package.json').read_text())
    assert package['name']=='jp.lilxyzw.liltoon' and package['version']==VERSION
    print('LILTOON_VERIFIED',VERSION,SHA256)


if __name__=='__main__':main()
