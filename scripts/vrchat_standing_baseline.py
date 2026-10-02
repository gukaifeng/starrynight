"""Reviewed neutral standing adaptation for author Idle clips that crouch/tilt.

Only the presentation Idle is changed. Source archives and sampled original
motions remain intact. Coordinates follow the converter's X reflection.
"""
import json
import struct
from pathlib import Path

REVIEWED_STANDING = {'rurune', 'mao', 'mizuki'}

def adapt_standing(model: Path, snapshot: Path):
    raw = bytearray(model.read_bytes())
    size = struct.unpack_from('<I', raw, 12)[0]
    document = json.loads(raw[20:20+size])
    nodes = json.loads(snapshot.read_text())['nodes']
    if len(nodes) > len(document['nodes']):
        raise ValueError('Standing snapshot node count changed')
    idle = next(a for a in document['animations'] if a['name'] == 'Idle')
    changed = 0
    for channel in idle['channels']:
        prop = channel['target']['path']
        if prop not in ('translation', 'rotation', 'scale'):
            continue
        index = channel['target']['node']
        node = nodes[index] if index < len(nodes) else None
        key = {'translation':'position', 'rotation':'rotation', 'scale':'scale'}[prop]
        axes = 'xyzw' if prop == 'rotation' else 'xyz'
        default = {'translation':[0,0,0], 'rotation':[0,0,0,1], 'scale':[1,1,1]}[prop]
        values = ([float(node[key][axis]) for axis in axes] if node is not None
                  else list(document['nodes'][index].get(prop, default)))
        if node is not None and prop == 'translation': values[0] *= -1
        if node is not None and prop == 'rotation': values[1] *= -1; values[2] *= -1
        sampler = idle['samplers'][channel['sampler']]
        if sampler.get('interpolation', 'LINEAR') not in ('LINEAR', 'STEP'):
            raise ValueError('Standing adaptation requires non-cubic samples')
        accessor = document['accessors'][sampler['output']]
        if accessor['componentType'] != 5126 or accessor['type'] != ('VEC4' if prop == 'rotation' else 'VEC3'):
            raise ValueError('Unsupported standing sample format')
        view = document['bufferViews'][accessor['bufferView']]
        offset = 28 + size + view.get('byteOffset',0) + accessor.get('byteOffset',0)
        stride = view.get('byteStride', 4*len(values))
        for frame in range(accessor['count']):
            struct.pack_into('<'+str(len(values))+'f', raw, offset+frame*stride, *values)
        changed += 1
    if not changed: raise ValueError('No Idle skeletal channels found')
    model.write_bytes(raw)
    return dict(kind='host-standing-adaptation', reason='Reviewed author Idle is not an upright initial pose', skeletalChannels=changed)
