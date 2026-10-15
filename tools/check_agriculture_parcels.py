#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
"""Verify public farm modules without Blender or private editable masters."""
from collections import Counter
import hashlib
import json
import math
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
from check_agriculture_assets import read_glb, positions, accessor_values, transform, multiply
from model_art.agricultural_parcels import KEYS


def manifest():
    return json.loads((ROOT / 'game/assets/agriculture/parcel_modules.json').read_text())


def budget(key):
    if key == 'farm_shed': return 8000
    if key == 'shade_shelter': return 4000
    return 400 if key.endswith('_strip') or key.startswith('fence_') else 2000


def _nodes(doc, binary, collision):
    parents = {child: i for i, n in enumerate(doc['nodes']) for child in n.get('children', [])}
    def world(i):
        local = transform(doc['nodes'][i])
        return multiply(world(parents[i]), local) if i in parents else local
    for i, node in enumerate(doc['nodes']):
        if 'mesh' not in node or node.get('name', '').endswith('-colonly') != collision: continue
        matrix = world(i)
        for primitive in doc['meshes'][node['mesh']]['primitives']:
            points = positions(doc, binary, primitive['attributes']['POSITION'])
            points = [tuple(sum(matrix[r][c] * (*p, 1)[c] for c in range(4)) for r in range(3)) for p in points]
            yield primitive, points



def unique_visible_triangles(doc, binary):
    """Reject exactly coincident authored triangles within each material."""
    seen = set()
    for primitive, points in _nodes(doc, binary, False):
        indices = [row[0] for row in accessor_values(doc, binary, primitive['indices'])]
        for i in range(0, len(indices), 3):
            vertices = tuple(sorted(tuple(round(x, 5) for x in points[j]) for j in indices[i:i+3]))
            key = (primitive['material'], vertices)
            assert key not in seen, 'coincident visible authored triangle'
            seen.add(key)


def visible_components(doc, binary, material):
    """Connected decoded surfaces, independent of export vertex splitting."""
    for primitive, points in _nodes(doc, binary, False):
        if doc['materials'][primitive['material']]['name'] != material: continue
        indices = [row[0] for row in accessor_values(doc, binary, primitive['indices'])]
        groups = []
        for i in range(0,len(indices),3):
            triangle = {tuple(round(x,5) for x in points[j]) for j in indices[i:i+3]}
            merged = set(triangle)
            for g in range(len(groups)-1,-1,-1):
                if triangle & groups[g]: merged.update(groups.pop(g))
            groups.append(merged)
        yield from groups


def validate_shed_details(doc, binary, x, z, width, depth, height):
    details = []
    for points in visible_components(doc,binary,'farm_cream'):
        lo, hi = _bounds(list(points))
        size = [hi[i]-lo[i] for i in range(3)]
        side = abs(size[0]-.1)<1e-3 and abs(size[2]-1.7)<1e-3 and abs((lo[2]+hi[2])/2-z)<1e-3
        rear = abs(size[0]-1.9)<1e-3 and abs(size[2]-.1)<1e-3 and abs((lo[0]+hi[0])/2-x)<1e-3
        door = abs(size[0]-2.9)<1e-3 and abs(size[2]-.14)<1e-3 and abs((lo[0]+hi[0])/2-x)<1e-3
        if side or rear or door:
            assert lo[1]>=-.001 and hi[1]<=height+.12-.15+1e-4, 'shed detail crosses wall/eave clearance'
            details.append('side' if side else ('rear' if rear else 'door'))
    assert Counter(details)==Counter(side=2,rear=1,door=1), 'missing shed window/door details'


def _bounds(points):
    assert points, 'missing geometry bounds'
    return [[min(v[i] for v in points) for i in range(3)], [max(v[i] for v in points) for i in range(3)]]


def exported_collision_bounds(doc, binary):
    return _bounds([p for _, points in _nodes(doc, binary, True) for p in points])


def _near(actual, expected):
    return len(actual) == len(expected) and all(abs(a - b) < 1e-4 for a, b in zip(actual, expected))


def _private(value):
    if isinstance(value, dict):
        assert 'extras' not in value, 'private extras'
        for child in value.values(): _private(child)
    elif isinstance(value, list):
        for child in value: _private(child)
    elif isinstance(value, str):
        assert not re.search(r'/Users/|/private/|/tmp/|\.blend(?:1)?\b|prompt', value, re.I), 'private path/process metadata'


def validate_module(key, entry, doc, binary):
    label = key + ': '
    assert entry['path'] == 'res://assets/agriculture/parcel-kit/' + key + '.glb', label + 'path'
    path = ROOT / 'game' / entry['path'].removeprefix('res://')
    assert hashlib.sha256(path.read_bytes()).hexdigest() == entry['model_sha256'], label + 'hash'
    _private(doc); _private(entry)
    assert all('uri' not in b for b in doc.get('buffers', [])), label + 'external buffer'
    assert doc.get('images') and all('uri' not in i and 'bufferView' in i for i in doc['images']), label + 'external image'
    assert all(s.get('wrapS', 10497) == 10497 and s.get('wrapT', 10497) == 10497 for s in doc.get('samplers', [])), label + 'material repeat'
    assert not doc.get('skins') and not doc.get('animations'), label + 'static module'
    assert all(m.get('name', '').startswith('farm_') for m in doc['materials']), label + 'original material'
    # Collision meshes may share an unnamed default material; exporter uses none.
    materials = sorted(m['name'] for m in doc['materials'])
    assert materials == entry['materials'], label + 'material roster'
    for n in doc['nodes']:
        assert all(k not in n for k in ('translation', 'rotation', 'scale', 'matrix')), label + 'baked metre transform'
    assert entry['origin'] == [0, 0, 0], label + 'origin'
    envelope = entry['placement_bounds']
    assert entry['collision_bounds'] == envelope, label + 'complete collision contract'
    colliders = [n for n in doc['nodes'] if n.get('name', '').endswith('-colonly')]
    assert len(colliders) == entry['collider_count'] == 1, label + 'collision envelope count'
    visible = []; triangles = 0
    for p, points in _nodes(doc, binary, False):
        assert p.get('mode', 4) == 4, label + 'triangle topology'
        visible.extend(points)
        triangles += doc['accessors'][p['indices']]['count'] // 3
        assert all(math.isfinite(x) for v in points for x in v), label + 'finite geometry'
        assert all(envelope[i] - 1e-4 <= v[i] <= envelope[i + 3] + 1e-4 for v in points for i in range(3)), label + 'envelope'
    assert 0 < triangles == entry['triangles'] <= budget(key), label + 'triangle budget/count'
    bounds = _bounds(visible)
    assert _near(sum(bounds, []), sum(entry['bounds_metres'], [])), label + 'decoded bounds'
    assert abs(bounds[0][1]) < 1e-4, label + 'ground contact'
    colliders = [n for n in doc['nodes'] if n.get('name', '').endswith('-colonly')]
    assert len(colliders) == entry['collider_count'] == 1, label + 'collision envelope count'
    assert _near(sum(exported_collision_bounds(doc, binary), []), envelope), label + 'collision bounds'
    # Verify all six actual box faces, not merely eight extrema or an accessor AABB.
    face_area = Counter(); edges = Counter(); corners = set(); total = 0
    for p, points in _nodes(doc, binary, True):
        assert p.get('mode', 4) == 4, label + 'collision topology'
        indices = [i[0] for i in accessor_values(doc, binary, p['indices'])]
        assert len(indices) % 3 == 0, label + 'collision indices'
        for j in range(0, len(indices), 3):
            vertices = [points[i] for i in indices[j:j + 3]]
            snapped = [tuple(round(x, 4) for x in v) for v in vertices]
            corners.update(snapped); total += 1
            plane = [(axis, side) for axis in range(3) for side in (0, 1)
                     if all(abs(v[axis] - envelope[axis + side * 3]) < 1e-4 for v in vertices)]
            assert len(plane) == 1, label + 'collision box surface'
            u = [vertices[1][i] - vertices[0][i] for i in range(3)]
            v = [vertices[2][i] - vertices[0][i] for i in range(3)]
            area = math.sqrt(sum((u[(i+1)%3]*v[(i+2)%3] - u[(i+2)%3]*v[(i+1)%3])**2 for i in range(3))) / 2
            face_area[plane[0]] += area
            for a, b in zip(snapped, snapped[1:] + snapped[:1]): edges[tuple(sorted((a, b)))] += 1
    assert total == 12 and len(corners) == 8 and all(n == 2 for n in edges.values()), label + 'collision closed support'
    for axis in range(3):
        other = [i for i in range(3) if i != axis]
        expected = math.prod(envelope[i+3] - envelope[i] for i in other)
        for side in (0, 1): assert abs(face_area[(axis, side)] - expected) < 1e-3, label + 'collision complete face'
    unique_visible_triangles(doc,binary)
    if key == 'farm_shed': validate_shed_details(doc,binary,0,0,10,7,3.5-.12)
    if key == 'fence_gate':
        for primitive,points in _nodes(doc,binary,False):
            if doc['materials'][primitive['material']]['name']=='farm_wood':
                assert all(abs(p[0])>1.2 for p in points), 'gate centre ground post'
    return dict(triangles=triangles, bounds=bounds)


def check():
    data = manifest()
    assert set(data['modules']) == set(KEYS), 'module roster'
    assert data['schema_version'] == 1 and data['units'] == 'metres', 'schema/units'
    assert data['up'] == '+Y' and data['forward'] == '+Z' and data['scale'] == 1/16, 'axis/scale'
    assert data['ground_y'] == .14, 'ground placement'
    provenance = json.loads((ROOT / 'docs/art/agriculture-parcels.json').read_text())
    assert provenance['modules'] == data['modules'], 'public provenance'
    _private(provenance)
    for key, entry in data['modules'].items():
        path = ROOT / 'game' / entry['path'].removeprefix('res://')
        doc, binary = read_glb(path)
        validate_module(key, entry, doc, binary)
        sidecar = path.with_suffix('.glb.import').read_text()
        for setting in ('gltf/embedded_image_handling=2', 'nodes/use_name_suffixes=true',
                        'meshes/generate_lods=true', 'nodes/root_scale=1.0', 'source_file="' + entry['path'] + '"'):
            assert setting in sidecar, key + ': import policy'
    for line in (ROOT / 'game/export_presets.cfg').read_text().splitlines():
        if line.startswith('include_filter='): assert 'assets/agriculture/parcel_modules.json' in line, 'manifest export filter'
    return len(data['modules'])


if __name__ == '__main__':
    print(f'Agricultural parcel kit clean: {check()} original modules')
