#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

"""Small, declared geometry repairs to runtime building models.

Each repair names the parts of a model to remove or move by material, size and
position (model metres, GLB axes: x, height, depth), so it is exact and
reviewable. `apply` keeps the model's bytes before repair in
assets/model-repair-originals/ (local, not packaged), rewrites the GLB with
every other part unchanged, keeps the catalog, landscaping and
material-provenance hashes in step, and records the result in
docs/art/model-repairs.json; `revert` restores the kept bytes.

Usage (from the repository root):
  python3 tools/repair_models.py status
  python3 tools/repair_models.py apply all|CODE [CODE ...]
  python3 tools/repair_models.py revert all|CODE [CODE ...]
"""
from __future__ import annotations

import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
from fix_mirrored_textures import CATALOG, ROOT, load_json, read_glb, save_json, set_hashes, sha, write_glb  # noqa: E402
from split_model_palms import (COMPONENT_TYPES, WIDTHS, catalog_entries, model_path, parts_of,  # noqa: E402
                               strip, triangle_count, world_transforms)

BACKUP = ROOT / 'assets/model-repair-originals'
RECORD = ROOT / 'docs/art/model-repairs.json'
# Palm splitting ran before these repairs; its record names the model bytes it
# produced, so it follows the repaired bytes (and back again on revert).
PALM_RECORD = ROOT / 'docs/art/palm-split.json'
NEAR = 0.02


def near(value: float, targets: list[float], tolerance: float = NEAR) -> bool:
    return any(abs(value - t) <= tolerance for t in targets)


def comstock_tier_window(part: dict) -> bool:
    """A punched window (glass, reveal, sill or mullion) on the two middle setback
    tiers, where each floor's windows sit inside the tier's ribbon of glass."""
    size = part['hi'] - part['lo']
    across = sorted([float(size[0]), float(size[2])])
    height = float(size[1])
    middle = float(part['lo'][1] + part['hi'][1]) * .5
    floors = [32.0, 36.0, 41.0, 45.0]
    material = part['material'].split(' • ')[0]
    if material == 'glass':
        return near(height, [2.05]) and near(across[1], [1.15]) and near(middle, floors)
    if material == 'frame':
        return near(height, [2.25]) and near(across[1], [1.37]) and near(middle, floors)
    if material == 'copper':
        return near(height, [2.05]) and across[1] < .1 and near(middle, floors)
    if material == 'cream':
        return near(height, [.13]) and near(across[1], [1.45]) and near(across[0], [.26]) \
            and near(middle, [f - 1.085 for f in floors])
    return False


def comstock_canopy_rim(part: dict) -> bool:
    """The copper rim along the entrance canopy's front, set 2 cm inside the slab."""
    return part['material'] == 'copper' and np.allclose(part['lo'], [.25, 3.28, 26.88], atol=.01) \
        and np.allclose(part['hi'], [7.75, 3.6, 26.98], atol=.01)


def comstock_canopy_letters(part: dict) -> bool:
    """HOTEL / CASINO on that rim, hidden behind the slab's front face."""
    return part['material'] == 'sign_ivory' and part['lo'][1] > 3.3 and part['hi'][1] < 3.58 \
        and part['lo'][2] > 26.98 and part['hi'][2] < 27.0 and 2.4 < part['lo'][0] and part['hi'][0] < 5.6


def police_display_car(part: dict) -> bool:
    """Two complete decorative patrol cars, including their solid collision."""
    return any(np.all(part['lo'] >= [x - 2.05, .21, 11.4])
               and np.all(part['hi'] <= [x + 2.05, 4.1, 19.0]) for x in [-9, 10])


REPAIRS = {
    210: {
        'name': 'Police Station',
        'why': 'Replace the two baked decorative patrol cars with shared, claimable service vehicles.',
        'drop': [('decorative patrol cars', police_display_car, 64)],
        'drop_collision': [('decorative patrol car collision', police_display_car, 12)],
    },
    251: {
        'name': 'Comstock Grand',
        'why': 'Punched windows overlapped the ribbon glass on the middle tiers; the entrance '
               'canopy hid its copper rim and the HOTEL / CASINO lettering behind its own slab.',
        'drop': [('tier windows inside the ribbon glass', comstock_tier_window, 448)],
        'move': [('canopy rim to the slab front', comstock_canopy_rim, 1, [0.0, 0.0, 0.12]),
                 ('lettering onto the rim face', comstock_canopy_letters, 12, [0.0, 0.0, 0.125])],
    },
}


def moved_binary(doc: dict, binary: bytes, moves: list[tuple[dict, np.ndarray]]) -> bytes:
    """The buffer with the vertices of each moved part shifted (model offset)."""
    out = bytearray(binary)
    world = world_transforms(doc)
    for part, offset in moves:
        node = next(i for i, n in enumerate(doc['nodes']) if n.get('mesh') == part['mesh'])
        local_offset = np.linalg.inv(world[node][:3, :3]) @ offset
        prim = doc['meshes'][part['mesh']]['primitives'][part['prim']]
        indices_accessor = doc['accessors'][prim['indices']]
        view = doc['bufferViews'][indices_accessor['bufferView']]
        start = view.get('byteOffset', 0) + indices_accessor.get('byteOffset', 0)
        dtype = np.dtype(COMPONENT_TYPES[indices_accessor['componentType']])
        triangles = np.frombuffer(binary, dtype, indices_accessor['count'], start).reshape(-1, 3)
        vertices = np.unique(triangles[part['tris']].ravel())
        accessor = doc['accessors'][prim['attributes']['POSITION']]
        assert accessor['componentType'] == 5126 and WIDTHS[accessor['type']] == 3
        view = doc['bufferViews'][accessor['bufferView']]
        base = view.get('byteOffset', 0) + accessor.get('byteOffset', 0)
        stride = view.get('byteStride', 12)
        for v in vertices:
            at = base + int(v) * stride
            value = np.frombuffer(bytes(out[at:at + 12]), np.float32) + local_offset.astype(np.float32)
            out[at:at + 12] = value.astype(np.float32).tobytes()
    return bytes(out)


def record() -> dict:
    return load_json(RECORD) if RECORD.exists() else {
        'title': 'Declared geometry repairs to runtime building models',
        'tool': 'tools/repair_models.py', 'models': {}}


def repair(code: int, data: bytes) -> tuple[bytes, dict]:
    spec = REPAIRS[code]
    doc, binary = read_glb(data)
    all_parts = parts_of(doc, bytes(binary))
    parts = [p for p in all_parts if not p['collision']]
    summary = {'drop': {}, 'move': {}}
    moves = []
    for label, test, expected, offset in spec.get('move', []):
        chosen = [p for p in parts if test(p)]
        assert len(chosen) == expected, f'{code}: {label}: found {len(chosen)} parts, expected {expected}'
        moves.extend((p, np.array(offset, float)) for p in chosen)
        summary['move'][label] = {'parts': len(chosen), 'offset': offset}
    dropped = []
    for label, test, expected in spec.get('drop', []):
        chosen = [p for p in parts if test(p)]
        assert len(chosen) == expected, f'{code}: {label}: found {len(chosen)} parts, expected {expected}'
        dropped.extend(chosen)
        summary['drop'][label] = {'parts': len(chosen), 'triangles': int(sum(len(p['tris']) for p in chosen))}
    for label, test, expected in spec.get('drop_collision', []):
        chosen = [p for p in all_parts if p['collision'] and test(p)]
        assert len(chosen) == expected, f'{code}: {label}: found {len(chosen)} parts, expected {expected}'
        dropped.extend(chosen)
        summary['drop'][label] = {'parts': len(chosen), 'triangles': int(sum(len(p['tris']) for p in chosen))}
    shifted = moved_binary(doc, bytes(binary), moves)
    repaired, repaired_binary, removed = strip(doc, shifted, [{'parts': dropped}])
    summary['removed_triangles'] = removed
    summary['triangles'] = triangle_count(repaired, bytes(repaired_binary))
    return write_glb(repaired, repaired_binary), summary


def follow_palm_split(code: int, old: str, new: str) -> None:
    if not PALM_RECORD.exists():
        return
    palms = load_json(PALM_RECORD)
    row = palms['models'].get(str(code))
    if row and row.get('state') == 'split' and row.get('split_sha256') == old:
        row['split_sha256'] = new
        save_json(PALM_RECORD, palms)


def codes(arguments: list[str]) -> list[int]:
    return sorted(REPAIRS) if arguments == ['all'] else [int(a) for a in arguments]


def apply(selected: list[int]) -> None:
    rec = record()
    entries = catalog_entries()
    BACKUP.mkdir(parents=True, exist_ok=True)
    for code in selected:
        path = model_path(entries[code])
        data = path.read_bytes()
        row = rec['models'].get(str(code))
        if row and row['state'] == 'repaired' and sha(data) == row['repaired_sha256']:
            print(f'{code}: already repaired')
            continue
        backup = BACKUP / path.name
        if not backup.exists():
            backup.write_bytes(data)
        assert sha(backup.read_bytes()) == sha(data), f'{code}: kept original differs from the current model'
        fixed, summary = repair(code, data)
        path.write_bytes(fixed)
        set_hashes(code, fixed)
        follow_palm_split(code, sha(data), sha(fixed))
        catalog = load_json(CATALOG)
        for item in catalog['entries']:
            if item['code'] == code:
                original_triangles = item['triangles']
                item['triangles'] = summary['triangles']
        save_json(CATALOG, catalog)
        rec['models'][str(code)] = {'state': 'repaired', 'name': REPAIRS[code]['name'], 'why': REPAIRS[code]['why'],
                                    'original_sha256': sha(data), 'original_bytes': len(data),
                                    'original_triangles': original_triangles,
                                    'repaired_sha256': sha(fixed), 'repaired_bytes': len(fixed), **summary}
        print(f'{code}: removed {summary["removed_triangles"]} triangles, moved '
              f'{sum(m["parts"] for m in summary["move"].values())} parts')
    save_json(RECORD, rec)


def revert(selected: list[int]) -> None:
    rec = record()
    entries = catalog_entries()
    for code in selected:
        row = rec['models'].get(str(code))
        if not row or row['state'] != 'repaired':
            continue
        path = model_path(entries[code])
        original = (BACKUP / path.name).read_bytes()
        assert sha(original) == row['original_sha256'], f'{code}: kept original does not match the record'
        path.write_bytes(original)
        set_hashes(code, original)
        follow_palm_split(code, row['repaired_sha256'], row['original_sha256'])
        catalog = load_json(CATALOG)
        for item in catalog['entries']:
            if item['code'] == code:
                item['triangles'] = row['original_triangles']
        save_json(CATALOG, catalog)
        row['state'] = 'original'
        print(f'{code}: restored')
    save_json(RECORD, rec)


def status() -> None:
    rec = record()
    entries = catalog_entries()
    for code in sorted(REPAIRS):
        current = sha(model_path(entries[code]).read_bytes())
        row = rec['models'].get(str(code))
        if row and row['state'] == 'repaired':
            state = 'repaired' if current == row['repaired_sha256'] else 'changed since repair'
        else:
            state = 'not repaired'
        print(f'{code} {REPAIRS[code]["name"]}: {state}')


def main(argv: list[str]) -> int:
    if not argv or argv[0] not in ('status', 'apply', 'revert'):
        print(__doc__)
        return 2
    if argv[0] == 'status':
        status()
    elif argv[0] == 'apply':
        apply(codes(argv[1:] or ['all']))
    else:
        revert(codes(argv[1:] or ['all']))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
