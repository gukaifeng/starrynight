#!/usr/bin/env python3
"""Copy generated Unity bundle data without allocating a second APFS asset copy."""
import ctypes
import os
from pathlib import Path
import shutil
import sys


def copy_data(source, target):
    if not source.is_dir() or source.is_symlink() or target.is_symlink():
        raise ValueError('Expected ordinary generated Unity Data directories')
    library=ctypes.CDLL('/usr/lib/libSystem.B.dylib',use_errno=True) if sys.platform=='darwin' else None
    if library:
        library.clonefile.argtypes=[ctypes.c_char_p,ctypes.c_char_p,ctypes.c_int]
    cloned=copied=0
    for src in source.rglob('*'):
        if src.is_symlink():raise ValueError('Unity Data must not contain symlinks')
        if not src.is_file():continue
        dst=target/src.relative_to(source);dst.parent.mkdir(parents=True,exist_ok=True)
        temporary=dst.with_name(dst.name+'.starry-copy.tmp')
        if temporary.exists():temporary.unlink()
        try:
            if library and library.clonefile(os.fsencode(src),os.fsencode(temporary),0)==0:
                shutil.copystat(src,temporary);cloned+=1
            else:
                shutil.copy2(src,temporary);copied+=1
            temporary.replace(dst)
        finally:
            if temporary.exists():temporary.unlink()
    return cloned,copied


if __name__=='__main__':
    if len(sys.argv)!=3:raise SystemExit('Usage: copy_unity_data.py SOURCE_DATA FRAMEWORK_DATA')
    source,target=map(Path,sys.argv[1:])
    if source.name!='Data' or target.name!='Data' or target.parent.name!='UnityFramework.framework':
        raise SystemExit('Destination must be generated UnityFramework.framework/Data')
    cloned,copied=copy_data(source,target)
    print(f'Unity Data copy PASS: {cloned} APFS clones, {copied} ordinary copies')
