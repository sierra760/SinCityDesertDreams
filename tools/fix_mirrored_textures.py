#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

"""Repair, or revert per model, building textures that Godot draws as streaks.

The original building GLBs sample the shared surface swatches with glTF
MIRRORED_REPEAT. Godot's StandardMaterial3D has no mirror wrap, so the importer
clamps them (texture_repeat=false) and metre-scale UVs smear the edge texels.

The fix bakes the mirror into each shared swatch (a 2 x 2 reflected tile that
repeats seamlessly), points the model at the baked image with plain repeat, and
halves the UVs its textured materials use. Geometry, materials, colors and
collision nodes are untouched, so the result matches the Blender authoring look.

Usage (from the repository root):
  python3 tools/fix_mirrored_textures.py status
  python3 tools/fix_mirrored_textures.py apply all|CODE [CODE ...]
  python3 tools/fix_mirrored_textures.py revert all|CODE [CODE ...]

`apply` keeps the exact original GLB in assets/texture-wrap-originals/ (local,
not packaged) before rewriting it; `revert` restores those bytes. Both keep the
catalog, landscaping and material-provenance hashes in step, and record each
model's state in docs/art/texture-wrap-fix.json.
"""
from __future__ import annotations

import hashlib
import json
import re
import struct
import sys
from io import BytesIO
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / 'game/assets/desert-dreams-3d'
BACKUP = ROOT / 'assets/texture-wrap-originals'
CATALOG = ASSETS / 'catalog.json'
LANDSCAPING = ASSETS / 'landscaping.json'
MATERIALS = ROOT / 'docs/art/building-materials.json'
RECORD = ROOT / 'docs/art/texture-wrap-fix.json'
MIRRORED = 33648
QUADRANT = 1024  # px per reflected quadrant; the baked tile is 2048 square


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def read_glb(data: bytes) -> tuple[dict, bytearray]:
    magic, version, _ = struct.unpack_from('<III', data)
    assert (magic, version) == (0x46546C67, 2)
    length, kind = struct.unpack_from('<II', data, 12)
    assert kind == 0x4E4F534A
    doc = json.loads(data[20:20 + length])
    offset = 20 + length
    blength, bkind = struct.unpack_from('<II', data, offset)
    assert bkind == 0x004E4942
    return doc, bytearray(data[offset + 8:offset + 8 + blength])


def write_glb(doc: dict, binary: bytearray) -> bytes:
    encoded = json.dumps(doc, separators=(',', ':'), ensure_ascii=False).encode()
    encoded += b' ' * ((-len(encoded)) % 4)
    while len(binary) % 4:
        binary.append(0)
    size = 12 + 8 + len(encoded) + 8 + len(binary)
    return (struct.pack('<III', 0x46546C67, 2, size) + struct.pack('<II', len(encoded), 0x4E4F534A)
            + encoded + struct.pack('<II', len(binary), 0x004E4942) + bytes(binary))


def is_mirrored(doc: dict) -> bool:
    return any(s.get('wrapS') == MIRRORED or s.get('wrapT') == MIRRORED for s in doc.get('samplers', []))


def load_json(path: Path) -> dict:
    return json.loads(path.read_text())


def save_json(path: Path, data: dict) -> None:
    path.write_text(json.dumps(data, indent=2) + '\n')


def record() -> dict:
    return load_json(RECORD) if RECORD.exists() else {
        'title': 'Mirrored-wrap texture repair for building models',
        'tool': 'tools/fix_mirrored_textures.py',
        'baked': {}, 'models': {}}


def bake(source_uri: str, rec: dict) -> str:
    """Return the baked surfaces/ URI for a shared swatch, creating it once."""
    if source_uri in rec['baked'] and (ASSETS / rec['baked'][source_uri]).exists():
        return rec['baked'][source_uri]
    source = ASSETS / source_uri
    image = Image.open(source).convert('RGB').resize((QUADRANT, QUADRANT), Image.LANCZOS)
    a = np.asarray(image)
    tile = np.concatenate([np.concatenate([a, a[:, ::-1]], 1), np.concatenate([a[::-1, :], a[::-1, ::-1]], 1)], 0)
    buffer = BytesIO()
    Image.fromarray(tile.astype(np.uint8), 'RGB').save(buffer, 'JPEG', quality=92, optimize=True)
    data = buffer.getvalue()
    uri = 'surfaces/%s.jpg' % sha(data)
    target = ASSETS / uri
    if not target.exists():
        target.write_bytes(data)
    sidecar = source.with_suffix(source.suffix + '.import').read_text()
    # Keep the source swatch's import parameters; Godot assigns identity on import.
    params = sidecar[sidecar.index('[params]'):]
    target.with_suffix('.jpg.import').write_text('[remap]\n\nimporter="texture"\ntype="CompressedTexture2D"\n\n' + params)
    rec['baked'][source_uri] = uri
    return uri


def repair(data: bytes, rec: dict) -> bytes:
    doc, binary = read_glb(data)
    assert is_mirrored(doc), 'model does not use mirrored wrap'
    for image in doc.get('images', []):
        assert re.fullmatch(r'surfaces/[0-9a-f]{64}\.jpg', image.get('uri', '')), 'unexpected image source'
        image['uri'] = bake(image['uri'], rec)
    for sampler in doc.get('samplers', []):
        sampler.pop('wrapS', None)
        sampler.pop('wrapT', None)  # glTF default is REPEAT
    # Each baked tile holds two periods, so textured UV sets are halved once.
    scaled = set()
    for mesh in doc['meshes']:
        for primitive in mesh['primitives']:
            material = doc['materials'][primitive['material']] if 'material' in primitive else {}
            info = material.get('pbrMetallicRoughness', {}).get('baseColorTexture')
            if info is None:
                continue
            assert 'extensions' not in info, 'texture transforms are not expected'
            accessor_index = primitive['attributes']['TEXCOORD_%d' % info.get('texCoord', 0)]
            if accessor_index in scaled:
                continue
            scaled.add(accessor_index)
            accessor = doc['accessors'][accessor_index]
            assert accessor['type'] == 'VEC2' and accessor['componentType'] == 5126 and 'sparse' not in accessor
            view = doc['bufferViews'][accessor['bufferView']]
            stride = view.get('byteStride', 8)
            start = view.get('byteOffset', 0) + accessor.get('byteOffset', 0)
            for i in range(accessor['count']):
                at = start + i * stride
                u, v = struct.unpack_from('<ff', binary, at)
                struct.pack_into('<ff', binary, at, u * .5, v * .5)
            for key in ('min', 'max'):
                if key in accessor:
                    accessor[key] = [x * .5 for x in accessor[key]]
    return write_glb(doc, binary)


def set_hashes(code: int, glb: bytes) -> None:
    digest = sha(glb)
    catalog = load_json(CATALOG)
    for entry in catalog['entries']:
        if entry['code'] == code:
            entry['glb_sha256'] = digest
    save_json(CATALOG, catalog)
    landscaping = load_json(LANDSCAPING)
    for profile in landscaping['entries']:
        if profile['code'] == code:
            profile['glb_sha256'] = digest
    save_json(LANDSCAPING, landscaping)
    materials = load_json(MATERIALS)
    for row in materials['models']:
        if row['code'] == code:
            row['runtime_glb_sha256'] = digest
            row['runtime_bytes'] = len(glb)
    save_json(MATERIALS, materials)


def sync_material_textures(rec: dict) -> None:
    """List exactly the shared images still referenced by any catalog model."""
    used = set()
    for path in ASSETS.glob('*-blender.glb'):
        doc, _ = read_glb(path.read_bytes())
        used.update(i['uri'] for i in doc.get('images', []) if 'uri' in i)
    materials = load_json(MATERIALS)
    rows = {row['path']: row for row in materials['textures']}
    for source, baked in rec['baked'].items():
        if baked in used and baked not in rows:
            data = (ASSETS / baked).read_bytes()
            name = rows.get(source, {}).get('source_name', '')
            rows[baked] = {'path': baked, 'sha256': sha(data), 'bytes': len(data),
                           'source_name': (name + ' (mirrored tile)').strip()}
    materials['textures'] = [row for path, row in rows.items() if path in used or path not in rec['baked'].values()]
    save_json(MATERIALS, materials)


def codes(arguments: list[str]) -> list[int]:
    if arguments == ['all']:
        return list(range(112, 256))
    return [int(a) for a in arguments]


def apply(selected: list[int]) -> None:
    rec = record()
    BACKUP.mkdir(parents=True, exist_ok=True)
    done = []
    for code in selected:
        path = ASSETS / f'{code}-blender.glb'
        data = path.read_bytes()
        doc, _ = read_glb(data)
        if not is_mirrored(doc):
            continue  # already repaired, or a model that never used mirrored wrap
        backup = BACKUP / path.name
        if not backup.exists():
            backup.write_bytes(data)
        assert sha(backup.read_bytes()) == sha(data), f'{code}: backup differs from the current model'
        fixed = repair(data, rec)
        path.write_bytes(fixed)
        set_hashes(code, fixed)
        rec['models'][str(code)] = {'state': 'repaired', 'original_sha256': sha(data), 'original_bytes': len(data),
                                    'repaired_sha256': sha(fixed), 'repaired_bytes': len(fixed)}
        done.append(code)
    save_json(RECORD, rec)
    sync_material_textures(rec)
    print(f'repaired {len(done)} models' + (f': {done[0]}…{done[-1]}' if done else ''))


def revert(selected: list[int]) -> None:
    rec = record()
    done = []
    for code in selected:
        row = rec['models'].get(str(code))
        if row is None or row['state'] != 'repaired':
            continue
        path = ASSETS / f'{code}-blender.glb'
        assert sha(path.read_bytes()) == row['repaired_sha256'], f'{code}: model changed since repair; not reverting'
        original = (BACKUP / path.name).read_bytes()
        assert sha(original) == row['original_sha256'], f'{code}: backup missing or altered'
        path.write_bytes(original)
        set_hashes(code, original)
        row['state'] = 'reverted'
        done.append(code)
    save_json(RECORD, rec)
    sync_material_textures(rec)
    print(f'reverted {len(done)} models: {done}')


def status() -> None:
    rec = record()
    states = {}
    for code in range(112, 256):
        data = (ASSETS / f'{code}-blender.glb').read_bytes()
        doc, _ = read_glb(data)
        row = rec['models'].get(str(code))
        if row and sha(data) == row.get('repaired_sha256'):
            states.setdefault('repaired', []).append(code)
        elif is_mirrored(doc):
            states.setdefault('mirrored (clamped in game)', []).append(code)
        else:
            states.setdefault('unaffected', []).append(code)
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
