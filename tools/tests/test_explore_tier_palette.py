# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
"""Inspect exported triangles: tier paint identities must occupy the right regions."""
import json
from collections import defaultdict
from pathlib import Path
import struct

import pytest

ROOT = Path(__file__).resolve().parents[2] / 'game/assets/desert-dreams-traffic'
COPPER = (.60, .22, .085)
RUBBER = (.035, .039, .037)
CREAM = (.88, .79, .59)
PATROL = (.085, .11, .12)


def _triangles(stem):
    raw = (ROOT / (stem + '.glb')).read_bytes()
    size = struct.unpack_from('<I', raw, 12)[0]
    doc = json.loads(raw[20:20 + size])
    binary = raw[28 + size:]

    def values(index):
        accessor = doc['accessors'][index]
        view = doc['bufferViews'][accessor['bufferView']]
        code = {5126: 'f', 5125: 'I', 5123: 'H', 5121: 'B'}[accessor['componentType']]
        count = {'VEC3': 3, 'SCALAR': 1}[accessor['type']]
        fmt = '<' + code * count
        step = view.get('byteStride', struct.calcsize(fmt))
        start = view.get('byteOffset', 0) + accessor.get('byteOffset', 0)
        return [struct.unpack_from(fmt, binary, start + i * step) for i in range(accessor['count'])]

    out = []
    # Coarse exports have a neutral root and baked mesh rotations/scales.
    for node in doc['nodes']:
        assert 'matrix' not in node and 'rotation' not in node and 'scale' not in node
        if 'mesh' not in node:
            assert node.get('translation', [0, 0, 0]) == [0, 0, 0]
            continue
        offset = node.get('translation', [0, 0, 0])
        for primitive in doc['meshes'][node['mesh']]['primitives']:
            vertices = values(primitive['attributes']['POSITION'])
            indices = values(primitive['indices'])
            rgb = doc['materials'][primitive['material']]['pbrMetallicRoughness']['baseColorFactor'][:3]
            for i in range(0, len(indices), 3):
                points = [tuple(v + t for v, t in zip(vertices[indices[j][0]], offset)) for j in range(i, i + 3)]
                out.append((points, rgb))
    return out


def _area(points):
    a, b, c = points
    u = [b[i] - a[i] for i in range(3)]
    v = [c[i] - a[i] for i in range(3)]
    return sum((u[(i + 1) % 3] * v[(i + 2) % 3] - u[(i + 2) % 3] * v[(i + 1) % 3]) ** 2 for i in range(3)) ** .5 / 2


def _is_color(actual, expected):
    return all(abs(a - b) < 1e-6 for a, b in zip(actual, expected))


@pytest.mark.parametrize('index', range(0, 16, 3))
@pytest.mark.parametrize('suffix', ['', '_far'])
def test_copper_hair_and_dark_shoes_are_separate(index, suffix):
    triangles = _triangles(f'pedestrian_{index:02d}' + suffix)
    hair = [(p, c) for p, c in triangles if min(v[1] for v in p) > 1.5 and min(v[2] for v in p) >= 0]
    assert sum(_area(p) for p, c in hair if _is_color(c, COPPER)) > .01
    assert not any(_is_color(c, RUBBER) and _area(p) > 1e-6 for p, c in hair)
    # Ankle faces can share the shoes' height range; identify the two complete
    # grounded boxes by position connectivity, including their top faces.
    low = [(p, c) for p, c in triangles if max(v[1] for v in p) < .08]
    neighbors = defaultdict(set)
    for face, (points, _) in enumerate(low):
        for vertex in points:
            neighbors[vertex].add(face)
    remaining = set(range(len(low)))
    grounded = []
    while remaining:
        pending = [min(remaining)]
        component = set()
        while pending:
            face = pending.pop()
            if face in component:
                continue
            component.add(face)
            remaining.discard(face)
            for vertex in low[face][0]:
                pending.extend(neighbors[vertex] - component)
        if any(abs(v[1]) < 1e-6 for face in component for v in low[face][0]):
            grounded.append(component)
    assert len(grounded) == 2
    assert all(len(component) == 12 for component in grounded)
    shoes = [low[face] for component in grounded for face in component]
    assert all(_is_color(color, RUBBER) for _, color in shoes)
    assert sum(_area(points) for points, _ in shoes) > .04


@pytest.mark.parametrize('suffix', ['', '_far'])
def test_police_body_and_roof_regions_keep_patrol_paint(suffix):
    triangles = _triangles('police' + suffix)
    body = [(p, c) for p, c in triangles if min(v[1] for v in p) > .25 and max(v[1] for v in p) < .85 and max(v[0] for v in p) - min(v[0] for v in p) > 1.8]
    assert sum(_area(p) for p, c in body if _is_color(c, PATROL)) > 5
    roof = [(p, c) for p, c in triangles if min(v[1] for v in p) > 1.5 and max(v[0] for v in p) - min(v[0] for v in p) > 1.2]
    assert sum(_area(p) for p, c in roof if _is_color(c, CREAM)) > 2


@pytest.mark.parametrize('suffix', ['', '_far'])
def test_helicopter_cabin_is_cream_with_teal_tail(suffix):
    triangles = _triangles('helicopter' + suffix)
    cabin = [(p, c) for p, c in triangles if min(v[1] for v in p) >= .44 and max(v[1] for v in p) < 1.86 and max(v[2] for v in p) < 1.5]
    assert sum(_area(p) for p, c in cabin if _is_color(c, CREAM)) > 4
    tail = [(p, c) for p, c in triangles if max(v[2] for v in p) > 3]
    assert sum(_area(p) for p, c in tail if _is_color(c, (.035, .32, .32))) > .5
