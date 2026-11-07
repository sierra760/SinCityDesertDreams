#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
"""Package original logo geometry into the current, repaired resort models.

Run after Blender's build_casino_logo_signs.py. Exact input models are retained
locally. Re-running composes from those originals, refuses changed inputs and
keeps catalog, landscaping and provenance records in step. No base geometry is
rebuilt: only explicitly selected old name triangles are removed.
"""
from __future__ import annotations

import copy
import hashlib
import json
from pathlib import Path
import sys

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
from fix_mirrored_textures import (ROOT, ASSETS, CATALOG, load_json, read_glb,
                                    save_json, set_hashes, sha, write_glb)
from split_model_palms import (accessor_array, catalog_entries, model_path,
                               parts_of, strip, triangle_count, world_transforms)

SOURCE = ROOT / 'assets/casino-signs'
RECORD = ROOT / 'docs/art/casino-logo-signs.json'


def specifications() -> dict[int, dict]:
    return {r['code']: r for r in load_json(ROOT / 'tools/casino_signs.json')['signs']}


def append_glb(base: bytes, addition: bytes) -> bytes:
    """Append a static authored sign; keep base buffer bytes intact."""
    doc, binary = read_glb(base)
    sign, extra = read_glb(addition)
    if sign.get('skins') or sign.get('animations'):
        raise ValueError('signs must be static geometry')
    if len(doc['buffers']) != 1 or len(sign['buffers']) != 1:
        raise ValueError('only self-contained single-buffer GLBs are supported')
    while len(binary) % 4:
        binary.append(0)
    offset = len(binary)
    starts = {k: len(doc.get(k, [])) for k in ('nodes', 'meshes', 'materials', 'bufferViews', 'accessors','images','textures','samplers')}
    for view in sign['bufferViews']:
        view['buffer'] = 0
        view['byteOffset'] = view.get('byteOffset', 0) + offset
    for accessor in sign['accessors']:
        if 'sparse' in accessor:
            raise ValueError('sparse sign accessors are not supported')
        accessor['bufferView'] += starts['bufferViews']
    for image in sign.get('images',[]):
        if 'bufferView' not in image:
            raise ValueError('sign textures must be embedded in their GLB')
        image['bufferView'] += starts['bufferViews']
    for texture in sign.get('textures',[]):
        texture['source'] += starts['images']
        if 'sampler' in texture:texture['sampler'] += starts['samplers']
    def texture_indices(value):
        if not isinstance(value,dict):return
        for key,child in value.items():
            if key.endswith('Texture') and isinstance(child,dict) and 'index' in child:
                child['index'] += starts['textures']
            else:texture_indices(child)
    for mat in sign.get('materials',[]):
        texture_indices(mat)
    for mesh in sign['meshes']:
        for primitive in mesh['primitives']:
            primitive['attributes'] = {k: v + starts['accessors'] for k, v in primitive['attributes'].items()}
            primitive['indices'] += starts['accessors']
            if 'material' in primitive:
                primitive['material'] += starts['materials']
    for node in sign['nodes']:
        if 'mesh' in node:
            node['mesh'] += starts['meshes']
        if 'children' in node:
            node['children'] = [n + starts['nodes'] for n in node['children']]
    for key in starts:
        doc.setdefault(key, []).extend(sign.get(key, []))
    scene = sign['scenes'][sign.get('scene', 0)]
    doc['scenes'][doc.get('scene', 0)].setdefault('nodes', []).extend(n + starts['nodes'] for n in scene['nodes'])
    for key in ('extensionsUsed', 'extensionsRequired'):
        if sign.get(key):
            doc[key] = sorted(set(doc.get(key, []) + sign[key]))
    binary.extend(extra)
    doc['buffers'] = [{'byteLength': len(binary)}]
    return write_glb(doc, binary)


def collision_hash(data: bytes) -> str:
    """Hash collision nodes and their exact local attribute/index arrays."""
    doc, binary = read_glb(data)
    digest = hashlib.sha256()
    for node in doc['nodes']:
        if 'mesh' not in node or not node.get('name', '').endswith('colonly'):
            continue
        digest.update(json.dumps({k: v for k, v in node.items() if k != 'mesh'}, sort_keys=True).encode())
        for primitive in doc['meshes'][node['mesh']]['primitives']:
            for key, index in sorted(primitive['attributes'].items()):
                digest.update(key.encode())
                digest.update(accessor_array(doc, binary, index).tobytes())
            digest.update(accessor_array(doc, binary, primitive['indices']).tobytes())
    return digest.hexdigest()


def superseded_parts(doc: dict, binary: bytes, spec: dict) -> list[dict]:
    parts = [p for p in parts_of(doc, binary) if not p['collision']]
    if 'old_mesh' in spec:
        meshes = {n['mesh'] for n in doc['nodes'] if n.get('name') == spec['old_mesh'] and 'mesh' in n}
        chosen = [p for p in parts if p['mesh'] in meshes]
    else:
        box = spec['old_box']
        chosen = [p for p in parts if p['material'].startswith('sign_')
                  and (p['lo'] >= box[:3]).all() and (p['hi'] <= box[3:]).all()]
    found = sum(len(p['tris']) for p in chosen)
    if found != spec['old_triangles']:
        raise ValueError(f'{spec["code"]}: old name has {found} triangles, expected {spec["old_triangles"]}')
    return chosen


def compose(base: bytes, sign: bytes, spec: dict) -> tuple[bytes, dict]:
    doc, binary = read_glb(base)
    if any(n.get('name', '').startswith('CasinoLogo') for n in doc['nodes']):
        raise ValueError('model already has a casino logo')
    original = triangle_count(doc, binary)
    gone = superseded_parts(doc, binary, spec)
    kept, buf, removed = strip(copy.deepcopy(doc), bytes(binary), [{'parts': gone}])
    # Blender folds sub-unit emission strength into emissiveFactor. Keep the
    # authored color separate from energy so dusk can brighten it correctly.
    logo_doc,logo_binary=read_glb(sign)
    for mat in logo_doc.get('materials',[]):
        name=mat.get('name','')
        if name=='sign_logo_letters':
            mat['emissiveFactor']=[1,1,1]
        elif name=='sign_logo_neon_a':
            color=spec.get('a','ffffff')
            values=[int(color[i:i+2],16)/255 for i in (0,2,4)]
            mat['emissiveFactor']=[v/12.92 if v<=.04045 else ((v+.055)/1.055)**2.4 for v in values]
        else:continue
        mat.setdefault('extensions',{})['KHR_materials_emissive_strength']={'emissiveStrength':.035}
    logo_doc['extensionsUsed']=sorted(set(logo_doc.get('extensionsUsed',[])+['KHR_materials_emissive_strength']))
    prepared_sign=write_glb(logo_doc,logo_binary)
    output = append_glb(write_glb(kept, buf), prepared_sign)
    final, final_buffer = read_glb(output)
    logo, logo_buffer = read_glb(sign)
    tris = triangle_count(final, final_buffer)
    collision = collision_hash(base)
    if collision_hash(output) != collision:
        raise ValueError('collision changed during sign composition')
    if tris > 40000:
        raise ValueError(f'{spec["code"]}: {tris} triangles exceeds the 40000 exterior budget')
    summary = {'original_triangles': original, 'removed_triangles': removed,
               'sign_triangles': triangle_count(logo, logo_buffer), 'triangles': tris,
               'sign_surfaces': sum(len(m['primitives']) for m in logo['meshes']),
               'collision_sha256': collision}
    transforms=world_transforms(final)
    top=0.0
    for index,node in enumerate(final['nodes']):
        if index not in transforms or 'mesh' not in node or node.get('name','').endswith('colonly'):continue
        for primitive in final['meshes'][node['mesh']]['primitives']:
            vertices=accessor_array(final,final_buffer,primitive['attributes']['POSITION'])
            world=(np.c_[vertices,np.ones(len(vertices))]@transforms[index].T)[:,:3]
            top=max(top,float(world[:,1].max()))
    summary['height_metres']=top
    return output, summary


def apply() -> None:
    records = load_json(RECORD) if RECORD.exists() else {'tool': 'tools/casino_sign_models.py', 'models': {}}
    entries = catalog_entries()
    specs = specifications()
    originals = SOURCE / 'originals'
    originals.mkdir(parents=True, exist_ok=True)
    # Preflight every model before writing anything. Never bless concurrent edits.
    candidates = []
    for code, spec in specs.items():
        path = model_path(entries[code])
        current = path.read_bytes()
        row = records['models'].get(str(code))
        backup = originals / path.name
        if row:
            if sha(current) != row['output_sha256']:
                raise ValueError(f'{code}: current model changed since logo packaging')
            base = backup.read_bytes()
            if sha(base) != row['input_sha256']:
                raise ValueError(f'{code}: original model differs from recorded input')
        else:
            base = current
            if backup.exists() and backup.read_bytes() != base:
                raise ValueError(f'{code}: kept original differs from current model')
        sign_path = SOURCE / 'models' / f'{code}-logo.glb'
        sign = sign_path.read_bytes()
        output, summary = compose(base, sign, spec)
        candidates.append((code, spec, path, base, sign, output, summary))
    for code, spec, path, base, sign, output, summary in candidates:
        (originals / path.name).write_bytes(base)
        path.write_bytes(output)
        set_hashes(code, output)
        # The sign adds one textured material to each classic resort. Keep
        # the descriptive counts as well as content hashes accurate.
        material_path=ROOT/'docs/art/building-materials.json'
        material_record=load_json(material_path)
        final_doc,_=read_glb(output)
        def textured(value):
            return isinstance(value,dict) and any((key.endswith('Texture') and isinstance(child,dict)) or textured(child) for key,child in value.items())
        for material_row in material_record['models']:
            if material_row['code']==code:
                material_row['textured_materials']=sum(textured(m) for m in final_doc.get('materials',[]))
        save_json(material_path,material_record)
        previous_output = records['models'].get(str(code), {}).get('output_sha256')
        records['models'][str(code)] = {'name': spec['name'], 'shape': spec['shape'],
            'input_sha256': sha(base), 'sign_sha256': sha(sign), 'output_sha256': sha(output),
            'lettering': 'original illustrated sign face', 'center': spec['center'], 'width': spec['width'], 'height': spec['height'],
            'source': f'assets/casino-signs/models/{code}-logo.blend', **summary}
        catalog = load_json(CATALOG)
        for entry in catalog['entries']:
            if entry['code'] == code:
                entry['triangles'] = summary['triangles']
                entry['height'] = summary['height_metres']/16.0
                entry['logo_sign'] = {key: spec[key] for key in ('name','shape','center','width','height')}
                entry['lettering'] = {'family':'original sign-painter lettering',
                    'source':'original generated artwork; assets/casino-signs/generation.json',
                    'output':'illustrated static sign face; original artwork','text':spec['name']}
        save_json(CATALOG, catalog)
        # These records describe operations preceding this additive sign layer.
        for name, hash_key, triangle_key in [('palm-split.json', 'split_sha256', 'split_triangles'),
                                              ('model-repairs.json', 'repaired_sha256', 'triangles')]:
            record_path = ROOT / 'docs/art' / name
            if not record_path.exists():
                continue
            prior = load_json(record_path)
            row = prior.get('models', {}).get(str(code))
            if row and row.get(hash_key) in (sha(base), previous_output):
                row[hash_key] = sha(output)
                if triangle_key in row:
                    row[triangle_key] = summary['triangles']
                bytes_key='split_bytes' if name=='palm-split.json' else 'repaired_bytes'
                if bytes_key in row:row[bytes_key]=len(output)
                row['logo_layer'] = 'docs/art/casino-logo-signs.json'
                save_json(record_path, prior)
        print(f'{code} {spec["name"]}: {summary["sign_triangles"]} sign / {summary["triangles"]} total triangles')
    save_json(RECORD, records)


if __name__ == '__main__':
    apply()
