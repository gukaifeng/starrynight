"""Resolve source Material Variant inheritance before emitting typed properties.

Only serialized data is read. Explicit null texture overrides clear a parent
texture; an absent override inherits it. Missing/cyclic parents fail closed.
"""
import copy
import re
from pathlib import Path
from audit_vrchat_archives import material_inventory,inline_reference,field

def effective_material(guid,assets,visited=()):
    if guid in visited:raise ValueError('Cyclic material parent: '+guid)
    asset=assets.get(guid)
    if not asset or asset['extension'] not in ('.mat','.asset'):
        raise ValueError('Missing material parent: '+guid)
    text=Path(asset['extractedPath']).read_text()
    if asset['extension']=='.asset' and not re.search(r'^--- !u!21 &\d+\nMaterial:',text,re.M):
        raise ValueError('Material parent .asset is not a Unity Material: '+guid)
    current=material_inventory(text,assets)
    ints=re.search(r'^    m_Ints:\n([\s\S]*?)(?=^    \w|\Z)',text,re.M)
    if ints:current['floats'].update({m[1]:float(m[2]) for m in re.finditer(r'^    - (\S+): ([-+\d.eE]+)$',ints[1],re.M)})
    parent=inline_reference(field(text,'m_Parent')).get('guid')
    if not parent:return current
    base=copy.deepcopy(effective_material(parent,assets,visited+(guid,)))
    # Shader selection is stored on the variant, independently of property
    # inheritance. Confirmed with Unity 6000.3's Material API on the author's
    # opaque parent / cutout child; inheriting the parent shader erases cutouts.
    if current['shader'].get('guid'):base['shader']=current['shader']
    base['floats'].update(current['floats']);base['colors'].update(current['colors'])
    textures={t['property']:t for t in base['textureBindings']}
    for match in re.finditer(r'^    - (\S+):\n        m_Texture: (\{[^}]*\})\n        m_Scale: (\{[^}]*\})\n        m_Offset: (\{[^}]*\})',text,re.M):
        ref=inline_reference(match[2],assets)
        if ref.get('fileID'):textures[match[1]]=dict(property=match[1],texture=ref,scale=match[3],offset=match[4])
        else:textures.pop(match[1],None)
    base['textureBindings']=list(textures.values())
    # Unity MaterialSerializedProperty.CustomRenderQueue = 1 << 4.
    if int(field(text,'m_ModifiedSerializedProperties') or 0)&16:
        base['customRenderQueue']=current['customRenderQueue']
    base['inheritedMaterials']=[parent]+base.get('inheritedMaterials',[])
    return base
