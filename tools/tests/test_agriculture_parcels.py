# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
"""Inspect the public GLBs, including damage to real exported mesh data."""
import copy
import importlib.util
from pathlib import Path
import struct
import pytest

ROOT = Path(__file__).resolve().parents[2]
KEYS = 'farm_shed shade_shelter water_trough water_tank grain_bin hay_bale vegetable_strip alfalfa_strip grain_strip fence_post fence_rail fence_gate'.split()


def checker():
    path = ROOT / 'tools/check_agriculture_parcels.py'
    assert path.exists(), 'missing modular farm kit checker'
    spec = importlib.util.spec_from_file_location('check_agriculture_parcels', path)
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result


@pytest.mark.parametrize('name', KEYS)
def test_original_module_has_embedded_resources_and_matching_bounds(name):
    c = checker()
    entry = c.manifest()['modules'][name]
    path = ROOT / 'game' / entry['path'].removeprefix('res://')
    doc, binary = c.read_glb(path)
    c.validate_module(name, entry, doc, binary)
    assert [v for p in c.exported_collision_bounds(doc, binary) for v in p] == pytest.approx(entry['collision_bounds'], abs=1e-4)


def test_complete_package_preserves_old_farm_models_and_catalog_contracts():
    assert checker().check() == 12


@pytest.mark.parametrize('damage,diagnostic', [
    ('external_image', 'external'), ('external_buffer', 'external'),
    ('private', 'private'), ('axis', 'transform'), ('scale', 'transform'),
    ('collision', 'collision'), ('collision_hole', 'collision'),
    ('vertex', 'envelope'), ('hash', 'hash'), ('triangles', 'triangle'),
    ('material', 'material'), ('bounds', 'bounds'),
])
def test_checker_rejects_damaged_real_module(damage, diagnostic):
    c = checker()
    entry = copy.deepcopy(c.manifest()['modules']['farm_shed'])
    doc, binary = c.read_glb(ROOT / 'game' / entry['path'].removeprefix('res://'))
    doc = copy.deepcopy(doc)
    node = next(n for n in doc['nodes'] if 'mesh' in n and not n.get('name', '').endswith('-colonly'))
    if damage == 'external_image': doc['images'][0]['uri'] = 'private.png'
    elif damage == 'external_buffer': doc['buffers'][0]['uri'] = 'private.bin'
    elif damage == 'private': doc['asset']['extras'] = {'source': '/Users/artist/master.blend'}
    elif damage == 'axis': node['rotation'] = [0.70710678, 0, 0, 0.70710678]
    elif damage == 'scale': node['scale'] = [0.0625] * 3
    elif damage == 'collision':
        for n in doc['nodes']: n['name'] = n.get('name', '').replace('-colonly', '-removed')
    elif damage == 'collision_hole':
        collider = next(n for n in doc['nodes'] if n.get('name', '').endswith('-colonly'))
        primitive = doc['meshes'][collider['mesh']]['primitives'][0]
        damaged_accessor = copy.deepcopy(doc['accessors'][primitive['indices']])
        damaged_accessor['count'] -= 3
        primitive['indices'] = len(doc['accessors'])
        doc['accessors'].append(damaged_accessor)
    elif damage == 'vertex':
        primitive = doc['meshes'][node['mesh']]['primitives'][0]
        accessor = doc['accessors'][primitive['attributes']['POSITION']]
        view = doc['bufferViews'][accessor['bufferView']]
        binary = bytearray(binary)
        struct.pack_into('<f', binary, view.get('byteOffset', 0) + accessor.get('byteOffset', 0), 1000)
    elif damage == 'hash': entry['model_sha256'] = '0' * 64
    elif damage == 'triangles': entry['triangles'] = 8001
    elif damage == 'material': doc['materials'][0]['name'] = 'foreign_surface'
    elif damage == 'bounds': entry['bounds_metres'][1][1] += 0.1
    with pytest.raises(AssertionError, match=diagnostic): c.validate_module('farm_shed', entry, doc, binary)


def test_vegetable_strip_retains_original_edible_crop_heads():
    entry = checker().manifest()['modules']['vegetable_strip']
    assert 'farm_cream' in entry['materials'], 'vegetable strip lost original cabbage heads'
    assert 'farm_cream' not in checker().manifest()['modules']['alfalfa_strip']['materials']


@pytest.mark.parametrize('name', ['hay_bale', 'fence_post', 'fence_rail', 'fence_gate'])
def test_caps_and_straps_do_not_share_visible_faces_with_their_support(name):
    c = checker()
    entry = c.manifest()['modules'][name]
    doc, binary = c.read_glb(ROOT / 'game' / entry['path'].removeprefix('res://'))
    faces = []
    for primitive, points in c._nodes(doc, binary, False):
        indices = [row[0] for row in c.accessor_values(doc, binary, primitive['indices'])]
        for i in range(0, len(indices), 3):
            triangle = [points[j] for j in indices[i:i+3]]
            for axis in range(3):
                if max(v[axis] for v in triangle) - min(v[axis] for v in triangle) < 1e-5:
                    faces.append((primitive['material'], axis, triangle))
    def interior(point, triangle, axis):
        x, y = [i for i in range(3) if i != axis]
        a, b, d = triangle
        den = (b[y]-d[y])*(a[x]-d[x])+(d[x]-b[x])*(a[y]-d[y])
        if abs(den) < 1e-8: return False
        u = ((b[y]-d[y])*(point[x]-d[x])+(d[x]-b[x])*(point[y]-d[y]))/den
        v = ((d[y]-a[y])*(point[x]-d[x])+(a[x]-d[x])*(point[y]-d[y]))/den
        return u > 1e-5 and v > 1e-5 and u+v < 1-1e-5
    for material, axis, triangle in faces:
        center = [sum(v[i] for v in triangle)/3 for i in range(3)]
        for other_material, other_axis, other in faces:
            if material == other_material or axis != other_axis: continue
            if abs(center[axis] - other[0][axis]) > 1e-5: continue
            assert not interior(center, other, axis), name + ': coplanar material overlap'


def test_shed_has_no_coincident_visible_triangles_and_gate_has_only_end_posts():
    c = checker()
    from collections import Counter
    for key in ('farm_shed', 'fence_gate'):
        entry = c.manifest()['modules'][key]
        doc, binary = c.read_glb(ROOT / 'game' / entry['path'].removeprefix('res://'))
        counts = Counter()
        for primitive, points in c._nodes(doc, binary, False):
            indices = [row[0] for row in c.accessor_values(doc, binary, primitive['indices'])]
            for i in range(0, len(indices), 3):
                vertices = tuple(sorted(tuple(round(x, 5) for x in points[j]) for j in indices[i:i+3]))
                counts[(primitive['material'], vertices)] += 1
            if key == 'fence_gate' and doc['materials'][primitive['material']]['name'] == 'farm_wood':
                assert all(abs(v[0]) > 1.2 for v in points), 'gate has a fixed centre ground post'
        assert all(n == 1 for n in counts.values()), key + ': coincident visible triangles'
