"""Read authored MMD bone curves without importing a runtime MMD interpreter.

VMD uses 30 frames/second and per-segment cubic Bezier timing. Positions and
quaternions remain in source MMD coordinates until the caller converts basis.
"""
import struct
from pathlib import Path
import numpy as np
from prepare_anime_characters import slerp


def read_vmd(path: Path):
    raw=path.read_bytes()
    if not raw.startswith(b'Vocaloid Motion Data 0002'):
        raise ValueError('Unsupported VMD signature: '+str(path))
    count=struct.unpack_from('<I',raw,50)[0]
    if 54+count*111+4>len(raw):raise ValueError('Truncated VMD bones')
    bones={}
    for i in range(count):
        off=54+i*111
        name=raw[off:off+15].split(b'\0')[0].decode('shift_jis')
        frame,*values=struct.unpack_from('<I7f',raw,off+15)
        # Last duplicate frame wins, matching MMD's effective keyed pose.
        bones.setdefault(name,{})[frame]=(np.array(values[:3]),np.array(values[3:]),raw[off+47:off+111])
    off=54+count*111;count=struct.unpack_from('<I',raw,off)[0];off+=4
    morphs={}
    if off+count*23>len(raw):raise ValueError('Truncated VMD morphs')
    for i in range(count):
        p=off+i*23;name=raw[p:p+15].split(b'\0')[0].decode('shift_jis')
        frame,weight=struct.unpack_from('<If',raw,p+15);morphs.setdefault(name,{})[frame]=weight
    return {k:sorted(v.items())for k,v in bones.items()},morphs


def bezier_time(t,controls):
    x1,y1,x2,y2=np.asarray(controls,dtype=float)/127
    lo=np.zeros_like(t);hi=np.ones_like(t)
    for _ in range(18):
        u=(lo+hi)*.5;v=1-u
        x=3*v*v*u*x1+3*v*u*u*x2+u*u*u
        lo=np.where(x<t,u,lo);hi=np.where(x>=t,u,hi)
    u=(lo+hi)*.5;v=1-u
    return 3*v*v*u*y1+3*v*u*u*y2+u*u*u


def sample_bone(track,times):
    if len(track)==1:
        p,q,_=track[0][1]
        return np.tile(p,(len(times),1)),np.tile(q,(len(times),1))
    frames=np.array([x[0]for x in track],dtype=float)/30
    left=np.clip(np.searchsorted(frames,times,side='right')-1,0,len(frames)-2)
    p=np.empty((len(times),3));q=np.empty((len(times),4))
    for i in np.unique(left):
        select=left==i;t=np.clip((times[select]-frames[i])/(frames[i+1]-frames[i]),0,1)
        p0,q0,_=track[i][1];p1,q1,curve=track[i+1][1]
        for axis in range(3):
            w=bezier_time(t,[curve[axis+j*4]for j in range(4)])
            p[select,axis]=p0[axis]+(p1[axis]-p0[axis])*w
        q[select]=slerp(q0,q1,bezier_time(t,[curve[3+j*4]for j in range(4)]))
    return p,q
