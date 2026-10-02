"""Select existing eyelid morphs from inspected data, without loading source code.

An unused SDK descriptor can contain index zero (often a mouth). Eyelid type
must therefore be checked before interpreting the indices. A nonempty name is
also insufficient: every selected shape must have finite, nonzero geometry.
"""
import re
import struct

import numpy as np


def moving_shape(shape, binary):
    moving = False
    for frame in shape.get('frames', []):
        span = frame['position']
        if span['type'] != 'f32' or span['width'] != 3 or span['count'] < 0:
            raise ValueError('Invalid eyelid geometry span')
        if span['offset'] < 0 or span['offset'] + span['count'] * 12 > binary.stat().st_size:
            raise ValueError('Eyelid geometry span exceeds inspected binary')
        if not span['count']:
            continue
        values = np.memmap(binary, dtype='<f4', mode='r', offset=span['offset'], shape=(span['count'], 3))
        if not np.isfinite(values).all():
            raise ValueError('Nonfinite eyelid geometry')
        nonzero = bool(np.any(np.abs(values) > 1e-7))
        del values
        moving |= nonzero
    return moving


def select_blink_bindings(descriptor, skin, binary):
    """Return one bilateral morph or an exact left/right pair on the head skin.

    This is a host timing adapter. Source tracking-control behaviors continue
    to decide whether automatic blinking may run during authored expressions.
    No layer-name heuristic claims that an author controller already blinks.
    """
    shapes = skin['shapes']
    names = [s['name'] for s in shapes]
    mouth_names = set(descriptor.get('VisemeBlendShapes') or [])
    mouth_names.add(descriptor.get('MouthOpenBlendShapeName', ''))

    def binding(name):
        if name in mouth_names or names.count(name) != 1:
            return None
        shape = shapes[names.index(name)]
        if not moving_shape(shape, binary):
            return None
        return dict(renderer='Avatar/' + skin['path'], shape=name, weight=1)

    eyes = descriptor.get('customEyeLookSettings') or {}
    indices = eyes.get('eyelidsBlendshapes')
    if eyes.get('eyelidType') == 2:
        if isinstance(indices, str) and re.fullmatch(r'(?:[0-9a-fA-F]{8})+', indices):
            index = struct.unpack('<i', bytes.fromhex(indices[:8]))[0]
        elif isinstance(indices, list) and indices and isinstance(indices[0], int):
            index = indices[0]
        else:
            index = -1
        if 0 <= index < len(names):
            chosen = binding(names[index])
            if chosen:
                return [chosen], 'source-descriptor'

    # Exact neutral-closure aliases observed in the audited source packages.
    # Smile/wink, pupil size and highlight morphs are intentionally ineligible.
    for pattern in (r'vrc[._]blink\s*', r'まばたき', r'blink', r'eye[._]?blink',
                    r'auto[._]blink', r'eyelid[._]blink', r'blink_eye_close'):
        matches = [n for n in names if re.fullmatch(pattern, n, re.I)]
        if len(matches) == 1:
            chosen = binding(matches[0])
            if chosen:
                return [chosen], 'source-neutral-eyelid'
    for left, right in (('bs.eye_close_L', 'bs.eye_close_R'),
                        ('vrc.blink_left', 'vrc.blink_right'),
                        ('eyeBlinkLeft', 'eyeBlinkRight')):
        chosen = [binding(left), binding(right)]
        if all(chosen):
            return chosen, 'source-paired-eyelids'
    return [], 'requires-eyelid-review'
