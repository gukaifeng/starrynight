#!/usr/bin/env python3
"""Reproduce the original, deliberately simple XEP integration fixture; no third-party assets."""
from pathlib import Path
import struct,json,sys
sys.path.insert(0,str(Path(__file__).parent))
from environment_tool import seal
ROOT=Path(__file__).resolve().parents[2]
out=ROOT/'environment-packages/imported/courtyard';out.mkdir(parents=True,exist_ok=True)
# One reusable unit cube, explicit normals; geometry is authored, not downloaded.
positions=[];normals=[];indices=[]
for n,corners in [((0,0,1),[(-1,-1,1),(1,-1,1),(1,1,1),(-1,1,1)]),((0,0,-1),[(1,-1,-1),(-1,-1,-1),(-1,1,-1),(1,1,-1)]),((1,0,0),[(1,-1,1),(1,-1,-1),(1,1,-1),(1,1,1)]),((-1,0,0),[(-1,-1,-1),(-1,-1,1),(-1,1,1),(-1,1,-1)]),((0,1,0),[(-1,1,1),(1,1,1),(1,1,-1),(-1,1,-1)]),((0,-1,0),[(-1,-1,-1),(1,-1,-1),(1,-1,1),(-1,-1,1)])]:
 start=len(positions);positions.extend(tuple(v*.5 for v in c) for c in corners);normals.extend([n]*4);indices.extend(start+i for i in [0,1,2,0,2,3])
data=b''.join(struct.pack('<3f',*v) for v in positions)+b''.join(struct.pack('<3f',*v) for v in normals)+struct.pack('<36H',*indices)
colors=[(.73,.72,.63,1),(.77,.80,.72,1),(.38,.45,.34,1),(.50,.36,.24,1)]
doc={'asset':{'version':'2.0','generator':'Xiaoban XEP original fixture'},'scene':0,'scenes':[{'name':'Courtyard','nodes':[0,1,2]}],
 'nodes':[{'name':'Floor','mesh':0,'translation':[0,-.05,0],'scale':[40,.1,40]},{'name':'Surface','children':[]},{'name':'Decor','children':[]}],
 'meshes':[{'name':'Box'+str(i),'primitives':[{'attributes':{'POSITION':0,'NORMAL':1},'indices':2,'material':i}]} for i in range(4)],
 'materials':[{'name':'Material'+str(i),'pbrMetallicRoughness':{'baseColorFactor':c,'metallicFactor':0,'roughnessFactor':.8}} for i,c in enumerate(colors)],
 'buffers':[{'byteLength':len(data)}], 'bufferViews':[{'buffer':0,'byteOffset':0,'byteLength':288,'target':34962},{'buffer':0,'byteOffset':288,'byteLength':288,'target':34962},{'buffer':0,'byteOffset':576,'byteLength':72,'target':34963}],
 'accessors':[{'bufferView':0,'componentType':5126,'count':24,'type':'VEC3','min':[-.5]*3,'max':[.5]*3},{'bufferView':1,'componentType':5126,'count':24,'type':'VEC3'},{'bufferView':2,'componentType':5123,'count':36,'type':'SCALAR'}]}
def box(name,at,size,material,group):
 doc['nodes'][group]['children'].append(len(doc['nodes']));doc['nodes'].append(dict(name=name,mesh=material,translation=at,scale=size))
for x in [-3.3,3.3]:box('Column',[x,1.7,-3.5],[.32,3.4,.32],1,1)
box('Lintel',[0,3.35,-3.5],[7,.35,.4],1,1)
for x in [-4.7,4.7]:
 box('Low wall',[x,.5,0],[.22,1,9],1,1)
 box('Planter',[x*.63,.25,-2.6],[.8,.5,.8],3,2)
 box('Foliage',[x*.63,.95,-2.6],[1.1,.9,1.1],2,2)
box('Bench',[2.7,.45,.1],[1.5,.15,.65],3,2)
for x in [2.15,3.25]:box('Foot',[x,.20,.1],[.12,.4,.55],3,2)
j=json.dumps(doc,separators=(',',':')).encode();j+=b' '*((-len(j))%4);data+=b'\0'*((-len(data))%4)
(out/'environment.glb').write_bytes(struct.pack('<4sII',b'glTF',2,12+8+len(j)+8+len(data))+struct.pack('<II',len(j),0x4E4F534A)+j+struct.pack('<II',len(data),0x004E4942)+data)
m=json.loads((ROOT/'environment-packages/builtins/garden/environment.json').read_text());m.update(id='courtyard',packageId='app.xiaoban.examples.courtyard',packageVersion='1.0.1')
m['display'].update(name='清风小院',description='一方庭院，留给两个人的安静',order=5,thumbnail='Environment_courtyard')
m['source'].update(kind='glb',model='environment.glb');m['bindings']=dict(surface=['Floor','Surface'],accent=['Decor'],decor=['Decor'])
m['license'].update(spdx='CC0-1.0',attribution='Original Xiaoban integration sample, CC0')
(out/'LICENSE.txt').write_text('Original geometry authored for the Xiaoban XEP integration example. Dedicated to the public domain under CC0 1.0: https://creativecommons.org/publicdomain/zero/1.0/\n')
(out/'environment.json').write_text(json.dumps(m,ensure_ascii=False,indent=2)+'\n');seal(out)
print(out)
