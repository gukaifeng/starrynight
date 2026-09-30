"""Read-only type-tree adapter for official build-time Unity containers.

No managed assemblies are loaded. Only control/configuration classes are read;
geometry and animation samples continue to come from the Unity inspector.
"""
from pathlib import Path

CONTROL_CLASSES={91,114,206,319,1101,1102,1107,1109}


def unity_guid(raw):
    # Unity's editor serialized-file GUID stores the low nibble first in each
    # byte. This is not a UUID's big-/little-endian word representation.
    if not isinstance(raw,bytes) or len(raw)!=16:raise ValueError('Invalid binary Unity GUID')
    return ''.join(f'{b & 15:x}{b >> 4:x}' for b in raw)


def normalize(value,externals):
    if isinstance(value,dict):
        if set(value)=={'m_FileID','m_PathID'}:
            file_index=value['m_FileID'];identity=value['m_PathID']
            if not isinstance(file_index,int) or not isinstance(identity,int):raise ValueError('Invalid Unity object pointer')
            if identity==0:return {'fileID':0}
            if file_index==0:return {'fileID':identity}
            if not 1<=file_index<=len(externals):raise ValueError('Unresolved binary external-file index')
            external=externals[file_index-1]
            return {'fileID':identity,'guid':unity_guid(external.guid),'type':external.type}
        return {k:normalize(v,externals) for k,v in value.items()}
    if isinstance(value,tuple) and len(value)==2:
        return {'first':normalize(value[0],externals),'second':normalize(value[1],externals)}
    if isinstance(value,(list,tuple)):return [normalize(v,externals) for v in value]
    if isinstance(value,bytes):return value.hex()
    return value


def read_documents(path):
    import UnityPy
    # Load bytes instead of a directory: never discover unrelated files or
    # execute source plugins while traversing binary references.
    environment=UnityPy.load(Path(path).read_bytes());result={}
    for obj in environment.objects:
        if obj.type.value not in CONTROL_CLASSES:continue
        row=normalize(obj.parse_as_dict(),obj.assets_file.externals)
        if obj.type.value==319 and isinstance(row.get('m_Mask'),list):
            row['m_Mask']=''.join(int(v).to_bytes(4,'little',signed=False).hex() for v in row['m_Mask'])
        result[str(obj.path_id)]=dict(classID=obj.type.value,**row)
    return result


def verify_native_references(evidence,index,read):
    """Cross-check every control object's links against Unity's own reader."""
    cache={};checked=0
    for obj in evidence['objects']:
        guid=obj['guid'];identity=str(obj['fileID'])
        if guid not in index:raise ValueError('Native reference container missing from generated audit')
        if guid not in cache:cache[guid]=read(index[guid]['extractedPath'])
        row=cache[guid].get(identity)
        if row is None:raise ValueError('Native control object missing from binary reader: '+guid+':'+identity)
        def pointers(value,path=''):
            if isinstance(value,dict):
                if 'fileID' in value:
                    if value['fileID']!=0:yield path,(value.get('guid') or guid,int(value['fileID']))
                else:
                    for key,item in value.items():yield from pointers(item,path+'.'+key if path else key)
            elif isinstance(value,list):
                for i,item in enumerate(value):yield from pointers(item,path+'.Array.data['+str(i)+']')
        parsed=dict(pointers(row))
        native={r['property']:(r['guid'],r['fileID']) for r in obj['references']}
        if parsed!=native:
            differences=sorted(k for k in parsed.keys()|native.keys() if parsed.get(k)!=native.get(k))
            raise ValueError('Binary/native reference mismatch: '+guid+':'+identity+' '+str(differences[:8]))
        checked+=len(native)
    return dict(objects=len(evidence['objects']),references=checked,status='passed')
