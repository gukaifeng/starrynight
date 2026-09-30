#!/usr/bin/env python3
"""Restore only the official mask data used to interpret VRChat control layers.

No SDK C#, DLL, platform animation, or Editor extension is installed. The archive
stays private; its license does not become an app asset redistribution grant.
"""
import hashlib
from pathlib import Path
import re
import urllib.request
import zipfile

ROOT=Path(__file__).resolve().parents[1]
URL='https://github.com/vrchat/packages/releases/download/3.10.5/com.vrchat.avatars-3.10.5.zip'
SHA256='03bdea0c24257070f0e7a73c9033742a1ce0f67463b12a6c2ad29608b1f33a77'


def main():
    archive=ROOT/'.local/dependencies/vrc-avatars-3.10.5.zip';archive.parent.mkdir(parents=True,exist_ok=True)
    if not archive.exists():urllib.request.urlretrieve(URL,archive)
    if hashlib.sha256(archive.read_bytes()).hexdigest()!=SHA256:raise ValueError('SDK reference hash mismatch')
    output=ROOT/'.local/dependencies/vrc-avatar-masks';output.mkdir(exist_ok=True)
    count=0
    with zipfile.ZipFile(archive) as z:
        for name in z.namelist():
            if not name.endswith('.mask') or not name.startswith('Samples/AV3 Demo Assets/'):continue
            meta=z.read(name+'.meta').decode();guid=re.search(r'^guid: ([a-f0-9]{32})$',meta,re.M).group(1)
            (output/(guid+'.mask')).write_bytes(z.read(name));count+=1
    print('VRCHAT_REFERENCE_MASKS_VERIFIED',count,SHA256)


if __name__=='__main__':main()
