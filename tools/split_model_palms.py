#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

"""Split the palms built into building models out into shared lot planting.

Many building models were authored with palms in their courtyards, parking lots
and frontages. Each one is a thin trunk (with its rings) under a wide, flat
crown of fronds, plus a collision post. Once split out, the game plants every
palm spot itself: the shared grove palm in the desert, a juniper or piñon in
the woodland and a pine or fir in the forest (see VegetationZones), so a lot's
trees follow its elevation and the city has one kind of palm.

`apply` finds every palm in a model, removes exactly those parts from the GLB
(all other geometry, materials and collision keep their bytes), and appends one
planting row per palm to landscaping.json: the trunk base in lot coordinates,
the trunk height and the crown radius. Shrubs, shade trees and roof planters
are not palms and stay in the model.

Usage (from the repository root):
  python3 tools/split_model_palms.py status
  python3 tools/split_model_palms.py apply all|CODE [CODE ...]
  python3 tools/split_model_palms.py revert all|CODE [CODE ...]

`apply` keeps the exact original GLB in assets/palm-split-originals/ (local,
not packaged) before rewriting it; `revert` restores those bytes and removes
the rows it added. Both keep the catalog, landscaping and material-provenance
hashes in step and record each model's state in docs/art/palm-split.json.
"""
from __future__ import annotations

import math
import re
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
from fix_mirrored_textures import (ASSETS, CATALOG, LANDSCAPING, ROOT, load_json,  # noqa: E402
                                   read_glb, save_json, set_hashes, sha, write_glb)

BACKUP = ROOT / 'assets/palm-split-originals'
RECORD = ROOT / 'docs/art/palm-split.json'
# Building models; agricultural models (266+) have no palms.
FIRST_CODE, LAST_CODE = 112, 265

COMPONENT_TYPES = {5120: np.int8, 5121: np.uint8, 5122: np.int16, 5123: np.uint16, 5125: np.uint32, 5126: np.float32}
WIDTHS = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4, 'MAT4': 16}
FOLIAGE = re.compile(r'foliage|leaf|frond|palm', re.I)
COLLISION_ONLY = re.compile(r'-(conv)?colonly$')

# Detection, in model metres. A crown is a wide, flat foliage part; its trunk is
# the tallest thin part standing under it, reaching up into the crown.
CROWN_MIN_WIDTH = 3.0
CROWN_MAX_WIDTH = 9.0
CROWN_MAX_THICKNESS = 0.6  # times its width
TRUNK_MAX_WIDTH = 0.95
TRUNK_MIN_HEIGHT = 2.0
TRUNK_CROWN_OFFSET = 1.2
RING_AXIS_OFFSET = 0.2
RING_MAX_WIDTH = 1.0
COLLISION_AXIS_OFFSET = 0.3
# Planting rows are quantized so palms of nearly equal size share one mesh.
HEIGHT_STEP = 1.0 / 64.0
RADIUS_STEP = 1.0 / 256.0


def accessor_array(doc: dict, binary: bytes, index: int) -> np.ndarray:
    accessor = doc['accessors'][index]
    assert 'sparse' not in accessor, 'sparse accessors are not supported'
    view = doc['bufferViews'][accessor['bufferView']]
    dtype = np.dtype(COMPONENT_TYPES[accessor['componentType']])
    width = WIDTHS[accessor['type']]
    count = accessor['count']
    start = view.get('byteOffset', 0) + accessor.get('byteOffset', 0)
    item = dtype.itemsize * width
    stride = view.get('byteStride', item)
    raw = np.frombuffer(binary, np.uint8, count=stride * (count - 1) + item, offset=start)
    if stride != item:
        raw = np.lib.stride_tricks.as_strided(raw, (count, item), (stride, 1)).copy()
    return np.frombuffer(raw.tobytes(), dtype).reshape(count, width)


def world_transforms(doc: dict) -> dict[int, np.ndarray]:
    def local(node: dict) -> np.ndarray:
        if 'matrix' in node:
            return np.array(node['matrix'], float).reshape(4, 4).T
        x, y, z, w = node.get('rotation', [0, 0, 0, 1])
        rotation = np.array([[1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
                             [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
                             [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)]])
        matrix = np.eye(4)
        matrix[:3, :3] = rotation * np.array(node.get('scale', [1, 1, 1]), float)
        matrix[:3, 3] = node.get('translation', [0, 0, 0])
        return matrix

    out: dict[int, np.ndarray] = {}

    def walk(index: int, parent: np.ndarray) -> None:
        out[index] = parent @ local(doc['nodes'][index])
        for child in doc['nodes'][index].get('children', []):
            walk(child, out[index])

    for scene in doc.get('scenes', []):
        for root in scene.get('nodes', []):
            walk(root, np.eye(4))
    return out


def components(positions: np.ndarray, triangles: np.ndarray) -> list[np.ndarray]:
    """Triangle indices of each connected part, joining vertices that share a position."""
    _, welded = np.unique(np.round(positions, 4), axis=0, return_inverse=True)
    welded = welded.ravel()
    parent = np.arange(welded.max() + 1 if welded.size else 0)

    def find(x: int) -> int:
        root = x
        while parent[root] != root:
            root = parent[root]
        while parent[x] != root:
            parent[x], x = root, parent[x]
        return root

    corners = welded[triangles]
    for a, b, c in corners:
        ra = find(a)
        parent[find(b)] = ra
        parent[find(c)] = ra
    parts: dict[int, list[int]] = {}
    for t, a in enumerate(corners[:, 0]):
        parts.setdefault(find(a), []).append(t)
    return [np.array(v) for v in parts.values()]


def parts_of(doc: dict, binary: bytes) -> list[dict]:
    """Every connected part of every primitive, in scene (model) space."""
    world = world_transforms(doc)
    materials = [m.get('name', '') for m in doc.get('materials', [])]
    out = []
    for node_index, node in enumerate(doc['nodes']):
        if 'mesh' not in node or node_index not in world:
            continue
        collision = bool(COLLISION_ONLY.search(node.get('name', '')))
        for prim_index, prim in enumerate(doc['meshes'][node['mesh']]['primitives']):
            assert prim.get('mode', 4) == 4, 'only triangle lists are supported'
            local = accessor_array(doc, binary, prim['attributes']['POSITION']).astype(float)
            positions = (np.c_[local, np.ones(len(local))] @ world[node_index].T)[:, :3]
            triangles = accessor_array(doc, binary, prim['indices']).ravel().astype(np.int64).reshape(-1, 3)
            material = materials[prim['material']] if prim.get('material') is not None else ''
            for tris in components(positions, triangles):
                points = positions[triangles[tris].ravel()]
                out.append({'mesh': node['mesh'], 'prim': prim_index, 'tris': tris, 'material': material,
                            'collision': collision, 'lo': points.min(0), 'hi': points.max(0)})
    return out


def _width(part: dict) -> float:
    size = part['hi'] - part['lo']
    return float(max(size[0], size[2]))


def _center(part: dict) -> np.ndarray:
    return (part['lo'] + part['hi']) * 0.5


def _apart(a: np.ndarray, b: np.ndarray) -> float:
    return float(np.linalg.norm(a[[0, 2]] - b[[0, 2]]))


def find_palms(parts: list[dict]) -> tuple[list[dict], list[dict]]:
    """Palms (trunk, rings, crown and collision parts) and crowns without a trunk.

    Each crown claims the tallest free thin part under it as its trunk. Every
    other foliage, ring and collision part then joins the nearest palm whose
    reach holds it, so neighboring palms never share a part."""
    foliage = [p for p in parts if not p['collision'] and FOLIAGE.search(p['material'])]
    crowns = [p for p in foliage if CROWN_MIN_WIDTH <= _width(p) <= CROWN_MAX_WIDTH
              and p['hi'][1] - p['lo'][1] <= CROWN_MAX_THICKNESS * _width(p)]
    thin = [p for p in parts if not p['collision'] and not FOLIAGE.search(p['material'])
            and _width(p) <= TRUNK_MAX_WIDTH and p['hi'][1] - p['lo'][1] >= TRUNK_MIN_HEIGHT]
    palms: list[dict] = []
    trunks_taken: set[int] = set()
    for seed in sorted(crowns, key=lambda p: (-len(p['tris']), -_width(p))):
        middle = _center(seed)
        # A second frond layer of a palm already found belongs to that palm.
        if any(_apart(middle, palm['crown_center']) <= TRUNK_CROWN_OFFSET and
               abs(float(seed['lo'][1] - palm['seed']['lo'][1])) <= 0.6 for palm in palms):
            continue
        trunks = [t for t in thin if id(t) not in trunks_taken and _apart(_center(t), middle) <= TRUNK_CROWN_OFFSET
                  and seed['lo'][1] - TRUNK_CROWN_OFFSET <= t['hi'][1] <= seed['hi'][1] + 0.3]
        if not trunks:
            continue
        trunk = max(trunks, key=lambda t: t['hi'][1] - t['lo'][1])
        trunks_taken.add(id(trunk))
        palms.append({'seed': seed, 'trunk': trunk, 'crown_center': middle, 'axis': _center(trunk),
                      'reach': _width(seed) * 0.5 + 0.4, 'parts': [trunk]})

    def nearest(candidates: list[tuple[float, dict]]) -> dict | None:
        return min(candidates, key=lambda c: c[0])[1] if candidates else None

    for part in foliage:
        middle = _center(part)
        owner = nearest([(_apart(middle, palm['crown_center']), palm) for palm in palms
                         if _apart(middle, palm['crown_center']) <= palm['reach']
                         and part['lo'][1] >= palm['seed']['lo'][1] - 0.6 and part['hi'][1] <= palm['seed']['hi'][1] + 0.8])
        if owner is not None:
            owner['parts'].append(part)
    for part in parts:
        if FOLIAGE.search(part['material']) and not part['collision']:
            continue
        if any(part is palm['trunk'] for palm in palms):
            continue
        middle = _center(part)
        if part['collision']:
            fits = [(_apart(middle, palm['axis']), palm) for palm in palms
                    if _width(part) <= TRUNK_MAX_WIDTH and _apart(middle, palm['axis']) <= COLLISION_AXIS_OFFSET
                    and part['hi'][1] >= palm['trunk']['hi'][1] - 1.5 and part['lo'][1] <= palm['trunk']['lo'][1] + 1.0]
        else:
            fits = [(_apart(middle, palm['axis']), palm) for palm in palms
                    if _width(part) <= RING_MAX_WIDTH and _apart(middle, palm['axis']) <= RING_AXIS_OFFSET
                    and part['lo'][1] >= palm['trunk']['lo'][1] - 0.05 and part['hi'][1] <= palm['trunk']['hi'][1] + 0.1]
        owner = nearest(fits)
        if owner is not None:
            owner['parts'].append(part)
    claimed = {id(p) for palm in palms for p in palm['parts']}
    orphans = [seed for seed in crowns if id(seed) not in claimed]
    out = [{'base': np.array([palm['axis'][0], palm['trunk']['lo'][1], palm['axis'][2]]),
            'height': float(palm['trunk']['hi'][1] - palm['trunk']['lo'][1]),
            'crown_radius': _width(palm['seed']) * 0.5, 'parts': palm['parts']} for palm in palms]
    out.sort(key=lambda p: (round(float(p['base'][2]), 3), round(float(p['base'][0]), 3)))
    return out, orphans


def strip(doc: dict, binary: bytes, palms: list[dict]) -> tuple[dict, bytearray, int]:
    """A copy of the model without the palm triangles; every other byte range is kept."""
    drop: dict[tuple[int, int], set[int]] = {}
    for palm in palms:
        for part in palm['parts']:
            drop.setdefault((part['mesh'], part['prim']), set()).update(int(t) for t in part['tris'])
    users: dict[int, int] = {}
    for node in doc['nodes']:
        if 'mesh' in node:
            users[node['mesh']] = users.get(node['mesh'], 0) + 1
    assert all(users[mesh] == 1 for mesh, _ in drop), 'a shared mesh holds a palm'
    assert not doc.get('skins') and not doc.get('animations'), 'skinned or animated model'
    out = dict(doc)
    out['accessors'], out['bufferViews'] = [], []
    data = bytearray()

    def add_view(raw: bytes, target: int | None = None) -> int:
        while len(data) % 4:
            data.append(0)
        view = {'buffer': 0, 'byteOffset': len(data), 'byteLength': len(raw)}
        if target is not None:
            view['target'] = target
        data.extend(raw)
        out['bufferViews'].append(view)
        return len(out['bufferViews']) - 1

    def add_accessor(template: dict, values: np.ndarray, target: int | None) -> int:
        accessor = {k: v for k, v in template.items() if k not in ('bufferView', 'byteOffset', 'count', 'min', 'max')}
        accessor['bufferView'] = add_view(values.tobytes(), target)
        accessor['count'] = int(values.shape[0])
        if 'min' in template:
            accessor['min'] = [v.item() for v in values.min(0)]
            accessor['max'] = [v.item() for v in values.max(0)]
        out['accessors'].append(accessor)
        return len(out['accessors']) - 1

    copied: dict[int, int] = {}

    def copy_accessor(index: int, target: int | None) -> int:
        if index not in copied:
            copied[index] = add_accessor(doc['accessors'][index], accessor_array(doc, binary, index), target)
        return copied[index]

    removed = 0
    meshes = []
    for mesh_index, mesh in enumerate(doc['meshes']):
        primitives = []
        for prim_index, prim in enumerate(mesh['primitives']):
            rewritten = dict(prim)
            gone = drop.get((mesh_index, prim_index))
            if gone is None:
                rewritten['attributes'] = {k: copy_accessor(v, 34962) for k, v in prim['attributes'].items()}
                rewritten['indices'] = copy_accessor(prim['indices'], 34963)
                primitives.append(rewritten)
                continue
            triangles = accessor_array(doc, binary, prim['indices']).ravel().astype(np.int64).reshape(-1, 3)
            keep = np.array([t for t in range(len(triangles)) if t not in gone], np.int64)
            removed += len(gone)
            if keep.size == 0:
                continue
            kept = triangles[keep]
            used, remapped = np.unique(kept.ravel(), return_inverse=True)
            rewritten['attributes'] = {
                name: add_accessor(doc['accessors'][index], accessor_array(doc, binary, index)[used], 34962)
                for name, index in prim['attributes'].items()}
            index_type = np.uint16 if used.size < 65536 else np.uint32
            template = dict(doc['accessors'][prim['indices']])
            template['componentType'] = 5123 if index_type is np.uint16 else 5125
            rewritten['indices'] = add_accessor(template, remapped.astype(index_type).reshape(-1, 1), 34963)
            primitives.append(rewritten)
        meshes.append(dict(mesh, primitives=primitives) if primitives else None)
    for image in out.get('images', []):
        if 'bufferView' in image:
            view = doc['bufferViews'][image['bufferView']]
            start = view.get('byteOffset', 0)
            image['bufferView'] = add_view(binary[start:start + view['byteLength']])
    # Drop emptied meshes, then childless nodes left without a mesh.
    mesh_map, out['meshes'] = {}, []
    for index, mesh in enumerate(meshes):
        if mesh is not None:
            mesh_map[index] = len(out['meshes'])
            out['meshes'].append(mesh)
    nodes = []
    for node in doc['nodes']:
        node = dict(node)
        if 'mesh' in node:
            if node['mesh'] in mesh_map:
                node['mesh'] = mesh_map[node['mesh']]
            else:
                del node['mesh']
        nodes.append(node)
    alive = [('mesh' in n or n.get('children') or 'camera' in n or 'extensions' in n) for n in nodes]
    node_map = {}
    for index, node in enumerate(nodes):
        if alive[index]:
            node_map[index] = len(node_map)
    out['nodes'] = []
    for index, node in enumerate(nodes):
        if not alive[index]:
            continue
        if 'children' in node:
            node['children'] = [node_map[c] for c in node['children'] if c in node_map]
            if not node['children']:
                del node['children']
        out['nodes'].append(node)
    out['scenes'] = [dict(s, nodes=[node_map[n] for n in s.get('nodes', []) if n in node_map]) for s in doc['scenes']]
    out['buffers'] = [{'byteLength': len(data)}]
    return out, data, removed


def planting_rows(entry: dict, palms: list[dict]) -> list[list[float]]:
    """Palms in lot coordinates (tile units, lot center at the origin)."""
    scale = float(entry['scale'])
    yaw = math.radians(float(entry.get('yaw', 0.0)))
    pivot = np.array(entry.get('pivot', [0, 0, 0]), float)
    half = np.array(entry['footprint'], float) * 0.5
    rows = []
    for palm in palms:
        p = (palm['base'] - pivot) * scale
        x = p[0] * math.cos(yaw) + p[2] * math.sin(yaw)
        z = -p[0] * math.sin(yaw) + p[2] * math.cos(yaw)
        height = max(HEIGHT_STEP, round(palm['height'] * scale / HEIGHT_STEP) * HEIGHT_STEP)
        radius = round(palm['crown_radius'] * scale / RADIUS_STEP) * RADIUS_STEP
        # Keep the crown inside the lot, as for every other planting row.
        radius = min(radius, math.floor((half[0] - abs(x)) / RADIUS_STEP) * RADIUS_STEP,
                     math.floor((half[1] - abs(z)) / RADIUS_STEP) * RADIUS_STEP)
        assert radius > 0, f"palm at {x:.3f},{z:.3f} stands on the lot edge"
        rows.append([round(x, 6), round(max(0.0, p[1]), 6), round(z, 6), height, radius])
    return rows


def record() -> dict:
    return load_json(RECORD) if RECORD.exists() else {
        'title': 'Palms split out of building models into shared lot planting',
        'tool': 'tools/split_model_palms.py', 'models': {}}


def catalog_entries() -> dict[int, dict]:
    return {e['code']: e for e in load_json(CATALOG)['entries']
            if FIRST_CODE <= e['code'] <= LAST_CODE and e['path'].endswith('-blender.glb')}


def model_path(entry: dict) -> Path:
    return ROOT / 'game' / entry['path'].removeprefix('res://')


def triangle_count(doc: dict, binary: bytes) -> int:
    total = 0
    for node in doc['nodes']:
        if 'mesh' in node and not COLLISION_ONLY.search(node.get('name', '')):
            for prim in doc['meshes'][node['mesh']]['primitives']:
                total += doc['accessors'][prim['indices']]['count'] // 3
    return total


def codes(arguments: list[str]) -> list[int]:
    return sorted(catalog_entries()) if arguments == ['all'] else [int(a) for a in arguments]


def apply(selected: list[int]) -> None:
    rec = record()
    entries = catalog_entries()
    BACKUP.mkdir(parents=True, exist_ok=True)
    done, skipped = [], []
    for code in selected:
        entry = entries[code]
        path = model_path(entry)
        data = path.read_bytes()
        row = rec['models'].get(str(code))
        if row and row['state'] == 'split' and sha(data) == row['split_sha256']:
            continue
        doc, binary = read_glb(data)
        palms, orphans = find_palms(parts_of(doc, bytes(binary)))
        if orphans:
            skipped.append(code)
            print(f'{code}: {len(orphans)} crown(s) without a trunk; not splitting this model')
            continue
        if not palms:
            continue
        backup = BACKUP / path.name
        if not backup.exists():
            backup.write_bytes(data)
        assert sha(backup.read_bytes()) == sha(data), f'{code}: backup differs from the current model'
        stripped, stripped_binary, removed = strip(doc, bytes(binary), palms)
        split = write_glb(stripped, stripped_binary)
        assert removed == sum(len(p['tris']) for palm in palms for p in palm['parts'])
        rows = planting_rows(entry, palms)
        path.write_bytes(split)
        set_hashes(code, split)
        catalog = load_json(CATALOG)
        for item in catalog['entries']:
            if item['code'] == code:
                item['triangles'] = triangle_count(stripped, bytes(stripped_binary))
        save_json(CATALOG, catalog)
        landscaping = load_json(LANDSCAPING)
        profile = next((p for p in landscaping['entries'] if p['code'] == code), None)
        if profile is None:
            profile = {'code': code, 'glb_sha256': sha(split), 'palms': []}
            landscaping['entries'].append(profile)
            landscaping['entries'].sort(key=lambda p: p['code'])
        profile['palms'].extend(rows)
        save_json(LANDSCAPING, landscaping)
        rec['models'][str(code)] = {'state': 'split', 'palms': len(palms), 'removed_triangles': removed,
                                    'original_sha256': sha(data), 'original_bytes': len(data),
                                    'split_sha256': sha(split), 'split_bytes': len(split),
                                    'original_triangles': entry['triangles'], 'rows': rows}
        done.append(code)
    save_json(RECORD, rec)
    print(f'split {len(done)} models, {sum(rec["models"][str(c)]["palms"] for c in done)} palms'
          + (f'; skipped {skipped}' if skipped else ''))


def revert(selected: list[int]) -> None:
    rec = record()
    entries = catalog_entries()
    done = []
    for code in selected:
        row = rec['models'].get(str(code))
        if row is None or row['state'] != 'split':
            continue
        path = model_path(entries[code])
        assert sha(path.read_bytes()) == row['split_sha256'], f'{code}: model changed since the split; not reverting'
        original = (BACKUP / path.name).read_bytes()
        assert sha(original) == row['original_sha256'], f'{code}: backup missing or altered'
        path.write_bytes(original)
        set_hashes(code, original)
        catalog = load_json(CATALOG)
        for item in catalog['entries']:
            if item['code'] == code:
                item['triangles'] = row['original_triangles']
        save_json(CATALOG, catalog)
        landscaping = load_json(LANDSCAPING)
        for profile in landscaping['entries']:
            if profile['code'] == code:
                for planted in row['rows']:
                    profile['palms'].remove(planted)
        landscaping['entries'] = [p for p in landscaping['entries'] if p['palms']]
        save_json(LANDSCAPING, landscaping)
        row['state'] = 'reverted'
        done.append(code)
    save_json(RECORD, rec)
    print(f'reverted {len(done)} models: {done}')


def status() -> None:
    rec = record()
    states: dict[str, list[int]] = {}
    for code, entry in sorted(catalog_entries().items()):
        data = model_path(entry).read_bytes()
        row = rec['models'].get(str(code))
        if row and row['state'] == 'split' and sha(data) == row['split_sha256']:
            states.setdefault('split', []).append(code)
            continue
        doc, binary = read_glb(data)
        palms, orphans = find_palms(parts_of(doc, bytes(binary)))
        if orphans:
            states.setdefault('crowns without trunks (needs review)', []).append(code)
        elif palms:
            states.setdefault('built-in palms', []).append(code)
        else:
            states.setdefault('no palms', []).append(code)
    for name, members in states.items():
        print(f'{name}: {len(members)}  {members}')


def main(argv: list[str]) -> int:
    if not argv or argv[0] not in ('status', 'apply', 'revert') or (argv[0] != 'status' and len(argv) < 2):
        print(__doc__)
        return 2
    {'status': lambda: status(), 'apply': lambda: apply(codes(argv[1:])),
     'revert': lambda: revert(codes(argv[1:]))}[argv[0]]()
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
