# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
"""Farm package failures must be detected before publication."""
import copy
import importlib.util
from pathlib import Path
import pytest

ROOT = Path(__file__).resolve().parents[2]

def checker():
    path = ROOT / 'tools/check_agriculture_assets.py'
    assert path.exists(), 'missing agricultural asset checker and sixteen farm GLBs'
    spec = importlib.util.spec_from_file_location('check_agriculture_assets', path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def test_package_covers_ten_developed_and_six_state_lots():
    lot_count, animal_count = checker().check()
    assert lot_count == 16
    assert animal_count == 3


@pytest.mark.parametrize('damage,diagnostic', [
    ('values', 'roster'), ('collider', 'collider'), ('support', 'support'),
    ('bounds', 'footprint'), ('triangles', 'triangle'),
    ('external', 'external'), ('private', 'external'), ('enclosure', 'enclosure'),
])
def test_checker_rejects_damaged_real_farm(damage, diagnostic):
    c = checker()
    records = c.load_records()
    record = copy.deepcopy(next(r for r in records if r['key'] == 'ag_cattle_range'))
    entry = copy.deepcopy(c.catalog_entry(record['code']))
    gltf, binary = c.read_glb(c.ASSETS / f"{record['code']}-blender.glb")
    gltf = copy.deepcopy(gltf)
    if damage == 'values': record['jobs'] += 1
    elif damage == 'collider':
        for node in gltf['nodes']: node['name'] = node.get('name', '').replace('-colonly', '-removed')
    elif damage == 'support':
        for node in gltf['nodes']: node['name'] = node.get('name', '').replace('Ground support', 'Removed')
    elif damage == 'bounds':
        for accessor in gltf['accessors']:
            if accessor.get('type') == 'VEC3' and 'max' in accessor: accessor['max'][0] = 1000
    elif damage == 'triangles': entry['triangles'] = 20001
    elif damage == 'external': gltf['images'] = [{'uri':'https://example.com/soil.png'}]
    elif damage == 'private': gltf['images'] = [{'uri':'../../assets/agriculture/soil.png'}]
    elif damage == 'enclosure': record['enclosure'] = None
    with pytest.raises(AssertionError, match=diagnostic):
        c.validate_lot(record, entry, gltf, binary)


def test_general_package_accepts_existing_lettering_provenance():
    checker()  # Establish tools import path before the existing checker import.
    import check_3d_assets
    count, byte_count = check_3d_assets.check()
    assert count > 16 and byte_count > 0


def test_serialized_fence_matches_physical_collider_thickness():
    c = checker()
    for record in c.load_records():
        if not record['enclosure']: continue
        gltf, binary = c.read_glb(c.ASSETS / f"{record['code']}-blender.glb")
        widths = []
        for n in gltf['nodes']:
            if n.get('name', '').startswith(('Pen fence', 'Closed service gate')):
                lo, hi = c.node_bounds(gltf, binary, n)
                widths.append(round(min(hi[0]-lo[0], hi[2]-lo[2]), 3))
        assert set(widths) == {.16}
        assert all(f['thickness'] == widths[0] for p in record['enclosure']['pens'] for f in p['fences'])


def test_livestock_has_three_real_independent_rigs():
    c = checker()
    assert hasattr(c, 'check_animals'), 'missing rigged animals and manifest validator'
    assert c.check_animals() == 3


@pytest.mark.parametrize('damage,diagnostic', [('rig','skin'),('joint','joint'),('radius','radius'),('triangles','triangle'),('rest','rest'),('weights','weight')])
def test_checker_rejects_damaged_real_livestock(damage,diagnostic):
    c=checker()
    import json
    record=copy.deepcopy(json.loads((ROOT/'game/assets/agriculture/enclosures.json').read_text())['species']['beef_cattle'])
    gltf,binary=c.read_glb(ROOT/'game/assets/agriculture/beef_cattle.glb')
    if damage=='rig':gltf['skins']=[]
    elif damage=='joint':
        next(n for n in gltf['nodes'] if n.get('name')=='Head')['name']='Missing'
    elif damage=='radius':record['body_radius']=.6
    elif damage=='triangles':record['triangles']=4001
    elif damage=='rest':
        next(n for n in gltf['nodes'] if n.get('name')=='Head')['translation']=[0,0,0]
    elif damage=='weights':
        for m in gltf['meshes']:
            for p in m['primitives']:p['attributes'].pop('WEIGHTS_0',None)
    assert hasattr(c,'validate_animal'), 'missing actual exported skin verification'
    with pytest.raises(AssertionError,match=diagnostic):c.validate_animal('beef_cattle',record,gltf,binary)
