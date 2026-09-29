#!/usr/bin/env python3
"""Add portable posture examples to the CC0 RobotExpressive GLB (idempotent)."""
import copy,json,math,struct,sys
from pathlib import Path
from character_tool import seal

def prepare(folder):
    folder=Path(folder);path=folder/'model.glb';raw=path.read_bytes()
    size=struct.unpack_from('<I',raw,12)[0];doc=json.loads(raw[20:20+size]);data=bytearray(raw[28+size:])
    manifest=json.loads((folder/'character.json').read_text())
    if manifest.get('posture'): return
    animations={a['name']:a for a in doc['animations']};nodes=doc['nodes'];parents={c:i for i,n in enumerate(nodes) for c in n.get('children',[])}
    driven=sorted({c['target']['node'] for name in ['Idle','Sitting'] for c in animations[name]['channels'] if c['target']['path']!='weights'})
    def nodepath(i):return (nodepath(parents[i])+'/' if i in parents else '')+nodes[i]['name']
    def read(i):
        a=doc['accessors'][i];v=doc['bufferViews'][a['bufferView']];width={'SCALAR':1,'VEC3':3,'VEC4':4}[a['type']]
        if a['componentType']!=5126:raise ValueError('expected float animation accessor')
        flat=struct.unpack_from('<'+'f'*a['count']*width,data,v.get('byteOffset',0)+a.get('byteOffset',0))
        return [list(flat[j:j+width]) for j in range(0,len(flat),width)]
    def accessor(rows,kind):
        while len(data)%4:data.append(0)
        offset=len(data);flat=[n for row in rows for n in row];data.extend(struct.pack('<'+'f'*len(flat),*flat))
        view=len(doc['bufferViews']);doc['bufferViews'].append(dict(buffer=0,byteOffset=offset,byteLength=len(flat)*4))
        i=len(doc['accessors']);a=dict(bufferView=view,componentType=5126,count=len(rows),type=kind)
        if kind=='SCALAR':a.update(min=[min(flat)],max=[max(flat)])
        doc['accessors'].append(a);return i
    def pose(name,last=False):
        out={(i,k):list(nodes[i].get(k,[0,0,0] if k=='translation' else [0,0,0,1])) for i in driven for k in ['translation','rotation']}
        for c in animations[name]['channels']:
            if c['target']['path']=='weights':continue
            a=animations[name]['samplers'][c['sampler']];out[c['target']['node'],c['target']['path']]=read(a['output'])[-1 if last else 0]
        return out
    idle=pose('Idle');sitting=pose('Sitting',True)
    def addtrack(animation,node,kind,values,times):
        sampler=len(animation['samplers']);animation['samplers'].append(dict(input=accessor([[v] for v in times],'SCALAR'),output=accessor(values,'VEC3' if kind=='translation' else 'VEC4'),interpolation='LINEAR'))
        animation['channels'].append(dict(sampler=sampler,target=dict(node=node,path=kind)))
    # Fill missing pose-owned tracks in all standing actions; preserved original curves still play.
    for name in {a['clip'] for a in manifest['actions']}:
        a=animations[name];existing={(c['target']['node'],c['target']['path']) for c in a['channels']}
        duration=max(read(s['input'])[-1][0] for s in a['samplers'])
        for key,v in idle.items():
            if key not in existing:addtrack(a,*key,[v,v],[0,duration])
    def static(name,values,head_shake=False):
        a=dict(name=name,samplers=[],channels=[])
        for (node,kind),v in values.items():
            if head_shake and nodes[node]['name']=='Head' and kind=='rotation':
                original=next(c for c in animations['No']['channels'] if c['target']==dict(node=node,path=kind))
                sampler=copy.deepcopy(animations['No']['samplers'][original['sampler']]);a['channels'].append(dict(sampler=len(a['samplers']),target=original['target']));a['samplers'].append(sampler)
            else:addtrack(a,node,kind,[v,v],[0,3.0])
        doc['animations'].append(a)
    def multiply(a,b):
        x,y,z,w=a;X,Y,Z,W=b
        return [w*X+x*W+y*Z-z*Y,w*Y-x*Z+y*W+z*X,w*Z+x*Y-y*X+z*W,w*W-x*X-y*Y-z*Z]
    body=next(i for i in driven if nodes[i]['name']=='Body');poses=[]
    static('P_sit',sitting);static('P_sit_No',sitting,True)
    for id,base in [('stand',idle),('sit',sitting)]:
        for tag,degrees in [('low',-4),('high',6)]:
            variant=copy.deepcopy(base);r=math.radians(degrees)/2
            variant[body,'rotation']=multiply(base[body,'rotation'],[math.sin(r),0,0,math.cos(r)])
            static('P_'+id+'_lean_'+tag,variant)
        poses.append(dict(id=id,label='站立' if id=='stand' else '坐下',symbol='figure.stand' if id=='stand' else 'figure.seated.side',support='floor',gaze='follow',transition=1.3,clip='Idle' if id=='stand' else 'P_sit',parameters=[dict(id='lean',label='上身前倾',unit='degrees',min=-4,max=6,initial=0,lowClip='P_'+id+'_lean_low',highClip='P_'+id+'_lean_high')],actions=[dict(action=a['id'],clip=a['clip']) for a in manifest['actions'] if a['id']!='Idle'] if id=='stand' else [dict(action='No',clip='P_sit_No')]))
    manifest['posture']=dict(bones=[nodepath(i) for i in driven],poses=poses)
    manifest['packageVersion']='1.1.0';manifest['compatibility']['minApiMinor']=1;manifest['compatibility']['required'].append('core.posture@1')
    doc['buffers'][0]['byteLength']=len(data)
    js=json.dumps(doc,separators=(',',':')).encode();js+=b' '*((-len(js))%4);data+=b'\0'*((-len(data))%4)
    result=struct.pack('<4sII',b'glTF',2,28+len(js)+len(data))+struct.pack('<II',len(js),0x4e4f534a)+js+struct.pack('<II',len(data),0x004e4942)+data
    path.write_bytes(result);(folder/'character.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n');seal(folder)
if __name__=='__main__':prepare(sys.argv[1])
