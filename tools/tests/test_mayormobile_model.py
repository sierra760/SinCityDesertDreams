# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
"""Runtime SUV packaging and authored moving-part contract."""
import hashlib
import json
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from fix_mirrored_textures import read_glb
from split_model_palms import triangle_count

ROOT = Path(__file__).resolve().parents[2]


def test_runtime_suv_matches_art_record_and_embeds_all_resources():
    record = json.loads((ROOT/'docs/art/mayormobile.json').read_text())
    data = (ROOT/record['runtime']).read_bytes()
    doc, binary = read_glb(data)
    assert hashlib.sha256(data).hexdigest() == record['runtime_sha256']
    assert triangle_count(doc, binary) == record['triangles'] < 12000
    assert not doc.get('images')
    assert all('uri' not in buffer for buffer in doc['buffers'])


def test_four_road_wheels_have_independent_spin_pivots_and_spare_is_static():
    record = json.loads((ROOT/'docs/art/mayormobile.json').read_text())
    doc, _ = read_glb((ROOT/record['runtime']).read_bytes())
    wheels = [n for n in doc['nodes'] if n.get('name', '').startswith('Wheel')]
    assert {n['name'] for n in wheels} == {'WheelFrontLeft', 'WheelFrontRight', 'WheelRearLeft', 'WheelRearRight'}
    for wheel in wheels:
        spins = [doc['nodes'][i] for i in wheel.get('children', [])]
        assert len(spins) == 1 and spins[0]['name'] == 'Spin'
        assert spins[0].get('children'), 'each animated pivot must carry actual wheel geometry'
    assert len(record['animation']['wheels']) == 4
