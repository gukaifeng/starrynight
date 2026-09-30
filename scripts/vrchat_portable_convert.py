#!/usr/bin/env python3
"""Convert trusted Unity prefab snapshots to portable mesh/motion/material data.

Unlike FBX-name recipes, coordinates and bind matrices come from the effective
Unity prefab. Source blendshapes use glTF sparse accessors without discarding
editable shapes. Original shader properties remain typed data, never code.
"""
from __future__ import annotations
import argparse
import copy
import hashlib
import json
from pathlib import Path
import re
import struct
import shutil
import numpy as np
from prepare_anime_characters import GLB, paths
from audit_vrchat_archives import material_inventory
from vrchat_materials import vector
from vrchat_controls import build as build_controls
from vrchat_conversion_signature import signature

MIRROR_P=np.array([-1.,1.,1.],np.float32)
MIRROR_Q=np.array([1.,-1.,-1.,1.],np.float32)


def write_json(path,value):
    path.parent.mkdir(parents=True,exist_ok=True)
    path.write_text(json.dumps(value,ensure_ascii=False,indent=2,allow_nan=False)+'\n')


class PortableGLB(GLB):
    def __init__(self):
        self.doc=dict(asset=dict(version='2.0',generator='StarryNight portable avatar adapter 1'),
                      scene=0,scenes=[dict(nodes=[0])],nodes=[],meshes=[],skins=[],materials=[],
                      accessors=[],bufferViews=[],animations=[])
        self.data=bytearray()

    def sparse(self,values):
        values=np.asarray(values,dtype='<f4').reshape(-1,3)
        present=np.flatnonzero(np.any(values!=0,axis=1))
        if len(present)>.65*len(values):return self.add(values,'VEC3')
        accessor=dict(componentType=5126,count=len(values),type='VEC3',min=values.min(axis=0).tolist(),max=values.max(axis=0).tolist())
        if len(present):
            index=self.add(present,'SCALAR',5123 if len(values)<65536 else 5125)
            value=self.add(values[present],'VEC3')
            accessor['sparse']=dict(count=len(present),indices=dict(bufferView=self.doc['accessors'][index]['bufferView'],componentType=self.doc['accessors'][index]['componentType']),values=dict(bufferView=self.doc['accessors'][value]['bufferView']))
        result=len(self.doc['accessors']);self.doc['accessors'].append(accessor);return result


def convert_geometry(folder):
    geometry=json.loads((folder/'geometry.json').read_text())
    binary=np.memmap(folder/'geometry.bin',mode='r',dtype=np.uint8)
    b=PortableGLB();g=b.doc;index={n['path']:i for i,n in enumerate(geometry['nodes'])}
    notes=list(geometry['limitations']);shape_frames=[]
    def array(slice):
        return np.ndarray((slice['count'],slice['width']),dtype='<f4' if slice['type']=='f32' else '<i4',buffer=binary,offset=slice['offset']).copy()
    def values(value,axes):return np.array([value[a] for a in axes],np.float32)
    for i,n in enumerate(geometry['nodes']):
        node=dict(name='Avatar' if i==0 else n['name'],translation=(values(n['position'],'xyz')*MIRROR_P).tolist(),rotation=(values(n['rotation'],'xyzw')*MIRROR_Q).tolist(),scale=values(n['scale'],'xyz').tolist())
        g['nodes'].append(node)
        if n['parent']>=0:g['nodes'][n['parent']].setdefault('children',[]).append(i)
    materials={}
    for s in geometry['skins']:
        node=g['nodes'][index[s['path']]]
        attr=dict(POSITION=b.add(array(s['position'])*MIRROR_P,'VEC3'))
        if s['normal']['count']:attr['NORMAL']=b.add(array(s['normal'])*MIRROR_P,'VEC3')
        if s['uv']['count']:
            uv=array(s['uv']);uv[:,1]=1-uv[:,1];attr['TEXCOORD_0']=b.add(uv,'VEC2')
        if s['bones']:
            joints=array(s['joints']);weights=array(s['weights'])
            for part in range(joints.shape[1]//4):
                attr['JOINTS_'+str(part)]=b.add(joints[:,part*4:(part+1)*4],'VEC4',5123)
                attr['WEIGHTS_'+str(part)]=b.add(weights[:,part*4:(part+1)*4],'VEC4')
            matrices=array(s['bindposes']).reshape(-1,4,4)
            # Source is column-major; conjugation by X reflection has the same
            # element-wise signs in both column/row-major storage.
            signs=np.array([-1,1,1,1],np.float32)
            matrices*=signs[None,:,None]*signs[None,None,:]
            node['skin']=len(g['skins'])
            g['skins'].append(dict(joints=[index[path] for path in s['bones']],inverseBindMatrices=b.add(matrices.reshape(-1,16),'MAT4')))
        targets=[];names=[];defaults=[]
        for shape in s['shapes']:
            if len(shape['frames'])!=1 or abs(shape['frames'][0]['weight']-100)>.001:
                shape_frames.append(dict(renderer=s['path'],shape=shape['name'],frames=[f['weight'] for f in shape['frames']]))
            frame=shape['frames'][-1]
            factor=100/max(abs(frame['weight']),.0001)
            targets.append(dict(POSITION=b.sparse(array(frame['position'])*MIRROR_P*factor),NORMAL=b.sparse(array(frame['normal'])*MIRROR_P*factor)))
            names.append(shape['name']);defaults.append(shape['weight']/100)
        primitives=[]
        for p in s['primitives']:
            guid=p['guid'] or 'missing'
            if guid not in materials:
                materials[guid]=len(g['materials'])
                g['materials'].append(dict(name='mat_'+guid,pbrMetallicRoughness=dict(baseColorFactor=[1,1,1,1],metallicFactor=0,roughnessFactor=.8),doubleSided=True))
            triangles=array(p['indices']).reshape(-1,3)[:,[0,2,1]]
            primitive=dict(attributes=attr,indices=b.add(triangles.reshape(-1),'SCALAR',5125),material=materials[guid],mode=4)
            if targets:primitive['targets']=targets
            primitives.append(primitive)
        node['mesh']=len(g['meshes']);mesh=dict(name=s['path'].split('/')[-1],primitives=primitives)
        if targets:mesh.update(weights=defaults,extras=dict(targetNames=names))
        g['meshes'].append(mesh)
    return b,geometry,index,dict(limitations=notes,nonlinearMorphFrames=shape_frames,materialGUIDs=list(materials))


def curve_value(keys,time):
    if not keys:return 0
    if time<=keys[0]['time']:return keys[0]['value']
    for left,right in zip(keys,keys[1:]):
        if time>right['time']:continue
        span=right['time']-left['time']
        if span<=0:return right['value']
        if not np.isfinite(left['outTangent']) or not np.isfinite(right['inTangent']):return left['value']
        t=(time-left['time'])/span
        return (2*t**3-3*t**2+1)*left['value']+(t**3-2*t**2+t)*span*left['outTangent']+(-2*t**3+3*t**2)*right['value']+(t**3-t**2)*span*right['inTangent']
    return keys[-1]['value']


def append_motions(b,geometry,index,folder):
    source=json.loads((folder/'motions.json').read_text())
    g=b.doc;result={};glb_paths=paths(g)
    for motion in source['motions']:
        animation=dict(name='VRC_'+motion['guid'],samplers=[],channels=[])
        times=np.array(motion['times'],np.float32)
        for track in motion['tracks']:
            node=index[track['path']]
            for source_key,target,kind,axes,multiplier in [('positions','translation','VEC3','xyz',MIRROR_P),('rotations','rotation','VEC4','xyzw',MIRROR_Q),('scales','scale','VEC3','xyz',np.ones(3))]:
                value=np.array([[v[k] for k in axes] for v in track[source_key]],np.float32)*multiplier
                if target=='rotation':
                    value/=np.maximum(np.linalg.norm(value,axis=1,keepdims=True),1e-12)
                    for i in range(1,len(value)):
                        if np.dot(value[i-1],value[i])<0:value[i]*=-1
                if np.max(abs(value-np.array(g['nodes'][node][target])))<1e-6:continue
                if np.max(abs(value-value[0]))<1e-6:
                    sample_times=times[[0,-1]];value=value[[0,-1]]
                else:sample_times=times
                animation['channels'].append(dict(sampler=len(animation['samplers']),target=dict(node=node,path=target)))
                animation['samplers'].append(dict(input=b.add(sample_times,'SCALAR'),output=b.add(value,kind),interpolation='LINEAR'))
        if animation['channels']:
            g['animations'].append(animation)
            result[motion['guid']]=dict(clip=animation['name'],bones=sorted({glb_paths[c['target']['node']] for c in animation['channels']}),duration=max(motion['duration'],1),loop=motion['loop'])
    # The neutral baseline is explicit and keys every node, so ending an overlay
    # can restore author defaults. An authored stand/idle clip takes precedence.
    baseline=dict(name='Idle',samplers=[],channels=[])
    preferred=[m for m in source['motions'] if re.search(r'(stand[_ ]?still|idle)',m['name'],re.I) and m['guid'] in result
               and not re.search(r'(hand|finger|afk|sleep|face|eye|ear|tail|chest|breast|foot)',m['name']+' '+m['path'],re.I)
               and any(t['path']==next((h['path'] for h in geometry['human'] if h['human']=='Hips'),None) for t in m['tracks'])]
    baseline_nodes=g['nodes']
    if preferred:
        chosen=max(preferred,key=lambda m:(bool(re.search('stand',m['name'],re.I)),-len(m['name'])))
        baseline=copy.deepcopy(next(a for a in g['animations'] if a['name']==result[chosen['guid']]['clip']));baseline['name']='Idle'
        source['baseline']=dict(kind='author-clip',guid=chosen['guid'],name=chosen['name'])
    else:
        standing=json.loads((folder/'host-standing.json').read_text())
        baseline_nodes=[dict(translation=(np.array([n['position'][a] for a in 'xyz'])*MIRROR_P).tolist(),rotation=(np.array([n['rotation'][a] for a in 'xyzw'])*MIRROR_Q).tolist(),scale=[n['scale'][a] for a in 'xyz']) for n in standing['nodes']]
        source['baseline']=dict(kind='host-standing-adaptation',reason='Source delegates its body baseline to the VRChat platform; no matching authored standing clip is present')
    present={(c['target']['node'],c['target']['path']) for c in baseline['channels']}
    times=b.add([0,1],'SCALAR')
    for i,node in enumerate(baseline_nodes):
        for prop,kind in [('translation','VEC3'),('rotation','VEC4'),('scale','VEC3')]:
            if (i,prop) in present:continue
            baseline['channels'].append(dict(sampler=len(baseline['samplers']),target=dict(node=i,path=prop)))
            baseline['samplers'].append(dict(input=times,output=b.add([node[prop],node[prop]],kind),interpolation='LINEAR'))
    g['animations'].insert(0,baseline)
    return source,result


def export_materials(stage,geometry,output,shader_root):
    audit=json.loads((stage/'source-audit.json').read_text())
    assets={a['guid']:a for ar in audit['archives'] for package in ar['unityPackages'] for a in package['assets']}
    shaders={};properties={}
    for path in shader_root.rglob('*.shader'):
        meta=Path(str(path)+'.meta')
        if not meta.exists():continue
        guid=re.search(r'guid: ([0-9a-f]{32})',meta.read_text())
        shader_text=path.read_text();name=re.search(r'Shader\s+"([^"]+)"',shader_text)
        if guid and name:
            shaders[guid[1]]=name[1]
            properties[name[1]]=set(re.findall(r'^\s*(?:\[[^\]]+\]\s*)*([_A-Za-z][_A-Za-z0-9]*)\s*\(',shader_text,re.M))
    materials=[];notes=[];seen=set()
    primitives=[p for skin in geometry['skins'] for p in skin['primitives']]
    motions=json.loads((stage/'Inspection/Portable'/geometry['role']/'motions.json').read_text())
    for m in motions['motions']:
        for c in m['objects']:
            for key in c['keys']:
                if key['guid'] in assets and assets[key['guid']]['extension']=='.mat':
                    primitives.append(dict(guid=key['guid'],material=Path(assets[key['guid']]['path']).stem))
    for primitive in primitives:
            guid=primitive['guid']
            if guid in seen:continue
            seen.add(guid)
            asset=assets.get(guid)
            if not asset:raise ValueError('Missing author material: '+guid)
            material_text=Path(asset['extractedPath']).read_text();source=material_inventory(material_text,assets)
            ints=re.search(r'^    m_Ints:\n([\s\S]*?)(?=^    \w|\Z)',material_text,re.M)
            if ints:source['floats'].update({m[1]:float(m[2]) for m in re.finditer(r'^    - (\S+): ([-+\d.eE]+)$',ints[1],re.M)})
            shader=shaders.get(source['shader'].get('guid',''))
            if not shader:
                shader='lilToon'
                notes.append(dict(material=guid,sourceShader=source['shader'],reason='Unresolved shader; lilToon fallback requires visual comparison'))
            row=dict(name='mat_'+guid,sourceName=primitive['material'],shader=shader,renderQueue=source['customRenderQueue'],
                     floats=[dict(name=k,value=v) for k,v in source['floats'].items()],
                     colors=[dict(name=k,value=v) for k,v in source['colors'].items()],textures=[])
            for binding in source['textureBindings']:
                prop=binding['property']
                if prop not in properties.get(shader,set()):continue
                feature=next((flag for prefix,flag in [('_MatCap2nd','_UseMatCap2nd'),('_MatCap','_UseMatCap'),('_Emission2nd','_UseEmission2nd'),('_Emission','_UseEmission'),('_Glitter','_UseGlitter'),('_Reflection','_UseReflection'),('_Rim','_UseRim'),('_Shadow','_UseShadow'),('_Bump2nd','_UseBump2ndMap'),('_Bump','_UseBumpMap'),('_Main2nd','_UseMain2ndTex'),('_Main3rd','_UseMain3rdTex'),('_AudioLink','_UseAudioLink')] if prop.startswith(prefix)),None)
                animated=bool(feature and any(c['property'].endswith('.'+feature) and any(k['value']>0 for k in c['keys']) for m in motions['motions'] for c in m['curves']))
                inactive=(feature and source['floats'].get(feature,0)<=0 and not animated) or (prop.startswith('_Outline') and 'Outline' not in shader) or (prop.startswith('_Fur') and 'Fur' not in shader) or (prop=='_AlphaMask' and source['floats'].get('_AlphaMaskMode',0)==0)
                if inactive:continue
                tex=assets.get(binding['texture'].get('guid'))
                if not tex:
                    if binding['texture'].get('guid','').startswith('0000000000000000'):continue
                    notes.append(dict(material=guid,property=binding['property'],reason='Unresolved source texture',reference=binding['texture']));continue
                path=Path(tex['extractedPath']);digest=hashlib.sha256(path.read_bytes()).hexdigest()
                meta=Path(tex['metaPath']).read_text(errors='replace') if tex.get('metaPath') else ''
                normal=bool(re.search(r'^\s+textureType:\s*1\s*$',meta,re.M))
                linear=bool(re.search(r'^\s+sRGBTexture:\s*0\s*$',meta,re.M))
                relative='textures/'+('normal_' if normal else 'linear_' if linear else 'color_')+digest[:24]+path.suffix.lower()
                target=output/relative;target.parent.mkdir(exist_ok=True)
                if not target.exists():__import__('shutil').copyfile(path,target)
                row['textures'].append(dict(name=binding['property'],path=relative,scale=vector(binding['scale'],'xy',[1,1]),offset=vector(binding['offset'],'xy',[0,0])))
            materials.append(row)
    write_json(output/'materials.json',dict(schemaVersion=2,sourceProfile='liltoon-properties-v1',materials=materials,limitations=notes))
    return notes


def portable_secondary(stage,role,b,geometry):
    from vrchat_physics import build_physics
    audit=json.loads((stage/'source-audit.json').read_text())
    full=build_physics(audit,stage/'Inspection')['roles'][0]
    index={n['path']:i for i,n in enumerate(geometry['nodes'])};nodes=b.doc['nodes'];segments={};notes=[]
    for chain in full['chains']:
        if not chain['enabled'] or not chain['activeInHierarchy']:continue
        root=chain['rootPath'] or ''
        driven={index[p] for p in chain['transformPaths'] if p in index}
        params=chain['parameters'];radius=min(.04,max(0,float(params.get('radius') or .005)))
        wind='hair' if re.search(r'hair|髪|アホ毛',root,re.I) else 'cloth' if re.search(r'cloth|skirt|sleeve|ribbon|coat|sailor|cape|tie|dress|服',root,re.I) else 'none'
        for i in driven:
            children=[j for j in nodes[i].get('children',[]) if j in driven]
            if not children and chain.get('endpointPositionLocal'):
                v=chain['endpointPositionLocal'];delta=np.array([v.get(a,0) for a in 'xyz'])*MIRROR_P
                if np.linalg.norm(delta)>1e-5:
                    tip=len(nodes);nodes.append(dict(name='XCP_tip_'+str(i),translation=delta.tolist()));nodes[i].setdefault('children',[]).append(tip);children=[tip]
            for tip in children:
                length=sum(v*v for v in nodes[tip].get('translation',[0,0,0]))
                if length>1e-8 and (i not in segments or length>segments[i][0]):segments[i]=(length,tip,radius,wind)
    p=paths(b.doc)
    strands=[dict(bone=p[i],tip=p[tip],radius=radius,angle=12 if wind=='hair' else 8,wind=wind,windResponse=.8) for i,(length,tip,radius,wind) in sorted(segments.items(),key=lambda x:p[x[0]].count('/'))]
    colliders=[]
    for source in full['colliders']:
        if not source['enabled'] or not source['activeInHierarchy']:continue
        shape=source['shape'];node=index.get(source['rootPath'])
        if node is None or shape['shapeType'] not in (0,1) or shape['insideBounds']:
            notes.append(dict(kind='unadapted-collider',root=source['rootPath']));continue
        q=shape['rotation'] or dict(x=0,y=0,z=0,w=1);q=np.array([q[k] for k in 'xyzw'],float);q/=max(np.linalg.norm(q),1e-12)
        center=np.array([(shape['position'] or {}).get(k,0) for k in 'xyz'],float)
        radius=float(shape['radius'] or 0);half=max(0,float(shape['height'] or 0)*.5-radius) if shape['shapeType']==1 else 0
        for offset in ([-half,0,half] if half else [0]):
            delta=np.array([0,offset,0],float);v=center+delta+2*np.cross(q[:3],np.cross(q[:3],delta)+q[3]*delta)
            colliders.append(dict(bone=p[node],offset=dict(zip('xyz',v)),radius=radius))
    return dict(schemaVersion=2,ambientHairAngle=6.5,ambientClothAngle=2.6,strands=strands,colliders=colliders),dict(source=full,limitations=notes+[
        dict(kind='solver-adaptation',detail='Host damped springs with bounded wind, not numerical VRChat PhysBone equivalence; source coefficients and collider associations are retained in this receipt.')])


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--stage',type=Path,required=True)
    p.add_argument('--role',required=True)
    p.add_argument('--output',type=Path,required=True)
    p.add_argument('--shaders',type=Path,default=Path('.local/dependencies/liltoon-2.3.4-source'))
    a=p.parse_args();a.output.mkdir(parents=True,exist_ok=True)
    snapshot=a.stage/'Inspection/Portable'/a.role
    b,geometry,index,report=convert_geometry(snapshot)
    source,motions=append_motions(b,geometry,index,snapshot)
    controls,descriptor=build_controls(a.stage,geometry)
    secondary,physics=portable_secondary(a.stage,a.role,b,geometry)
    b.write(a.output/'model.glb')
    report['materialLimitations']=export_materials(a.stage,geometry,a.output,a.shaders)
    report.update(role=a.role,meshBytes=(a.output/'model.glb').stat().st_size,nodes=len(index),morphs=sum(len(s['shapes']) for s in geometry['skins']),clips=len(motions),baseline=source['baseline'],controls=len(controls['controls']),controllerLimitations=controls['limitations'],conversionSignature=signature(a.stage,a.role))
    write_json(a.output/'portable-conversion.json',report)
    write_json(a.output/'motion-map.json',motions)
    write_json(a.output/'avatar-controls.json',controls)
    # Unity's trusted curve reader accepts stepped tangents as Infinity; normalize
    # them to an explicit step marker before entering the strict JSON package.
    for motion in source['motions']:
        for curve in motion['curves']:
            for key in curve['keys']:
                key['steppedIn']=not np.isfinite(key['inTangent']);key['steppedOut']=not np.isfinite(key['outTangent'])
                if key['steppedIn']:key['inTangent']=0
                if key['steppedOut']:key['outTangent']=0
    write_json(a.output/'avatar-motions.json',source)
    write_json(a.output/'avatar-geometry.json',dict(nodes=geometry['nodes'],human=geometry['human'],skins=[dict(path=s['path'],enabled=s['enabled']) for s in geometry['skins']]))
    write_json(a.output/'avatar-descriptor.json',descriptor)
    write_json(a.output/'secondary-motion.json',secondary)
    write_json(a.output/'physics-source.json',physics)
    print(json.dumps(report,ensure_ascii=False,indent=2))


if __name__=='__main__':main()
