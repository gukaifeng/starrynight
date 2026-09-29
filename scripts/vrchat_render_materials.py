#!/usr/bin/env python3
"""Convert audited author material data to the host's mobile toon sidecar.

Not a complete lilToon implementation: reports every unsupported source layer.
No original shader code or SDK is installed. PNG processing preserves UV layout.
"""
import json,shutil
from pathlib import Path
import numpy as np
from PIL import Image
from vrchat_source_paths import resolve_source_path

def load(value):return json.loads(Path(value).read_text()) if isinstance(value,(str,Path)) else value
def color(values):return dict(zip(('r','g','b','a'),values))
def linear(v):return np.where(v<=.04045,v/12.92,((v+.055)/1.055)**2.4)
def srgb(v):return np.where(v<=.0031308,v*12.92,1.055*np.maximum(v,0)**(1/2.4)-.055)

def prepare_materials(source_catalog,prefab_report,output_folder,include_hidden=False):
    catalog,inspection=load(source_catalog),load(prefab_report);folder=Path(output_folder);(folder/'textures').mkdir(exist_ok=True)
    all_materials={g:m for a in catalog['archives'] for p in a['packages'] for g,m in p['materialsByGUID'].items()}
    used={g:n for s in inspection['skins'] if include_hidden or s['active'] and s['enabled'] for n,g in zip(s['materials'],s['materialGUIDs'])}
    names={};rows=[];limitations=[];skipped=[];sources={};verified_textures={}
    def texture_path(tex):
        key=(tex['extractedPath'],tex['sha256'])
        if key not in verified_textures:
            verified_textures[key]=resolve_source_path(key[0],expected_sha256=key[1])
        return verified_textures[key]
    def copy_texture(tex,prefix):
        if not tex or not tex.get('extractedPath'):return ''
        if tex.get('scale',[1,1])!=[1,1] or tex.get('offset',[0,0])!=[0,0]:raise ValueError('UV transform needs explicit baking')
        source=texture_path(tex);digest=tex['sha256']
        name=f'textures/{prefix}_{digest[:16]}.png';shutil.copyfile(source,folder/name);return name
    def pixels(tex,size):
        if not tex or not tex.get('extractedPath'):return np.ones((size[1],size[0],4),np.float32)
        im=Image.open(texture_path(tex)).convert('RGBA')
        if im.size!=size:im=im.resize(size,Image.Resampling.LANCZOS)
        return np.asarray(im,dtype=np.float32)/255
    for guid,name in used.items():
        m=all_materials[guid];f=m['source']['floats'];c=m['source']['colors'];t=m['textures'];h=m['conversionHints']
        if name in names and names[name]!=guid:raise ValueError('Conflicting material names')
        names[name]=guid;sources[name]=m
        if h['blendFactorsSource']==dict(src=0,dst=3):
            skipped.append(name);limitations.append(name+': source projected stencil fake-shadow pass omitted; host realtime scene shadows retained.');continue
        if h['mainHSVG']!=[0,1,1,1]:raise ValueError('Main HSVG transform needs implementation')
        def cc(key,default):return color([c.get(key,{}).get(a,d) for a,d in zip('rgba',default)])
        kind='hair' if 'Hair' in name else 'eye' if 'eye' in name else 'face' if name in ('Body','Body_skin') else 'cloth' if 'Outfit' in name else 'accessory'
        alpha='MASK' if h['alphaModeCandidate']=='BLEND' or ('alpha' in name.lower()) else 'OPAQUE'
        if h['alphaModeCandidate']=='BLEND':limitations.append(name+': continuous transparency mapped to alpha cutout 0.12 (mobile depth stability).')
        row=dict(name=name,kind=kind,texture=copy_texture(h['baseColorTexture'],'base'),normal=copy_texture(h['normal']['map'],'normal'),color=color(h['baseColorFactor']),shadeColor=cc('_ShadowColor',[.85,.85,.9,1]),secondShadeColor=cc('_Shadow2ndColor',[.7,.7,.8,1]),rimColor=cc('_RimColor',[0,0,0,1]),alphaMode=alpha,cutoff=.12 if alpha=='MASK' else .5,bumpScale=h['normal']['scale'],matcap='',matcapMask='',matcapColor=color([1,1,1,1]),matcapStrength=0,emission='',emissionColor=color([0,0,0,1]),sourceShadow=bool(f.get('_UseShadow')),sourceRim=bool(f.get('_UseRim')))
        caps=h['matcaps']
        if caps:
            cap=caps[0];row.update(matcap=copy_texture(cap['texture'],'matcap'),matcapMask=copy_texture(cap['mask'],'mask'),matcapColor=color(cap['color']),matcapStrength=cap['blend'])
            row['matcapAdditive']=cap['blendMode']==1
            if len(caps)>1:limitations.append(name+': first authored masked view-dependent MatCap retained; second masked MatCap is archived but not rendered by this UTS adapter.')
        em=h['emission']
        if em['enabled'] and em['map'] and em['map'].get('extractedPath'):
            source=Image.open(texture_path(em['map'])).convert('RGBA');size=source.size
            e=pixels(em['map'],size);mask=pixels(em['blendMask'],size);base=pixels(h['baseColorTexture'],size)
            rgb=linear(e[:,:,:3])*linear(mask[:,:,:3])*mask[:,:,3:4]
            strength=float(em['mainStrength']);rgb*=1-strength+linear(base[:,:,:3])*strength
            rgba=np.concatenate([srgb(rgb),np.ones((*rgb.shape[:2],1))],axis=2)
            out=f'textures/emission_{name}.png';Image.fromarray(np.round(np.clip(rgba,0,1)*255).astype('uint8'),'RGBA').save(folder/out)
            row.update(emission=out,emissionColor=color(em['color']))
            if f.get('_EmissionFluorescence',0):limitations.append(name+': emission mask/main multiplication baked in linear light; illumination-dependent fluorescence approximated by static emission.')
        rows.append(row)
    data=dict(schemaVersion=1,sourceProfile='vrchat-liltoon-v1',materials=rows,limitations=limitations,skippedOverlayMaterials=skipped)
    (folder/'materials.json').write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n')
    # Source material properties are provenance, never dynamically executed.
    (folder/'source-materials.json').write_text(json.dumps(sources,ensure_ascii=False,indent=2)+'\n')
    return dict(materials=rows,byGUID=used,rendererSlots={s['path']:s['materials'] for s in inspection['skins'] if include_hidden or s['active'] and s['enabled']},skippedOverlayMaterials=skipped,limitations=limitations)
