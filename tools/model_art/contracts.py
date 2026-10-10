# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

"""Pure model interchange validation; independent of Blender and Godot."""
import math

CAPS = {'pedestrian': (13000, 3500, 1500), 'road': (16000, 6000, 2000),
        'large': (24000, 8000, 3000)}
LARGE = {'train', 'subway', 'ship', 'sailboat', 'boat', 'helicopter', 'plane', 'aircraft'}

def validate_model(metadata: dict) -> list[str]:
    errors = []
    if not isinstance(metadata, dict):
        return ['metadata must be a dictionary']
    def finite(value):
        if not isinstance(value, (float, int)) or isinstance(value, bool): return False
        try: return math.isfinite(value)
        except OverflowError: return False
    def scan(value, path):
        if isinstance(value, float) and not math.isfinite(value): errors.append(f'{path} must be finite')
        elif isinstance(value, dict):
            for key, item in value.items(): scan(item, f'{path}.{key}')
        elif isinstance(value, (list, tuple)):
            for index, item in enumerate(value): scan(item, f'{path}[{index}]')
    scan(metadata, 'metadata')
    for key, expected in {'units':'meters', 'meters_per_tile':16,
                          'source_forward':'+Y', 'source_up':'+Z',
                          'godot_forward':'-Z', 'godot_up':'+Y'}.items():
        if metadata.get(key) != expected: errors.append(f'{key} must be {expected}')
    tier = metadata.get('tier')
    kind = metadata.get('kind')
    if not isinstance(kind, str):
        errors.append('kind must be a string')
        kind = ''
    group = 'pedestrian' if kind == 'pedestrian' else 'large' if kind in LARGE else 'road'
    if tier not in ('near', 'middle', 'far'): errors.append('unknown tier')
    else:
        cap = CAPS[group][('near', 'middle', 'far').index(tier)]
        for key, limit in [('triangles', cap), ('materials', 12 if tier == 'near' else 6)]:
            value = metadata.get(key)
            if not finite(value) or int(value) != value or not 0 < value <= limit:
                errors.append(f'{key} must be a positive integer <= {limit}')
    origin = 'feet' if group == 'pedestrian' else 'waterline' if kind in {'ship','sailboat','boat'} else 'contact'
    if metadata.get('origin') != origin: errors.append(f'origin must be {origin}')
    vectors = []
    for key in ('size_m', 'envelope_m'):
        value = metadata.get(key)
        valid = isinstance(value, (list, tuple)) and len(value) == 3 and all(finite(x) and x > 0 for x in value)
        if not valid: errors.append(f'{key} must contain three positive finite meters')
        vectors.append(value if valid else None)
    if all(v is not None for v in vectors) and any(a > b for a, b in zip(*vectors)):
        errors.append('size exceeds envelope')
    motion = metadata.get('motion', {})
    if not isinstance(motion, dict): errors.append('motion must be a dictionary')
    else:
        def motion_entry(entry):
            for key, value in entry.items():
                if not isinstance(key, str):
                    errors.append('motion keys must be strings')
                    continue
                if key.endswith('axis') and value not in ('X', 'Y', 'Z'): errors.append(f'unknown motion axis {value}')
                if key in ('wheel_radius_m','radius_m') and (not finite(value) or value <= 0): errors.append(f'{key} must be positive finite meters')
                if key == 'radians_per_second' and not finite(value): errors.append('rotor rate must be finite')
            for key in ('wheels','rotors'):
                if key in entry:
                    if not isinstance(entry[key], list): errors.append(f'{key} must be a list')
                    else:
                        for item in entry[key]:
                            if isinstance(item, dict): motion_entry(item)
                            else: errors.append(f'{key} entries must be dictionaries')
        motion_entry(motion)
    return errors
